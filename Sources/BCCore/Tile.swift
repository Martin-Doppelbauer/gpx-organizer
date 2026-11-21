import Foundation

public struct Level {
    public let index: Int      // 0 = most detailed
    public let bits: Int       // resolution bits
    public let count: Int
    public let firstSub: Int
}

public struct Subdivision {
    public let rgnOffset: Int
    public let flags: Int
    public let cx: Int, cy: Int
    public let hw: Int, hh: Int   // half extent in map units
    public let level: Int         // index into levels array
    public let shift: Int
    public var polyg2 = 0..<0     // extended-type sections (absolute file ranges)
    public var polyl2 = 0..<0
    public var point2 = 0..<0
}

public enum FeatureKind: UInt8 { case point, line, polygon }

public struct Feature {
    public let kind: FeatureKind
    public let type: Int
    public let subtype: Int
    public let label: Int       // label offset (0 = none)
    public let labelKind: UInt8 // 0 none, 1 LBL1 offset, 2 via NET1, 3 via POI index (LBL6)
    public let coords: [Int32]  // interleaved lon,lat in map units
    public let oneway: Bool     // polyline direction flag: traffic only in drawing direction
    init(kind: FeatureKind, type: Int, subtype: Int, label: Int, labelKind: UInt8 = 0, coords: [Int32], oneway: Bool = false) {
        self.kind = kind; self.type = type; self.subtype = subtype
        self.label = label; self.labelKind = label == 0 ? 0 : labelKind; self.coords = coords; self.oneway = oneway
    }
}

public struct Bounds {
    public var north: Int, east: Int, south: Int, west: Int
    public init(north: Int, east: Int, south: Int, west: Int) { self.north = north; self.east = east; self.south = south; self.west = west }
    public func intersects(_ o: Bounds) -> Bool {
        !(o.west > east || o.east < west || o.south > north || o.north < south)
    }
}

/// One map tile: TRE (index), RGN (geometry) files.
public final class Tile {
    public let number: Int
    public let dir: String
    let opener: (String) -> MappedFile?
    public private(set) var bounds: Bounds
    var tre: MappedFile?
    var rgn: MappedFile?
    var lbl: MappedFile?, net: MappedFile?
    var lbl1Off = 0, lbl1Len = 0, lblShift = 0, lblCoding = 0, lblCodepage = 0, lbl6Off = 0
    var net1Off = 0, net1Shift = 0
    var labelCache: [Int: String] = [:]
    var treHdr = 0, rgnHdr = 0        // header positions (non-zero inside a GMP container)
    public private(set) var isGMP = false
    public private(set) var levels: [Level] = []
    public private(set) var subs: [Subdivision] = []
    var rgnData = 0, rgnLen = 0
    var loaded = false
    let lock = NSLock()
    var cache: [Int: [Feature]] = [:]

    public init?(number: Int, dir: String, opener: ((String) -> MappedFile?)? = nil) {
        self.number = number; self.dir = dir
        self.opener = opener ?? { ext in MappedFile(path: "\(dir)/\(number).\(ext)") }
        var t: MappedFile?
        if let m = self.opener("TRE"), m.size > 0x40 {
            t = m
        } else if opener == nil, let name = (try? FileManager.default.contentsOfDirectory(atPath: dir))?.first(where: { $0.uppercased().hasSuffix(".GMP") }),
                  let m = MappedFile(path: "\(dir)/\(name)"), m.size > 0x40, m.string(2, 10) == "GARMIN GMP" {
            t = m; isGMP = true
            treHdr = m.u32(0x19); rgnHdr = m.u32(0x1D)
            if m.string(treHdr + 2, 10) != "GARMIN TRE" || m.string(rgnHdr + 2, 10) != "GARMIN RGN" { return nil }
        } else { return nil }
        tre = t
        let h = treHdr
        bounds = Bounds(north: t!.i24(h + 0x15), east: t!.i24(h + 0x18), south: t!.i24(h + 0x1B), west: t!.i24(h + 0x1E))
        if t!.u8(h + 0x0D) & 0x80 != 0 { return nil }   // locked / encrypted data: not supported
    }

