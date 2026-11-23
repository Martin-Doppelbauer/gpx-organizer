import Foundation
import ImageIO

/// A map found at a web address.
public struct MapCandidate: Identifiable {
    public let id = UUID()
    public var name: String
    public var template: String
    public var subdomains: [String]
    public var maxZoom: Int
    public var attribution: String
    public var note: String
    public var preview: Data?
    public init(name: String, template: String, subdomains: [String] = [], maxZoom: Int = 18, attribution: String = "", note: String = "") {
        self.name = name; self.template = template; self.subdomains = subdomains; self.maxZoom = maxZoom; self.attribution = attribution; self.note = note
    }
}

/// Looks for online map tiles at a web address: a tile address itself, a web page that shows a map, TileJSON / style files,
/// WMTS capabilities, ArcGIS services, or typical tile paths of a server. Forgiving about typing errors in the address.
public enum MapDiscovery {
    /// "https://{s}.tile.example.org/{z}/{x}/{y}.png" -> "tile.example.org"
    public static func hostName(of template: String) -> String {
        let t = template.replacingOccurrences(of: "{s}.", with: "").replacingOccurrences(of: "{s}-", with: "-").replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
        return URL(string: t)?.host ?? "Online map"
    }
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 6; c.timeoutIntervalForResource = 15
        c.httpAdditionalHeaders = ["User-Agent": "GPXOrganizer map search", "Accept": "*/*"]
        return URLSession(configuration: c)
    }()

    /// Tiles used to test a map: central Europe, Alps, Germany, North America, Japan, Australia (a map may cover only one region).
    private static let samples: [(Int, Int, Int)] = [(6, 33, 22), (8, 134, 90), (5, 16, 10), (3, 4, 2), (6, 15, 24), (6, 56, 25), (6, 57, 39), (10, 545, 354)]

    // MARK: tile addresses

    public static func fill(_ template: String, _ subs: [String], z: Int, x: Int, y: Int) -> URL? {
        var u = template.replacingOccurrences(of: "{z}", with: "\(z)").replacingOccurrences(of: "{x}", with: "\(x)")
            .replacingOccurrences(of: "{-y}", with: "\((1 << z) - 1 - y)").replacingOccurrences(of: "{y}", with: "\(y)")
        if !subs.isEmpty { u = u.replacingOccurrences(of: "{s}", with: subs[(x + y) % subs.count]) }
        return URL(string: u)
    }

    private static func isImage(_ d: Data) -> Bool {
        guard d.count > 60, let src = CGImageSourceCreateWithData(d as CFData, nil), CGImageSourceGetCount(src) > 0,
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, w >= 16 else { return false }
        return true
    }

    /// A sample tile of the map, or nil when no test tile can be loaded.
    public static func probe(_ template: String, _ subs: [String]) async -> Data? {
        await withTaskGroup(of: Data?.self) { g in
            for s in samples {
                g.addTask {
                    guard let u = fill(template, subs, z: s.0, x: s.1, y: s.2),
                          let (d, r) = try? await session.data(from: u), (r as? HTTPURLResponse)?.statusCode == 200, isImage(d) else { return nil }
                    return d
                }
            }
            for await r in g { if let r { g.cancelAll(); return r } }
            return nil
        }
    }

    /// Turns the many ways to write a tile address into `{z}/{x}/{y}` (and `{s}`) form; nil when it is not a tile address.
    public static func normalize(_ raw: String) -> (template: String, subdomains: [String])? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'<>`")))
        s = s.replacingOccurrences(of: "\\/", with: "/").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "%7B", with: "{").replacingOccurrences(of: "%7b", with: "{")
            .replacingOccurrences(of: "%7D", with: "}").replacingOccurrences(of: "%7d", with: "}").replacingOccurrences(of: "${", with: "{")
        while let l = s.last, ")],;\\".contains(l) { s.removeLast() }
        if s.hasPrefix("//") { s = "https:" + s }
        guard s.hasPrefix("http"), let re = try? NSRegularExpression(pattern: "\\{([^{}/?&]+)\\}") else { return nil }
        var subs: [String] = []
        var out = s
        let ns = s as NSString
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            let tok = ns.substring(with: m.range(at: 1))
            let low = tok.lowercased()
            var rep: String?
            switch low {
            case "z", "zoom", "level", "tilematrix", "tile_z", "lod": rep = "{z}"
            case "x", "col", "tilecol", "column", "tile_x": rep = "{x}"
            case "y", "row", "tilerow", "tile_y": rep = "{y}"
            case "-y", "reverse_y", "tms_y": rep = "{-y}"
            case "s", "server", "subdomain": rep = "{s}"; if subs.isEmpty { subs = ["a", "b", "c"] }
            case "r", "retina", "ratio", "scale": rep = ""
            default:
                if low.count == 3, low.dropFirst().first == "-", let a = low.first?.asciiValue, let b = low.last?.asciiValue, a < b, b - a < 8 {
                    subs = (a...b).map { String(UnicodeScalar($0)) }; rep = "{s}"
                } else if tok.contains(","), tok.count < 20 {
                    subs = tok.split(separator: ",").map(String.init); rep = "{s}"
                }
            }
            guard let rep else { return nil }          // an unknown placeholder: not usable
            out = (out as NSString).replacingCharacters(in: m.range, with: rep)
        }
        guard out.contains("{z}"), out.contains("{x}"), out.contains("{y}") || out.contains("{-y}") else { return nil }
        return (out, subs)
    }

    /// An address with real tile numbers (`…/12/2200/1343.png`) becomes a template; both column/row orders are returned.
    private static func templatesFromLiteral(_ url: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: "/(\\d{1,2})/(\\d{1,7})/(\\d{1,7})(\\.[A-Za-z]{3,4})?(?=$|\\?|#)") else { return [] }
        let ns = url as NSString
        guard let m = re.firstMatch(in: url, range: NSRange(location: 0, length: ns.length)) else { return [] }
        let z = Int(ns.substring(with: m.range(at: 1))) ?? 99
        guard z <= 22 else { return [] }
        let ext = m.range(at: 4).location != NSNotFound ? ns.substring(with: m.range(at: 4)) : ""
        let pre = ns.substring(to: m.range.location), post = ns.substring(from: m.range.location + m.range.length)
        let rowFirst = url.lowercased().contains("mapserver/tile") || url.lowercased().contains("wmts") || url.lowercased().contains("/tile/")
        let a = "\(pre)/{z}/{x}/{y}\(ext)\(post)", b = "\(pre)/{z}/{y}/{x}\(ext)\(post)"
        return rowFirst ? [b, a] : [a, b]
    }

    // MARK: fetching

    private static func get(_ url: URL, limit: Int = 12_000_000) async -> (Data, String)? {
        guard let (d, r) = try? await session.data(from: url), let h = r as? HTTPURLResponse, h.statusCode == 200, d.count <= limit else { return nil }
        return (d, (h.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased())
    }

    /// An address typed in a hurry: scheme missing or misspelled, spaces, quotes.
    public static func cleanAddress(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'<>`")))
        guard !s.isEmpty else { return nil }
        if let re = try? NSRegularExpression(pattern: "^[hH][tT]{1,3}[pP][sS]?:?/{0,3}") , let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) {
            s = "https://" + (s as NSString).substring(from: m.range.length)
        } else if !s.contains("://") { s = "https://" + (s.hasPrefix("//") ? String(s.dropFirst(2)) : s) }
        return s
    }

    // MARK: finding templates inside text

    private static func templates(inText t: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: "(?:https?:)?\\\\?/\\\\?/[A-Za-z0-9\\-\\._~:/\\?#\\[\\]@!\\$&\\(\\)\\*\\+,;=%\\{\\}\\\\]+") else { return [] }
        let ns = t as NSString
        var out: [String] = []
        for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
            let tok = ns.substring(with: m.range)
            if tok.contains("{") || tok.contains("%7B") || tok.contains("${") { out.append(tok) }
        }
        return out
    }

    private static func subdomains(inText t: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: "subdomains\\s*[:=]\\s*(\\[[^\\]]*\\]|[\"'][A-Za-z0-9]+[\"'])"),
              let m = re.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length)) else { return [] }
        let v = (t as NSString).substring(with: m.range(at: 1))
        let letters = v.filter { $0.isLetter || $0.isNumber || $0 == "," || $0 == "[" || $0 == "]" || $0 == "'" || $0 == "\"" }
        if v.hasPrefix("[") { return letters.split(whereSeparator: { ",[]'\"".contains($0) }).map(String.init) }
        return letters.filter { $0 != "'" && $0 != "\"" }.map { String($0) }
    }

    // MARK: structured sources

    private static func fromJSON(_ d: Data, base: URL) async -> [MapCandidate] {
        guard let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [] }
        var out: [MapCandidate] = []
        let host = base.host ?? "map"
        func add(_ tiles: [String], _ name: String, _ maxz: Int?, _ attr: String?) {
            for t in tiles { if let n = normalize(t) { out.append(MapCandidate(name: name, template: n.template, subdomains: n.subdomains, maxZoom: maxz ?? 18, attribution: attr ?? "© " + host, note: "from a map file")) } }
        }
        if let tiles = obj["tiles"] as? [String] { add(tiles, (obj["name"] as? String) ?? host, obj["maxzoom"] as? Int, obj["attribution"] as? String) }
        if let sources = obj["sources"] as? [String: Any] {                  // a MapLibre / Mapbox style
            for (k, v) in sources {
                guard let s = v as? [String: Any], (s["type"] as? String) == "raster" else { continue }
                if let tiles = s["tiles"] as? [String] { add(tiles, "\(host) – \(k)", s["maxzoom"] as? Int, s["attribution"] as? String) }
                else if let u = s["url"] as? String, let url = URL(string: u, relativeTo: base), let (dd, _) = await get(url) { out += await fromJSON(dd, base: url) }
            }
        }
        if let ti = obj["tileInfo"] as? [String: Any], (obj["singleFusedMapCache"] as? Bool) ?? true {   // an ArcGIS map service with tiles
            let lods = (ti["lods"] as? [[String: Any]])?.count ?? 19
            var u = base.absoluteString
            if let q = u.firstIndex(of: "?") { u = String(u[..<q]) }
            var nm = host
            if let r = u.range(of: "/MapServer") { nm = u[..<r.lowerBound].split(separator: "/").last.map { String($0).replacingOccurrences(of: "_", with: " ") } ?? host }
            if u.contains("/MapServer") { out.append(MapCandidate(name: nm, template: u.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/tile/{z}/{y}/{x}",
                                                                   maxZoom: max(1, lods - 1), attribution: (obj["copyrightText"] as? String) ?? "© " + host, note: "ArcGIS map service")) }
        }
        if let services = obj["services"] as? [[String: Any]] {              // an ArcGIS folder
            for s in services.prefix(40) where (s["type"] as? String) == "MapServer" {
                guard let n = s["name"] as? String, let root = rootOf(base, marker: "/rest/services"),
                      let u = URL(string: root + "/rest/services/" + n + "/MapServer?f=json"), let (dd, _) = await get(u) else { continue }
                out += await fromJSON(dd, base: u)
            }
        }
        return out
    }

    private static func rootOf(_ u: URL, marker: String) -> String? {
        let s = u.absoluteString
        guard let r = s.range(of: marker) else { return nil }
        return String(s[..<r.lowerBound])
    }

    private final class WMTSParser: NSObject, XMLParserDelegate {
        struct Layer { var title = "", id = "", formats: [String] = [], styles: [String] = [], sets: [String] = [], resources: [(String, String)] = [], dims: [String: String] = [:] }
        var layers: [Layer] = []
        var sets: [String: (crs: String, ids: [String])] = [:]
        var getTile: String?
        var cur: Layer?
        var curSet: String?
        var path: [String] = []
        var text = ""
        var inGetTile = false
        var dimName = ""
        func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
            let n = name.split(separator: ":").last.map(String.init) ?? name
            path.append(n); text = ""
            if n == "Layer" { cur = Layer() }
            if n == "TileMatrixSet", path.count >= 2, path[path.count - 2] == "Contents" { curSet = nil }
            if n == "ResourceURL", a["resourceType"] == "tile", let t = a["template"] { cur?.resources.append((a["format"] ?? "", t)) }
            if n == "Operation", a["name"] == "GetTile" { inGetTile = true }
            if n == "Get", inGetTile, getTile == nil, let h = a["xlink:href"] ?? a["href"] { getTile = h }
        }
        func parser(_ p: XMLParser, foundCharacters s: String) { text += s }
        func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let n = name.split(separator: ":").last.map(String.init) ?? name
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let parent = path.count >= 2 ? path[path.count - 2] : ""
            switch n {
            case "Title": if parent == "Layer" { cur?.title = t }
            case "Identifier":
                if parent == "Layer" { cur?.id = t }
                else if parent == "Dimension" { dimName = t }
                else if parent == "Style" { cur?.styles.append(t) }
                else if parent == "TileMatrixSet", path.count >= 3, path[path.count - 3] == "Contents" { curSet = t; if sets[t] == nil { sets[t] = ("", []) } }
                else if parent == "TileMatrix", let s = curSet { sets[s]?.ids.append(t) }
            case "SupportedCRS": if let s = curSet { sets[s]?.crs = t }
            case "Default": if parent == "Dimension", !dimName.isEmpty { cur?.dims[dimName] = t }
            case "Format": if parent == "Layer" { cur?.formats.append(t) }
            case "TileMatrixSet": if parent == "TileMatrixSetLink" { cur?.sets.append(t) }
            case "Layer": if let l = cur { layers.append(l) }; cur = nil
            case "Operation": inGetTile = false
            default: break
            }
            path.removeLast()
        }
    }

    private static func fromWMTS(_ d: Data, base: URL) -> [MapCandidate] {
        let p = WMTSParser(); let x = XMLParser(data: d); x.delegate = p; x.parse()
        guard !p.layers.isEmpty else { return [] }
        let host = base.host ?? "server"
        var out: [MapCandidate] = []
        for l in p.layers.prefix(80) {
            guard let setID = l.sets.first(where: { id in
                let s = p.sets[id]; let k = ((s?.crs ?? "") + " " + id).lowercased()
                return k.contains("3857") || k.contains("900913") || k.contains("3785") || k.contains("webmercator") || k.contains("googlemaps") || id == "PM"
            }), let set = p.sets[setID] else { continue }
            // how the zoom level appears in the matrix identifiers ("7", "EPSG:3857:7", "WebMercatorQuad:7")
            var zExpr = "{z}"
            if let id5 = set.ids.first(where: { $0.hasSuffix("5") && Int($0.split(separator: ":").last ?? "") == 5 }), id5 != "5" { zExpr = String(id5.dropLast()) + "{z}" }
            let style = l.styles.first ?? "default"
            let fmt = l.formats.first ?? "image/png"
            let maxz = max(1, set.ids.compactMap { Int($0.split(separator: ":").last ?? "") }.max() ?? (set.ids.count - 1))
            var template: String?
            if let r = l.resources.first(where: { $0.0 == fmt }) ?? l.resources.first {
                var t0 = r.1.replacingOccurrences(of: "{Layer}", with: l.id)
                for (k, v) in l.dims { t0 = t0.replacingOccurrences(of: "{\(k)}", with: v) }
                if t0.contains("{Time}") { t0 = t0.replacingOccurrences(of: "{Time}", with: "current") }
                template = t0.replacingOccurrences(of: "{TileMatrixSet}", with: setID).replacingOccurrences(of: "{Style}", with: style)
                    .replacingOccurrences(of: "{TileMatrix}", with: zExpr).replacingOccurrences(of: "{TileRow}", with: "{y}").replacingOccurrences(of: "{TileCol}", with: "{x}")
            } else if let g0 = p.getTile {
                let g = g0.firstIndex(of: "?").map { String(g0[..<$0]) } ?? g0
                let sep = "?"
                let f = fmt.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "/-_.~"))) ?? fmt
                template = g + sep + "SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=\(l.id)&STYLE=\(style)&FORMAT=\(f)&TILEMATRIXSET=\(setID)&TILEMATRIX=\(zExpr)&TILEROW={y}&TILECOL={x}"
            }
            // other placeholders (time …) get their default
            if var t = template, let n = normalize(t) { t = n.template; out.append(MapCandidate(name: l.title.isEmpty ? l.id : l.title, template: t, subdomains: n.subdomains, maxZoom: maxz, attribution: "© " + host, note: "WMTS layer \(l.id)")) }
        }
        return out
    }

    // MARK: the search

    /// Searches an address for maps. Returns the maps that really deliver tiles (with a preview) and short notes about what was tried.
    public static func discover(_ input: String, progress: @escaping @Sendable (String) -> Void) async -> (candidates: [MapCandidate], notes: [String]) {
        var notes: [String] = []
        var found: [MapCandidate] = []
        var tried = Set<String>()
        func add(_ c0: MapCandidate) {
            var c = c0
            // addresses that carry a personal access key are not offered (the key belongs to the page's owner)
            if let re = try? NSRegularExpression(pattern: "[?&](api_?key|key|token|access_token|appid|app_id|apikey)=", options: .caseInsensitive),
               re.firstMatch(in: c.template, range: NSRange(location: 0, length: (c.template as NSString).length)) != nil {
                if !notes.contains(where: { $0.contains("access key") }) { notes.append("Maps that need an access key (API key) are not offered.") }
                return
            }
            // a.tile.example.org / tile-b.example.org: all servers of a pool become one map with {s}
            if !c.template.contains("{s}"), let host = URL(string: c.template.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: ""))?.host {
                var newHost: String?
                if let r = host.range(of: "^[a-d]\\.", options: .regularExpression) { newHost = "{s}." + host[r.upperBound...] }
                else if let r = host.range(of: "-[a-d]\\.", options: .regularExpression) { newHost = host[..<r.lowerBound] + "-{s}." + host[r.upperBound...] }
                if let nh = newHost { c.template = c.template.replacingOccurrences(of: host, with: nh); c.subdomains = ["a", "b", "c"] }
            }
            if tried.insert(c.template.lowercased()).inserted { found.append(c) }
        }

        let tokens = input.split(whereSeparator: { $0.isWhitespace || $0 == "," && !$0.isLetter }).map(String.init)
        // "openstreetmap", "esri" … : known maps, also with typing errors
        for e in MapCatalog.fuzzyMatches(input).prefix(8) {
            add(MapCandidate(name: e.name, template: e.template, subdomains: e.subdomains, maxZoom: e.maxZoom, attribution: e.attribution, note: e.note))
        }
        for token in tokens {
            guard token.contains(".") || token.contains("/") || token.contains("{") else { continue }
            // 1. a tile address itself
            if let n = normalize(cleanAddress(token) ?? token) {
                progress("Testing the tile address …")
                if let d = await probe(n.template, n.subdomains) {
                    var c = MapCandidate(name: hostName(of: n.template),
                                         template: n.template, subdomains: n.subdomains, note: "tile address"); c.preview = d; add(c); continue
                }
            }
            guard let addr = cleanAddress(token) else { continue }
            for t in templatesFromLiteral(addr) {
                if let n = normalize(t) {
                    progress("Testing the tile address …")
                    if let d = await probe(n.template, n.subdomains) {
                        var c = MapCandidate(name: URL(string: addr)?.host ?? "Online map", template: n.template, subdomains: n.subdomains, note: "tile address"); c.preview = d; add(c)
                        break
                    }
                }
            }
            if found.contains(where: { $0.preview != nil }) { continue }
            // 2. the page or file at the address, then the server
            guard var url = URL(string: addr), url.host != nil else { notes.append("“\(token)” is not a web address."); continue }
            var page = await { () -> (Data, String)? in progress("Opening \(url.host ?? addr) …"); return await get(url) }()
            if page == nil, url.scheme == "https", let u2 = URL(string: addr.replacingOccurrences(of: "https://", with: "http://")) { page = await get(u2); if page != nil { url = u2 } }
            if page == nil, let h = url.host, !h.hasPrefix("www."), let u3 = URL(string: addr.replacingOccurrences(of: "://" + h, with: "://www." + h)) { page = await get(u3); if page != nil { url = u3 } }
            if page == nil { notes.append("\(url.host ?? addr) did not answer at “\(addr)”; the usual tile paths of the server are tried.") }
            var raws: [String] = []
            var extraSubs: [String] = []
            if let (data, type) = page {
                if type.contains("json") || data.first == UInt8(ascii: "{") {
                    progress("Reading map file …"); for c in await fromJSON(data, base: url) { add(c) }
                }
                if type.contains("xml") || data.prefix(200).contains(UInt8(ascii: "<")) && String(decoding: data.prefix(400), as: UTF8.self).contains("Capabilities") {
                    progress("Reading WMTS capabilities …"); for c in fromWMTS(data, base: url) { add(c) }
                }
                let text = String(decoding: data, as: UTF8.self)
                raws += templates(inText: text); extraSubs = subdomains(inText: text)
                if type.contains("html") || text.contains("<script") {
                    // scripts of the page usually hold the tile addresses
                    var scripts: [URL] = []
                    if let re = try? NSRegularExpression(pattern: "<script[^>]+src=[\"']([^\"']+)[\"']", options: .caseInsensitive) {
                        let ns = text as NSString
                        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)).prefix(10) {
                            if let u = URL(string: ns.substring(with: m.range(at: 1)), relativeTo: url)?.absoluteURL { scripts.append(u) }
                        }
                    }
                    for (i, s) in scripts.enumerated() {
                        progress("Searching the page's scripts (\(i + 1) of \(scripts.count)) …")
                        if let (sd, _) = await get(s, limit: 3_000_000) { let st = String(decoding: sd, as: UTF8.self); raws += templates(inText: st); if extraSubs.isEmpty { extraSubs = subdomains(inText: st) } }
                    }
                    if let re = try? NSRegularExpression(pattern: "(?:href|src)=[\"']([^\"']*(?:capabilit|tilejson|style\\.json|\\.json)[^\"']*)[\"']", options: .caseInsensitive) {
                        let ns = text as NSString
                        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)).prefix(4) {
                            guard let u = URL(string: ns.substring(with: m.range(at: 1)), relativeTo: url)?.absoluteURL, let (dd, ty) = await get(u) else { continue }
                            if ty.contains("xml") { for c in fromWMTS(dd, base: u) { add(c) } } else { for c in await fromJSON(dd, base: u) { add(c) } }
                        }
                    }
                }
            }
            for r in Set(raws) {
                if let n = normalize(r) {
                    var subs = n.subdomains
                    if n.template.contains("{s}"), extraSubs.count > 0 { subs = extraSubs }
                    add(MapCandidate(name: hostName(of: n.template),
                                     template: n.template, subdomains: subs, note: "found in the page"))
                }
            }
            // 3. typical places on the server
            if found.filter({ $0.preview != nil }).isEmpty {
                let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                var root = (comps?.scheme ?? "https") + "://" + (url.host ?? "")
                if let p = comps?.port { root += ":\(p)" }
                var base = root + url.path
                while base.hasSuffix("/") { base.removeLast() }
                let paths = ["/{z}/{x}/{y}.png", "/{z}/{x}/{y}.jpg", "/{z}/{x}/{y}.jpeg", "/{z}/{x}/{y}.webp", "/tiles/{z}/{x}/{y}.png", "/tile/{z}/{x}/{y}.png", "/tile/{z}/{y}/{x}", "/{z}/{y}/{x}.png",
                             "/{z}/{x}/{y}", "/maps/{z}/{x}/{y}.png", "/osm/{z}/{x}/{y}.png"]
                var guesses = paths.map { base + $0 }
                if base != root { guesses += paths.map { root + $0 } }
                for (i, g) in guesses.enumerated() {
                    progress("Trying typical tile paths (\(i + 1) of \(guesses.count)) …")
                    var subs: [String] = []
                    var t = g
                    if let h = url.host, let r = h.range(of: "^[a-d]\\.", options: .regularExpression) { t = t.replacingOccurrences(of: h, with: "{s}." + h[r.upperBound...]); subs = ["a", "b", "c"] }
                    if let d = await probe(t, subs) { var c = MapCandidate(name: (url.host ?? "Online map") + " tiles", template: t, subdomains: subs, note: "typical tile path"); c.preview = d; add(c); break }
                }
                // capabilities and service lists at the usual places
                for suffix in ["", "?SERVICE=WMTS&REQUEST=GetCapabilities&VERSION=1.0.0", "/WMTSCapabilities.xml", "/wmts?SERVICE=WMTS&REQUEST=GetCapabilities", "/1.0.0/WMTSCapabilities.xml", "/wmts/1.0.0/WMTSCapabilities.xml",
                               "/geoserver/gwc/service/wmts?REQUEST=GetCapabilities", "/tilejson.json", "/tiles.json", "/styles.json", "/arcgis/rest/services?f=json", "/rest/services?f=json"] {
                    for b in Set([base, root]) {
                        if suffix.isEmpty && b == root { continue }
                        guard let u = URL(string: b + suffix), let (dd, ty) = await get(u) else { continue }
                        progress("Reading \(suffix) …")
                        if ty.contains("xml") || dd.prefix(300).contains(UInt8(ascii: "<")) { for c in fromWMTS(dd, base: u) { add(c) } } else { for c in await fromJSON(dd, base: u) { add(c) } }
                    }
                    if found.count >= 25 { break }
                }
            }
            if url.path.contains("/MapServer") || url.path.contains("/rest/services") {
                var j = url.absoluteString
                if !j.contains("f=json") { j += (j.contains("?") ? "&" : "?") + "f=json" }
                if let u = URL(string: j), let (dd, _) = await get(u) { progress("Reading ArcGIS services …"); for c in await fromJSON(dd, base: url) { add(c) } }
            }
        }
        // check what really delivers tiles
        var good: [MapCandidate] = []
        // a large service lists hundreds of layers: the ones that look like a general map are tested first
        let likely = ["topo", "plan", "map", "carte", "karte", "ortho", "photo", "satell", "imagery", "relief", "base", "osm", "street", "scan", "pixelkarte", "standard", "outdoor"]
        func score(_ c: MapCandidate) -> Int { let h = (c.name + " " + c.template).lowercased(); return likely.filter { h.contains($0) }.count }
        let ranked = found.enumerated().sorted { (score($0.element), -$0.offset) > (score($1.element), -$1.offset) }.map { $0.element }
        if ranked.count > 40 { notes.append("\(ranked.count) maps were found; the 40 most likely ones are tested. Narrow the address to find a specific one.") }
        let list = Array(ranked.prefix(40))
        var i = 0
        while i < list.count {
            let chunk = Array(list[i..<min(list.count, i + 6)])
            progress("Testing \(min(list.count, i + 6)) of \(list.count) maps …")
            let results = await withTaskGroup(of: (Int, Data?).self) { g -> [(Int, Data?)] in
                for (k, c) in chunk.enumerated() {
                    g.addTask { if let p = c.preview { return (k, p) }; return (k, await probe(c.template, c.subdomains)) }
                }
                var r: [(Int, Data?)] = []
                for await x in g { r.append(x) }
                return r
            }
            for (k, d) in results.sorted(by: { $0.0 < $1.0 }) { if let d { var c = chunk[k]; c.preview = d; good.append(c) } }
            i += 6
        }
        if good.isEmpty { notes.append("No map tiles could be found there.") }
        return (good, notes)
    }
}
