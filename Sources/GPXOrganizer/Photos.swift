import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import BCCore

// Photos with GPS data are shown on the map as small stamps. The photo folder is only READ: no photo is ever
// added, removed or changed. The metadata index and the thumbnails live in the folder "Photos" inside the
// online-map cache folder (Settings > Storage).

// MARK: Model

struct PhotoEntry: Codable {
    var path: String
    var mtime: Double
    var size: Int64
    var lat: Double?
    var lon: Double?
    var date: Double
    var camera: String?
}

/// A photo with GPS position, ready for the map.
struct PhotoItem: Identifiable {
    var id: String { path }
    let path: String
    let mtime: Double
    let date: Date
    let camera: String
    let lat: Double
    let lon: Double
    let x: Double      // Web-Mercator 0..1
    let y: Double

    init(_ e: PhotoEntry) {
        path = e.path; mtime = e.mtime; date = Date(timeIntervalSince1970: e.date); camera = e.camera ?? ""
        lat = e.lat ?? 0; lon = e.lon ?? 0
        x = Merc.x(lon: lon); y = Merc.y(lat: lat)
    }

    private static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d.M.yy HH:mm"; return f }()
    var shortDate: String { Self.fmt.string(from: date) }
    var longDate: String { date.formatted(date: .complete, time: .standard) }
}

@MainActor
final class PhotoStore: ObservableObject {
    static let shared = PhotoStore()
    @Published private(set) var items: [PhotoItem] = []
    @Published var status = ""
    @Published var folderPath: String? = UserDefaults.standard.string(forKey: "photoFolder")
    @Published private(set) var fileCount = 0

    private var generation = 0
    private var started = false

    nonisolated static var cacheDir: URL { TileCache.shared.root.appendingPathComponent("Photos", isDirectory: true) }
    nonisolated static var thumbDir: URL { cacheDir.appendingPathComponent("Thumbs", isDirectory: true) }
    private nonisolated static var indexURL: URL { cacheDir.appendingPathComponent("index.json") }

    private struct Index: Codable { var folder: String; var entries: [PhotoEntry]; var rev: Int? = nil }
    private static let indexRev = 2          // 2: positions are read more carefully (hemisphere, GPS status); older positions are read again

