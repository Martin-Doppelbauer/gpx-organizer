import Foundation

public struct GPXPoint {
    public var lat: Double
    public var lon: Double
    public var ele: Double?
    public var time: String?
    public var hr: Double?        // heart rate, beats per minute (Garmin TrackPointExtension)
    public var cad: Double?       // cadence, revolutions per minute
    public var power: Double?     // watts
    public init(lat: Double, lon: Double, ele: Double? = nil, time: String? = nil) {
        self.lat = lat; self.lon = lon; self.ele = ele; self.time = time
    }
}

public struct GPXWaypoint {
    public var point: GPXPoint
    public var name: String
    public var desc: String
    public var sym: String
    // marker attributes (extensions inside <wpt>)
    public var markerIcon: String?
    public var markerColor: String?      // "RRGGBB"
    public var markerSize: Double?       // factor: 0.8 / 1 / 1.4
    public init(point: GPXPoint, name: String, desc: String = "", sym: String = "") {
        self.point = point; self.name = name; self.desc = desc; self.sym = sym
    }
}

extension GPXWaypoint {
    /// `<extensions>` with the marker attributes (icon, color, size); empty when none is set.
    public func extensionsXML() -> String {
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        var inner = ""
        if let v = markerIcon, !v.isEmpty { inner += "<gpxorg:micon>\(esc(v))</gpxorg:micon>" }
        if let v = markerColor, !v.isEmpty { inner += "<gpxorg:mcolor>\(esc(v))</gpxorg:mcolor>" }
        if let v = markerSize { inner += "<gpxorg:msize>\(String(format: "%g", v))</gpxorg:msize>" }
        return inner.isEmpty ? "" : "<extensions>\(inner)</extensions>"
    }
}

public struct GPXTrackData {
    public var name: String
    public var isRoute: Bool
    public var segments: [[GPXPoint]]
    public init(name: String, isRoute: Bool, segments: [[GPXPoint]]) { self.name = name; self.isRoute = isRoute; self.segments = segments }
}

public struct Profile {
    public var dist: [Double] = []     // metres from start
    public var ele: [Double] = []
    public var lat: [Double] = []
    public var lon: [Double] = []
    public var totalDistance = 0.0
    public var ascent = 0.0
    public var descent = 0.0
    public var minEle = 0.0
    public var maxEle = 0.0
    public var speed: [Double] = []    // km/h at each sample (empty without timestamps)
    public var maxSpeed = 0.0
    public var avgSpeed = 0.0          // km/h while moving
    public var movingSeconds = 0.0
    public var hr: [Double] = []       // heart rate, bpm (empty when the file has none)
    public var power: [Double] = []    // watts
    public var cad: [Double] = []      // revolutions per minute
    public var hasElevation: Bool { !ele.isEmpty }
    public var hasSpeed: Bool { !speed.isEmpty }
    public var hasHeartRate: Bool { !hr.isEmpty }
    public var hasPower: Bool { !power.isEmpty }
    public var hasCadence: Bool { !cad.isEmpty }
}

/// Complete, editable GPX file content (tracks, routes, waypoints). Value type so edits can be snapshotted for undo.
public struct GPXDocument {
    public var name: String
    public var tracks: [GPXTrackData] = []
    public var waypoints: [GPXWaypoint] = []
    public var icon: String?                  // gpxorg:icon / color / width, kept when the file is saved again
    public var color: String?
    public var iconColor: String?
    public var width: String?

    public init(name: String) { self.name = name }

    public var pointCount: Int { tracks.reduce(0) { $0 + $1.segments.reduce(0) { $0 + $1.count } } }

    // MARK: parse

    public static func parse(_ url: URL) -> GPXDocument? {
        if url.pathExtension.lowercased() != "gpx" { return ForeignTracks.parse(url) }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let d = Parser(name: url.deletingPathExtension().lastPathComponent)
        let p = XMLParser(data: data)
        p.delegate = d
        p.parse()
        d.flush()
        return d.doc.tracks.isEmpty && d.doc.waypoints.isEmpty ? nil : d.doc
    }

