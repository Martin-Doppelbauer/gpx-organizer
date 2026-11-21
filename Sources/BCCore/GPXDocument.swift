import Foundation

public struct GPXPoint {
    public var lat: Double
    public var lon: Double
    public var ele: Double?
    public var time: String?
    public init(lat: Double, lon: Double, ele: Double? = nil, time: String? = nil) {
        self.lat = lat; self.lon = lon; self.ele = ele; self.time = time
    }
}

public struct GPXWaypoint {
    public var point: GPXPoint
    public var name: String
    public var desc: String
    public var sym: String
    public init(point: GPXPoint, name: String, desc: String = "", sym: String = "") {
        self.point = point; self.name = name; self.desc = desc; self.sym = sym
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
    public var hasElevation: Bool { !ele.isEmpty }
}

/// Complete, editable GPX file content (tracks, routes, waypoints). Value type so edits can be snapshotted for undo.
public struct GPXDocument {
    public var name: String
    public var tracks: [GPXTrackData] = []
    public var waypoints: [GPXWaypoint] = []

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
        var wptName = "", wptDesc = "", wptSym = ""
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
                wptName = ""; wptDesc = ""; wptSym = ""
            default: break
            }
        }
        func parser(_ parser: XMLParser, foundCharacters s: String) {
            if let l = stack.last, ["name", "ele", "time", "desc", "sym"].contains(l) { text += s }
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            defer { stack.removeLast() }
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let parent = stack.count >= 2 ? stack[stack.count - 2] : ""
            switch name {
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
                doc.waypoints.append(GPXWaypoint(point: pt, name: wptName, desc: wptDesc, sym: wptSym))
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
        o += "<gpx version=\"1.1\" creator=\"GPX Organizer\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n"
        o += "  <metadata><name>\(Self.esc(name))</name></metadata>\n"
        func pt(_ tag: String, _ p: GPXPoint, indent: String, extra: String = "") -> String {
            var s = "\(indent)<\(tag) lat=\"\(String(format: "%.7f", p.lat))\" lon=\"\(String(format: "%.7f", p.lon))\">"
            if let e = p.ele { s += "<ele>\(String(format: "%.2f", e))</ele>" }
            if let t = p.time { s += "<time>\(Self.esc(t))</time>" }
            s += extra + "</\(tag)>\n"
            return s
        }
        for w in waypoints {
            var extra = ""
            if !w.name.isEmpty { extra += "<name>\(Self.esc(w.name))</name>" }
            if !w.desc.isEmpty { extra += "<desc>\(Self.esc(w.desc))</desc>" }
            if !w.sym.isEmpty { extra += "<sym>\(Self.esc(w.sym))</sym>" }
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
        var rawD: [Double] = [0], rawE: [Double?] = [all[0].ele], idx = [0]
        for i in 1..<all.count {
            dist += haversine(all[i - 1].lat, all[i - 1].lon, all[i].lat, all[i].lon)
            rawD.append(dist); rawE.append(all[i].ele); idx.append(i)
        }
        pr.totalDistance = dist
        let withEle = rawE.compactMap { $0 }
        guard withEle.count >= 2 else { return pr }
        // fill gaps in elevation by carrying the last known value
        var e: [Double] = []
        var last = withEle[0]
        for v in rawE { if let v { last = v }; e.append(last) }
        // smoothing: median of all heights within ±50 m of track, then 4 m hysteresis for ascent/descent
        var sm = e
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
        let stride = max(1, all.count / maxPoints)
        var i = 0
        while i < all.count {
            pr.dist.append(rawD[i]); pr.ele.append(sm[i]); pr.lat.append(all[i].lat); pr.lon.append(all[i].lon)
            i += stride
        }
        if (i - stride) != all.count - 1 {
            let k = all.count - 1
            pr.dist.append(rawD[k]); pr.ele.append(sm[k]); pr.lat.append(all[k].lat); pr.lon.append(all[k].lon)
        }
        return pr
    }
}
