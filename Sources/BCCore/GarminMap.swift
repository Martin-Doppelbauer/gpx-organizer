import Foundation

public final class GarminMap: Identifiable {
    public let id: String
    public let name: String
    public let url: URL
    public private(set) var tiles: [Tile] = []
    public private(set) var unsupportedReason: String?
    public var isSupported: Bool { unsupportedReason == nil && !tiles.isEmpty }
    public private(set) var bounds: Bounds?
    public private(set) var typ: TYPStyles?
    /// Routing rules derived from this map's own data (see `analyzeRouting`); nil until analysed.
    public internal(set) var routingRules: RoutingRules?

    public init(url: URL) {
        self.url = url
        self.id = url.lastPathComponent
        self.name = url.deletingPathExtension().lastPathComponent
        load()
    }

    /// Single-file Garmin map (gmapsupp.img or similar).
    public init(imgURL: URL) {
        self.url = imgURL
        self.id = "img:" + imgURL.path
        self.name = imgURL.deletingPathExtension().lastPathComponent
        loadIMG()
    }

    private func loadIMG() {
        guard let c = IMGContainer(path: url.path) else { unsupportedReason = "Not a valid Garmin IMG file"; return }
        if c.subfiles.keys.contains(where: { $0.hasSuffix(".GMP") }) {
            unsupportedReason = "Garmin NT format (GMP): map geometry not readable yet"; return
        }
        var all: [Tile] = []
        for (i, n) in c.tileNames.enumerated() {
            if let t = Tile(number: Int(n) ?? i, dir: "", opener: { ext in c.subfiles["\(n).\(ext)"] }) { all.append(t) }
        }
        // Drop a world/overview map that overlaps all detail tiles (much larger than the typical tile).
        if all.count >= 3 {
            func area(_ t: Tile) -> Double { Double(max(1, t.bounds.north - t.bounds.south)) * Double(max(1, t.bounds.east - t.bounds.west)) }
            let med = all.map(area).sorted()[all.count / 2]
            let detail = all.filter { area($0) <= med * 4 }
            if !detail.isEmpty { all = detail }
        }
        tiles = all
        if let typFile = c.subfiles.first(where: { $0.key.hasSuffix(".TYP") })?.value { typ = TYPStyles(file: typFile) }
        if tiles.isEmpty { unsupportedReason = c.tileNames.isEmpty ? "No map tiles found" : "Map is locked or unreadable" }
        if let f = tiles.first {
            var b = f.bounds
            for t in tiles { b.north = max(b.north, t.bounds.north); b.east = max(b.east, t.bounds.east)
                b.south = min(b.south, t.bounds.south); b.west = min(b.west, t.bounds.west) }
            bounds = b
        }
    }

    public static func discover(in root: URL) -> [GarminMap] {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let imgs = items.filter { $0.pathExtension.lowercased() == "img" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { GarminMap(imgURL: $0) }
        return items.filter { $0.pathExtension.lowercased() == "gmap" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { GarminMap(url: $0) } + imgs
    }

    private func tag(_ xml: String, _ t: String) -> String? {
        guard let a = xml.range(of: "<\(t)>"), let b = xml.range(of: "</\(t)>", range: a.upperBound..<xml.endIndex) else { return nil }
        return String(xml[a.upperBound..<b.lowerBound])
    }

    private func load() {
        let fm = FileManager.default
        let xml = (try? String(contentsOf: url.appendingPathComponent("Info.xml"), encoding: .utf8)) ?? ""
        if let t = tag(xml, "TYP") { typ = TYPStyles(path: url.appendingPathComponent(t).path) }
        let dirName = tag(xml, "Directory") ?? "Product1"
        let productDir = url.appendingPathComponent(dirName)
        guard let entries = try? fm.contentsOfDirectory(atPath: productDir.path) else {
            unsupportedReason = "Kein Kartenverzeichnis"; return
        }
        var numbers: [Int]
        if let tdb = tag(xml, "TDB"), let list = Self.tdbTiles(productDir.appendingPathComponent(tdb).path) {
            numbers = list
        } else {
            numbers = entries.compactMap { Int($0) }
        }
        var hasGMP = false
        for n in numbers.sorted() {
            let d = productDir.appendingPathComponent(String(n)).path
            if let t = Tile(number: n, dir: d) { tiles.append(t) }
            else if let sub = try? fm.contentsOfDirectory(atPath: d), sub.contains(where: { $0.uppercased().hasSuffix(".GMP") }) { hasGMP = true }
        }
        if tiles.contains(where: { $0.isGMP }) { unsupportedReason = "Garmin NT format (GMP): map geometry not readable yet"; return }
        if tiles.isEmpty { unsupportedReason = hasGMP ? "GMP tiles unreadable (locked or unknown)" : "No readable tiles" }
        if let f = tiles.first {
            var b = f.bounds
            for t in tiles { b.north = max(b.north, t.bounds.north); b.east = max(b.east, t.bounds.east)
                b.south = min(b.south, t.bounds.south); b.west = min(b.west, t.bounds.west) }
            bounds = b
        }
    }

    /// Reads detail-map numbers ('L' blocks) of a TDB file.
    static func tdbTiles(_ path: String) -> [Int]? {
        guard let f = MappedFile(path: path) else { return nil }
        var o = 0
        var out: [Int] = []
        while o + 3 <= f.size {
            let type = f.u8(o), len = f.u16(o + 1)
            if type == 0x4C && len >= 8 { out.append(f.u32(o + 3)) }
            o += 3 + len
        }
        return out.isEmpty ? nil : out
    }
}