    private func load() {
        lock.lock(); defer { lock.unlock() }
        if loaded { return }
        loaded = true
        guard let t = tre else { return }
        rgn = isGMP ? t : opener("RGN")
        if let r = rgn { rgnData = r.u32(rgnHdr + 0x15); rgnLen = r.u32(rgnHdr + 0x19) }

        if !isGMP, let l = opener("LBL"), l.size > 0x60 {
            lbl = l
            lbl1Off = l.u32(0x15); lbl1Len = l.u32(0x19); lblShift = l.u8(0x1D); lblCoding = l.u8(0x1E)
            lbl6Off = l.u32(0x57)
            if l.u16(0) > 0xAA { lblCodepage = l.u16(0xAA) }
            if let n = opener("NET"), n.size > 0x20 {
                net = n; net1Off = n.u32(0x15); net1Shift = n.u8(0x1D)
            }
        }
        let h = treHdr
        let lp = t.u32(h + 0x21), ls = t.u32(h + 0x25), sp = t.u32(h + 0x29), ss = t.u32(h + 0x2D)
        var raw: [(zoom: Int, bits: Int, n: Int)] = []
        for i in 0..<(ls / 4) {
            raw.append((t.u8(lp + i * 4) & 0x0F, t.u8(lp + i * 4 + 1) & 0x1F, t.u16(lp + i * 4 + 2)))
        }
        var first = 0
        for r in raw {
            levels.append(Level(index: r.zoom, bits: r.bits, count: r.n, firstSub: first))
            first += r.n
        }
        var off = sp
        let end = sp + ss
        for (li, lv) in levels.enumerated() {
            let recLen = lv.index == 0 ? 14 : 16
            for _ in 0..<lv.count {
                if off + recLen > end { break }
                let rgnOff = t.u24(off)
                let flags = t.u8(off + 3)
                let cx = t.i24(off + 4), cy = t.i24(off + 7)
                let w = t.u16(off + 10) & 0x7FFF, h = t.u16(off + 12)
                let shift = 24 - lv.bits
                subs.append(Subdivision(rgnOffset: rgnOff, flags: flags, cx: cx, cy: cy,
                                        hw: w << shift, hh: h << shift, level: li, shift: shift))
                off += recLen
            }
        }
        loadExtended(t)
    }

    /// Extended (NT) object sections: per-subdivision ranges into the polygon2/polyline2/point2 areas of RGN.
    private func loadExtended(_ t: MappedFile) {
        guard let r = rgn else { return }
        let h = treHdr, rh = rgnHdr
        guard !isGMP, t.u16(h) >= 0x9A, t.u32(h + 0x80) > 0 else { return }
        let rec = t.u16(h + 0x84)
        guard rec >= 13 else { return }
        let off = t.u32(h + 0x7C), size = t.u32(h + 0x80)
        let n = min(subs.count, size / rec)
        let skipPois = rec != 13
        let pg = (r.u32(rh + 0x1D), r.u32(rh + 0x21)), pl = (r.u32(rh + 0x39), r.u32(rh + 0x3D)), pt = (r.u32(rh + 0x55), r.u32(rh + 0x59))
        func starts(_ k: Int) -> [Int] { (0..<n).map { t.u32(off + $0 * rec + k) } }
        let sg = starts(0), sl = starts(4), sp = skipPois ? [Int](repeating: 0, count: n) : starts(8)
        for i in 0..<n {
            func range(_ s: [Int], _ sec: (Int, Int)) -> Range<Int> {
                let a = sec.0 + s[i]
                let b = i + 1 < n ? sec.0 + s[i + 1] : sec.0 + sec.1
                return a < b ? a..<b : 0..<0
            }
            subs[i].polyg2 = range(sg, pg)
            subs[i].polyl2 = range(sl, pl)
            if !skipPois { subs[i].point2 = range(sp, pt) }
        }
    }

    public func ensureLoaded() { if !loaded { load() } }

    /// Frees the decoded features (they are decoded again when needed). Used after a one-off analysis of a map.
    public func dropFeatureCache() { lock.lock(); cache.removeAll(); lock.unlock() }

    /// Pick the level whose resolution fits `unitsPerPixel` (map units per screen pixel).
    public func levelIndex(unitsPerPixel u: Double) -> Int? {
        ensureLoaded()
        if levels.isEmpty { return nil }
        let want = 24 - log2(max(u, 1e-9)) + 1  // needed bits (+1: prefer more detail)
        var best: Int? = nil
        for (i, lv) in levels.enumerated() where Double(lv.bits) >= want - 0.5 {
            if best == nil || lv.bits < levels[best!].bits { best = i }
        }
        if best == nil { best = levels.indices.max(by: { levels[$0].bits < levels[$1].bits }) }
        return best
    }