    private final class Parser: NSObject, XMLParserDelegate {
        var doc: GPXDocument
        var stack: [String] = []
        var text = ""
        var curTrack: GPXTrackData?
        var curSeg: [GPXPoint] = []
        var pt = GPXPoint(lat: 0, lon: 0)
        var wptName = "", wptDesc = "", wptSym = "", wptIcon: String?, wptColor: String?, wptSize: Double?
        var metaNameSet = false
        init(name: String) { doc = GPXDocument(name: name) }

        func flushSeg() {
            if !curSeg.isEmpty { curTrack?.segments.append(curSeg) }
            curSeg = []
        }
        func flush() { flushSeg(); if let t = curTrack, !t.segments.isEmpty { doc.tracks.append(t) }; curTrack = nil }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
            stack.append(name); text = ""
            switch name {
            case "trk": flush(); curTrack = GPXTrackData(name: "", isRoute: false, segments: [])
            case "rte": flush(); curTrack = GPXTrackData(name: "", isRoute: true, segments: [])
            case "trkseg": flushSeg()
            case "trkpt", "rtept", "wpt":
                pt = GPXPoint(lat: Double(a["lat"] ?? "") ?? 0, lon: Double(a["lon"] ?? "") ?? 0)
                wptName = ""; wptDesc = ""; wptSym = ""; wptIcon = nil; wptColor = nil; wptSize = nil
            default: break
            }
        }
        /// Heart rate, cadence and power in the track point extensions (with or without namespace prefix).
        static func ext(_ n: String) -> Int? {
            switch n.split(separator: ":").last.map({ $0.lowercased() }) ?? "" {
            case "hr", "heartrate": return 1
            case "cad", "cadence": return 2
            case "power", "watts", "powerinwatts": return 3
            default: return nil
            }
        }
        func parser(_ parser: XMLParser, foundCharacters s: String) {
            if let l = stack.last, Self.ext(l) != nil { text += s; return }
            if let l = stack.last, ["name", "ele", "time", "desc", "sym", "gpxorg:icon", "gpxorg:iconcolor", "gpxorg:color", "gpxorg:width", "gpxorg:micon", "gpxorg:mcolor", "gpxorg:msize"].contains(l) { text += s }
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            defer { stack.removeLast() }
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let parent = stack.count >= 2 ? stack[stack.count - 2] : ""
            if let k = Self.ext(name), let v = Double(t) {
                switch k { case 1: pt.hr = v; case 2: pt.cad = v; default: pt.power = v }
            }
            switch name {
            case "gpxorg:icon": if !t.isEmpty { doc.icon = t }
            case "gpxorg:color": if !t.isEmpty { doc.color = t }
            case "gpxorg:iconcolor": if !t.isEmpty { doc.iconColor = t }
            case "gpxorg:width": if !t.isEmpty { doc.width = t }
            case "gpxorg:micon": wptIcon = t.isEmpty ? nil : t
            case "gpxorg:mcolor": wptColor = t.isEmpty ? nil : t
            case "gpxorg:msize": wptSize = Double(t)
            case "ele": pt.ele = Double(t)
            case "time": if parent == "trkpt" || parent == "rtept" || parent == "wpt" { pt.time = t }
            case "desc": if parent == "wpt" { wptDesc = t }
            case "sym": if parent == "wpt" { wptSym = t }
            case "name":
                if parent == "wpt" { wptName = t }
                else if parent == "trk" || parent == "rte" { curTrack?.name = t }
                else if parent == "metadata" && !metaNameSet && !t.isEmpty { doc.name = t; metaNameSet = true }
            case "trkpt", "rtept":
                if abs(pt.lat) <= 90, abs(pt.lon) <= 180 { curSeg.append(pt) }
            case "wpt":
                var w = GPXWaypoint(point: pt, name: wptName, desc: wptDesc, sym: wptSym)
                w.markerIcon = wptIcon; w.markerColor = wptColor; w.markerSize = wptSize
                doc.waypoints.append(w)
            case "trkseg": flushSeg()
            case "trk", "rte": flush()
            default: break
            }
        }
    }

    // MARK: write

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    public func xml() -> String {
        var o = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        o += "<gpx version=\"1.1\" creator=\"GPX Organizer\" xmlns=\"http://www.topografix.com/GPX/1/1\" xmlns:\(GPXIconTag.prefix)=\"\(GPXIconTag.namespace)\" xmlns:gpxtpx=\"http://www.garmin.com/xmlschemas/TrackPointExtension/v1\">\n"
        var inner = ""
        if let v = icon { inner += "<gpxorg:icon>\(Self.esc(v))</gpxorg:icon>" }
        if let v = iconColor { inner += "<gpxorg:iconcolor>\(Self.esc(v))</gpxorg:iconcolor>" }
        if let v = color { inner += "<gpxorg:color>\(Self.esc(v))</gpxorg:color>" }
        if let v = width { inner += "<gpxorg:width>\(Self.esc(v))</gpxorg:width>" }
        let iconXML = inner.isEmpty ? "" : "<extensions>\(inner)</extensions>"
        o += "  <metadata><name>\(Self.esc(name))</name>\(iconXML)</metadata>\n"
        func pt(_ tag: String, _ p: GPXPoint, indent: String, extra: String = "") -> String {
            var s = "\(indent)<\(tag) lat=\"\(String(format: "%.7f", p.lat))\" lon=\"\(String(format: "%.7f", p.lon))\">"
            if let e = p.ele { s += "<ele>\(String(format: "%.2f", e))</ele>" }
            if let t = p.time { s += "<time>\(Self.esc(t))</time>" }
            s += extra
            if p.hr != nil || p.cad != nil || p.power != nil {
                s += "<extensions>"
                if let v = p.power { s += "<power>\(String(format: "%.0f", v))</power>" }
                if p.hr != nil || p.cad != nil {
                    s += "<gpxtpx:TrackPointExtension>"
                    if let v = p.hr { s += "<gpxtpx:hr>\(String(format: "%.0f", v))</gpxtpx:hr>" }
                    if let v = p.cad { s += "<gpxtpx:cad>\(String(format: "%.0f", v))</gpxtpx:cad>" }
                    s += "</gpxtpx:TrackPointExtension>"
                }
                s += "</extensions>"
            }
            s += "</\(tag)>\n"
            return s
        }
        for w in waypoints {
            var extra = ""
            if !w.name.isEmpty { extra += "<name>\(Self.esc(w.name))</name>" }
            if !w.desc.isEmpty { extra += "<desc>\(Self.esc(w.desc))</desc>" }
            if !w.sym.isEmpty { extra += "<sym>\(Self.esc(w.sym))</sym>" }
            extra += w.extensionsXML()
            o += pt("wpt", w.point, indent: "  ", extra: extra)
        }
        for t in tracks {
            if t.isRoute {
                o += "  <rte>\n"
                if !t.name.isEmpty { o += "    <name>\(Self.esc(t.name))</name>\n" }
                for seg in t.segments { for p in seg { o += pt("rtept", p, indent: "    ") } }
                o += "  </rte>\n"
            } else {
                o += "  <trk>\n"
                if !t.name.isEmpty { o += "    <name>\(Self.esc(t.name))</name>\n" }
                for seg in t.segments {
                    o += "    <trkseg>\n"
                    for p in seg { o += pt("trkpt", p, indent: "      ") }
                    o += "    </trkseg>\n"
                }
                o += "  </trk>\n"
            }
        }
        o += "</gpx>\n"
        return o
    }

    // MARK: elevation profile

    public func profile(maxPoints: Int = 3000) -> Profile {
        var pr = Profile()
        var all: [GPXPoint] = []
        for t in tracks { for s in t.segments { all.append(contentsOf: s) } }
        guard all.count >= 2 else { return pr }
        var dist = 0.0
        var rawD: [Double] = [0], rawE: [Double?] = [all[0].ele]
        for i in 1..<all.count {
            dist += haversine(all[i - 1].lat, all[i - 1].lon, all[i].lat, all[i].lon)
            rawD.append(dist); rawE.append(all[i].ele)
        }
        pr.totalDistance = dist

        // speed from timestamps: distance over a window of at least ~30 s around each point
        let times: [Double?] = all.map { $0.time.flatMap { isoSeconds($0) } }
        var spd: [Double] = []
        if times.compactMap({ $0 }).count >= 2 {
            var carry = 0.0
            spd.reserveCapacity(all.count)
            for i in all.indices {
                guard let ti = times[i] else { spd.append(carry); continue }
                var lo = i, hi = i, tLo = ti, tHi = ti, steps = 0
                while tHi - tLo < 30, steps < 80 {
                    steps += 1
                    if hi + 1 < all.count, let t = times[hi + 1] { hi += 1; tHi = t }
                    if tHi - tLo >= 30 { break }
                    if lo - 1 >= 0, let t = times[lo - 1] { lo -= 1; tLo = t }
                    if (hi + 1 >= all.count) && (lo == 0) { break }
                }
                let dt = tHi - tLo
                let v = dt > 0 ? min(300, max(0, (rawD[hi] - rawD[lo]) / dt * 3.6)) : 0
                carry = v; spd.append(v)
            }
            var movD = 0.0, movT = 0.0
            for i in 1..<all.count {
                if let a = times[i - 1], let b = times[i], b > a, b - a <= 180 { movT += b - a; movD += rawD[i] - rawD[i - 1] }
            }
            pr.movingSeconds = movT
            pr.avgSpeed = movT > 0 ? movD / movT * 3.6 : 0
            pr.maxSpeed = spd.max() ?? 0
        }

        let withEle = rawE.compactMap { $0 }
        let hasEle = withEle.count >= 2
        var sm: [Double] = []
        if hasEle {
            // fill gaps in elevation by carrying the last known value
            var e: [Double] = []
            var last = withEle[0]
            for v in rawE { if let v { last = v }; e.append(last) }
            // smoothing: median of all heights within ±50 m of track, then 4 m hysteresis for ascent/descent
            sm = e
            var lo = 0, hi = 0
            for i in 0..<e.count {
                while hi < e.count, rawD[hi] <= rawD[i] + 50 { hi += 1 }
                while lo < i, rawD[lo] < rawD[i] - 50 { lo += 1 }
                sm[i] = hi - lo >= 3 ? median(Array(e[lo..<hi])) : e[i]
            }
            var base = sm[0]
            for v in sm {
                if v - base >= 4 { pr.ascent += v - base; base = v }
                else if base - v >= 4 { pr.descent += base - v; base = v }
            }
            pr.minEle = sm.min()!; pr.maxEle = sm.max()!
        }
        // heart rate, power and cadence: gaps carry the last value, then a light moving average over the decimation step
        let stride = max(1, all.count / maxPoints)
        func channel(_ get: (GPXPoint) -> Double?) -> [Double] {
            let raw = all.map(get)
            guard raw.compactMap({ $0 }).count >= 2 else { return [] }
            var out: [Double] = []; out.reserveCapacity(raw.count)
            var last = raw.compactMap { $0 }.first ?? 0
            for v in raw { if let v { last = v }; out.append(last) }
            let r = max(1, stride / 2)
            var prefix = [0.0]; prefix.reserveCapacity(out.count + 1)
            for v in out { prefix.append(prefix.last! + v) }
            return out.indices.map { i in
                let lo = max(0, i - r), hi = min(out.count - 1, i + r)
                return (prefix[hi + 1] - prefix[lo]) / Double(hi - lo + 1)
            }
        }
        let hrAll = channel { $0.hr }, powAll = channel { $0.power }, cadAll = channel { $0.cad }
        guard hasEle || !spd.isEmpty || !hrAll.isEmpty || !powAll.isEmpty || !cadAll.isEmpty else { return pr }
        func add(_ i: Int) {
            pr.dist.append(rawD[i]); pr.lat.append(all[i].lat); pr.lon.append(all[i].lon)
            if hasEle { pr.ele.append(sm[i]) }
            if !spd.isEmpty { pr.speed.append(spd[i]) }
            if !hrAll.isEmpty { pr.hr.append(hrAll[i]) }
            if !powAll.isEmpty { pr.power.append(powAll[i]) }
            if !cadAll.isEmpty { pr.cad.append(cadAll[i]) }
        }
        var i = 0
        while i < all.count { add(i); i += stride }
        if (i - stride) != all.count - 1 { add(all.count - 1) }
        return pr
    }
}

extension GPXWaypoint {
    /// Marker color and glyph derived from the Garmin symbol name.
    public var rgb: [Double] { Waypoint.rgb(forSymbol: sym) }
    public var iconName: String { Waypoint.iconName(forSymbol: sym) }
}
