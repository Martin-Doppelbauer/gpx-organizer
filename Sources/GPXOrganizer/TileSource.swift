import Foundation
import CoreGraphics
import ImageIO

/// An online raster map (Web-Mercator XYZ tiles).
struct TileSource: Identifiable, Hashable {
    let id: String
    let name: String
    let template: String          // {s} subdomain, {z} zoom, {x}, {y}
    let subdomains: [String]
    let maxZoom: Int
    let attribution: String

    func url(z: Int, x: Int, y: Int) -> URL? {
        var u = template.replacingOccurrences(of: "{z}", with: "\(z)").replacingOccurrences(of: "{x}", with: "\(x)")
            .replacingOccurrences(of: "{y}", with: "\(y)")
        if !subdomains.isEmpty { u = u.replacingOccurrences(of: "{s}", with: subdomains[(x + y) % subdomains.count]) }
        return URL(string: u)
    }

    static let all: [TileSource] = [
        TileSource(id: "online:opentopomap", name: "OpenTopoMap (Topo, worldwide)",
                   template: "https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png", subdomains: ["a", "b", "c"], maxZoom: 17,
                   attribution: "Map data © OpenStreetMap contributors, SRTM | Rendering © OpenTopoMap (CC-BY-SA)"),
        TileSource(id: "online:topplusopen", name: "TopPlusOpen (Topo, Germany/Europe)",
                   template: "https://sgx.geodatenzentrum.de/wmts_topplus_open/tile/1.0.0/web/default/WEBMERCATOR/{z}/{y}/{x}.png", subdomains: [], maxZoom: 18,
                   attribution: "© Federal Agency for Cartography and Geodesy (TopPlusOpen), data sources: sg.geodatenzentrum.de"),
        TileSource(id: "online:topplusopen-grau", name: "TopPlusOpen gray",
                   template: "https://sgx.geodatenzentrum.de/wmts_topplus_open/tile/1.0.0/web_grau/default/WEBMERCATOR/{z}/{y}/{x}.png", subdomains: [], maxZoom: 18,
                   attribution: "© Federal Agency for Cartography and Geodesy (TopPlusOpen), data sources: sg.geodatenzentrum.de"),
        TileSource(id: "online:osm", name: "OpenStreetMap (Standard)",
                   template: "https://tile.openstreetmap.org/{z}/{x}/{y}.png", subdomains: [], maxZoom: 19,
                   attribution: "© OpenStreetMap contributors")
    ]
}

private final class TileImage {
    let image: CGImage
    init(_ i: CGImage) { image = i }
}

/// Memory + disk cache for online tiles. The disk cache lives next to the other maps (Garmin Maps folder).
final class TileCache {
    static let shared = TileCache()
    private let mem = NSCache<NSString, TileImage>()
    private let lock = NSLock()
    private var inflight = Set<String>()
    private var failedAt: [String: Date] = [:]
    private var pending: [() -> Void] = []
    private var active = 0
    private let maxConcurrent = 6
    private let io = DispatchQueue(label: "tiles.io", qos: .userInitiated, attributes: .concurrent)
    private let session: URLSession
    private(set) var root: URL

    init() {
        mem.totalCostLimit = 250_000_000
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.httpMaximumConnectionsPerHost = 4
        cfg.httpAdditionalHeaders = ["User-Agent": "GPXOrganizer/0.1 (macOS GPX and map viewer)"]
        session = URLSession(configuration: cfg)
        root = TileCache.chooseRoot()
    }

    /// Cache folder: inside the maps folder when writable, else in the user's caches.
    private static func chooseRoot() -> URL {
        let fm = FileManager.default
        let preferred = AppSettings.onlineTilesRoot
        if (try? fm.createDirectory(at: preferred, withIntermediateDirectories: true)) != nil, fm.isWritableFile(atPath: preferred.path) {
            return preferred
        }
        let alt = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("GPXOrganizer/tiles")
        try? fm.createDirectory(at: alt, withIntermediateDirectories: true)
        return alt
    }

    /// Called after the maps folder changed (first start).
    func reconfigure() { lock.lock(); root = TileCache.chooseRoot(); lock.unlock() }

    private func key(_ s: TileSource, _ z: Int, _ x: Int, _ y: Int) -> String { "\(s.id)/\(z)/\(x)/\(y)" }
    private func file(_ s: TileSource, _ z: Int, _ x: Int, _ y: Int) -> URL {
        root.appendingPathComponent(s.id.replacingOccurrences(of: "online:", with: ""))
            .appendingPathComponent("\(z)/\(x)/\(y).png")
    }

