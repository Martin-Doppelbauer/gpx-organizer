import Foundation

/// Minimal reader for Apple binary property lists ("bplist00") including the UID type used by NSKeyedArchiver.
/// Foundation's PropertyListSerialization hides UID values, so the format is parsed directly.
struct BPlist {
    indirect enum Value {
        case null, bool(Bool), int(Int), real(Double), date(Double), data(Data), string(String)
        case uid(Int), array([Value]), dict([String: Value])
    }

    private let d: Data
    private let offsetSize: Int, refSize: Int, count: Int, offsetTable: Int
    let top: Int
    private var cache: [Int: Value] = [:]

    init?(_ data: Data) {
        guard data.count > 40, data.starts(with: Array("bplist00".utf8)) else { return nil }
        d = data
        let t = data.count - 32
        offsetSize = Int(data[t + 6]); refSize = Int(data[t + 7])
        func be(_ o: Int, _ n: Int) -> Int { var v = 0; for k in 0..<n { v = v << 8 | Int(data[o + k]) }; return v }
        count = be(t + 8, 8) & 0x7FFFFFFF; top = be(t + 16, 8) & 0x7FFFFFFF; offsetTable = be(t + 24, 8) & 0x7FFFFFFF
        guard offsetSize > 0, refSize > 0, count > 0, offsetTable + count * offsetSize <= data.count else { return nil }
    }

    private func be(_ o: Int, _ n: Int) -> Int { Int(truncatingIfNeeded: beU(o, n)) }
    private func beU(_ o: Int, _ n: Int) -> UInt64 { var v: UInt64 = 0; for k in 0..<min(n, 8) where o + k < d.count { v = v << 8 | UInt64(d[o + k]) }; return v }

    mutating func object(_ index: Int) -> Value {
        if let c = cache[index] { return c }
        let v = parse(index)
        cache[index] = v
        return v
    }

    private mutating func parse(_ index: Int) -> Value {
        guard index >= 0, index < count else { return .null }
        var p = be(offsetTable + index * offsetSize, offsetSize)
        guard p < d.count else { return .null }
        let marker = d[p]; p += 1
        let hi = marker >> 4, lo = Int(marker & 0xF)
        // length that may be stored in a following int object
        func length() -> (Int, Int) {
            if lo != 0xF { return (lo, p) }
            let m = d[p]; let n = 1 << Int(m & 0xF)
            return (be(p + 1, n), p + 1 + n)
        }
        switch hi {
        case 0x0: return marker == 0x08 ? .bool(false) : marker == 0x09 ? .bool(true) : .null
        case 0x1: return .int(be(p, min(8, 1 << lo)))
        case 0x2:
            if lo == 2 { return .real(Double(Float(bitPattern: UInt32(truncatingIfNeeded: beU(p, 4))))) }
            return .real(Double(bitPattern: beU(p, 8)))
        case 0x3: return .date(Double(bitPattern: beU(p, 8)))
        case 0x4: let (n, s) = length(); return .data(d.subdata(in: s..<min(d.count, s + n)))
        case 0x5: let (n, s) = length(); return .string(String(decoding: d[s..<min(d.count, s + n)], as: UTF8.self))
        case 0x6:
            let (n, s) = length()
            return .string(String(data: d.subdata(in: s..<min(d.count, s + n * 2)), encoding: .utf16BigEndian) ?? "")
        case 0x8: return .uid(be(p, lo + 1))
        case 0xA, 0xB:
            let (n, s) = length()
            var out: [Value] = []
            out.reserveCapacity(n)
            for i in 0..<n { out.append(object(be(s + i * refSize, refSize))) }
            return .array(out)
        case 0xD:
            let (n, s) = length()
            var out: [String: Value] = [:]
            for i in 0..<n {
                let k = object(be(s + i * refSize, refSize))
                let v = object(be(s + (n + i) * refSize, refSize))
                if case .string(let key) = k { out[key] = v }
            }
            return .dict(out)
        default: return .null
        }
    }
}

/// Resolves an NSKeyedArchiver graph (UID references, NSArray/NSDictionary/NSData/NSDate wrappers) into plain Swift values.
final class KeyedArchive {
    private var plist: BPlist
    private var objects: [BPlist.Value] = []
    private var memo: [Int: Any] = [:]
    private var inProgress = Set<Int>()
    let root: Any?

    init?(_ data: Data) {
        guard var p = BPlist(data), case .dict(let top) = p.object(p.top),
              case .array(let objs)? = top["$objects"], case .dict(let t)? = top["$top"], case .uid(let r)? = t["root"] else { return nil }
        plist = p; objects = objs
        root = nil
        self.rootIndex = r
    }
    private var rootIndex = 0

    func resolveRoot() -> Any? { resolve(rootIndex) }

    private func resolve(_ i: Int) -> Any? {
        if let m = memo[i] { return m }
        guard i > 0, i < objects.count, !inProgress.contains(i) else { return nil }
        inProgress.insert(i); defer { inProgress.remove(i) }
        let v = convert(objects[i])
        if let v { memo[i] = v }
        return v
    }

    private func convert(_ v: BPlist.Value) -> Any? {
        switch v {
        case .null: return nil
        case .bool(let b): return b
        case .int(let n): return n
        case .real(let r): return r
        case .date(let r): return r
        case .data(let x): return x
        case .string(let s): return s == "$null" ? nil : s
        case .uid(let i): return resolve(i)
        case .array(let a): return a.compactMap { convert($0) }
        case .dict(let d):
            var out: [String: Any] = [:]
            for (k, val) in d where k != "$class" { if let c = convert(val) { out[k] = c } }
            if let objs = out["NS.objects"] as? [Any] {
                if let keys = out["NS.keys"] as? [Any] {
                    var m: [String: Any] = [:]
                    for (k, o) in zip(keys, objs) { if let ks = k as? String { m[ks] = o } }
                    return m
                }
                return objs
            }
            if let data = out["NS.data"] as? Data { return data }
            if let t = out["NS.time"] { return t }
            return out
        }
    }
}
