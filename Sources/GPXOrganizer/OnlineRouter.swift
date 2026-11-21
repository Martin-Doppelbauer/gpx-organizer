import Foundation
import BCCore

/// Routing on OpenStreetMap data through the public BRouter server (brouter.de). Used for the online maps:
/// the picture of the map does not matter, the route follows the OSM paths and roads.
enum OnlineRouter {
    static let host = "brouter.de"

    struct Failure: LocalizedError {
        let errorDescription: String?
        var tooLong = false          // the server gave up (time limit): a shorter request may work
    }

    typealias Pt = (lat: Double, lon: Double)
    private struct Leg { var points: [Pt]; var distance: Double; var duration: Double }

    /// BRouter profile and the parameters that express what each of our profiles prefers.
    static func query(_ p: RouteProfile) -> String {
        switch p {
        case .hiking: return "profile=hiking-mountain"
        case .roadBike: return "profile=fastbike&profile:consider_traffic=0.5"            // busy (federal) roads rather avoided
        case .mountainBike: return "profile=mtb"
        case .car: return "profile=car-fast&profile:consider_town=1"                       // fast roads, town centres avoided
        case .motorcycle: return "profile=car-fast&profile:avoid_motorways=1&profile:consider_town=1"
        }
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 240
        c.timeoutIntervalForResource = 600
        c.httpAdditionalHeaders = ["User-Agent": "GPX Organizer"]
        return URLSession(configuration: c)
    }()

    static func plan(vias: [Pt], profile: RouteProfile, cancelled: () -> Bool) async throws -> RouteResult {
        var result = RouteResult()
        guard vias.count >= 2 else { return result }
        result.viaIndex = [0]
        for leg in 0..<(vias.count - 1) {
            if cancelled() { throw RouteError.cancelled }
            let l = try await routeLeg(vias[leg], vias[leg + 1], query(profile), profile, leg: leg, cancelled: cancelled)
            for (i, p) in l.points.enumerated() where !(i == 0 && !result.points.isEmpty) { result.points.append(p) }
            result.distance += l.distance; result.duration += l.duration
            result.viaIndex.append(result.points.count - 1)
        }
        return result
    }

    /// One leg. The public server stops long calculations (about 8 s); very long legs are therefore cut into pieces
    /// of roughly 40 km along a quick guide route and the pieces are routed with the real profile.
    private static func routeLeg(_ a: Pt, _ b: Pt, _ q: String, _ profile: RouteProfile, leg: Int, cancelled: () -> Bool) async throws -> Leg {
        let straight = length([a, b])
        if straight < 70_000 {
            do { return try await fetch(a, b, q, profile, leg: leg) }
            catch let f as Failure where f.tooLong { /* fall through to the pieces */ }
        }
        // guide route: the cheapest profile that works for this kind of vehicle
        let motor = profile == .car || profile == .motorcycle
        let guideQ = motor ? "profile=car-fast" : "profile=fastbike"
        var guide: Leg?
        do { guide = try await fetch(a, b, guideQ, profile, leg: leg) } catch { guide = nil }
        var cuts: [Pt] = [a]
        if let g = guide {
            var acc = 0.0
            for i in 1..<g.points.count {
                acc += length([g.points[i - 1], g.points[i]])
                if acc >= 40_000, length([g.points[i], b]) > 15_000 { cuts.append(g.points[i]); acc = 0 }
            }
        } else {
            let n = max(1, Int((straight / 40_000).rounded(.up)))
            for k in 1..<n { let t = Double(k) / Double(n); cuts.append((a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t)) }
        }
        cuts.append(b)
        var out = Leg(points: [], distance: 0, duration: 0)
        for i in 0..<(cuts.count - 1) {
            if cancelled() { throw RouteError.cancelled }
            let piece: Leg
            do { piece = try await fetch(cuts[i], cuts[i + 1], q, profile, leg: leg) }
            catch let f as Failure where f.tooLong {
                throw Failure(errorDescription: "The online server could not calculate this long route. Add via points to split it.")
            }
            for (k, p) in piece.points.enumerated() where !(k == 0 && !out.points.isEmpty) { out.points.append(p) }
            out.distance += piece.distance; out.duration += piece.duration
        }
        return out
    }

