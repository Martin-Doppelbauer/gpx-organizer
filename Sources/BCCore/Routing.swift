import Foundation

public enum RouteProfile: String, CaseIterable, Identifiable {
    case hiking, jogging, mountainBike, touringBike, roadBike, car, motorcycle
    public var id: String { rawValue }
    public var title: String {
        switch self { case .hiking: return "Hiking"; case .jogging: return "Jogging"; case .roadBike: return "Road Bike"
        case .touringBike: return "Touring Bike"; case .mountainBike: return "Mountainbike"; case .car: return "Car"; case .motorcycle: return "Motorcycle" }
    }
    public var symbol: String {
        switch self { case .hiking: return "figure.hiking"; case .jogging: return "figure.run"; case .roadBike: return "bicycle"
        case .touringBike: return "bicycle.circle"; case .mountainBike: return "figure.outdoor.cycle"; case .car: return "car"; case .motorcycle: return "motorcycle" }
    }

    /// Average speed in km/h used for the estimated duration (the speeds per road class only steer the choice of the way).
    public var averageSpeed: Double {
        switch self { case .hiking: return 4.5; case .jogging: return 9; case .mountainBike: return 15; case .touringBike: return 20
        case .roadBike: return 25; case .car: return 60; case .motorcycle: return 60 }
    }

    /// Extra minutes per 100 m of ascent (hiking: Naismith, 600 m per hour) and minutes saved per 100 m of descent (only the two road-going bikes).
    public var ascentMinutesPer100m: Double {
        switch self { case .hiking: return 10; case .jogging: return 6; case .mountainBike: return 4; case .touringBike: return 3
        case .roadBike: return 2.5; case .car, .motorcycle: return 0 }
    }
    public var descentMinutesSavedPer100m: Double {
        switch self { case .touringBike: return 1; case .roadBike: return 1.5; default: return 0 }
    }
    /// Estimated duration in seconds: distance at the average speed, plus the ascent surcharge, minus the descent bonus
    /// (the bonus never takes off more than a quarter of the flat time).
    public func duration(distance: Double, ascent: Double, descent: Double) -> Double {
        let flat = distance / (averageSpeed / 3.6)
        let bonus = min(descent / 100 * descentMinutesSavedPer100m * 60, flat * 0.25)
        return flat + ascent / 100 * ascentMinutesPer100m * 60 - bonus
    }

    /// (speed km/h, cost multiplier) for a road class; nil = not usable for this profile.
    func rule(_ cls: RoadClass) -> (speed: Double, mult: Double)? {
        switch self {
        case .hiking:
            switch cls {
            case .motorway: return nil
            case .primary: return (4.5, 3.0)
            case .secondary: return (4.5, 2.0)
            case .tertiary: return (4.5, 1.5)
            case .minor: return (4.5, 1.2)
            case .residential, .service: return (4.5, 1.0)
            case .ramp: return (4.5, 1.2)
            case .track: return (4.2, 0.9)
            case .path, .pathLink: return (4.0, 0.8)
            }
        case .jogging:
            // running pace; quiet roads, tracks and trails preferred (soft ground), busy roads avoided
            switch cls {
            case .motorway: return nil
            case .primary: return (9.5, 3.0)
            case .secondary: return (9.5, 2.0)
            case .tertiary: return (9.5, 1.4)
            case .minor: return (9.5, 1.1)
            case .residential, .service: return (9.0, 1.0)
            case .ramp: return (9.0, 1.3)
            case .track: return (9.0, 0.8)
            case .path, .pathLink: return (8.0, 0.8)
            }
        case .roadBike:
            switch cls {
            case .motorway: return nil
            case .primary: return (26, 2.2)               // federal roads: avoided
            case .secondary: return (25, 0.95)            // country roads: preferred
            case .tertiary: return (24, 0.9)              // district roads: preferred
            case .minor: return (24, 0.95)
            case .residential: return (22, 1.05)
            case .service: return (18, 1.4)
            case .ramp: return (20, 1.3)
            case .pathLink: return (18, 1.6)
            case .track: return (12, 4.0)
            case .path: return (8, 6.0)
            }
        case .touringBike:
            // like the road bike, but tracks and good paths are acceptable
            switch cls {
            case .motorway: return nil
            case .primary: return (23, 2.5)
            case .secondary: return (22, 1.1)
            case .tertiary: return (21, 1.0)
            case .minor: return (21, 1.0)
            case .residential: return (19, 1.1)
            case .service: return (16, 1.3)
            case .ramp: return (18, 1.3)
            case .pathLink: return (15, 1.5)
            case .track: return (14, 1.2)
            case .path: return (9, 3.0)
            }
        case .mountainBike:
            switch cls {
            case .motorway: return nil
            case .primary: return (22, 3.0)
            case .secondary: return (21, 1.8)
            case .tertiary: return (20, 1.4)
            case .minor, .residential: return (19, 1.2)
            case .service, .ramp: return (17, 1.1)
            case .track: return (15, 0.7)
            case .path, .pathLink: return (11, 0.8)
            }
        case .car:
            // motorways and federal roads preferred, town centres avoided
            switch cls {
            case .motorway: return (110, 0.8)
            case .primary: return (80, 0.85)
            case .secondary: return (60, 1.0)
            case .tertiary: return (50, 1.1)
            case .minor: return (40, 1.2)
            case .residential: return (30, 2.0)
            case .service: return (15, 2.5)
            case .ramp: return (25, 1.0)
            case .track: return (20, 3.0)
            case .path, .pathLink: return nil
            }
        case .motorcycle:
            // country and federal roads preferred, motorways rather avoided, town centres avoided
            switch cls {
            case .motorway: return (110, 2.5)
            case .primary: return (80, 0.9)
            case .secondary: return (70, 0.8)
            case .tertiary: return (60, 0.8)
            case .minor: return (50, 0.9)
            case .residential: return (30, 2.0)
            case .service: return (15, 2.5)
            case .ramp: return (25, 1.0)
            case .track: return (20, 3.0)
            case .path, .pathLink: return nil
            }
        }
    }
}

