import Foundation

/// Heights for a route from a map without height data (Garmin maps): the open-meteo.com elevation service
/// is asked for a few hundred sample points along the route; the rest is interpolated.
enum ElevationService {
    typealias Pt = (lat: Double, lon: Double)

    static func elevations(for pts: [Pt], cancelled: () -> Bool) async -> [Double?]? {
        guard pts.count >= 2 else { return nil }
        var cum = [0.0]
        for i in 1..<pts.count {
            let dy = (pts[i].lat - pts[i - 1].lat) * 111_320
            let dx = (pts[i].lon - pts[i - 1].lon) * 111_320 * cos(pts[i].lat * .pi / 180)
            cum.append(cum[i - 1] + hypot(dx, dy))
        }
        let total = cum.last!
        guard total > 0 else { return nil }
        // sample points: about every 100 m, at most 400
        let n = min(400, max(2, Int(total / 100) + 2))
        var idx: [Int] = [], j = 0
        for k in 0..<n {
            let target = total * Double(k) / Double(n - 1)
            while j < pts.count - 1, cum[j] < target { j += 1 }
            if idx.last != j { idx.append(j) }
        }
        var heights: [Double] = []
        var from = 0
        while from < idx.count {
            if cancelled() { return nil }
            let chunk = idx[from..<min(idx.count, from + 100)]
            let lat = chunk.map { String(format: "%.5f", pts[$0].lat) }.joined(separator: ",")
            let lon = chunk.map { String(format: "%.5f", pts[$0].lon) }.joined(separator: ",")
            guard let url = URL(string: "https://api.open-meteo.com/v1/elevation?latitude=\(lat)&longitude=\(lon)"),
                  let (data, resp) = try? await URLSession.shared.data(from: url),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let e = json["elevation"] as? [Double], e.count == chunk.count else { return nil }
            heights += e
            from += 100
        }
        // interpolate along the distance
        var out = [Double?](repeating: nil, count: pts.count)
        var s = 0
        for i in 0..<pts.count {
            while s < idx.count - 2, cum[idx[s + 1]] < cum[i] { s += 1 }
            let a = cum[idx[s]], b = cum[idx[min(s + 1, idx.count - 1)]]
            let t = b > a ? min(1, max(0, (cum[i] - a) / (b - a))) : 0
            out[i] = heights[s] + (heights[min(s + 1, heights.count - 1)] - heights[s]) * t
        }
        return out
    }
}