    private static func fetch(_ a: Pt, _ b: Pt, _ q: String, _ profile: RouteProfile, leg: Int) async throws -> Leg {
        let lonlats = String(format: "lonlats=%.6f,%.6f%%7C%.6f,%.6f", a.lon, a.lat, b.lon, b.lat)
        guard let url = URL(string: "https://\(host)/brouter?\(lonlats)&\(q)&alternativeidx=0&format=gpx") else {
            throw Failure(errorDescription: "Invalid request")
        }
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(from: url) }
        catch let e as URLError where e.code == .timedOut { throw Failure(errorDescription: "The online server took too long.", tooLong: true) }
        catch { throw Failure(errorDescription: "Online routing not reachable: \(error.localizedDescription)") }
        let text = String(data: data, encoding: .utf8) ?? ""
        guard (resp as? HTTPURLResponse)?.statusCode == 200, text.contains("<trkpt") else {
            let msg = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let low = msg.lowercased()
            if low.contains("watchdog") || low.contains("timeout") || low.contains("killed") {
                throw Failure(errorDescription: "The online server stopped the calculation (time limit).", tooLong: true)
            }
            throw Failure(errorDescription: msg.isEmpty || msg.count > 160 ? "No route found between point \(leg + 1) and \(leg + 2)."
                                                                         : "No route between point \(leg + 1) and \(leg + 2): \(msg)")
        }
        let pts = parsePoints(text)
        guard pts.count >= 2 else { throw RouteError.noPath(leg) }
        let len = comment(text, "track-length =") ?? length(pts)
        return Leg(points: pts, distance: len, duration: seconds(text) ?? len / (typicalSpeed(profile) / 3.6))
    }

    private static func typicalSpeed(_ p: RouteProfile) -> Double {
        switch p { case .hiking: return 4.5; case .roadBike: return 22; case .mountainBike: return 14; case .car: return 60; case .motorcycle: return 60 }
    }

    private static func parsePoints(_ t: String) -> [Pt] {
        var out: [Pt] = []
        var rest = Substring(t)
        while let r = rest.range(of: "<trkpt") {
            rest = rest[r.upperBound...]
            guard let end = rest.firstIndex(of: ">") else { break }
            let tag = rest[..<end]
            if let lat = attr(tag, "lat"), let lon = attr(tag, "lon") { out.append((lat, lon)) }
            rest = rest[end...]
        }
        return out
    }

    private static func attr(_ tag: Substring, _ name: String) -> Double? {
        guard let r = tag.range(of: name + "=\"") else { return nil }
        let v = tag[r.upperBound...]
        guard let q = v.firstIndex(of: "\"") else { return nil }
        return Double(v[..<q])
    }

    private static func comment(_ t: String, _ key: String) -> Double? {
        guard let r = t.range(of: key) else { return nil }
        let v = t[r.upperBound...].drop { $0 == " " }
        return Double(v.prefix { $0.isNumber || $0 == "." })
    }

    /// "time=1h 2m 3s" in the header comment of BRouter's GPX.
    private static func seconds(_ t: String) -> Double? {
        guard let r = t.range(of: "time=") else { return nil }
        let line = t[r.upperBound...].prefix { $0 != "\n" && $0 != "-" }
        var total = 0.0, num = ""
        for ch in line {
            if ch.isNumber { num.append(ch) }
            else if ch == "h" { total += (Double(num) ?? 0) * 3600; num = "" }
            else if ch == "m" { total += (Double(num) ?? 0) * 60; num = "" }
            else if ch == "s" { total += Double(num) ?? 0; num = "" }
        }
        return total > 0 ? total : nil
    }

    private static func length(_ p: [Pt]) -> Double {
        var d = 0.0
        for i in 1..<p.count {
            let dy = (p[i].lat - p[i - 1].lat) * 111_320
            let dx = (p[i].lon - p[i - 1].lon) * 111_320 * cos(p[i].lat * .pi / 180)
            d += hypot(dx, dy)
        }
        return d
    }
}