    init() {
        NotificationCenter.default.addObserver(forName: .mapsFolderChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.started = false; self?.start() }
        }
    }

    /// Loads the cache, then looks for changes in the photo folder.
    func start() {
        guard !started else { return }
        started = true
        guard let f = folderPath else { return }
        generation += 1
        let gen = generation
        status = "Loading photo index …"
        Task.detached(priority: .userInitiated) {
            var loaded: [String: PhotoEntry] = [:]
            var shown: [PhotoEntry] = []            // what the old index knows: shown until the new reading is done
            if let d = try? Data(contentsOf: Self.indexURL), let idx = try? JSONDecoder().decode(Index.self, from: d), idx.folder == f {
                shown = idx.entries
                let old = (idx.rev ?? 1) < Self.indexRev
                loaded = Dictionary(idx.entries.filter { !(old && $0.lat != nil) }.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })   // positions of an old index are read again
            }
            let first = shown.filter { $0.lat != nil }.map(PhotoItem.init)
            let shownCount = max(shown.count, loaded.count)
            await MainActor.run {
                guard gen == self.generation else { return }
                self.items = first; self.fileCount = shownCount; NotificationCenter.default.post(name: .photosChanged, object: nil)
            }
            await self.scan(folder: f, known: loaded, gen: gen)
        }
    }

    func setFolder(_ url: URL?) {
        folderPath = url?.path
        if url != nil {                                  // a chosen folder switches the photos on
            UserDefaults.standard.set(true, forKey: "photosOn")
            NotificationCenter.default.post(name: .photosEnabledChanged, object: nil)
        }
        if let p = url?.path { UserDefaults.standard.set(p, forKey: "photoFolder") } else { UserDefaults.standard.removeObject(forKey: "photoFolder") }
        items = []; fileCount = 0; status = ""; NotificationCenter.default.post(name: .photosChanged, object: nil)
        started = false
        if url != nil { start() } else { generation += 1; try? FileManager.default.removeItem(at: Self.indexURL) }
    }

    func rescan() { started = false; start() }

    /// Asks for the photo folder; returns false when cancelled.
    @discardableResult
    func chooseFolder() -> Bool {
        let p = NSOpenPanel()
        p.message = "Choose a folder with photos. (read only - no files are added, removed or altered)"
        p.prompt = "Use This Folder"
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = false
        if let f = folderPath { p.directoryURL = URL(fileURLWithPath: f) }
        guard p.runModal() == .OK, let u = p.url else { return false }
        setFolder(u)
        return true
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: Self.cacheDir)
        PhotoThumbs.shared.clearMemory()
        if folderPath != nil { items = []; fileCount = 0; NotificationCenter.default.post(name: .photosChanged, object: nil); rescan() }
    }

    func cacheUsage() -> String {
        var bytes: Int64 = 0
        if let en = FileManager.default.enumerator(at: Self.cacheDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let u as URL in en { bytes += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static let exts: Set<String> = ["jpg", "jpeg", "heic", "heif", "tif", "tiff", "png"]   // RAW formats are ignored on purpose

    nonisolated private func scan(folder: String, known: [String: PhotoEntry], gen: Int) async {
        let root = URL(fileURLWithPath: folder)
        var files: [(URL, Double, Int64)] = []
        if let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                                                   options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let u as URL in en where Self.exts.contains(u.pathExtension.lowercased()) {
                guard let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]), v.isRegularFile == true else { continue }
                files.append((u, v.contentModificationDate?.timeIntervalSince1970 ?? 0, Int64(v.fileSize ?? 0)))
            }
        }
        var result = [PhotoEntry?](repeating: nil, count: files.count)
        var todo: [Int] = []
        for (i, f) in files.enumerated() {
            if let k = known[f.0.path], k.mtime == f.1, k.size == f.2 { result[i] = k } else { todo.append(i) }
        }
        let total = todo.count
        let box = ResultBox(count: files.count)
        func snapshot() -> [PhotoEntry] { (0..<files.count).compactMap { result[$0] ?? box[$0] } }
        func publish(_ entries: [PhotoEntry], final: Bool) async {
            let idx = Index(folder: folder, entries: entries, rev: Self.indexRev)
            try? FileManager.default.createDirectory(at: Self.cacheDir, withIntermediateDirectories: true)
            if let d = try? JSONEncoder().encode(idx) { try? d.write(to: Self.indexURL, options: .atomic) }
            let list = entries.filter { $0.lat != nil }.map(PhotoItem.init)
            await MainActor.run {
                guard gen == self.generation else { return }
                self.items = list; self.fileCount = entries.count; if final { self.status = "" }; NotificationCenter.default.post(name: .photosChanged, object: nil)
            }
        }
        if total > 0 {
            let chunk = 300
            var lastPublish = Date()
            var from = 0
            while from < total {
                let to = min(from + chunk, total)
                // a few cores stay free, so the rest of the app (folder tree, map) is not starved while the photos are read
                let workers = max(2, ProcessInfo.processInfo.activeProcessorCount - 4)
                let next = NextIndex(from)
                DispatchQueue.concurrentPerform(iterations: workers) { _ in
                    while let i0 = next.take(below: to) {
                        let i = todo[i0]
                        let f = files[i]
                        box[i] = Self.readMetadata(f.0, mtime: f.1, size: f.2)      // every index is written by one thread only
                    }
                }
                from = to
                let stale = await MainActor.run { () -> Bool in
                    if gen == self.generation { self.status = "Reading photos … \(from) of \(total)" }
                    return gen != self.generation
                }
                if stale { return }
                if Date().timeIntervalSince(lastPublish) > 20, from < total {            // photos found so far are shown while the rest is read
                    await publish(snapshot(), final: false); lastPublish = Date()
                }
            }
        }
        for i in todo { result[i] = box[i] }
        await publish(result.compactMap { $0 }, final: true)
    }

    /// Hands out the numbers from..<limit to several threads, each number once.
    private final class NextIndex: @unchecked Sendable {
        private var n: Int; private let lock = NSLock()
        init(_ start: Int) { n = start }
        func take(below limit: Int) -> Int? { lock.lock(); defer { lock.unlock() }; guard n < limit else { return nil }; n += 1; return n - 1 }
    }

    /// Fixed-size storage that several threads may fill at the same time, each writing different positions.
    private final class ResultBox: @unchecked Sendable {
        private let p: UnsafeMutablePointer<PhotoEntry?>
        private let n: Int
        init(count: Int) { n = count; p = .allocate(capacity: max(count, 1)); p.initialize(repeating: nil, count: max(count, 1)) }
        deinit { p.deinitialize(count: max(n, 1)); p.deallocate() }
        subscript(i: Int) -> PhotoEntry? { get { p[i] } set { p[i] = newValue } }
    }

    /// Reads position, date and camera from the photo's metadata (the picture itself is not decoded).
    nonisolated private static func readMetadata(_ url: URL, mtime: Double, size: Int64) -> PhotoEntry {
        var e = PhotoEntry(path: url.path, mtime: mtime, size: size, lat: nil, lon: nil, date: mtime, camera: nil)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return e }
        var gpsUTC: Date?
        if let g = p[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           var lat = g[kCGImagePropertyGPSLatitude] as? Double, var lon = g[kCGImagePropertyGPSLongitude] as? Double {
            // the hemisphere comes from the reference letters (the numbers are normally unsigned; some files carry a sign as well)
            switch (g[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased() { case "S": lat = -abs(lat); case "N": lat = abs(lat); default: break }
            switch (g[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased() { case "W": lon = -abs(lon); case "E": lon = abs(lon); default: break }
            // GPSStatus "V" = the receiver had no valid fix: the position is the last known one, often far away
            let noFix = (g[kCGImagePropertyGPSStatus] as? String)?.uppercased().hasPrefix("V") == true
            if !noFix, abs(lat) <= 90, abs(lon) <= 180, !(abs(lat) < 0.001 && abs(lon) < 0.001) { e.lat = lat; e.lon = lon }
            if let ds = g[kCGImagePropertyGPSDateStamp] as? String, let ts = g[kCGImagePropertyGPSTimeStamp] as? String {
                gpsUTC = parse(ds + " " + String(ts.prefix(8)), zone: TimeZone(identifier: "UTC")!)
            }
        }
        let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let taken = exif?[kCGImagePropertyExifDateTimeOriginal] as? String ?? exif?[kCGImagePropertyExifDateTimeDigitized] as? String
        if let s = taken {
            if let off = exif?["OffsetTimeOriginal" as CFString] as? String, let z = zoneFrom(off), let d = parse(s, zone: z) { e.date = d.timeIntervalSince1970 }
            else if let u = gpsUTC { e.date = u.timeIntervalSince1970 }
            else if let d = parse(s, zone: .current) { e.date = d.timeIntervalSince1970 }
        } else if let u = gpsUTC { e.date = u.timeIntervalSince1970 }
        if let t = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            let make = (t[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let model = (t[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let name = model.lowercased().hasPrefix(make.lowercased()) ? model : (make + " " + model).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { e.camera = name }
        }
        return e
    }

    nonisolated private static func zoneFrom(_ s: String) -> TimeZone? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count >= 6, let sign = t.first, sign == "+" || sign == "-" else { return nil }
        let h = Int(t.dropFirst().prefix(2)) ?? 0, m = Int(t.suffix(2)) ?? 0
        return TimeZone(secondsFromGMT: (sign == "-" ? -1 : 1) * (h * 3600 + m * 60))
    }

    /// "yyyy:MM:dd HH:mm:ss" (or with dashes).
    nonisolated private static func parse(_ s: String, zone: TimeZone) -> Date? {
        let n = s.split(whereSeparator: { ": -T".contains($0) }).compactMap { Int($0) }
        guard n.count >= 6 else { return nil }
        var c = DateComponents(); c.year = n[0]; c.month = n[1]; c.day = n[2]; c.hour = n[3]; c.minute = n[4]; c.second = n[5]
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        return cal.date(from: c)
    }
}

// MARK: Thumbnails

final class PhotoThumbs {
    static let shared = PhotoThumbs()
    private let mem = NSCache<NSString, NSImage>()
    private let queue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 4; q.qualityOfService = .utility; return q }()
    private let lock = NSLock()
    private var waiting: [String: [(NSImage?) -> Void]] = [:]

    init() { mem.countLimit = 3000 }

    func clearMemory() { mem.removeAllObjects() }

    private func key(_ it: PhotoItem) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in (it.path + "|\(it.mtime)|v2").utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    func cached(_ it: PhotoItem) -> NSImage? { mem.object(forKey: key(it) as NSString) }

    /// Calls `done` on the main thread with the thumbnail (made once, then kept on disk).
    func load(_ it: PhotoItem, done: @escaping (NSImage?) -> Void) {
        let k = key(it)
        if let i = mem.object(forKey: k as NSString) { done(i); return }
        lock.lock()
        if waiting[k] != nil { waiting[k]!.append(done); lock.unlock(); return }
        waiting[k] = [done]
        lock.unlock()
        queue.addOperation { [self] in
            let disk = PhotoStore.thumbDir.appendingPathComponent(k + ".jpg")
            var img: NSImage?
            if let d = try? Data(contentsOf: disk) { img = NSImage(data: d) }
            if img == nil, let cg = Self.makeThumb(URL(fileURLWithPath: it.path), maxPixel: 320) {
                try? FileManager.default.createDirectory(at: PhotoStore.thumbDir, withIntermediateDirectories: true)
                if let dst = CGImageDestinationCreateWithURL(disk as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(dst, cg, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
                    CGImageDestinationFinalize(dst)
                }
                img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
            if let i = img { mem.setObject(i, forKey: k as NSString) }
            lock.lock(); let cbs = waiting.removeValue(forKey: k) ?? []; lock.unlock()
            DispatchQueue.main.async { for c in cbs { c(img) } }
        }
    }

    /// A larger version for the viewer.
    func full(_ path: String, done: @escaping (NSImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var img: NSImage?
            if let cg = Self.makeThumb(URL(fileURLWithPath: path), maxPixel: 4096) { img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
            DispatchQueue.main.async { done(img) }
        }
    }

    private static func makeThumb(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let o: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,   // not the small preview embedded in the file
                                   kCGImageSourceCreateThumbnailWithTransform: true,
                                  kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, o as CFDictionary)
    }
}

// MARK: Which photos are shown

final class PhotoMapCache {
    var key = ""
    var items: [PhotoItem] = []
}

extension AppModel {
    /// Photos for the map: all of them, or only those close to the selected track (about 300 m).
    func photoItemsForMap() -> (items: [PhotoItem], token: Int) {
        let all = photos.items
        guard photosAlongTrack, let id = foregroundPath, let f = tracks.first(where: { $0.id == id }), !f.isWaypointFile else {
            return (all, all.count &* 31 &+ photoRevision)
        }
        let key = "\(id)|\(photoRevision)|\(f.segments.reduce(0) { $0 + $1.count })"
        if photoCache.key == key { return (photoCache.items, key.hashValue) }
        var cells = Set<Int64>()
        var lat0 = 45.0
        if let s = f.segments.first, s.count >= 2 { lat0 = Merc.lat(y: s[1]) }
        let cell = 300.0 / (cos(lat0 * .pi / 180) * 40_075_017)
        func cellKey(_ x: Double, _ y: Double) -> Int64 { Int64(floor(x / cell)) &* 4_000_037 &+ Int64(floor(y / cell)) }
        for seg in f.segments {
            var i = 0
            var px = 0.0, py = 0.0
            while i + 1 < seg.count {
                let x = seg[i], y = seg[i + 1]
                if i > 0 {
                    let n = Int(max(abs(x - px), abs(y - py)) / (cell / 2))
                    if n > 1 { for k in 1..<n { let t = Double(k) / Double(n); cells.insert(cellKey(px + (x - px) * t, py + (y - py) * t)) } }
                }
                cells.insert(cellKey(x, y)); px = x; py = y; i += 2
            }
        }
        let out = all.filter { it in
            let cx = Int64(floor(it.x / cell)), cy = Int64(floor(it.y / cell))
            for dx in -1...1 { for dy in -1...1 where cells.contains((cx + Int64(dx)) &* 4_000_037 &+ (cy + Int64(dy))) { return true } }
            return false
        }
        photoCache.key = key; photoCache.items = out
        return (out, key.hashValue)
    }

    /// At the start: no photo folder yet -> the folder dialog appears by itself.
    func askPhotoFolderIfNeeded() {
        guard photos.folderPath == nil, !UserDefaults.standard.bool(forKey: "photoFolderDeclined") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
            guard photos.folderPath == nil else { return }
            NSApp.activate(ignoringOtherApps: true)
            if !photos.chooseFolder() { UserDefaults.standard.set(true, forKey: "photoFolderDeclined") }   // after a cancel: only in the settings
        }
    }

    /// The switch in the settings (or a newly chosen folder) turns the photos on or off.
    func observePhotoSetting() {
        photoChangeObs = NotificationCenter.default.addObserver(forName: .photosChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.photoRevision += 1 }
        }
        photoObs = NotificationCenter.default.addObserver(forName: .photosEnabledChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let on = UserDefaults.standard.bool(forKey: "photosOn")
                if on != self.photosOn { self.photosOn = on }
            }
        }
    }

    func togglePhotos() {
        if !photosOn, photos.folderPath == nil { guard photos.chooseFolder() else { return }; if photosOn { photos.start(); return } }
        photosOn.toggle()
        if photosOn { photos.start() } else { photoStrip = nil }
    }

    func openPhotoStrip(_ list: [PhotoItem]) {
        photoStrip = list.sorted { $0.date > $1.date }
        showProfile = showProfile    // the strip replaces the elevation profile while it is open
    }
}

// MARK: Strip at the bottom

struct PhotoStripView: View {
    @EnvironmentObject var model: AppModel
    let items: [PhotoItem]
    @StateObject private var pan = PanState()
    private let w: CGFloat = 132, gap: CGFloat = 10

    final class PanState: ObservableObject { @Published var offset: CGFloat = 0; var start: CGFloat = 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(items.count) photo\(items.count == 1 ? "" : "s") here").font(.headline)
                Spacer()
                Button { model.photoStrip = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("Close the photo strip (Esc)")
            }
            GeometryReader { geo in
                let maxOffset = max(0, CGFloat(items.count) * (w + gap) - gap - geo.size.width)
                ZStack {
                    HStack(spacing: gap) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, it in      // identity = the photo, so the thumbnails are replaced when another stamp is clicked
                            PhotoThumbView(item: it, width: w).onTapGesture { model.photoViewIndex = i }
                        }
                    }
                    .offset(x: -min(max(pan.offset, 0), maxOffset))
                    .frame(width: geo.size.width, alignment: .leading)
                    .gesture(DragGesture(minimumDistance: 6)
                        .onChanged { v in pan.offset = min(max(pan.start - v.translation.width, 0), maxOffset) }
                        .onEnded { _ in pan.start = pan.offset })
                    HStack {
                        if pan.offset > 1 { arrow("chevron.left") { move(-(w + gap) * 3, maxOffset) } }
                        Spacer()
                        if pan.offset < maxOffset - 1 { arrow("chevron.right") { move((w + gap) * 3, maxOffset) } }
                    }
                }
                .clipped()
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.bar)
        .onChange(of: items.map(\.id)) { _ in pan.offset = 0; pan.start = 0 }
    }

    private func move(_ d: CGFloat, _ maxOffset: CGFloat) {
        withAnimation(.easeOut(duration: 0.25)) { pan.offset = min(max(pan.offset + d, 0), maxOffset) }
        pan.start = min(max(pan.start + d, 0), maxOffset)
    }

    private func arrow(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 16, weight: .bold)).frame(width: 30, height: 56)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }
}