    func cached(_ s: TileSource, _ z: Int, _ x: Int, _ y: Int) -> CGImage? {
        mem.object(forKey: key(s, z, x, y) as NSString)?.image
    }

    /// Loads a tile in the background (disk first, then network). `done` is called on the main queue when it became available.
    func fetch(_ s: TileSource, _ z: Int, _ x: Int, _ y: Int, done: @escaping () -> Void) {
        let k = key(s, z, x, y)
        lock.lock()
        if inflight.contains(k) || (failedAt[k].map { Date().timeIntervalSince($0) < 30 } ?? false) || mem.object(forKey: k as NSString) != nil {
            lock.unlock(); return
        }
        inflight.insert(k)
        lock.unlock()
        io.async { [self] in
            let f = file(s, z, x, y)
            var data: Data?
            var stale = false
            if let attrs = try? FileManager.default.attributesOfItem(atPath: f.path), let d = try? Data(contentsOf: f) {
                data = d
                stale = (attrs[.modificationDate] as? Date).map { Date().timeIntervalSince($0) > 60 * 24 * 3600 } ?? false
            }
            if let d = data, !stale, finish(k, d, done) { return }
            download(s, z, x, y, fallback: data, k: k, file: f, done: done)
        }
    }

    @discardableResult
    private func finish(_ k: String, _ d: Data, _ done: @escaping () -> Void) -> Bool {
        guard let src = CGImageSourceCreateWithData(d as CFData, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return false }
        mem.setObject(TileImage(img), forKey: k as NSString, cost: img.width * img.height * 4)
        lock.lock(); inflight.remove(k); lock.unlock()
        DispatchQueue.main.async(execute: done)
        return true
    }

    private func download(_ s: TileSource, _ z: Int, _ x: Int, _ y: Int, fallback: Data?, k: String, file f: URL, done: @escaping () -> Void) {
        guard let url = s.url(z: z, x: x, y: y) else { fail(k); return }
        lock.lock(); pending.append { [self] in
            session.dataTask(with: url) { [self] data, resp, _ in
                defer { slotDone() }
                if let data, (resp as? HTTPURLResponse)?.statusCode == 200, finish(k, data, done) {
                    try? FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: f, options: .atomic)
                } else if let fb = fallback, finish(k, fb, done) {
                } else { fail(k) }
            }.resume()
        }
        lock.unlock()
        pump()
    }

    private func fail(_ k: String) {
        lock.lock(); inflight.remove(k); failedAt[k] = Date(); lock.unlock()
    }

    private func pump() {
        lock.lock()
        while active < maxConcurrent, !pending.isEmpty { active += 1; let job = pending.removeFirst(); lock.unlock(); job(); lock.lock() }
        lock.unlock()
    }

    private func slotDone() { lock.lock(); active -= 1; lock.unlock(); pump() }

    /// True if a recent copy of the tile is already on disk.
    func isOnDisk(_ s: TileSource, _ z: Int, _ x: Int, _ y: Int) -> Bool {
        let f = file(s, z, x, y)
        guard let a = try? FileManager.default.attributesOfItem(atPath: f.path) else { return false }
        return (a[.modificationDate] as? Date).map { Date().timeIntervalSince($0) < 60 * 24 * 3600 } ?? false
    }

    /// Downloads a tile to disk only (no decoding). `done(success, httpStatus)` is called on a background queue.
    func prefetch(_ s: TileSource, _ z: Int, _ x: Int, _ y: Int, done: @escaping (Bool, Int) -> Void) {
        if isOnDisk(s, z, x, y) { done(true, 0); return }
        guard let url = s.url(z: z, x: x, y: y) else { done(false, 0); return }
        let f = file(s, z, x, y)
        lock.lock(); pending.append { [self] in
            session.dataTask(with: url) { data, resp, _ in
                defer { slotDone() }
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if let data, code == 200 {
                    try? FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: f, options: .atomic)
                    done(true, code)
                } else { done(false, code) }
            }.resume()
        }
        lock.unlock()
        pump()
    }

    /// Number of tiles and size of the disk cache.
    func diskUsage() -> (files: Int, bytes: Int64) {
        var n = 0; var b: Int64 = 0
        if let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let u as URL in en where u.pathExtension == "png" {
                n += 1; b += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return (n, b)
    }

    func clearAll() {
        mem.removeAllObjects()
        let fm = FileManager.default
        for item in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] { try? fm.removeItem(at: item) }
    }
}
