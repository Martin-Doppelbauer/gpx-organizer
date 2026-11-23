import Foundation
import CoreGraphics

/// Average-speed limits (km/h) used to tell hikes, bike rides and car trips apart; between two classes the kind stays "unknown".
public struct KindThresholds: Equatable {
    public var hikeMax = 7.5, bikeMin = 9.0, bikeMax = 30.0, carMin = 36.0
    public init() {}
    public static let standard = KindThresholds()
}

public enum TrackKind: String, CaseIterable {
    case planned, hike, bike, car, other
    public var title: String {
        switch self { case .planned: return "Planned"; case .hike: return "Hike"; case .bike: return "Bike ride"; case .car: return "Car / motorcycle"; case .other: return "Track" }
    }
    public var iconName: String {
        switch self { case .planned: return "pencil.and.ruler.fill"; case .hike: return "figure.hiking"
        case .bike: return "figure.outdoor.cycle"; case .car: return "car.fill"
        case .other: return "point.topleft.down.to.point.bottomright.curvepath" }
    }
}

public struct Waypoint {
    public let x: Double, y: Double
    public let name: String
    public let sym: String          // Garmin symbol name, e.g. "Flag, Blue"
    // marker attributes written by GPX Organizer (extensions inside <wpt>)
    public var desc = ""            // <desc>, shown as the tooltip
    public var iconID: String?      // gpxorg:micon
    public var colorHex: String?    // gpxorg:mcolor, "RRGGBB"
    public var size: Double?        // gpxorg:msize, factor (0.8 small, 1 medium, 1.4 large)
    public var index = 0            // position among the <wpt> elements of the file
    public init(x: Double, y: Double, name: String, sym: String = "") { self.x = x; self.y = y; self.name = name; self.sym = sym }

    /// Color for the map marker, derived from the symbol name (Garmin names carry a color: "Flag, Blue", "Circle, Red" …).
    public var rgb: [Double] { Waypoint.rgb(forSymbol: sym) }
    /// SF Symbol name used as the glyph for this waypoint's Garmin symbol.
    public var iconName: String { Waypoint.iconName(forSymbol: sym) }
    public static func iconName(forSymbol sym: String) -> String {
        let s = sym.lowercased()
        let table: [(String, String)] = [
            ("city (large)", "building.2.fill"), ("city (medium)", "building.2"), ("city", "building"),
            ("flag", "flag.fill"), ("summit", "mountain.2.fill"), ("parking", "parkingsign"),
            ("navaid", "antenna.radiowaves.left.and.right"), ("bank", "banknote"), ("trail head", "figure.hiking"),
            ("boat ramp", "sailboat.fill"), ("triangle", "triangle.fill"), ("lodge", "bed.double.fill"),
            ("circle", "circle.fill"), ("restaurant", "fork.knife"), ("park", "tree.fill"), ("shower", "drop.fill"),
            ("residence", "house.fill"), ("scenic", "binoculars.fill"), ("campground", "tent.fill"),
            ("pin", "pin.fill"), ("waypoint", "mappin")]
        for (k, v) in table where s.contains(k) { return v }
        return "mappin"
    }

    /// Color order of an arbitrary color: the nearest of the standard colors.
    public static func colorRank(rgb c: [Double]) -> Int {
        let table: [([Double], Int)] = [([0.90, 0.12, 0.12], 0), ([0.95, 0.50, 0.10], 1), ([0.95, 0.80, 0.05], 2),
            ([0.10, 0.65, 0.25], 3), ([0.0, 0.62, 0.65], 4), ([0.10, 0.35, 0.95], 5), ([0.55, 0.25, 0.70], 6),
            ([0.55, 0.33, 0.15], 7), ([0.25, 0.35, 0.60], 8), ([0.45, 0.45, 0.45], 9)]
        return table.min { d($0.0, c) < d($1.0, c) }?.1 ?? 10
        func d(_ a: [Double], _ b: [Double]) -> Double { (a[0]-b[0])*(a[0]-b[0]) + (a[1]-b[1])*(a[1]-b[1]) + (a[2]-b[2])*(a[2]-b[2]) }
    }

