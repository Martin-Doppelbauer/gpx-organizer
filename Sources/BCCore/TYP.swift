import Foundation
import CoreGraphics

/// Reads the color/width definitions of a Garmin TYP file (polygons + polylines).
/// Bitmap fills are approximated by their average color; icons are not interpreted yet.
public final class TYPStyles {
    public struct Polygon { public var fill: CGColor; public var order: Int }
    public struct Line { public var color: CGColor; public var border: CGColor?; public var width: CGFloat; public var borderWidth: CGFloat; public var dashed: Bool }

    public private(set) var polygons: [Int: Polygon] = [:]
    public private(set) var lines: [Int: Line] = [:]

    public convenience init?(path: String) {
        guard let f = MappedFile(path: path) else { return nil }
        self.init(file: f)
    }

    public init?(file f: MappedFile) {
        guard f.size > 0x5B, f.string(2, 10) == "GARMIN TYP" else { return nil }
        let lineData = f.u32(0x1F), polyData = f.u32(0x27)
        func section(_ i: Int) -> (off: Int, mod: Int, size: Int) {
            (f.u32(0x33 + i * 10), f.u16(0x33 + i * 10 + 4), f.u32(0x33 + i * 10 + 6))
        }
        func key(_ t16: Int) -> Int {
            let typ = (t16 >> 5) & 0x7F, sub = t16 & 0x1F
            return t16 & 0x2000 != 0 ? 0x10000 | (typ << 8) | sub : typ
        }
        func offset(_ s: (off: Int, mod: Int, size: Int), _ e: Int) -> Int {
            let o = s.off + e * s.mod
            switch s.mod { case 5: return f.u16(o + 2) | (f.u8(o + 4) << 16); case 4: return f.u16(o + 2); default: return f.u8(o + 2) }
        }
        func rgb(_ o: Int) -> CGColor {   // stored as B,G,R
            CGColor(red: CGFloat(f.u8(o + 2)) / 255, green: CGFloat(f.u8(o + 1)) / 255, blue: CGFloat(f.u8(o)) / 255, alpha: 1)
        }
        func blend(_ a: CGColor, _ b: CGColor, _ t: CGFloat) -> CGColor {
            let ca = a.components ?? [0, 0, 0, 1], cb = b.components ?? [0, 0, 0, 1]
            return CGColor(red: ca[0] * t + cb[0] * (1 - t), green: ca[1] * t + cb[1] * (1 - t), blue: ca[2] * t + cb[2] * (1 - t), alpha: 1)
        }
        func ones(_ o: Int, _ bytes: Int) -> CGFloat {
            var n = 0
            for i in 0..<bytes { n += f.u8(o + i).nonzeroBitCount }
            return CGFloat(n) / CGFloat(bytes * 8)
        }

        // draw order (position in the order table = later is drawn on top)
        var order: [Int: Int] = [:]
        let os = section(3)
        if os.mod == 5, os.size > 0 {
            for e in 0..<(os.size / 5) {
                let typ = f.u8(os.off + e * 5), sub = f.u32(os.off + e * 5 + 1)
                if typ == 0 { continue }
                if sub == 0 { order[typ] = e + 1 }
                else { for n in 0..<32 where sub & (1 << n) != 0 { order[0x10000 | (typ << 8) | n] = e + 1 } }
            }
        }

        // polygons
        let ps = section(2)
        if ps.mod >= 3, ps.size > 0 {
            for e in 0..<(ps.size / ps.mod) {
                let k = key(f.u16(ps.off + e * ps.mod))
                let o = polyData + offset(ps, e)
                let ctyp = f.u8(o) & 0x0F
                let c = o + 1
                var fill: CGColor?
                switch ctyp {
                case 0x01, 0x06, 0x07: fill = rgb(c)
                case 0x08: fill = blend(rgb(c), rgb(c + 3), ones(c + 6, 128))
                case 0x09: fill = blend(rgb(c), rgb(c + 3), ones(c + 12, 128))
                case 0x0B, 0x0D, 0x0E, 0x0F:
                    let bits = ctyp == 0x0B ? c + 9 : ctyp == 0x0D ? c + 9 : ctyp == 0x0E ? c + 3 : c + 6
                    let col = rgb(c), a = max(0.25, ones(bits, 128))
                    fill = col.copy(alpha: a)
                default: break
                }
                if let fill { polygons[k] = Polygon(fill: fill, order: order[k] ?? 0) }
            }
        }

        // polylines
        let ls = section(1)
        if ls.mod >= 3, ls.size > 0 {
            for e in 0..<(ls.size / ls.mod) {
                let k = key(f.u16(ls.off + e * ls.mod))
                let o = lineData + offset(ls, e)
                let b0 = f.u8(o), ctyp = b0 & 7, rows = b0 >> 3
                let c = o + 2
                var line: Line?
                if rows == 0 {
                    switch ctyp {
                    case 0: line = Line(color: rgb(c), border: rgb(c + 3), width: CGFloat(f.u8(c + 6)), borderWidth: CGFloat(f.u8(c + 7)), dashed: false)
                    case 1: line = Line(color: rgb(c), border: rgb(c + 3), width: CGFloat(f.u8(c + 12)), borderWidth: CGFloat(f.u8(c + 13)), dashed: false)
                    case 3: line = Line(color: rgb(c), border: rgb(c + 3), width: CGFloat(f.u8(c + 9)), borderWidth: CGFloat(f.u8(c + 10)), dashed: false)
                    case 5: line = Line(color: rgb(c), border: nil, width: CGFloat(f.u8(c + 9)), borderWidth: 0, dashed: false)
                    case 6: line = Line(color: rgb(c), border: nil, width: CGFloat(f.u8(c + 3)), borderWidth: 0, dashed: false)
                    case 7: line = Line(color: rgb(c), border: nil, width: CGFloat(f.u8(c + 6)), borderWidth: 0, dashed: false)
                    default: break
                    }
                } else {
                    // pixmap line: use its foreground color; transparent-background variants are drawn dashed
                    line = Line(color: rgb(c), border: nil, width: max(1, CGFloat(rows)), borderWidth: 0, dashed: [3, 5, 6, 7].contains(Int(ctyp)))
                }
                if let line { lines[k] = line }
            }
        }
        if polygons.isEmpty && lines.isEmpty { return nil }
    }
}
