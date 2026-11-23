import Foundation

/// Edits single `<wpt>` elements of a GPX file as text, so everything else in the file stays exactly as it is.
public enum WptText {
    /// Ranges of the `<wpt …>…</wpt>` (or `<wpt …/>`) elements, in file order.
    public static func ranges(in t: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        var from = t.startIndex
        while let r = t.range(of: "<wpt", range: from..<t.endIndex) {
            let after = t.index(r.lowerBound, offsetBy: 4)
            guard after < t.endIndex, [" ", ">", "\n", "\t", "\r", "/"].contains(t[after]) else { from = after; continue }
            guard let gt = t[r.lowerBound...].firstIndex(of: ">") else { break }
            if t[t.index(before: gt)] == "/" {
                let e = t.index(after: gt); out.append(r.lowerBound..<e); from = e
            } else if let c = t.range(of: "</wpt>", range: gt..<t.endIndex) {
                out.append(r.lowerBound..<c.upperBound); from = c.upperBound
            } else { break }
        }
        return out
    }

    /// Where a new `<wpt>` goes: before the first route/track (schema order), else before `</gpx>`.
    public static func insertionPoint(in t: String) -> String.Index? {
        var best: String.Index?
        for key in ["<rte", "<trk"] {
            var from = t.startIndex
            while let r = t.range(of: key, range: from..<t.endIndex) {
                let after = t.index(r.lowerBound, offsetBy: key.count)
                if after < t.endIndex, [" ", ">", "\n", "\t", "\r"].contains(t[after]) { if best == nil || r.lowerBound < best! { best = r.lowerBound }; break }
                from = after
            }
        }
        if var b = best {                       // start of that line, so the indentation of the track stays as it is
            while b > t.startIndex, t[t.index(before: b)] == " " || t[t.index(before: b)] == "\t" { b = t.index(before: b) }
            return b
        }
        return t.range(of: "</gpx>", options: .backwards)?.lowerBound
    }

    /// The root element must declare the `gpxorg` prefix before it is used inside a waypoint.
    public static func ensureNamespace(_ t: String) -> String {
        guard let rs = t.range(of: "<gpx"), let re = t.range(of: ">", range: rs.upperBound..<t.endIndex) else { return t }
        if t[rs.lowerBound..<re.upperBound].contains("xmlns:\(GPXIconTag.prefix)=") { return t }
        var s = t
        var at = re.lowerBound
        if s[s.index(before: at)] == "/" { at = s.index(before: at) }
        s.insert(contentsOf: " xmlns:\(GPXIconTag.prefix)=\"\(GPXIconTag.namespace)\"", at: at)
        return s
    }

    public static func wellFormed(_ t: String) -> Bool { XMLParser(data: Data(t.utf8)).parse() }

    public static func insert(_ element: String, into t: String) -> String? {
        guard let i = insertionPoint(in: t) else { return nil }
        var s = t
        s.insert(contentsOf: "  " + element + "\n", at: i)
        s = ensureNamespace(s)
        return wellFormed(s) ? s : nil
    }

    public static func replace(_ n: Int, with element: String, in t: String) -> String? {
        let r = ranges(in: t)
        guard r.indices.contains(n) else { return nil }
        var s = t; s.replaceSubrange(r[n], with: element)
        s = ensureNamespace(s)
        return wellFormed(s) ? s : nil
    }

    public static func remove(_ n: Int, in t: String) -> String? {
        let r = ranges(in: t)
        guard r.indices.contains(n) else { return nil }
        var s = t
        var range = r[n]
        // also take the line break and indentation in front of it
        var lo = range.lowerBound
        while lo > s.startIndex, s[s.index(before: lo)] == " " || s[s.index(before: lo)] == "\t" { lo = s.index(before: lo) }
        var hi = range.upperBound
        if hi < s.endIndex, s[hi] == "\n" { hi = s.index(after: hi) }
        range = lo..<hi
        s.removeSubrange(range); return s
    }

    /// New position of the n-th waypoint (the other content of the element is kept).
    public static func move(_ n: Int, lat: Double, lon: Double, in t: String) -> String? {
        let r = ranges(in: t)
        guard r.indices.contains(n) else { return nil }
        var el = String(t[r[n]])
        guard let gt = el.firstIndex(of: ">") else { return nil }
        var head = String(el[..<gt])
        let tail = String(el[gt...])
        func setAttr(_ name: String, _ v: Double) {
            let val = String(format: "%.7f", v)
            if let a = head.range(of: name + "=\""), let q = head[a.upperBound...].firstIndex(of: "\"") {
                head.replaceSubrange(a.upperBound..<q, with: val)
            } else { head += " \(name)=\"\(val)\"" }
        }
        setAttr("lat", lat); setAttr("lon", lon)
        el = head + tail
        var s = t; s.replaceSubrange(r[n], with: el); return s
    }

    /// `ele` and `time` children of an element, kept when the element is rewritten.
    public static func keptChildren(of el: String) -> String {
        var out = ""
        for tag in ["ele", "time"] {
            if let a = el.range(of: "<\(tag)>"), let b = el.range(of: "</\(tag)>", range: a.upperBound..<el.endIndex) { out += String(el[a.lowerBound..<b.upperBound]) }
        }
        return out
    }
}