    /// "RRGGBB" -> 0…1 components.
    public static func rgb(fromHex h: String) -> [Double]? {
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return [Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255]
    }

    /// Position of the color in the list order: red, orange, yellow, green, teal, blue, purple, brown, grey.
    public var colorRank: Int { Waypoint.colorRank(forSymbol: sym) }
    public static func colorRank(forSymbol sym: String) -> Int {
        let c = rgb(forSymbol: sym)
        let table: [([Double], Int)] = [([0.90, 0.12, 0.12], 0), ([0.95, 0.50, 0.10], 1), ([1.0, 0.5, 0.0], 1), ([0.95, 0.80, 0.05], 2),
            ([0.10, 0.65, 0.25], 3), ([0.0, 0.62, 0.65], 4), ([0.10, 0.35, 0.95], 5), ([0.55, 0.25, 0.70], 6),
            ([0.55, 0.33, 0.15], 7), ([0.25, 0.35, 0.60], 8), ([0.45, 0.45, 0.45], 9)]
        return table.first { $0.0 == c }?.1 ?? 10
    }
    public static func rgb(forSymbol sym: String) -> [Double] {
        let s = sym.lowercased()
        if s.contains("blue") { return [0.10, 0.35, 0.95] }
        if s.contains("red") { return [0.90, 0.12, 0.12] }
        if s.contains("green") { return [0.10, 0.65, 0.25] }
        if s.contains("yellow") { return [0.95, 0.80, 0.05] }
        if s.contains("orange") { return [1.0, 0.5, 0.0] }
        if s.contains("summit") || s.contains("peak") { return [0.55, 0.33, 0.15] }
        if s.contains("parking") { return [0.25, 0.35, 0.60] }
        if s.contains("city (large)") { return [0.90, 0.12, 0.12] }
        if s.contains("city (medium)") { return [0.95, 0.50, 0.10] }
        if s.contains("city") { return [0.95, 0.80, 0.05] }
        if s.contains("lodge") || s.contains("residence") { return [0.55, 0.25, 0.70] }
        if s.contains("trail head") { return [0.0, 0.62, 0.65] }
        return [0.95, 0.50, 0.10]
    }
}

public final class GPXFile: Identifiable {
    public let url: URL
    public var id: String { url.path }
    public var name: String
    /// Track segments as interleaved Web-Mercator x,y (0..1).
    public var segments: [[Double]] = []
    public var waypoints: [Waypoint] = []
    public var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
    public var distance: Double = 0       // metres
    public var ascent: Double = 0         // metres
    public var displayColor: String?
    // facts used to tell planned tracks, hikes, bike rides and car/motorcycle trips apart
    public var hasTime = false             // any trackpoint carries a timestamp
    public var movingSeconds = 0.0         // time between consecutive timed points (gaps > 3 min ignored)
    public var movingMeters = 0.0          // distance covered during that time
    public var pointTotal = 0
    public var isRouteElement = false      // came from <rte>
    public var hint: String?               // <type> of the track, if any
    /// Icon chosen by the user (SF Symbol name); overrides the automatic one.
    public var iconOverride: String?
    /// Icon name found inside the file (`gpxorg:icon`).
    public var embeddedIcon: String?
    public var embeddedColor: String?        // gpxorg:color, "RRGGBB"
    public var embeddedIconColor: String?    // gpxorg:iconcolor, "RRGGBB"
    public var embeddedWidth: Double?        // gpxorg:width, points
    public var hue: CGFloat
    private var lodCache: [Int: [[Double]]] = [:]
    private let lodLock = NSLock()

