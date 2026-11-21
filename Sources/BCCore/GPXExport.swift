import Foundation

extension GPXDocument {
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    /// GPX where every track is written as a route (`rte`) instead of a track (`trk`).
    public func gpxAsRoute() -> String {
        var d = self
        d.tracks = tracks.map { t in
            GPXTrackData(name: t.name, isRoute: true, segments: [t.segments.flatMap { $0 }])
        }
        return d.xml()
    }

    /// GPX where routes are written as tracks.
    public func gpxAsTrack() -> String {
        var d = self
        d.tracks = tracks.map { GPXTrackData(name: $0.name, isRoute: false, segments: $0.segments) }
        return d.xml()
    }

    public func kml() -> String {
        var o = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<kml xmlns=\"http://www.opengis.net/kml/2.2\">\n<Document>\n  <name>\(Self.esc(name))</name>\n"
        o += "  <Style id=\"line\"><LineStyle><color>ff1e5cff</color><width>4</width></LineStyle></Style>\n"
        for w in waypoints {
            o += "  <Placemark><name>\(Self.esc(w.name))</name><Point><coordinates>\(w.point.lon),\(w.point.lat),\(w.point.ele ?? 0)</coordinates></Point></Placemark>\n"
        }
        for t in tracks {
            for seg in t.segments {
                o += "  <Placemark><name>\(Self.esc(t.name.isEmpty ? name : t.name))</name><styleUrl>#line</styleUrl><LineString><tessellate>1</tessellate><coordinates>\n"
                for p in seg { o += "    \(String(format: "%.7f,%.7f", p.lon, p.lat)),\(p.ele.map { String(format: "%.1f", $0) } ?? "0")\n" }
                o += "  </coordinates></LineString></Placemark>\n"
            }
        }
        return o + "</Document>\n</kml>\n"
    }

    public func csv() -> String {
        var o = "nr;lat;lon;ele;distance_m;time\n"
        var n = 0
        var dist = 0.0
        var prev: GPXPoint?
        for t in tracks { for s in t.segments { for p in s {
            if let q = prev { dist += haversine(q.lat, q.lon, p.lat, p.lon) }
            prev = p; n += 1
            o += "\(n);\(String(format: "%.7f;%.7f", p.lat, p.lon));\(p.ele.map { String(format: "%.1f", $0) } ?? "");\(String(format: "%.1f", dist));\(p.time ?? "")\n"
        } } }
        return o
    }
}
