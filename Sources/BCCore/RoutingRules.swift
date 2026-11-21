import Foundation

/// Road classes the router distinguishes. Every line type of a map is assigned to one of them (or to none = not a road).
public enum RoadClass: String, CaseIterable {
    case motorway, primary, secondary, tertiary, minor, residential, service, ramp, track, path, pathLink
    public var title: String {
        switch self {
        case .motorway: return "Motorway"; case .primary: return "Main road"; case .secondary: return "Secondary road"
        case .tertiary: return "Minor road"; case .minor: return "Collector road"; case .residential: return "Residential street"
        case .service: return "Service road"; case .ramp: return "Ramp"; case .track: return "Unpaved track"
        case .path: return "Path"; case .pathLink: return "Track / path (unspecified)"
        }
    }
}

public struct RoadTypeInfo {
    public let type: Int
    public let count: Int          // lines in the sample
    public let joined: Double      // share of line ends that meet another line (road networks are connected)
    public let oneway: Double
    public let share: Double       // share of all network lines
    public let cls: RoadClass?     // nil = not part of the routable network
}

/// Routing rules of one map. They are derived from the map's data every time the program starts, so any
/// Garmin map works on any computer: line types that form a connected network are kept, the meaning of a type is
/// taken from the usual Garmin type codes and corrected by how the type is actually used in this map.
public final class RoutingRules {
    public let types: [RoadTypeInfo]
    public let linesSampled: Int
    private let classOf: [Int: RoadClass]

    init(types: [RoadTypeInfo], linesSampled: Int) {
        self.types = types; self.linesSampled = linesSampled
        var c: [Int: RoadClass] = [:]
        for t in types { if let k = t.cls { c[t.type] = k } }
        classOf = c
    }

    public func roadClass(_ type: Int) -> RoadClass? { classOf[type] }
    public func rule(_ p: RouteProfile, type: Int) -> (speed: Double, mult: Double)? { classOf[type].flatMap { p.rule($0) } }

    /// Enough connected, walkable lines to build routes.
    public var isRoutable: Bool {
        types.filter { $0.cls != nil && RouteProfile.hiking.rule($0.cls!) != nil }.reduce(0) { $0 + $1.count } >= 300
    }
    public func supports(_ p: RouteProfile) -> Bool {
        types.filter { $0.cls.flatMap { p.rule($0) } != nil }.reduce(0) { $0 + $1.count } >= 300
    }

    /// Readable table for the info window.
    public var summary: String {
        var out = "Sample: \(linesSampled) lines\n\n"
        for t in types.sorted(by: { $0.type < $1.type }) {
            out += String(format: "0x%02X  %7d lines  %3.0f%%  joined %3.0f%%  one-way %3.0f%%  →  %@\n", t.type, t.count, t.share * 100,
                          t.joined * 100, t.oneway * 100, t.cls?.title ?? "not routable")
        }
        return out
    }
}

extension GarminMap {
    /// Looks at a sample of the map's finest level and derives the routing rules from it. Called in the background
    /// when the program starts (and when maps are added).
    @discardableResult
    public func analyzeRouting() -> RoutingRules {
        struct Acc { var n = 0, one = 0, ends = 0, joinedEnds = 0 }
        var acc: [Int: Acc] = [:]
        var lines = 0
        let order: [Int] = {
            let c = tiles.count
            guard c > 0 else { return [] }
            let step = max(1, c / 12)
            var o: [Int] = [], seen = Set<Int>()
            for off in 0..<step { for i in stride(from: off, to: c, by: step) where seen.insert(i).inserted { o.append(i) } }
            return o
        }()
        var used = 0
        for ti in order where isSupported {
            if used >= 40 || (used >= 10 && lines >= 60_000) { break }
            let t = tiles[ti]
            t.ensureLoaded()
            guard let li = t.levels.indices.max(by: { t.levels[$0].bits < t.levels[$1].bits }) else { continue }
            used += 1
            var nodes: [UInt64: Int32] = [:]          // vertex -> line id, -1 = used by several lines
            var lineId: Int32 = 0
            var ends: [(type: Int, a: UInt64, b: UInt64)] = []
            for si in t.subdivisions(level: li, in: t.bounds) {
                for f in t.features(sub: si) where f.kind == .line && f.coords.count >= 4 && f.type < 0x20 {
                    var a = acc[f.type] ?? Acc()
                    a.n += 1; if f.oneway { a.one += 1 }
                    acc[f.type] = a
                    lines += 1
                    let n = f.coords.count
                    func key(_ i: Int) -> UInt64 { (UInt64(UInt32(bitPattern: f.coords[i])) << 32) | UInt64(UInt32(bitPattern: f.coords[i + 1])) }
                    let k0 = key(0), k1 = key(n - 2)
                    ends.append((f.type, k0, k1))
                    lineId += 1
                    var i = 0
                    while i + 1 < n {
                        let k = key(i); i += 2
                        if let v = nodes[k] { if v != lineId { nodes[k] = -1 } } else { nodes[k] = lineId }
                    }
                }
            }
            t.dropFeatureCache()                       // do not keep millions of decoded lines in memory
            for e in ends {
                var a = acc[e.type]!
                a.ends += e.a == e.b ? 1 : 2
                if nodes[e.a] == -1 { a.joinedEnds += 1 }
                if e.a != e.b, nodes[e.b] == -1 { a.joinedEnds += 1 }
                acc[e.type] = a
            }
        }
        // 1. network = types whose ends meet other lines; never railways, shores, water, borders (standard codes)
        let notRoad: Set<Int> = [0x14, 0x15, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f]
        let net = acc.filter {
            let j = Double($0.value.joinedEnds) / Double(max(1, $0.value.ends))
            let standard = ($0.key >= 1 && $0.key <= 0x0c) || $0.key == 0x16        // usual road codes: a lower bar
            return $0.value.n >= 50 && !notRoad.contains($0.key) && j >= (standard ? 0.15 : 0.3)
        }
        let total = max(1, net.values.reduce(0) { $0 + $1.n })
        var infos: [RoadTypeInfo] = []
        for (type, a) in acc.sorted(by: { $0.key < $1.key }) {
            let joined = Double(a.joinedEnds) / Double(max(1, a.ends))
            let one = Double(a.one) / Double(max(1, a.n))
            var cls: RoadClass?
            if net[type] != nil {
                let share = Double(a.n) / Double(total)
                switch type {
                case 0x01: cls = .motorway
                case 0x02: cls = .primary
                case 0x03: cls = .secondary
                case 0x04: cls = .tertiary
                case 0x05: cls = .minor
                case 0x06, 0x0c: cls = .residential
                // a "service road" type that makes up a large part of the whole network is really the path network
                case 0x07: cls = share > 0.2 ? .pathLink : .service
                // real ramps are rare and mostly one-way; a frequent two-way type is a local road/track network
                case 0x08, 0x09: cls = (share < 0.04 && one > 0.3) ? .ramp : .pathLink
                case 0x0a: cls = .track
                case 0x0b: cls = (share < 0.02 && one > 0.3) ? .secondary : .pathLink
                case 0x16: cls = .path
                default: cls = .pathLink
                }
            }
            infos.append(RoadTypeInfo(type: type, count: a.n, joined: joined, oneway: one,
                                      share: net[type] != nil ? Double(a.n) / Double(total) : 0, cls: cls))
        }
        let r = RoutingRules(types: infos, linesSampled: lines)
        routingRules = r
        return r
    }
}