    init(url: URL) {
        self.url = url
        self.name = url.deletingPathExtension().lastPathComponent
        var h: UInt64 = 1469598103934665603
        for b in url.path.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        self.hue = CGFloat(h % 360) / 360
    }

    public var isEmpty: Bool { segments.isEmpty && waypoints.isEmpty }

    /// Average speed while moving, km/h (nil without usable timestamps).
    public var movingSpeedKmh: Double? {
        movingSeconds >= 60 && movingMeters >= 300 ? movingMeters / movingSeconds * 3.6 : nil
    }

    public static var kindThresholds = KindThresholds()

    /// Best guess of what kind of track this is: from the file's own type, else from timestamps and speed.
    public var kind: TrackKind {
        if let h = hint?.lowercased() {
            if ["mtb", "mountain", "bik", "cycl", "rad", "ride"].contains(where: h.contains) { return .bike }
            if ["hik", "walk", "trek", "wander", "foot", "run", "jog"].contains(where: h.contains) { return .hike }
            if ["car", "auto", "drive", "motor"].contains(where: h.contains) { return .car }
        }
        if isRouteElement || !hasTime { return .planned }
        // timestamps but no clear speed pattern: neutral track icon
        guard let v = movingSpeedKmh else { return .other }
        let t = GPXFile.kindThresholds
        if v < t.hikeMax { return .hike }
        if v < t.bikeMin { return .other }          // fast hike or slow bike ride
        if v < t.bikeMax { return .bike }
        if v < t.carMin { return .other }           // fast bike ride or slow car trip
        return .car
    }

    /// A file that only holds waypoints (no track or route).
    public var isWaypointFile: Bool { segments.isEmpty && !waypoints.isEmpty }

    /// Waypoint-only files get their bounds from the waypoints.
    public func boundsFromWaypointsIfNeeded() {
        guard segments.isEmpty else { return }
        for w in waypoints { minX = min(minX, w.x); maxX = max(maxX, w.x); minY = min(minY, w.y); maxY = max(maxY, w.y) }
    }

    /// Segments thinned so that consecutive points are at least ~`step` apart (Web-Mercator units); cached per power-of-two level.
    public func lodSegments(step: Double) -> [[Double]] {
        let base = 1.5e-8
        guard step > base * 2 else { return segments }
        let k = max(1, Int(floor(log2(step / base))))
        lodLock.lock()
        if let c = lodCache[k] { lodLock.unlock(); return c }
        lodLock.unlock()
        let st = base * pow(2.0, Double(k))
        var out: [[Double]] = []
        out.reserveCapacity(segments.count)
        for seg in segments {
            var r: [Double] = []
            var lx = -1.0, ly = -1.0
            var i = 0
            while i + 1 < seg.count {
                if r.isEmpty || abs(seg[i] - lx) >= st || abs(seg[i + 1] - ly) >= st {
                    r.append(seg[i]); r.append(seg[i + 1]); lx = seg[i]; ly = seg[i + 1]
                }
                i += 2
            }
            if seg.count >= 2, r.count >= 2, (r[r.count - 2] != seg[seg.count - 2] || r[r.count - 1] != seg[seg.count - 1]) {
                r.append(seg[seg.count - 2]); r.append(seg[seg.count - 1])
            }
            out.append(r)
        }
        lodLock.lock(); lodCache[k] = out; lodLock.unlock()
        return out
    }