    /// Subdivisions at a level that intersect `area`.
    public func subdivisions(level: Int, in area: Bounds) -> [Int] {
        ensureLoaded()
        let lv = levels[level]
        var out: [Int] = []
        for i in lv.firstSub..<min(subs.count, lv.firstSub + lv.count) {
            let s = subs[i]
            let b = Bounds(north: s.cy + s.hh, east: s.cx + s.hw, south: s.cy - s.hh, west: s.cx - s.hw)
            if b.intersects(area) { out.append(i) }
        }
        return out
    }

    public func features(sub idx: Int) -> [Feature] {
        ensureLoaded()
        lock.lock()
        if let c = cache[idx] { lock.unlock(); return c }
        lock.unlock()
        let f = decode(sub: idx)
        lock.lock()
        if cache.count > 3000 { cache.removeAll() }
        cache[idx] = f
        lock.unlock()
        return f
    }

    // MARK: RGN decoding

    private func decode(sub idx: Int) -> [Feature] {
        guard let r = rgn else { return [] }
        let s = subs[idx]
        var out: [Feature] = []
        if !s.polyg2.isEmpty { decodeExtPoly(r, s.polyg2, s, line: false, &out) }
        if !s.polyl2.isEmpty { decodeExtPoly(r, s.polyl2, s, line: true, &out) }
        if !s.point2.isEmpty { decodeExtPoints(r, s.point2, s, &out) }
        let start = rgnData + s.rgnOffset
        let end = idx + 1 < subs.count ? rgnData + subs[idx + 1].rgnOffset : rgnData + rgnLen
        if end <= start { return out }

        var kinds: [Int] = []  // 0x10 pts, 0x20 idx pts, 0x40 lines, 0x80 polys
        for k in [0x10, 0x20, 0x40, 0x80] where s.flags & k != 0 { kinds.append(k) }
        if kinds.isEmpty { return out }
        var starts: [Int] = [start + 2 * (kinds.count - 1)]
        for i in 0..<(kinds.count - 1) { starts.append(start + r.u16(start + 2 * i)) }

        for (i, k) in kinds.enumerated() {
            let a = starts[i]
            let b = i + 1 < starts.count ? starts[i + 1] : end
            switch k {
            case 0x10, 0x20: decodePoints(r, a, b, s, &out)
            case 0x40: decodePoly(r, a, b, s, line: true, &out)
            default: decodePoly(r, a, b, s, line: false, &out)
            }
        }
        return out
    }

    private func decodePoints(_ r: MappedFile, _ a: Int, _ b: Int, _ s: Subdivision, _ out: inout [Feature]) {
        var o = a
        while o + 8 <= b {
            let type = r.u8(o)
            let lbl = r.u24(o + 1)
            let dx = r.i16(o + 4), dy = r.i16(o + 6)
            var sub = 0
            o += 8
            if lbl & 0x800000 != 0 { sub = r.u8(o); o += 1 }
            out.append(Feature(kind: .point, type: type, subtype: sub, label: lbl & 0x3FFFFF,
                               labelKind: lbl & 0x400000 != 0 ? 3 : 1,
                               coords: [Int32(clamping: s.cx + (dx << s.shift)), Int32(clamping: s.cy + (dy << s.shift))]))
        }
    }

    private func decodePoly(_ r: MappedFile, _ a: Int, _ b: Int, _ s: Subdivision, line: Bool, _ out: inout [Feature]) {
        var o = a
        while o + 7 <= b {
            let tb = r.u8(o)
            let lbl = r.u24(o + 1)
            let dx = r.i16(o + 4), dy = r.i16(o + 6)
            o += 8
            var len: Int
            if tb & 0x80 != 0 { len = r.u16(o); o += 2 } else { len = r.u8(o); o += 1 }
            len += 1   // stored as length-1
            if o + len > b { break }
            let type = line ? (tb & 0x3F) : (tb & 0x7F)
            let x0 = s.cx + (dx << s.shift), y0 = s.cy + (dy << s.shift)
            let pts = decodeBits(r, o, len, s.shift, x0, y0, hasExtra: lbl & 0x400000 != 0)
            o += len
            if pts.count >= 4 {
                out.append(Feature(kind: line ? .line : .polygon, type: type, subtype: 0,
                                   label: lbl & 0x3FFFFF, labelKind: lbl & 0x800000 != 0 ? 2 : 1, coords: pts,
                                   oneway: line && (tb & 0x40 != 0)))
            }
        }
    }

