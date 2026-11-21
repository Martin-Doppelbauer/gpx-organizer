import Foundation
import CoreGraphics
import CoreText

public struct ViewState: Equatable {
    public var mx: Double      // centre, Web-Mercator normalised 0..1
    public var my: Double
    public var worldSize: Double   // pixels covering the full world width
    public var width: Int
    public var height: Int
    public init(mx: Double, my: Double, worldSize: Double, width: Int, height: Int) {
        self.mx = mx; self.my = my; self.worldSize = worldSize; self.width = width; self.height = height
    }
    public func screen(mx x: Double, my y: Double) -> CGPoint {
        CGPoint(x: (x - mx) * worldSize + Double(width) / 2, y: (y - my) * worldSize + Double(height) / 2)
    }
    public func world(_ p: CGPoint) -> (Double, Double) {
        ((Double(p.x) - Double(width) / 2) / worldSize + mx, (Double(p.y) - Double(height) / 2) / worldSize + my)
    }
    /// Visible area in Garmin map units.
    public var mapBounds: Bounds {
        let (x0, y0) = world(.zero), (x1, y1) = world(CGPoint(x: width, y: height))
        let toU = { (deg: Double) in Int(deg / degPerUnit) }
        return Bounds(north: toU(Merc.lat(y: y0)), east: toU(Merc.lon(x: x1)),
                      south: toU(Merc.lat(y: y1)), west: toU(Merc.lon(x: x0)))
    }
}

public enum MapRenderer {
    /// Renders `map` into a top-left-origin bitmap. Returns nil if cancelled.
    public static func render(map: GarminMap, view v: ViewState, scale: CGFloat = 1, showLabels: Bool = true,
                              cancelled: () -> Bool = { false }) -> CGImage? {
        let w = Int(CGFloat(v.width) * scale), h = Int(CGFloat(v.height) * scale)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: scale, y: -scale)
        ctx.setFillColor(MapStyle.background)
        ctx.fill(CGRect(x: 0, y: 0, width: v.width, height: v.height))
        ctx.setLineCap(.round); ctx.setLineJoin(.round)

        let area = v.mapBounds
        let unitsPerPixel = unitsPerCircle / v.worldSize
        let tiles = map.tiles.filter { $0.bounds.intersects(area) }
        if tiles.count > 400 { return ctx.makeImage() }   // too far zoomed out

        struct Item { let order: Int; let f: Feature; let t: Tile }
        var polys: [Item] = [], lines: [Item] = [], points: [(Feature, Tile)] = []
        for t in tiles {
            if cancelled() { return nil }
            guard let li = t.levelIndex(unitsPerPixel: unitsPerPixel) else { continue }
            for si in t.subdivisions(level: li, in: area) {
                for f in t.features(sub: si) {
                    switch f.kind {
                    case .polygon:
                        if let s = map.typ?.polygons[f.type] { polys.append(Item(order: 1000 + s.order, f: f, t: t)) }
                        else if let s = MapStyle.polygon(f.type) { polys.append(Item(order: s.1, f: f, t: t)) }
                    case .line:
                        if let s = map.typ?.lines[f.type] { lines.append(Item(order: -Int(max(s.width, s.borderWidth) * 10), f: f, t: t)) }
                        else if let s = MapStyle.line(f.type) { lines.append(Item(order: s.2 > 0 ? -Int(s.1 * 10) + 100 : 0, f: f, t: t)) }
                    case .point: points.append((f, t))
                    }
                }
            }
        }
        polys.sort { $0.order < $1.order }
        lines.sort { $0.order < $1.order }

        // Precompute pixel coordinates lazily per feature.
        func path(_ f: Feature, close: Bool) -> CGPath {
            let p = CGMutablePath()
            var i = 0
            while i + 1 < f.coords.count {
                let x = Merc.x(unit: Int(f.coords[i])), y = Merc.y(unit: Int(f.coords[i + 1]))
                let pt = v.screen(mx: x, my: y)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                i += 2
            }
            if close { p.closeSubpath() }
            return p
        }

        for it in polys {
            guard let fill = map.typ?.polygons[it.f.type]?.fill ?? MapStyle.polygon(it.f.type)?.0 else { continue }
            ctx.setFillColor(fill)
            ctx.addPath(path(it.f, close: true)); ctx.fillPath()
        }
        let zoomBoost = max(0.6, min(2.2, CGFloat(log2(v.worldSize / 4096.0)) * 0.35 + 1))
        for it in lines {
            if cancelled() { return nil }
            if let t = map.typ?.lines[it.f.type] {
                let p = path(it.f, close: false)
                let k: CGFloat = 0.5
                if let b = t.border, t.borderWidth > t.width {
                    ctx.setStrokeColor(b); ctx.setLineWidth(max(0.6, t.borderWidth * k))
                    ctx.setLineDash(phase: 0, lengths: []); ctx.addPath(p); ctx.strokePath()
                }
                ctx.setStrokeColor(t.color); ctx.setLineWidth(max(0.5, t.width * k))
                ctx.setLineDash(phase: 0, lengths: t.dashed ? [4, 3] : [])
                ctx.addPath(p); ctx.strokePath()
                continue
            }
            guard let s = MapStyle.line(it.f.type) else { continue }
            let p = path(it.f, close: false)
            // casing for roads
            if s.2 >= 44 {
                ctx.setStrokeColor(CGColor(gray: 0.55, alpha: 1)); ctx.setLineWidth(s.1 * zoomBoost + 1.2)
                ctx.setLineDash(phase: 0, lengths: []); ctx.addPath(p); ctx.strokePath()
            }
            ctx.setStrokeColor(s.0); ctx.setLineWidth(max(0.4, s.1 * zoomBoost))
            if s.3 { ctx.setLineDash(phase: 0, lengths: [4, 3]) } else { ctx.setLineDash(phase: 0, lengths: []) }
            ctx.addPath(p); ctx.strokePath()
        }
        ctx.setLineDash(phase: 0, lengths: [])
        for (f, _) in points {
            guard let s = MapStyle.point(f.type), f.coords.count >= 2 else { continue }
            let pt = v.screen(mx: Merc.x(unit: Int(f.coords[0])), my: Merc.y(unit: Int(f.coords[1])))
            ctx.setFillColor(s.0)
            ctx.fillEllipse(in: CGRect(x: pt.x - s.1, y: pt.y - s.1, width: s.1 * 2, height: s.1 * 2))
        }
        if showLabels { drawLabels(ctx, v, polys.map { ($0.f, $0.t) }, lines.map { ($0.f, $0.t) }, points, cancelled) }
        return ctx.makeImage()
    }
}