    /// Color from the Garmin DisplayColor extension, falling back to a per-file hue.
    public var color: CGColor {
        let table: [String: (CGFloat, CGFloat, CGFloat)] = [
            "Black": (0, 0, 0), "DarkRed": (0.55, 0, 0), "DarkGreen": (0, 0.45, 0), "DarkYellow": (0.6, 0.55, 0),
            "DarkBlue": (0, 0, 0.6), "DarkMagenta": (0.55, 0, 0.55), "DarkCyan": (0, 0.5, 0.55),
            "LightGray": (0.75, 0.75, 0.75), "DarkGray": (0.4, 0.4, 0.4), "Red": (0.95, 0.1, 0.1),
            "Green": (0.1, 0.75, 0.1), "Yellow": (0.95, 0.85, 0), "Blue": (0.1, 0.2, 0.95),
            "Magenta": (0.9, 0.1, 0.8), "Cyan": (0, 0.8, 0.9)]
        if let c = displayColor, let t = table[c] { return CGColor(red: t.0, green: t.1, blue: t.2, alpha: 1) }
        return NSColorLike.hsb(hue, 0.85, 0.85)
    }

    /// Fast path first (direct byte scan, ~10x quicker); falls back to the XML parser for unusual files.
    public static func load(_ url: URL) -> GPXFile? {
        if url.pathExtension.lowercased() != "gpx" {
            guard let doc = ForeignTracks.parse(url) else { return nil }
            return from(document: doc, url: url)
        }
        if let f = loadFast(url) { return f }
        return loadXML(url)
    }

    /// Builds the display model (decimated geometry, distance, ascent) from an already parsed document.
    public static func from(document: GPXDocument, url: URL) -> GPXFile? {
        let f = GPXFile(url: url)
        let d = Delegate(f)
        for t in document.tracks {
            for seg in t.segments {
                d.flush()
                for p in seg { d.ptLat = p.lat; d.ptLon = p.lon; d.ptEle = p.ele; d.ptTime = p.time.flatMap { isoSeconds($0) }; d.addPoint() }
            }
        }
        d.finish()
        for w in document.waypoints { f.waypoints.append(Waypoint(x: Merc.x(lon: w.point.lon), y: Merc.y(lat: w.point.lat), name: w.name, sym: w.sym)) }
        f.boundsFromWaypointsIfNeeded()
        return f.isEmpty ? nil : f
    }

