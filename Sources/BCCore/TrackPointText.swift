import Foundation

/// Reads and patches the heights of track points (`<trkpt>`, `<rtept>`) as text, so everything else in a GPX file stays as it is.
public enum TrackPointText {
    public struct Point {
        public let range: Range<String.Index>        // the whole element
        public let tag: String                       // "trkpt" or "rtept"
        public let lat: Double, lon: Double
        public let ele: Double?
        let selfClosing: Bool
        let eleRange: Range<String.Index>?           // text between <ele> and </ele>
        let openEnd: String.Index                    // just after the '>' of the opening tag
    }

    private static func attr(_ tag: Substring, _ name: String) -> Double? {
        guard let a = tag.range(of: name + "=\"") else { return nil }
        let rest = tag[a.upperBound...]
        guard let q = rest.firstIndex(of: "\"") else { return nil }
        return Double(rest[..<q])
    }

    /// All track and route points in file order (points with impossible coordinates are left out).
    public static func points(in t: String) -> [Point] {
        var out: [Point] = []
        for tag in ["trkpt", "rtept"] {
            var from = t.startIndex
            while let r = t.range(of: "<" + tag, range: from..<t.endIndex) {
                let after = t.index(r.lowerBound, offsetBy: tag.count + 1)
                guard after < t.endIndex, [" ", ">", "\n", "\t", "\r", "/"].contains(t[after]) else { from = after; continue }
                guard let gt = t[r.lowerBound...].firstIndex(of: ">") else { break }
                let head = t[r.lowerBound...gt]
                let selfClosing = t[t.index(before: gt)] == "/"
                var end = t.index(after: gt)
                var eleRange: Range<String.Index>?
                var ele: Double?
                if !selfClosing {
                    guard let c = t.range(of: "</" + tag + ">", range: end..<t.endIndex) else { break }
                    let inner = t[end..<c.lowerBound]
                    if let a = inner.range(of: "<ele>"), let b = inner.range(of: "</ele>", range: a.upperBound..<inner.endIndex) {
                        eleRange = a.upperBound..<b.lowerBound
                        ele = Double(inner[a.upperBound..<b.lowerBound].trimmingCharacters(in: .whitespaces))
                    }
                    end = c.upperBound
                }
                if let lat = attr(head, "lat"), let lon = attr(head, "lon"), abs(lat) <= 90, abs(lon) <= 180 {
                    out.append(Point(range: r.lowerBound..<end, tag: tag, lat: lat, lon: lon, ele: ele, selfClosing: selfClosing,
                                     eleRange: eleRange, openEnd: t.index(after: gt)))
                }
                from = end
            }
        }
        return out.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// Writes the heights into the text (one per point, in the order of `points`).
    public static func setHeights(_ heights: [Double], of pts: [Point], in t: String) -> String {
        var s = t
        for (p, h) in zip(pts, heights).reversed() {          // from the back, so earlier positions stay valid
            let v = String(format: "%.1f", h)
            if let r = p.eleRange { s.replaceSubrange(r, with: v) }
            else if p.selfClosing {
                let end = p.range.upperBound                  // "…/>" becomes "…><ele>v</ele></tag>"
                let slash = s.index(end, offsetBy: -2)
                s.replaceSubrange(slash..<end, with: "><ele>\(v)</ele></\(p.tag)>")
            } else { s.insert(contentsOf: "<ele>\(v)</ele>", at: p.openEnd) }
        }
        return s
    }

    /// Ascent and descent (metres) of a height series; changes below 4 m do not count.
    public static func climb(_ e: [Double]) -> (up: Double, down: Double) {
        guard let first = e.first else { return (0, 0) }
        var base = first, up = 0.0, down = 0.0
        for v in e {
            if v - base >= 4 { up += v - base; base = v } else if base - v >= 4 { down += base - v; base = v }
        }
        return (up, down)
    }
}