    // MARK: extended (NT) objects

    private func decodeExtPoints(_ r: MappedFile, _ range: Range<Int>, _ s: Subdivision, _ out: inout [Feature]) {
        var o = range.lowerBound
        while o + 6 <= range.upperBound {
            let t = r.u8(o), st = r.u8(o + 1)
            let dx = r.i16(o + 2), dy = r.i16(o + 4)
            var size = 6
            var label = 0
            var lk: UInt8 = 1
            if st & 0x20 != 0 { let raw = r.u24(o + 6); label = raw & 0x3FFFFF; lk = raw & 0x400000 != 0 ? 3 : 1; size += 3 }
            if st & 0x80 != 0 { size += 1 }
            out.append(Feature(kind: .point, type: 0x10000 + (t << 8) + (st & 0x1F), subtype: 0, label: label, labelKind: lk,
                               coords: [Int32(clamping: s.cx + (dx << s.shift)), Int32(clamping: s.cy + (dy << s.shift))]))
            o += size
        }
    }

    private func decodeExtPoly(_ r: MappedFile, _ range: Range<Int>, _ s: Subdivision, line: Bool, _ out: inout [Feature]) {
        var o = range.lowerBound
        while o + 8 <= range.upperBound {
            let t = r.u8(o), st = r.u8(o + 1)
            let dx = r.i16(o + 2), dy = r.i16(o + 4)
            var p = o + 6
            var L: Int
            if r.u8(p) & 1 == 0 { L = (r.u16(p) >> 2) - 1; p += 2 } else { L = (r.u8(p) >> 1) - 1; p += 1 }
            if L < 0 { break }
            let hasLabel = st & 0x20 != 0
            let total = (p - o) + 1 + L + (hasLabel ? 3 : 0)
            if o + total > range.upperBound + 3 { break }
            let pts = decodeBits(r, p, L + 1, s.shift, s.cx + (dx << s.shift), s.cy + (dy << s.shift), hasExtra: false, v2: true)
            let label = hasLabel ? r.u24(p + 1 + L) & 0x3FFFFF : 0
            if pts.count >= 4 {
                out.append(Feature(kind: line ? .line : .polygon, type: 0x10000 + (t << 8) + (st & 0x1F), subtype: 0, label: label, labelKind: 1, coords: pts))
            }
            o += total
        }
    }

    private func decodeBits(_ r: MappedFile, _ o: Int, _ len: Int, _ shift: Int,
                            _ x0: Int, _ y0: Int, hasExtra: Bool, v2: Bool = false) -> [Int32] {
        var pts: [Int32] = [Int32(clamping: x0), Int32(clamping: y0)]
        if len < 2 { return pts }
        var br = BitReader(file: r, start: o, byteLength: len)
        func width(_ base: Int) -> Int { base <= 9 ? base + 2 : 2 * base - 9 + 2 }
        let xb = br.read(4), yb = br.read(4)
        var xbits = width(xb), ybits = width(yb)
        let xSame = br.bit() == 1
        var xNeg = false
        if xSame { xNeg = br.bit() == 1 } else { xbits += 1 }
        let ySame = br.bit() == 1
        var yNeg = false
        if ySame { yNeg = br.bit() == 1 } else { ybits += 1 }
        if v2 && br.bit() == 1 { xbits += 1; ybits += 1 }
        var x = x0, y = y0
        // Value with in-band sign: two's complement, the bare sign pattern is an escape (adds max and continues).
        func signed(_ n: Int) -> Int {
            let sign = 1 << (n - 1)
            var acc = 0
            var v = br.read(n)
            while v == sign && br.remaining >= n {
                acc += v - 1
                v = br.read(n)
            }
            return v < sign ? acc + v : v - 2 * sign - acc
        }
        let step = xbits + ybits + (hasExtra ? 1 : 0)
        pts.reserveCapacity(len)
        while br.remaining >= step {
            if hasExtra { _ = br.bit() }
            var dx: Int, dy: Int
            if xSame { dx = br.read(xbits); if xNeg { dx = -dx } } else { dx = signed(xbits) }
            if ySame { dy = br.read(ybits); if yNeg { dy = -dy } } else { dy = signed(ybits) }
            x += dx << shift
            y += dy << shift
            pts.append(Int32(clamping: x)); pts.append(Int32(clamping: y))
        }
        return pts
    }
}