struct PhotoThumbView: View {
    let item: PhotoItem
    let width: CGFloat
    @StateObject private var holder = ImageHolder()
    final class ImageHolder: ObservableObject { @Published var image: NSImage? }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.2))
                if let i = holder.image { Image(nsImage: i).resizable().scaledToFill() }
            }
            .frame(width: width, height: width * 0.75).clipShape(RoundedRectangle(cornerRadius: 4))
            Text(item.shortDate).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onAppear { if holder.image == nil { PhotoThumbs.shared.load(item) { holder.image = $0 } } }
    }
}

// MARK: Large view

struct PhotoViewer: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var holder = PhotoThumbView.ImageHolder()
    var items: [PhotoItem] { model.photoStrip ?? [] }
    var index: Int { min(max(model.photoViewIndex ?? 0, 0), max(items.count - 1, 0)) }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(items.indices.contains(index) ? URL(fileURLWithPath: items[index].path).lastPathComponent : "").font(.headline).lineLimit(1)
                Spacer()
                Text("\(index + 1) / \(items.count)").foregroundStyle(.secondary)
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").imageScale(.large).foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("Close (Esc)")
            }
            ZStack {
                Color.black.opacity(0.85)
                if let i = holder.image { Image(nsImage: i).resizable().scaledToFit() } else { ProgressView() }
                HStack {
                    Button { step(-1) } label: { Image(systemName: "chevron.left").font(.system(size: 22, weight: .bold)).frame(width: 36, height: 60) }
                        .buttonStyle(.plain).foregroundStyle(.white).opacity(index > 0 ? 0.9 : 0.2).keyboardShortcut(.leftArrow, modifiers: [])
                    Spacer()
                    Button { step(1) } label: { Image(systemName: "chevron.right").font(.system(size: 22, weight: .bold)).frame(width: 36, height: 60) }
                        .buttonStyle(.plain).foregroundStyle(.white).opacity(index < items.count - 1 ? 0.9 : 0.2).keyboardShortcut(.rightArrow, modifiers: [])
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            if items.indices.contains(index) {
                let it = items[index]
                VStack(alignment: .leading, spacing: 2) {
                    Text(it.path).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                    Text(it.longDate)
                    Text("Camera: " + (it.camera.isEmpty ? "unknown" : it.camera))
                    Text(String(format: "Position: %.5f, %.5f", it.lat, it.lon)).foregroundStyle(.secondary)
                }
                .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("") { dismiss() }.keyboardShortcut(.cancelAction).frame(width: 0, height: 0).opacity(0)
        }
        .padding(14).frame(minWidth: 700, idealWidth: 980, minHeight: 560, idealHeight: 760)
        .onAppear(perform: load).onChange(of: model.photoViewIndex) { _ in load() }
    }

    private func step(_ d: Int) { let n = index + d; if items.indices.contains(n) { model.photoViewIndex = n } }

    private func load() {
        guard items.indices.contains(index) else { return }
        let path = items[index].path
        holder.image = nil
        PhotoThumbs.shared.full(path) { img in if items.indices.contains(index), items[index].path == path { holder.image = img } }
    }
}

