import Foundation

/// Stores per-file choices of this program (icon name, track colour, line width) inside the GPX file as
/// `<metadata><extensions><gpxorg:icon>mountains</gpxorg:icon><gpxorg:color>E6191A</gpxorg:color><gpxorg:width>3</gpxorg:width></extensions></metadata>`.
/// The file is patched as text, so everything else in it (Garmin extensions, formatting) stays byte-for-byte the same.
public enum GPXIconTag {
    public static let prefix = "gpxorg"
    public static let namespace = "https://github.com/Martin-Doppelbauer/gpx-organizer/ns/1"
    public static let keys = ["icon", "iconcolor", "color", "width"]

    /// Returns the text with the given values set (nil removes a value); nil if the result would not be well-formed XML.
    public static func apply(to text: String, values: [String: String?]) -> String? {
        var s = text
        for key in values.keys {                                       // remove existing elements of these keys
            if let r = s.range(of: "<\(prefix):\(key)>[^<]*</\(prefix):\(key)>", options: .regularExpression) { s.removeSubrange(r) }
        }
        if let r = s.range(of: "<extensions>\\s*</extensions>", options: .regularExpression) { s.removeSubrange(r) }
        if let r = s.range(of: "<metadata>\\s*</metadata>", options: .regularExpression) { s.removeSubrange(r) }
        let fragment = keys.compactMap { k -> String? in
            guard let v = values[k], let value = v else { return nil }
            return "<\(prefix):\(k)>\(value)</\(prefix):\(k)>"
        }.joined()
        if fragment.isEmpty { return isWellFormed(s) ? s : nil }

        // namespace declaration on the root element
        guard let rootStart = s.range(of: "<gpx"), let rootEnd = s.range(of: ">", range: rootStart.upperBound..<s.endIndex) else { return nil }
        if !s[rootStart.lowerBound..<rootEnd.upperBound].contains("xmlns:\(prefix)=") {
            var insertAt = rootEnd.lowerBound
            if s[s.index(before: insertAt)] == "/" { insertAt = s.index(before: insertAt) }
            s.insert(contentsOf: " xmlns:\(prefix)=\"\(namespace)\"", at: insertAt)
        }
        guard let rs = s.range(of: "<gpx"), let re = s.range(of: ">", range: rs.upperBound..<s.endIndex) else { return nil }

        if let ms = s.range(of: "<metadata>"), let me = s.range(of: "</metadata>", range: ms.upperBound..<s.endIndex) {
            let inner = s[ms.upperBound..<me.lowerBound]
            if let es = inner.range(of: "<extensions>") {
                s.insert(contentsOf: fragment, at: es.upperBound)
            } else {
                s.insert(contentsOf: "<extensions>\(fragment)</extensions>", at: me.lowerBound)
            }
        } else if s.range(of: "<metadata") != nil {
            return nil                                                  // unusual metadata element: leave the file alone
        } else {
            s.insert(contentsOf: "<metadata><extensions>\(fragment)</extensions></metadata>", at: re.upperBound)
        }
        return isWellFormed(s) ? s : nil
    }

    public static func apply(to text: String, icon: String?) -> String? { apply(to: text, values: ["icon": icon]) }

    private static func isWellFormed(_ s: String) -> Bool { XMLParser(data: Data(s.utf8)).parse() }

    /// Sets the name stored inside the file (`<metadata><name>` and the name of the first track/route) to `newName`.
    /// Waypoint names and everything else stay untouched; names that do not exist are not added. Nil if the result would not be well-formed.
    public static func renameInside(_ text: String, to newName: String) -> String? {
        let esc = newName.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        var s = text
        func setName(in range: Range<String.Index>) -> Bool {
            guard let r = s.range(of: "<name>[\\s\\S]*?</name>", options: .regularExpression, range: range) else { return false }
            s.replaceSubrange(r, with: "<name>\(esc)</name>")
            return true
        }
        var changed = false
        if let ms = s.range(of: "<metadata>"), let me = s.range(of: "</metadata>", range: ms.upperBound..<s.endIndex) {
            changed = setName(in: ms.upperBound..<me.lowerBound) || changed
        }
        if let ts = s.range(of: "<trk>|<rte>", options: .regularExpression) {
            // the name sits before the first segment / point
            let stop = s.range(of: "<trkseg|<rtept|<trkpt", options: .regularExpression, range: ts.upperBound..<s.endIndex)?.lowerBound ?? s.endIndex
            changed = setName(in: ts.upperBound..<stop) || changed
        }
        guard changed else { return text }
        return isWellFormed(s) ? s : nil
    }
}
