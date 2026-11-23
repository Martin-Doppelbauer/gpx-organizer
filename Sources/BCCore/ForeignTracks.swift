import Foundation

/// Readers for other track formats that appear next to GPX files:
/// .trc (MiTAC Mio / MyNav track log), .ikt (IK3D project, XML), .ptm / .axe (Microsoft AutoRoute journeys).
public enum ForeignTracks {
    public static let extensions: Set<String> = ["gpx", "trc", "ikt", "ptm", "axe", "ovl", "trail", "fit"]
    public static func isSupported(_ url: URL) -> Bool {
        let e = url.pathExtension.lowercased()
        guard extensions.contains(e) else { return false }
        return e == "fit" ? isFITFile(url) : true       // ".fit" is also used by astronomy images (FITS): check the Garmin FIT header
    }

    /// Garmin FIT files carry ".FIT" at byte 8 of the header.
    static func isFITFile(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 12), d.count >= 12 else { return false }
        return d[8] == 0x2E && d[9] == 0x46 && d[10] == 0x49 && d[11] == 0x54
    }

    public static func parse(_ url: URL) -> GPXDocument? {
        switch url.pathExtension.lowercased() {
        case "fit": return parseFIT(url)
        case "trc": return parseTRC(url)
        case "ikt": return parseIKT(url)
        case "ptm", "axe": return parseAutoRoute(url)
        case "ovl": return parseOVL(url)
        case "trail": return parseTrail(url)
        default: return nil
        }
    }

    private static func baseName(_ url: URL) -> String { url.deletingPathExtension().lastPathComponent }

    private static func isoUTC(_ t: Int) -> String {
        var tt = time_t(t)
        var tmv = tm()
        gmtime_r(&tt, &tmv)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02dZ", Int(tmv.tm_year) + 1900, Int(tmv.tm_mon) + 1, Int(tmv.tm_mday),
                      Int(tmv.tm_hour), Int(tmv.tm_min), Int(tmv.tm_sec))
    }

    // MARK: .fit — Garmin FIT activity (binary): record messages with position, altitude, heart rate, cadence, power

    static func parseFIT(_ url: URL) -> GPXDocument? {
        guard isFITFile(url), let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count > 14 else { return nil }
        let b = [UInt8](data)
        let headerSize = Int(b[0])
        guard headerSize >= 12, headerSize <= 16 else { return nil }
        let dataSize = Int(b[4]) | Int(b[5]) << 8 | Int(b[6]) << 16 | Int(b[7]) << 24
        let end = min(b.count, headerSize + dataSize)
        struct Field { var num: Int; var size: Int; var type: Int }
        struct Def { var big: Bool; var global: Int; var fields: [Field]; var devSize: Int; var total: Int }
        var defs: [Int: Def] = [:]
        var pos = headerSize
        var lastTS: UInt32 = 0
        var pts: [GPXPoint] = []
        let fitEpoch = 631_065_600                      // 1989-12-31 00:00:00 UTC in Unix seconds

        func uint(_ at: Int, _ n: Int, big: Bool) -> UInt64 {
            var v: UInt64 = 0
            for i in 0..<n { let byte = UInt64(b[at + (big ? i : n - 1 - i)]); v = v << 8 | byte }
            return v
        }

        while pos < end {
            let h = b[pos]; pos += 1
            if h & 0x80 != 0 {                          // compressed timestamp header: data message of local type bits 5-6
                let local = Int(h >> 5) & 0x03, offset = UInt32(h & 0x1F)
                guard let d = defs[local], pos + d.total <= end else { break }
                var ts = (lastTS & ~UInt32(0x1F)) + offset
                if offset < (lastTS & 0x1F) { ts += 32 }
                lastTS = ts
                if d.global == 20 { addRecord(d, at: pos, ts: ts) }
                pos += d.total
                continue
            }
            let local = Int(h & 0x0F)
            if h & 0x40 != 0 {                          // definition message
                guard pos + 5 <= end else { break }
                let big = b[pos + 1] == 1
                let global = Int(uint(pos + 2, 2, big: big))
                let n = Int(b[pos + 4])
                pos += 5
                guard pos + n * 3 <= end else { break }
                var fields: [Field] = []
                var total = 0
                for i in 0..<n {
                    let f = Field(num: Int(b[pos + i * 3]), size: Int(b[pos + i * 3 + 1]), type: Int(b[pos + i * 3 + 2]) & 0x1F)
                    fields.append(f); total += f.size
                }
                pos += n * 3
                var dev = 0
                if h & 0x20 != 0 {                      // developer fields: only their sizes matter
                    guard pos < end else { break }
                    let dn = Int(b[pos]); pos += 1
                    guard pos + dn * 3 <= end else { break }
                    for i in 0..<dn { dev += Int(b[pos + i * 3 + 1]) }
                    pos += dn * 3
                }
                defs[local] = Def(big: big, global: global, fields: fields, devSize: dev, total: total + dev)
            } else {                                    // data message
                guard let d = defs[local], pos + d.total <= end else { break }
                if d.global == 20 { addRecord(d, at: pos, ts: nil) }
                else if d.global == 18 || d.global == 19 || d.global == 21 || true {
                    // other messages: only remember a full timestamp (field 253) for compressed headers
                    var off = pos
                    for f in d.fields { if f.num == 253, f.size == 4 { lastTS = UInt32(uint(off, 4, big: d.big)) }; off += f.size }
                }
                pos += d.total
            }
        }

        func addRecord(_ d: Def, at start: Int, ts compressed: UInt32?) {
            var lat: Int32?, lon: Int32?
            var alt: Double?, hr: Double?, cad: Double?, pow: Double?
            var ts: UInt32? = compressed
            var off = start
            for f in d.fields {
                defer { off += f.size }
                switch (f.num, f.size) {
                case (253, 4): let v = UInt32(uint(off, 4, big: d.big)); if v != 0xFFFF_FFFF { ts = v; lastTS = v }
                case (0, 4): let v = Int32(truncatingIfNeeded: uint(off, 4, big: d.big)); if v != 0x7FFF_FFFF { lat = v }
                case (1, 4): let v = Int32(truncatingIfNeeded: uint(off, 4, big: d.big)); if v != 0x7FFF_FFFF { lon = v }
                case (2, 2): let v = uint(off, 2, big: d.big); if v != 0xFFFF, alt == nil { alt = Double(v) / 5 - 500 }
                case (78, 4): let v = uint(off, 4, big: d.big); if v != 0xFFFF_FFFF { alt = Double(v) / 5 - 500 }      // enhanced altitude wins
                case (3, 1): let v = b[off]; if v != 0xFF, v > 0 { hr = Double(v) }
                case (4, 1): let v = b[off]; if v != 0xFF { cad = Double(v) }
                case (7, 2): let v = uint(off, 2, big: d.big); if v != 0xFFFF { pow = Double(v) }
                default: break
                }
            }
            guard let la = lat, let lo = lon else { return }          // no position (indoor, no fix)
            let degLat = Double(la) * 180 / 2_147_483_648, degLon = Double(lo) * 180 / 2_147_483_648
            guard abs(degLat) <= 90, abs(degLon) <= 180, !(degLat == 0 && degLon == 0) else { return }
            var p = GPXPoint(lat: degLat, lon: degLon, ele: alt, time: ts.map { isoUTC(fitEpoch + Int($0)) })
            p.hr = hr; p.cad = cad; p.power = pow
            pts.append(p)
        }

        guard pts.count >= 2 else { return nil }
        var doc = GPXDocument(name: baseName(url))
        doc.tracks = [GPXTrackData(name: baseName(url), isRoute: false, segments: [pts])]
        return doc
    }

    // MARK: .trc — text log, records "5|lon|lat|alt|speed|course|unixtime|…" (also "1|…"); lon/lat in 1/1000 arc-second

    static func parseTRC(_ url: URL) -> GPXDocument? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        var pts: [GPXPoint] = []
        text.enumerateLines { line, _ in
            let u = line.utf8
            guard let c = u.first, c == 0x35 || c == 0x31, u.dropFirst().first == 0x7C else { return }
            let f = line.split(separator: "|", omittingEmptySubsequences: false)
            guard f.count > 6, let lo = Double(f[1]), let la = Double(f[2]) else { return }
            let lon = lo / 3_600_000, lat = la / 3_600_000
            guard abs(lon) > 0.001, abs(lat) > 0.001, abs(lat) <= 90, abs(lon) <= 180 else { return }
            // The raw GPS heights of these logs jump by 100+ m (and 0 = no fix); they are not usable, so only position and time are kept.
            let ele: Double? = nil
            let t = Int(f[6]).map(isoUTC)
            pts.append(GPXPoint(lat: lat, lon: lon, ele: ele, time: t))
        }
        guard pts.count >= 2 else { return nil }
        var d = GPXDocument(name: baseName(url))
        d.tracks = [GPXTrackData(name: baseName(url), isRoute: false, segments: [pts])]
        return d
    }

    // MARK: .ikt — IK3D project file (XML): MMGeoObject with PathPoints / Point / GeoPosition X=lon Y=lat

    private final class IKTParser: NSObject, XMLParserDelegate {
        var doc: GPXDocument
        var stack: [String] = []
        var text = ""
        var objName = ""
        var points: [GPXPoint] = []
        var cur = GPXPoint(lat: 0, lon: 0)
        var have = false
        var date: (Int, Int, Int)?, time: (Int, Int, Int)?
        init(name: String) { doc = GPXDocument(name: name) }

        func finishObject() {
            if points.count >= 2 {
                doc.tracks.append(GPXTrackData(name: objName, isRoute: false, segments: [points]))
            } else if let p = points.first {
                doc.waypoints.append(GPXWaypoint(point: p, name: objName))
            }
            points = []
        }

        /// Older exports number their elements ("MMGeoObject_0", "Point_12"): strip that suffix.
        static func base(_ n: String) -> String {
            guard let u = n.lastIndex(of: "_"), n[n.index(after: u)...].allSatisfy(\.isNumber), !n[n.index(after: u)...].isEmpty else { return n }
            return String(n[..<u])
        }

        func parser(_ parser: XMLParser, didStartElement rawName: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
            let name = Self.base(rawName)
            stack.append(name); text = ""
            switch name {
            case "MMGeoObject": points = []; objName = ""
            case "Point": cur = GPXPoint(lat: 0, lon: 0); have = false; date = nil; time = nil
            case "GeoPosition":
                if let x = Double(a["X"] ?? ""), let y = Double(a["Y"] ?? "") { cur.lon = x; cur.lat = y; have = true }
            case "Date":
                if let d = Int(a["Day"] ?? ""), let m = Int(a["Month"] ?? ""), let y = Int(a["Year"] ?? "") { date = (y, m, d) }
            case "Time":
                if let h = Int(a["Hour"] ?? ""), let mi = Int(a["Minute"] ?? ""), let s = Int(a["Second"] ?? "") { time = (h, mi, s) }
            default: break
            }
        }
        func parser(_ parser: XMLParser, foundCharacters s: String) { text += s }
        func parser(_ parser: XMLParser, didEndElement rawName: String, namespaceURI: String?, qualifiedName: String?) {
            defer { stack.removeLast() }
            let name = Self.base(rawName)
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "Name": if stack.count >= 2, stack[stack.count - 2] == "MMGeoObject" { objName = t }
            case "Height": cur.ele = Double(t)
            case "Point":
                if have, abs(cur.lat) <= 90, abs(cur.lon) <= 180 {
                    if let d = date, let tm = time { cur.time = String(format: "%04d-%02d-%02dT%02d:%02d:%02dZ", d.0, d.1, d.2, tm.0, tm.1, tm.2) }
                    points.append(cur)
                }
            case "MMGeoObject": finishObject()
            default: break
            }
        }
    }

    static func parseIKT(_ url: URL) -> GPXDocument? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let d = IKTParser(name: baseName(url))
        let p = XMLParser(data: data)
        p.delegate = d
        p.parse()
        return d.doc.tracks.isEmpty && d.doc.waypoints.isEmpty ? nil : d.doc
    }

    // MARK: .ovl — Top25/DOMG overlay ("DOMGVCRD Ovlfile"): lines are chains of (lon, lat, pad) doubles, 24 bytes apart

    static func parseOVL(_ url: URL) -> GPXDocument? {
        guard let d = try? Data(contentsOf: url), d.count > 700, d.starts(with: Array("DOMGVCRD".utf8)) else { return nil }
        func dbl(_ o: Int) -> Double {
            var v: UInt64 = 0
            for k in 0..<8 { v |= UInt64(d[o + k]) << (8 * UInt64(k)) }
            return Double(bitPattern: v)
        }
        func ok(_ o: Int) -> (Double, Double)? {
            guard o + 16 <= d.count else { return nil }
            let lon = dbl(o), lat = dbl(o + 8)
            guard lon > -20, lon < 45, lat > 30, lat < 75 else { return nil }
            return (lat, lon)
        }
        var runs: [[GPXPoint]] = []
        var off = 0
        while off + 16 <= d.count {
            guard let first = ok(off) else { off += 1; continue }
            var pts = [GPXPoint(lat: first.0, lon: first.1)]
            var o = off + 24
            while let q = ok(o), abs(q.0 - pts.last!.lat) < 0.5, abs(q.1 - pts.last!.lon) < 0.7 {
                pts.append(GPXPoint(lat: q.0, lon: q.1)); o += 24
            }
            runs.append(pts)
            off = o
        }
        // the first single pair in the header is the overlay's reference point, not part of the drawing
        if let f = runs.first, f.count == 1 { runs.removeFirst() }
        var doc = GPXDocument(name: baseName(url))
        var n = 0
        for r in runs {
            if r.count >= 2 {
                n += 1
                doc.tracks.append(GPXTrackData(name: n == 1 ? baseName(url) : "\(baseName(url)) (\(n))", isRoute: false, segments: [r]))
            } else if let p = r.first {
                doc.waypoints.append(GPXWaypoint(point: p, name: "Point"))
            }
        }
        return doc.tracks.isEmpty && doc.waypoints.isEmpty ? nil : doc
    }

    // MARK: .trail — Trailrunner document (NSKeyedArchiver): sections hold nested archives of track points; routes list sections

    private static func trailPoints(_ section: [String: Any]) -> [GPXPoint] {
        guard let blob = section["trackData"] as? Data, let inner = KeyedArchive(blob),
              let root = inner.resolveRoot() as? [String: Any], let list = root["trackPoints"] as? [Any] else { return [] }
        var pts: [GPXPoint] = []
        pts.reserveCapacity(list.count)
        for case let p as [String: Any] in list {
            guard let lat = p["lat"] as? Double, let lon = p["lon"] as? Double, abs(lat) <= 90, abs(lon) <= 180, abs(lat) + abs(lon) > 0.001 else { continue }
            let alt = p["alt"] as? Double
            var time: String?
            if let t = p["time"] as? Double, t > 1 { time = isoUTC(Int(t) + 978_307_200) }   // Apple reference date → Unix
            pts.append(GPXPoint(lat: lat, lon: lon, ele: (alt ?? 0) == 0 ? nil : alt, time: time))
        }
        return pts
    }

    static func parseTrail(_ url: URL) -> GPXDocument? {
        guard let data = try? Data(contentsOf: url), let ka = KeyedArchive(data), let root = ka.resolveRoot() as? [String: Any] else { return nil }
        var doc = GPXDocument(name: baseName(url))
        let sections = (root["sections"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        var byID: [String: [GPXPoint]] = [:]
        var order: [String] = []
        for (i, s) in sections.enumerated() {
            let id = (s["identifier"] as? String) ?? "section\(i)"
            let pts = trailPoints(s)
            if !pts.isEmpty { byID[id] = pts; order.append(id) }
        }
        var used = Set<String>()
        for case let r as [String: Any] in (root["routes"] as? [Any]) ?? [] {
            let path = (r["routeSectionsPath"] as? [Any])?.compactMap { ($0 as? [String: Any])?["identifier"] as? String } ?? []
            var line: [GPXPoint] = []
            for id in path {
                guard var pts = byID[id] else { continue }
                used.insert(id)
                // sections may be walked in either direction: keep the route continuous
                if let last = line.last, let f = pts.first, let l = pts.last {
                    let dFirst = abs(f.lat - last.lat) + abs(f.lon - last.lon), dLast = abs(l.lat - last.lat) + abs(l.lon - last.lon)
                    if dLast < dFirst { pts.reverse() }
                }
                line += pts
            }
            if line.count >= 2 { doc.tracks.append(GPXTrackData(name: (r["name"] as? String) ?? baseName(url), isRoute: false, segments: [line])) }
        }
        for id in order where !used.contains(id) {
            if let pts = byID[id], pts.count >= 2 { doc.tracks.append(GPXTrackData(name: baseName(url), isRoute: false, segments: [pts])) }
        }
        // one document often holds several routes with the same name: tell them apart by start date (or running number)
        var seen: [String: Int] = [:]
        for t in doc.tracks { seen[t.name, default: 0] += 1 }
        var counter: [String: Int] = [:]
        for i in doc.tracks.indices where seen[doc.tracks[i].name]! > 1 {
            let base = doc.tracks[i].name
            counter[base, default: 0] += 1
            if let t = doc.tracks[i].segments.first?.first?.time { doc.tracks[i].name = "\(base) (\(t.prefix(10)))" }
            else { doc.tracks[i].name = "\(base) (\(counter[base]!))" }
        }
        for case let w as [String: Any] in (root["wayPoints"] as? [Any]) ?? [] {
            if let lat = w["lat"] as? Double, let lon = w["lon"] as? Double, abs(lat) + abs(lon) > 0.001 {
                doc.waypoints.append(GPXWaypoint(point: GPXPoint(lat: lat, lon: lon, ele: (w["alt"] as? Double).flatMap { $0 == 0 ? nil : $0 }),
                                                 name: (w["name"] as? String) ?? ""))
            }
        }
        return doc.tracks.isEmpty ? nil : doc
    }

    // MARK: .ptm / .axe — Microsoft AutoRoute journey (OLE container, stream "Journey")

    /// Minimal reader for OLE2 compound files: returns the stream with the given name.
    private static func oleStream(_ d: Data, named wanted: String) -> Data? {
        func u16(_ o: Int) -> Int { o + 2 <= d.count ? Int(d[o]) | Int(d[o + 1]) << 8 : 0 }
        func u32(_ o: Int) -> Int { o + 4 <= d.count ? u16(o) | u16(o + 2) << 16 : 0 }
        guard d.count > 512, u32(0) == 0xE011CFD0 else { return nil }
        let ss = 1 << u16(0x1E), mss = 1 << u16(0x20)
        let dirStart = u32(0x30), cutoff = u32(0x38), miniFatStart = u32(0x3C)
        var fat: [Int] = []
        for i in 0..<109 {
            let s = u32(0x4C + i * 4)
            if s >= 0xFFFFFFFA { continue }
            let base = 512 + s * ss
            guard base + ss <= d.count else { continue }
            for k in 0..<(ss / 4) { fat.append(u32(base + k * 4)) }
        }
        func chain(_ s0: Int) -> [Int] {
            var out: [Int] = []; var s = s0
            while s < 0xFFFFFFFA, s < fat.count, out.count < 100_000 { out.append(s); s = fat[s] }
            return out
        }
        func read(_ s: Int) -> Data {
            var out = Data()
            for c in chain(s) { let b = 512 + c * ss; if b + ss <= d.count { out.append(d[b..<(b + ss)]) } }
            return out
        }
        let dir = read(dirStart)
        struct Ent { var name: String; var type: Int; var start: Int; var size: Int }
        var ents: [Ent] = []
        var i = 0
        while i + 128 <= dir.count {
            let nl = Int(dir[i + 64]) | Int(dir[i + 65]) << 8
            if nl > 2, nl <= 64 {
                let nameData = dir[(i)..<(i + nl - 2)]
                let name = String(data: nameData, encoding: .utf16LittleEndian) ?? ""
                func r32(_ o: Int) -> Int { Int(dir[i + o]) | Int(dir[i + o + 1]) << 8 | Int(dir[i + o + 2]) << 16 | Int(dir[i + o + 3]) << 24 }
                ents.append(Ent(name: name, type: Int(dir[i + 66]), start: r32(116), size: r32(120)))
            }
            i += 128
        }
        guard let root = ents.first, let e = ents.first(where: { $0.type == 2 && $0.name == wanted }) else { return nil }
        if e.size >= cutoff { return read(e.start).prefix(e.size) }
        let mini = read(root.start)
        var miniFat: [Int] = []
        for c in chain(miniFatStart) { let b = 512 + c * ss; if b + ss <= d.count { for k in 0..<(ss / 4) { miniFat.append(u32(b + k * 4)) } } }
        var out = Data(); var s = e.start
        while s < 0xFFFFFFFA, s < miniFat.count, out.count < e.size {
            let b = s * mss
            if b + mss <= mini.count { out.append(mini[b..<(b + mss)]) }
            s = miniFat[s]
        }
        return out.prefix(e.size)
    }

    static func parseAutoRoute(_ url: URL) -> GPXDocument? {
        guard let file = try? Data(contentsOf: url), let j = oleStream(file, named: "Journey"), j.count > 40 else { return nil }
        let k = 360.0 / 4_294_967_296.0     // 32-bit "full circle" units
        func i32(_ o: Int) -> Int32 { Int32(bitPattern: UInt32(j[o]) | UInt32(j[o + 1]) << 8 | UInt32(j[o + 2]) << 16 | UInt32(j[o + 3]) << 24) }
        var pts: [GPXPoint] = []
        var names: [(Double, Double, String)] = []
        var off = 0
        while off + 14 < j.count {
            let n = Int(j[off + 8])
            let end = off + 9 + n
            if n >= 1, n <= 120, end + 4 <= j.count, j[end] == 0xFF, j[end + 1] == 0xFE, j[end + 2] == 0xFF, Int(j[end + 3]) == n {
                let lon = Double(i32(off)) * k, lat = Double(i32(off + 4)) * k
                if lon > -30, lon < 60, lat > 30, lat < 75 {
                    let name = String(data: j[(off + 9)..<end], encoding: .windowsCP1252) ?? ""
                    if let l = pts.last, abs(l.lat - lat) < 1e-5, abs(l.lon - lon) < 1e-5 { off += 1; continue }
                    pts.append(GPXPoint(lat: lat, lon: lon))
                    names.append((lat, lon, name))
                    off = end + 4; continue
                }
            }
            off += 1
        }
        guard pts.count >= 2 else { return nil }
        var d = GPXDocument(name: baseName(url))
        d.tracks = [GPXTrackData(name: baseName(url), isRoute: true, segments: [pts])]
        d.waypoints = names.map { GPXWaypoint(point: GPXPoint(lat: $0.0, lon: $0.1), name: $0.2) }
        return d
    }
}