    public static func loadXML(_ url: URL) -> GPXFile? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let f = GPXFile(url: url)
        let p = XMLParser(data: data)
        let d = Delegate(f)
        p.delegate = d
        p.shouldProcessNamespaces = false
        p.parse()
        d.finish()
        f.boundsFromWaypointsIfNeeded()
        return f.isEmpty ? nil : f
    }

    // MARK: fast scanner

    private static func up(_ r: UnsafeMutableRawPointer) -> UnsafePointer<UInt8> { UnsafePointer(r.assumingMemoryBound(to: UInt8.self)) }

    private static func eq(_ p: UnsafePointer<UInt8>, _ len: Int, _ s: StaticString) -> Bool {
        len == s.utf8CodeUnitCount && memcmp(p, s.utf8Start, len) == 0
    }

    private static func parseDouble(_ p: UnsafePointer<UInt8>, _ end: UnsafePointer<UInt8>) -> Double? {
        var q = p
        var neg = false
        if q < end, q.pointee == 0x2D { neg = true; q += 1 } else if q < end, q.pointee == 0x2B { q += 1 }
        var v = 0.0
        var digits = 0
        while q < end, q.pointee >= 0x30, q.pointee <= 0x39 { v = v * 10 + Double(q.pointee - 0x30); q += 1; digits += 1 }
        if q < end, q.pointee == 0x2E {
            q += 1
            var scale = 0.1
            while q < end, q.pointee >= 0x30, q.pointee <= 0x39 { v += Double(q.pointee - 0x30) * scale; scale *= 0.1; q += 1; digits += 1 }
        }
        if digits == 0 { return nil }
        if q < end, q.pointee == 0x65 || q.pointee == 0x45 {
            q += 1
            var eneg = false
            if q < end, q.pointee == 0x2D { eneg = true; q += 1 } else if q < end, q.pointee == 0x2B { q += 1 }
            var e = 0
            while q < end, q.pointee >= 0x30, q.pointee <= 0x39 { e = e * 10 + Int(q.pointee - 0x30); q += 1 }
            v *= pow(10, Double(eneg ? -e : e))
        }
        return neg ? -v : v
    }

    /// Value of attribute `name=` (e.g. "lat=") inside [from, to), parsed as a number.
    private static func attrNumber(_ from: UnsafePointer<UInt8>, _ to: UnsafePointer<UInt8>, _ key: StaticString) -> Double? {
        guard let hit = memmem(from, to - from, key.utf8Start, key.utf8CodeUnitCount) else { return nil }
        var q = up(hit) + key.utf8CodeUnitCount
        if q < to, q.pointee == 0x22 || q.pointee == 0x27 { q += 1 }
        return parseDouble(q, to)
    }

    /// Text between `<tag>` (found in [from, to)) and the next '<'.
    private static func textOf(_ from: UnsafePointer<UInt8>, _ to: UnsafePointer<UInt8>, _ open: StaticString) -> String? {
        guard let hit = memmem(from, to - from, open.utf8Start, open.utf8CodeUnitCount) else { return nil }
        let s = up(hit) + open.utf8CodeUnitCount
        guard let lt = memchr(s, 0x3C, to - s) else { return nil }
        let e = up(lt)
        let str = String(decoding: UnsafeBufferPointer(start: s, count: e - s), as: UTF8.self)
        return str.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func loadFast(_ url: URL) -> GPXFile? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count > 30 else { return nil }
        let f = GPXFile(url: url)
        let d = Delegate(f)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let end = base + raw.count
            // color extension normally sits near the top of the file
            if let c = textOf(base, min(end, base + 200_000), "DisplayColor>") { f.displayColor = c }
            if let ic = textOf(base, min(end, base + 200_000), "<gpxorg:icon>"), !ic.isEmpty { f.embeddedIcon = ic }
            if let c = textOf(base, min(end, base + 200_000), "<gpxorg:color>"), !c.isEmpty { f.embeddedColor = c }
            if let c = textOf(base, min(end, base + 200_000), "<gpxorg:iconcolor>"), !c.isEmpty { f.embeddedIconColor = c }
            if let w = textOf(base, min(end, base + 200_000), "<gpxorg:width>"), let v = Double(w) { f.embeddedWidth = v }
            var p = base
            var wantName = false, nameSet = false
            while p < end {
                guard let lt = memchr(p, 0x3C, end - p) else { break }
                p = up(lt)
                if p + 1 >= end { break }
                let c1 = p[1]
                if c1 == 0x2F {                                   // closing tag
                    var q = p + 2
                    while q < end, q.pointee != 0x3E, q.pointee != 0x20 { q += 1 }
                    let len = q - (p + 2)
                    if eq(p + 2, len, "trkseg") || eq(p + 2, len, "trk") || eq(p + 2, len, "rte") { d.flush() }
                    p = q; continue
                }
                if c1 == 0x21 || c1 == 0x3F {                     // comment / declaration
                    if let gt = memchr(p, 0x3E, end - p) { p = up(gt) + 1; continue } else { break }
                }
                var q = p + 1
                while q < end, q.pointee != 0x3E, q.pointee != 0x20, q.pointee != 0x2F, q.pointee != 0x0A, q.pointee != 0x0D, q.pointee != 0x09 { q += 1 }
                let tag = p + 1, len = q - tag
                guard let gtp = memchr(q, 0x3E, end - q) else { break }
                let gt = up(gtp)
                if eq(tag, len, "trkpt") || eq(tag, len, "rtept") {
                    wantName = false
                    if let lat = attrNumber(q, gt, "lat="), let lon = attrNumber(q, gt, "lon=") {
                        var ele: Double?
                        if gt[-1] != 0x2F {
                            let closeKey: StaticString = eq(tag, len, "trkpt") ? "</trkpt>" : "</rtept>"
                            if let cl = memmem(gt, end - gt, closeKey.utf8Start, closeKey.utf8CodeUnitCount) {
                                let stop = up(cl)
                                if let hit = memmem(gt, stop - gt, "<ele>", 5) {
                                    ele = parseDouble(up(hit) + 5, stop)
                                }
                                if let th = memmem(gt, stop - gt, "<time>", 6) { d.ptTime = isoSeconds(up(th) + 6, stop) }
                            }
                        }
                        d.ptLat = lat; d.ptLon = lon; d.ptEle = ele
                        d.addPoint()
                    }
                } else if eq(tag, len, "wpt") {
                    if let lat = attrNumber(q, gt, "lat="), let lon = attrNumber(q, gt, "lon=") {
                        var name = "", sym = "", desc = "", micon: String?, mcolor: String?, msize: Double?
                        if gt[-1] != 0x2F, let cl = memmem(gt, end - gt, "</wpt>", 6) {
                            name = textOf(gt, up(cl), "<name>") ?? ""
                            sym = textOf(gt, up(cl), "<sym>") ?? ""
                            desc = textOf(gt, up(cl), "<desc>") ?? ""
                            micon = textOf(gt, up(cl), "<gpxorg:micon>")
                            mcolor = textOf(gt, up(cl), "<gpxorg:mcolor>")
                            msize = textOf(gt, up(cl), "<gpxorg:msize>").flatMap { Double($0) }
                        }
                        var w = Waypoint(x: Merc.x(lon: lon), y: Merc.y(lat: lat), name: name, sym: sym)
                        w.desc = desc; w.iconID = micon; w.colorHex = mcolor; w.size = msize; w.index = f.waypoints.count
                        f.waypoints.append(w)
                    }
                } else if eq(tag, len, "trkseg") {
                    d.flush()
                } else if eq(tag, len, "trk") || eq(tag, len, "rte") {
                    if eq(tag, len, "rte") { f.isRouteElement = true }
                    d.flush(); wantName = !nameSet
                } else if eq(tag, len, "type"), f.hint == nil, f.pointTotal == 0, f.waypoints.isEmpty,
                          let lt2 = memchr(gt, 0x3C, end - gt) {
                    let e = up(lt2)
                    let t = String(decoding: UnsafeBufferPointer(start: gt + 1, count: e - (gt + 1)), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { f.hint = t }
                } else if wantName, eq(tag, len, "name") {
                    if let lt2 = memchr(gt, 0x3C, end - gt) {
                        let e = up(lt2)
                        let s = String(decoding: UnsafeBufferPointer(start: gt + 1, count: e - (gt + 1)), as: UTF8.self)
                            .replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !s.isEmpty { f.name = s; nameSet = true; wantName = false }
                    }
                }
                p = gt + 1
            }
        }
        d.finish()
        f.boundsFromWaypointsIfNeeded()
        return f.segments.isEmpty && f.waypoints.isEmpty ? nil : f
    }

    // MARK: parser

    private final class Delegate: NSObject, XMLParserDelegate {
        let f: GPXFile
        var stack: [String] = []
        var text = ""
        var cur: [Double] = []
        var lastX = -1.0, lastY = -1.0
        var lastLat = 0.0, lastLon = 0.0, haveLast = false
        var ptLat = 0.0, ptLon = 0.0, ptEle: Double?
        var ptTime: Double?, lastTime: Double?
        var wptName = "", wptSym = "", wptDesc = "", wptIcon: String?, wptColor: String?, wptSize: Double?, trackNameSet = false
        var lastEle: Double?
        let minStep = 2.5e-8   // ≈ 1 m in Web-Mercator units; thin out dense points
        init(_ f: GPXFile) { self.f = f }

        func flush() {
            if cur.count >= 4 { f.segments.append(cur) }
            cur = []; lastX = -1; lastY = -1; haveLast = false; lastEle = nil; winD = []; winE = []; eleBase = nil
        }
        func finish() { flush() }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes a: [String: String]) {
            stack.append(name); text = ""
            switch name {
            case "trkseg": flush()
            case "rte": f.isRouteElement = true; flush()
            case "trkpt", "rtept", "wpt":
                ptLat = Double(a["lat"] ?? "") ?? 0; ptLon = Double(a["lon"] ?? "") ?? 0; ptEle = nil; ptTime = nil; wptName = ""; wptSym = ""; wptDesc = ""; wptIcon = nil; wptColor = nil; wptSize = nil
            default: break
            }
        }
        func parser(_ parser: XMLParser, foundCharacters s: String) {
            if let l = stack.last, l == "name" || l == "sym" || l == "ele" || l == "time" || l == "type" || l == "gpxorg:icon" || l == "gpxorg:color" || l == "gpxorg:width" || l == "gpxorg:iconcolor" || l == "desc" || l == "gpxorg:micon" || l == "gpxorg:mcolor" || l == "gpxorg:msize" || l == "gpxx:DisplayColor" || l == "gpxtrx:DisplayColor" { text += s }
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
            defer { stack.removeLast() }
            switch name {
            case "sym": if stack.count >= 2, stack[stack.count - 2] == "wpt" { wptSym = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            case "desc": if stack.count >= 2, stack[stack.count - 2] == "wpt" { wptDesc = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            case "gpxorg:micon": wptIcon = text.trimmingCharacters(in: .whitespacesAndNewlines)
            case "gpxorg:mcolor": wptColor = text.trimmingCharacters(in: .whitespacesAndNewlines)
            case "gpxorg:msize": wptSize = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
            case "gpxorg:icon": f.embeddedIcon = text.trimmingCharacters(in: .whitespacesAndNewlines)
            case "gpxorg:color": f.embeddedColor = text.trimmingCharacters(in: .whitespacesAndNewlines)
            case "gpxorg:iconcolor": f.embeddedIconColor = text.trimmingCharacters(in: .whitespacesAndNewlines)
            case "gpxorg:width": f.embeddedWidth = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
            case "ele": ptEle = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
            case "time": if stack.count >= 2, ["trkpt", "rtept"].contains(stack[stack.count - 2]) { ptTime = isoSeconds(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            case "type": if stack.count >= 2, ["trk", "rte"].contains(stack[stack.count - 2]), f.hint == nil { f.hint = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            case "name":
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let parent = stack.count >= 2 ? stack[stack.count - 2] : ""
                if parent == "wpt" { wptName = t }
                else if (parent == "trk" || parent == "rte") && !trackNameSet && !t.isEmpty { f.name = t; trackNameSet = true }
            case "gpxx:DisplayColor", "gpxtrx:DisplayColor":
                if f.displayColor == nil { f.displayColor = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            case "trkpt", "rtept": addPoint()
            case "wpt":
                var w = Waypoint(x: Merc.x(lon: ptLon), y: Merc.y(lat: ptLat), name: wptName, sym: wptSym)
                w.desc = wptDesc; w.iconID = wptIcon; w.colorHex = wptColor; w.size = wptSize; w.index = f.waypoints.count
                f.waypoints.append(w)
            case "trkseg", "rte": flush()
            default: break
            }
        }

        var winD: [Double] = [], winE: [Double] = []
        var eleBase: Double?

        func addPoint() {
            guard abs(ptLat) <= 90, abs(ptLon) <= 180 else { return }
            let x = Merc.x(lon: ptLon), y = Merc.y(lat: ptLat)
            var step = 0.0
            if haveLast { step = haversine(lastLat, lastLon, ptLat, ptLon); f.distance += step }
            haveLast = true; lastLat = ptLat; lastLon = ptLon
            f.pointTotal += 1
            if let t = ptTime {
                f.hasTime = true
                if let lt = lastTime, t > lt, t - lt <= 180 { f.movingSeconds += t - lt; f.movingMeters += step }
                lastTime = t; ptTime = nil
            }
            if let e = ptEle {
                // median of the last ~100 m of track (robust against GPS spikes), then count climbs with a 4 m hysteresis (ignores GPS height noise)
                winD.append(f.distance); winE.append(e)
                while let d0 = winD.first, f.distance - d0 > 100, winD.count > 1 { winD.removeFirst(); winE.removeFirst() }
                let m = median(winE)
                if let b = eleBase {
                    if m - b >= 4 { f.ascent += m - b; eleBase = m } else if b - m >= 4 { eleBase = m }
                } else { eleBase = m }
            }
            if abs(x - lastX) < minStep && abs(y - lastY) < minStep { return }
            cur.append(x); cur.append(y); lastX = x; lastY = y
            f.minX = min(f.minX, x); f.maxX = max(f.maxX, x); f.minY = min(f.minY, y); f.maxY = max(f.maxY, y)
        }
    }
}

func median(_ a: [Double]) -> Double {
    let s = a.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

func haversine(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
    let r = 6371000.0, p = Double.pi / 180
    let dLat = (lat2 - lat1) * p, dLon = (lon2 - lon1) * p
    let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * p) * cos(lat2 * p) * sin(dLon / 2) * sin(dLon / 2)
    return 2 * r * asin(min(1, sqrt(a)))
}

enum NSColorLike {
    static func hsb(_ h: CGFloat, _ s: CGFloat, _ b: CGFloat) -> CGColor {
        let i = Int(h * 6), f = h * 6 - CGFloat(i)
        let p = b * (1 - s), q = b * (1 - f * s), t = b * (1 - (1 - f) * s)
        let (r, g, bl): (CGFloat, CGFloat, CGFloat)
        switch i % 6 { case 0: (r, g, bl) = (b, t, p); case 1: (r, g, bl) = (q, b, p); case 2: (r, g, bl) = (p, b, t)
        case 3: (r, g, bl) = (p, q, b); case 4: (r, g, bl) = (t, p, b); default: (r, g, bl) = (b, p, q) }
        return CGColor(red: r, green: g, blue: bl, alpha: 1)
    }
}

/// "2012-04-14T10:22:33(.123)Z" -> seconds since 1970 (time zone ignored: only differences matter).
func isoSeconds(_ p: UnsafePointer<UInt8>, _ end: UnsafePointer<UInt8>) -> Double? {
    guard end - p >= 19 else { return nil }
    func d(_ i: Int, _ n: Int) -> Int? {
        var v = 0
        for k in 0..<n { let c = p[i + k]; guard c >= 48, c <= 57 else { return nil }; v = v * 10 + Int(c - 48) }
        return v
    }
    guard let y = d(0, 4), let mo = d(5, 2), let da = d(8, 2), let h = d(11, 2), let mi = d(14, 2), let sec = d(17, 2) else { return nil }
    let yy = mo <= 2 ? y - 1 : y
    let era = yy / 400, yoe = yy - era * 400
    let doy = (153 * (mo + (mo > 2 ? -3 : 9)) + 2) / 5 + da - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    let days = era * 146097 + doe - 719468
    var t = Double(days * 86400 + h * 3600 + mi * 60 + sec)
    if end - p > 20, p[19] == 0x2E {
        var f = 0.1, i = 20
        while p + i < end, p[i] >= 48, p[i] <= 57 { t += Double(p[i] - 48) * f; f /= 10; i += 1 }
    }
    return t
}

/// Time stamp of a GPX point (ISO 8601) as seconds since 1970; nil when it cannot be read.
public func parseISOSeconds(_ s: String) -> Double? { isoSeconds(s) }

func isoSeconds(_ s: String) -> Double? {
    let b = Array(s.utf8)
    return b.withUnsafeBufferPointer { bp in bp.baseAddress.flatMap { isoSeconds($0, $0 + bp.count) } }
}