public struct RouteResult {
    public init() {}
    public var points: [(lat: Double, lon: Double)] = []
    public var elevations: [Double?] = []   // metres, parallel to `points`; empty when the map has no heights
    public var distance = 0.0       // metres
    public var duration = 0.0       // seconds (at the profile's typical speed, without preference penalties)
    public var viaIndex: [Int] = [] // index into `points` where each via point was reached
    /// Ascent and descent in metres with a 4 m hysteresis (small noise does not count); nil without elevation data.
    public var climb: (up: Double, down: Double)? {
        var e: [Double] = [], last: Double?
        for i in 0..<points.count { if let v = i < elevations.count ? elevations[i] : nil { last = v }; if let l = last { e.append(l) } }
        guard let first = e.first else { return nil }
        var base = first, up = 0.0, down = 0.0
        for v in e { if v - base >= 4 { up += v - base; base = v } else if base - v >= 4 { down += base - v; base = v } }
        return (up, down)
    }
    public func estimatedDuration(_ p: RouteProfile) -> Double {
        let c = climb
        return p.duration(distance: distance, ascent: c?.up ?? 0, descent: c?.down ?? 0)
    }
}

public enum RouteError: LocalizedError {
    case noMap, notRoutable, noSnap(Int), noPath(Int), cancelled
    public var errorDescription: String? {
        switch self {
        case .noMap: return "No map selected."
        case .notRoutable: return "This map contains no usable roads/paths for the profile."
        case .noSnap(let i): return "Point \(i + 1) is too far from a path."
        case .noPath(let i): return "No route found between point \(i + 1) and \(i + 2) (map incomplete or profile blocks the path)."
        case .cancelled: return "Abgebrochen."
        }
    }
}

/// Road/path graph built from the polylines of the selected map (finest detail level) around one leg.
final class RouteGraph {
    var xs: [Int32] = [], ys: [Int32] = []
    private var index: [UInt64: Int32] = [:]
    private var ef: [Int32] = [], et: [Int32] = []
    private var ec: [Float] = [], el: [Float] = [], etm: [Float] = []
    // CSR adjacency
    var start: [Int32] = []
    var adjTo: [Int32] = [], adjCost: [Float] = [], adjLen: [Float] = [], adjTime: [Float] = []

    func node(_ x: Int32, _ y: Int32) -> Int32 {
        let k = (UInt64(UInt32(bitPattern: x)) << 32) | UInt64(UInt32(bitPattern: y))
        if let i = index[k] { return i }
        let i = Int32(xs.count)
        xs.append(x); ys.append(y); index[k] = i
        return i
    }

    func addEdge(_ a: Int32, _ b: Int32, len: Float, cost: Float, time: Float, oneway: Bool) {
        ef.append(a); et.append(b); ec.append(cost); el.append(len); etm.append(time)
        if !oneway { ef.append(b); et.append(a); ec.append(cost); el.append(len); etm.append(time) }
    }

