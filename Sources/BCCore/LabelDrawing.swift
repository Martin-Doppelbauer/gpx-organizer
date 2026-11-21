import Foundation
import CoreGraphics
import CoreText

extension MapRenderer {
    private static func font(_ size: CGFloat, bold: Bool = false, italic: Bool = false) -> CTFont {
        let name = bold ? "HelveticaNeue-Bold" : (italic ? "HelveticaNeue-Italic" : "HelveticaNeue")
        return CTFontCreateWithName(name as CFString, size, nil)
    }

    private static func makeLine(_ text: String, _ f: CTFont) -> (CTLine, CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): f,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        return (line, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
    }

    /// Draw `line` with a light halo so it stays readable on any background. Origin = baseline start (flipped context).
    private static func paint(_ ctx: CGContext, _ line: CTLine, at p: CGPoint, color: CGColor) {
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = p
        ctx.setTextDrawingMode(.stroke)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.85)); ctx.setLineWidth(3); ctx.setLineJoin(.round)
        CTLineDraw(line, ctx)
        ctx.textPosition = p
        ctx.setTextDrawingMode(.fill)
        ctx.setFillColor(color)
        CTLineDraw(line, ctx)
    }

    private static let genericNames: Set<String> = ["Unterstand", "Bank", "Sitzbank", "Papierkorb", "Mülleimer", "Brunnen", "Telefon", "Parkplatz", "Toilette", "Hütte"]

    static func drawLabels(_ ctx: CGContext, _ v: ViewState, _ polys: [(Feature, Tile)], _ lines: [(Feature, Tile)],
                           _ points: [(Feature, Tile)], _ cancelled: () -> Bool) {
        let ws = v.worldSize
        let bounds = CGRect(x: 0, y: 0, width: v.width, height: v.height)
        var placed: [CGRect] = []
        func free(_ r: CGRect) -> Bool {
            guard bounds.insetBy(dx: -2, dy: -2).contains(r) else { return false }
            let rr = r.insetBy(dx: -2, dy: -1)
            for q in placed where q.intersects(rr) { return false }
            placed.append(rr); return true
        }
        func scr(_ f: Feature, _ i: Int) -> CGPoint {
            v.screen(mx: Merc.x(unit: Int(f.coords[i])), my: Merc.y(unit: Int(f.coords[i + 1])))
        }
        let dark = CGColor(gray: 0.12, alpha: 1)

        // 1) places and points of interest (most important first)
        var named: [(Feature, Tile, String)] = []
        for (f, t) in points where f.labelKind != 0 && f.coords.count >= 2 {
            let ty = f.type
            let isPlace = (0x01...0x0c).contains(ty)
            let isPeak = ty == 0x66 && f.subtype == 0x16
            let isPOI = (0x11...0x30).contains(ty) || (0x2a...0x30).contains(ty)
            if isPlace || (isPeak && ws >= 1048576.0) || (isPOI && ws >= 4194304.0) {
                if let s = t.labelText(f), !(isPOI && !isPeak && genericNames.contains(s)) { named.append((f, t, s)) }
            }
        }
        named.sort { ($0.0.type < $1.0.type) }
        for (f, _, text) in named.prefix(400) {
            if cancelled() { return }
            let ty = f.type
            let place = (0x01...0x0c).contains(ty)
            let size: CGFloat = ty <= 0x04 ? 15 : (ty <= 0x08 ? 13 : (place ? 11.5 : 10))
            let (line, w) = makeLine(text, font(size, bold: place && ty <= 0x08, italic: !place))
            let p = scr(f, 0)
            let rect = CGRect(x: p.x + 5, y: p.y - size * 0.8, width: w, height: size)
            if free(rect) { paint(ctx, line, at: CGPoint(x: rect.minX, y: rect.minY + size * 0.8),
                                  color: place ? dark : CGColor(red: 0.25, green: 0.3, blue: 0.45, alpha: 1)) }
        }

        // 2) names of large areas (lakes, parks) at moderate zoom and above
        if ws >= 524288.0 {
            var done = 0
            for (f, t) in polys where f.labelKind != 0 && f.coords.count >= 6 && done < 60 {
                let water = [0x28, 0x32, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49].contains(f.type)
                let park = (0x14...0x17).contains(f.type) || f.type == 0x18 || f.type == 0x19
                guard water || park, let text = t.labelText(f) else { continue }
                var minX = CGFloat.infinity, minY = CGFloat.infinity, maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
                var i = 0
                while i + 1 < f.coords.count { let p = scr(f, i); i += 2
                    minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
                let (line, w) = makeLine(text, font(11, italic: true))
                if maxX - minX < w * 1.15 || maxY - minY < 16 { continue }
                let rect = CGRect(x: (minX + maxX) / 2 - w / 2, y: (minY + maxY) / 2 - 7, width: w, height: 14)
                if free(rect) {
                    paint(ctx, line, at: CGPoint(x: rect.minX, y: rect.minY + 11),
                          color: water ? CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1) : CGColor(red: 0.2, green: 0.45, blue: 0.2, alpha: 1))
                    done += 1
                }
            }
        }

        // 3) street / trail names along the line
        if ws >= 2097152.0 {
            var done = 0
            var seen: [String: [CGPoint]] = [:]
            for (f, t) in lines where f.labelKind != 0 && f.coords.count >= 4 && done < 250 {
                if cancelled() { return }
                guard (0x01...0x0c).contains(f.type) || f.type == 0x16, let text = t.labelText(f) else { continue }
                let (line, w) = makeLine(text, font(10.5))
                // longest visible segment
                var best: (CGFloat, CGPoint, CGPoint)?
                var prev = scr(f, 0)
                var i = 2
                while i + 1 < f.coords.count {
                    let q = scr(f, i); i += 2
                    let len = hypot(q.x - prev.x, q.y - prev.y)
                    let mid = CGPoint(x: (q.x + prev.x) / 2, y: (q.y + prev.y) / 2)
                    if bounds.contains(mid), best == nil || len > best!.0 { best = (len, prev, q) }
                    prev = q
                }
                guard let (len, a, b) = best, len >= w + 8 else { continue }
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                if let others = seen[text], others.contains(where: { hypot($0.x - mid.x, $0.y - mid.y) < 180 }) { continue }
                var ang = atan2(b.y - a.y, b.x - a.x)
                if ang > .pi / 2 { ang -= .pi } else if ang < -.pi / 2 { ang += .pi }
                let ex = abs(cos(ang)) * w / 2 + abs(sin(ang)) * 6, ey = abs(sin(ang)) * w / 2 + abs(cos(ang)) * 6
                guard free(CGRect(x: mid.x - ex, y: mid.y - ey, width: ex * 2, height: ey * 2)) else { continue }
                ctx.saveGState()
                ctx.translateBy(x: mid.x, y: mid.y); ctx.rotate(by: ang)
                paint(ctx, line, at: CGPoint(x: -w / 2, y: 3.5), color: dark)
                ctx.restoreGState()
                seen[text, default: []].append(mid)
                done += 1
            }
        }
    }
}