/// Sheet for the large view.
struct PhotoHook: ViewModifier {
    @EnvironmentObject var model: AppModel
    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { model.photoViewIndex != nil }, set: { if !$0 { model.photoViewIndex = nil } })) {
            PhotoViewer().environmentObject(model)
        }
    }
}

// MARK: Toolbar button and panel

struct PhotoButton: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var open = FlagState()
    var body: some View {
        ToolButton(model.photosOn ? "photo.stack.fill" : "photo.stack", "Photos on the map (click: on/off, right-click or ⌥-click: options)", on: model.photosOn) {
            if NSEvent.modifierFlags.contains(.option) { open.on.toggle() } else { model.togglePhotos() }
        }
        .contextMenu { Button("Photo Options …") { open.on = true } }
        .popover(isPresented: $open.on) { PhotoPanel().environmentObject(model) }
    }
}

struct PhotoPanel: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var store = PhotoStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Photos").font(.headline)
            Toggle("Show photos on the map", isOn: Binding(get: { model.photosOn }, set: { _ in model.togglePhotos() }))
            Toggle("Only along the selected track", isOn: $model.photosAlongTrack)
            Divider()
            Text(store.folderPath ?? "No photo folder chosen").lineLimit(2).truncationMode(.middle).font(.caption).foregroundStyle(.secondary)
            Text("\(store.items.count) photos with GPS (of \(store.fileCount) photo files)").font(.caption)
            if !store.status.isEmpty { Text(store.status).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Choose Folder …") { store.chooseFolder() }
                Button("Rescan") { store.rescan() }.disabled(store.folderPath == nil)
            }
            Text("The photo folder is only read. No files are added, removed or altered.").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14).frame(width: 300)
    }
}