    func finalize() {
        let n = xs.count
        start = [Int32](repeating: 0, count: n + 1)
        for f in ef { start[Int(f) + 1] += 1 }
        for i in 0..<n { start[i + 1] += start[i] }
        var fill = start
        adjTo = [Int32](repeating: 0, count: ef.count); adjCost = [Float](repeating: 0, count: ef.count)
        adjLen = adjCost; adjTime = adjCost
        for e in 0..<ef.count {
            let f = Int(ef[e]); let p = Int(fill[f]); fill[f] += 1
            adjTo[p] = et[e]; adjCost[p] = ec[e]; adjLen[p] = el[e]; adjTime[p] = etm[e]
        }
        ef = []; et = []; ec = []; el = []; etm = []; index = [:]
    }
}

public enum Router {
    private static let metersPerDegree = 111_320.0

    /// Plans a route through `vias` (lat, lon) using the network of `map`.
    public static func plan(map: GarminMap, vias: [(lat: Double, lon: Double)], profile: RouteProfile,
                            cancelled: () -> Bool = { false }) throws -> RouteResult {
        guard map.isSupported else { throw RouteError.noMap }
        let rules = map.routingRules ?? map.analyzeRouting()
        guard rules.isRoutable else { throw RouteError.notRoutable }
        guard vias.count >= 2 else { return RouteResult() }
        var result = RouteResult()
        result.viaIndex = [0]
        for leg in 0..<(vias.count - 1) {
            if cancelled() { throw RouteError.cancelled }
            let a = vias[leg], b = vias[leg + 1]
            let g = try buildGraph(map: map, a: a, b: b, profile: profile, rules: rules, cancelled: cancelled)
            guard g.xs.count > 1 else { throw RouteError.notRoutable }
            guard let s = nearest(g, a, maxMeters: 400) else { throw RouteError.noSnap(leg) }
            guard let t = nearest(g, b, maxMeters: 400) else { throw RouteError.noSnap(leg + 1) }
            let path = try astar(g, from: s, to: t, profile: profile, cancelled: cancelled, leg: leg)
            for (i, n) in path.nodes.enumerated() where !(i == 0 && !result.points.isEmpty) {
                result.points.append((Double(g.ys[Int(n)]) * degPerUnit, Double(g.xs[Int(n)]) * degPerUnit))
            }
            result.distance += path.length; result.duration += path.length / (profile.averageSpeed / 3.6)
            result.viaIndex.append(result.points.count - 1)
        }
        return result
    }

    private static func buildGraph(map: GarminMap, a: (lat: Double, lon: Double), b: (lat: Double, lon: Double),
                                   profile: RouteProfile, rules: RoutingRules, cancelled: () -> Bool) throws -> RouteGraph {
        let dLat = abs(a.lat - b.lat), dLon = abs(a.lon - b.lon)
        let pad = min(1.5, max(0.02, 0.3 * max(dLat, dLon)))
        let area = Bounds(north: Int((max(a.lat, b.lat) + pad) / degPerUnit), east: Int((max(a.lon, b.lon) + pad) / degPerUnit),
                          south: Int((min(a.lat, b.lat) - pad) / degPerUnit), west: Int((min(a.lon, b.lon) - pad) / degPerUnit))
        let g = RouteGraph()
        let midLat = (a.lat + b.lat) / 2
        let mx = metersPerDegree * degPerUnit * cos(midLat * .pi / 180)   // metres per longitude unit
        let my = metersPerDegree * degPerUnit
        for t in map.tiles where t.bounds.intersects(area) {
            if cancelled() { throw RouteError.cancelled }
            t.ensureLoaded()
            guard let li = t.levels.indices.max(by: { t.levels[$0].bits < t.levels[$1].bits }) else { continue }
            for si in t.subdivisions(level: li, in: area) {
                for f in t.features(sub: si) where f.kind == .line && f.coords.count >= 4 {
                    guard let rule = rules.rule(profile, type: f.type) else { continue }
                    let oneway = (profile == .car || profile == .motorcycle) && f.oneway
                    var prev = g.node(f.coords[0], f.coords[1])
                    var px = Double(f.coords[0]), py = Double(f.coords[1])
                    var i = 2
                    while i + 1 < f.coords.count {
                        let x = Double(f.coords[i]), y = Double(f.coords[i + 1])
                        let cur = g.node(f.coords[i], f.coords[i + 1])
                        if cur != prev {
                            let len = hypot((x - px) * mx, (y - py) * my)
                            let secs = len / (rule.speed / 3.6)
                            g.addEdge(prev, cur, len: Float(len), cost: Float(secs * rule.mult), time: Float(secs), oneway: oneway)
                        }
                        prev = cur; px = x; py = y; i += 2
                    }
                }
            }
        }
        g.finalize()
        return g
    }

    private static func nearest(_ g: RouteGraph, _ p: (lat: Double, lon: Double), maxMeters: Double) -> Int32? {
        let ux = p.lon / degPerUnit, uy = p.lat / degPerUnit
        let c = cos(p.lat * .pi / 180)
        var best: Int32?, bd = Double.infinity
        for i in 0..<g.xs.count where g.start[i + 1] > g.start[i] {
            let dx = (Double(g.xs[i]) - ux) * c, dy = Double(g.ys[i]) - uy
            let d = dx * dx + dy * dy
            if d < bd { bd = d; best = Int32(i) }
        }
        guard let b = best, bd.squareRoot() * degPerUnit * metersPerDegree <= maxMeters else { return nil }
        return b
    }

    private struct Heap {
        var a: [(Float, Int32)] = []
        var isEmpty: Bool { a.isEmpty }
        mutating func push(_ f: Float, _ n: Int32) {
            a.append((f, n)); var i = a.count - 1
            while i > 0 { let p = (i - 1) / 2; if a[p].0 <= a[i].0 { break }; a.swapAt(p, i); i = p }
        }
        mutating func pop() -> (Float, Int32) {
            let top = a[0]; let last = a.removeLast()
            if !a.isEmpty {
                a[0] = last; var i = 0
                while true {
                    let l = 2 * i + 1, r = l + 1; var m = i
                    if l < a.count && a[l].0 < a[m].0 { m = l }
                    if r < a.count && a[r].0 < a[m].0 { m = r }
                    if m == i { break }; a.swapAt(i, m); i = m
                }
            }
            return top
        }
    }

    private static func astar(_ g: RouteGraph, from s: Int32, to t: Int32, profile: RouteProfile,
                              cancelled: () -> Bool, leg: Int) throws -> (nodes: [Int32], length: Double, time: Double) {
        let n = g.xs.count
        var dist = [Float](repeating: .infinity, count: n)
        var parent = [Int32](repeating: -1, count: n)
        var pLen = [Float](repeating: 0, count: n), pTime = [Float](repeating: 0, count: n)
        var closed = [Bool](repeating: false, count: n)
        let gx = Double(g.xs[Int(t)]), gy = Double(g.ys[Int(t)])
        let c = cos(gy * degPerUnit * .pi / 180)
        // optimistic remaining cost: straight line at the profile's best speed / lowest multiplier
        let vmax: Double = { switch profile { case .hiking: return 5.0; case .jogging: return 10.0; case .roadBike: return 30; case .touringBike, .mountainBike: return 25; case .car, .motorcycle: return 120 } }() / 3.6
        let minMult: Double = { switch profile { case .hiking, .jogging: return 0.8; case .roadBike: return 0.9; case .touringBike: return 0.9; case .mountainBike: return 0.7; case .car, .motorcycle: return 0.8 } }()
        func h(_ i: Int) -> Float {
            let dx = (Double(g.xs[i]) - gx) * c, dy = Double(g.ys[i]) - gy
            return Float(hypot(dx, dy) * degPerUnit * metersPerDegree / vmax * minMult)
        }
        var heap = Heap()
        dist[Int(s)] = 0; heap.push(h(Int(s)), s)
        var steps = 0
        while !heap.isEmpty {
            let (_, u) = heap.pop()
            let ui = Int(u)
            if closed[ui] { continue }
            closed[ui] = true
            if u == t { break }
            steps += 1
            if steps & 0x3FFF == 0, cancelled() { throw RouteError.cancelled }
            for e in Int(g.start[ui])..<Int(g.start[ui + 1]) {
                let v = Int(g.adjTo[e])
                if closed[v] { continue }
                let nd = dist[ui] + g.adjCost[e]
                if nd < dist[v] {
                    dist[v] = nd; parent[v] = u
                    pLen[v] = pLen[ui] + g.adjLen[e]; pTime[v] = pTime[ui] + g.adjTime[e]
                    heap.push(nd + h(v), Int32(v))
                }
            }
        }
        guard closed[Int(t)] else { throw RouteError.noPath(leg) }
        var nodes: [Int32] = []
        var cur = t
        while cur != -1 { nodes.append(cur); cur = parent[Int(cur)] }
        return (nodes.reversed(), Double(pLen[Int(t)]), Double(pTime[Int(t)]))
    }
}