extension Notification.Name { static let photosChanged = Notification.Name("photosChanged"); static let photosEnabledChanged = Notification.Name("photosEnabledChanged") }

struct PhotoSettingsSection: View {
    @ObservedObject var store = PhotoStore.shared
    @AppStorage("photosOn") private var photosOn = false
    @StateObject private var u = UsageHolder()
    final class UsageHolder: ObservableObject { @Published var text = "" }
    var body: some View {
        Section {
            Text("Photos with GPS data are shown on the map as small stamps. The folder (and all its sub-folders) is only read: no files are added, removed or altered.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Show photos on the map", isOn: $photosOn)
                .disabled(store.folderPath == nil)
                .onChange(of: photosOn) { on in
                    NotificationCenter.default.post(name: .photosEnabledChanged, object: nil)
                    if on { store.start() }
                }
            HStack {
                Text(store.folderPath ?? "No folder chosen").lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer()
                Button("Choose …") { store.chooseFolder() }
            }
            HStack {
                Text("\(store.items.count) photos with GPS, \(store.fileCount) files" + (store.status.isEmpty ? "" : " · " + store.status)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Rescan") { store.rescan() }.disabled(store.folderPath == nil)
                Button("Remove Folder") { store.setFolder(nil) }.disabled(store.folderPath == nil)
            }
            HStack {
                Text("Photo cache (index and thumbnails) in the online map cache folder: " + u.text).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear Photo Cache") { store.clearCache(); u.text = store.cacheUsage() }
            }
        } header: { Text("Photos").font(.headline) }
        .onAppear { u.text = store.cacheUsage() }
    }
}

/// Small notice at the top right of the map while the photo folder is being read.
struct PhotoStatusOverlay: View {
    @ObservedObject var store = PhotoStore.shared
    var body: some View {
        if !store.status.isEmpty {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(store.status).font(.caption) }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                .padding(10).allowsHitTesting(false)
        }
    }
}
