import Foundation
import CoreGraphics
import AppKit
import BCCore

/// Draws all background tracks into one transparent bitmap (the selected/edited track is drawn live on top).
enum TrackOverlay {
    static func render(tracks: [GPXFile], styles: [String: TrackStyle], skip: Set<String>, view v: ViewState,
                       scale: CGFloat, cancelled: () -> Bool) -> CGImage? {
        let w = Int(CGFloat(v.width) * scale), h = Int(CGFloat(v.height) * scale)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: scale, y: -scale)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        let (wx0, wy0) = v.world(CGPoint(x: -20, y: -20))
        let (wx1, wy1) = v.world(CGPoint(x: Double(v.width) + 20, y: Double(v.height) + 20))
        let step = 0.6 / v.worldSize
        for f in tracks where !skip.contains(f.id) {
            if cancelled() { return nil }
            guard f.maxX >= wx0, f.minX <= wx1, f.maxY >= wy0, f.minY <= wy1 else {
                // the route is out of view, but a marker kept in the same file may still be in view
                if !f.isWaypointFile, f.waypoints.contains(where: { $0.iconID != nil }) { drawWaypointMarkers(ctx, f, v, scale: 1) }
                continue
            }
            if f.isWaypointFile { drawWaypointMarkers(ctx, f, v, scale: 1); continue }
            let p = CGMutablePath()
            for seg in f.lodSegments(step: step) {
                var i = 0
                var last = CGPoint(x: -1e9, y: -1e9)
                var started = false
                while i + 1 < seg.count {
                    let pt = v.screen(mx: seg[i], my: seg[i + 1]); i += 2
                    if !started { p.move(to: pt); started = true; last = pt; continue }
                    if abs(pt.x - last.x) < 0.8 && abs(pt.y - last.y) < 0.8 { continue }
                    p.addLine(to: pt); last = pt
                }
            }
            let st = styles[f.id]
            let col = st?.cgColor ?? f.color
            ctx.setStrokeColor(col.copy(alpha: 0.78) ?? col); ctx.setLineWidth(CGFloat(st?.width ?? 2.2))
            ctx.addPath(p); ctx.strokePath()
            if f.waypoints.contains(where: { $0.iconID != nil }) { drawWaypointMarkers(ctx, f, v, scale: 1) }
        }
        return ctx.makeImage()
    }
}

/// White glyph images (SF Symbols) for the waypoint markers, rendered once per symbol name.
enum WaypointGlyphs {
    private static var cache: [String: CGImage] = [:]
    private static let lock = NSLock()
    static func image(_ name: String) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        if let c = cache[name] { return c }
        let base: NSImage
        if CustomIcons.isCustom(name) { base = CustomIcons.image(name, size: 40) }
        else if let sf = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 40, weight: .bold)) { base = sf }
        else { return nil }
        let size = base.size
        let w = Int(ceil(size.width)), h = Int(ceil(size.height))
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = gc
        base.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        ctx.setBlendMode(.sourceIn); ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let img = ctx.makeImage()
        if let img { cache[name] = img }
        return img
    }
}

/// Size of the waypoint markers on the map: small / medium (the default, the original size) / large. Set in Settings.
enum MarkerSize {
    static let factors: [CGFloat] = [0.8, 1.0, 1.25]
    static let titles = [L("Small"), L("Medium"), L("Large")]
    static var index: Int {
        get { let v = UserDefaults.standard.object(forKey: "markerSize") as? Int ?? 1; return max(0, min(factors.count - 1, v)) }
        set { UserDefaults.standard.set(newValue, forKey: "markerSize") }
    }
    static var factor: CGFloat { factors[index] }
}

/// One round marker: filled circle in the symbol's color with a white glyph, white ring around it.
func drawMarker(_ ctx: CGContext, at pt: CGPoint, rgb c: [Double], icon: String, k: CGFloat, highlighted: Bool = false, sizeFactor: CGFloat = 1) {
    let r: CGFloat = 9 * k * MarkerSize.factor * sizeFactor
    if highlighted {
        ctx.setFillColor(CGColor(red: 1, green: 0.9, blue: 0.1, alpha: 0.55))
        ctx.fillEllipse(in: CGRect(x: pt.x - r - 6, y: pt.y - r - 6, width: (r + 6) * 2, height: (r + 6) * 2))
    }
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: pt.x - r - 1.8, y: pt.y - r - 1.8, width: (r + 1.8) * 2, height: (r + 1.8) * 2))
    ctx.setFillColor(CGColor(red: c[0], green: c[1], blue: c[2], alpha: 1))
    ctx.fillEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.45)); ctx.setLineWidth(0.8)
    ctx.strokeEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
    if let g = WaypointGlyphs.image(icon) {
        let gh = r * 1.15
        let gw = gh * CGFloat(g.width) / CGFloat(g.height)
        ctx.saveGState()
        ctx.translateBy(x: pt.x, y: pt.y); ctx.scaleBy(x: 1, y: -1)       // the contexts here are flipped
        ctx.draw(g, in: CGRect(x: -gw / 2, y: -gh / 2, width: gw, height: gh))
        ctx.restoreGState()
    }
}

/// The marker being dragged right now (hidden in the cached layers, drawn live under the pointer).
enum MarkerDrag {
    private static let lock = NSLock()
    private static var _hidden: (file: String, index: Int)?
    static var hidden: (file: String, index: Int)? {
        get { lock.lock(); defer { lock.unlock() }; return _hidden }
        set { lock.lock(); _hidden = newValue; lock.unlock() }
    }
    static var key: String { hidden.map { "\($0.file)#\($0.index)" } ?? "" }
}

/// Waypoints drawn as markers: all of a waypoint file, and in a track file the markers made with this app (they have an icon).
func markerWaypoints(_ f: GPXFile) -> [Waypoint] {
    f.isWaypointFile ? f.waypoints : f.waypoints.filter { $0.iconID != nil }
}

/// Symbol, color and size factor of one marker: its own attributes win, then the file's, then the Garmin symbol.
func markerLook(_ f: GPXFile, _ w: Waypoint) -> (symbol: String, rgb: [Double], size: CGFloat) {
    let size = CGFloat(w.size ?? 1)
    if let id = w.iconID {
        let rgb = w.colorHex.flatMap { Waypoint.rgb(fromHex: $0) } ?? IconStyle.rgb(ofIcon: id) ?? [0.95, 0.5, 0.1]
        return (IconCatalog.symbol(for: id), rgb, size)
    }
    let m = IconStyle.marker(file: f, sym: w.sym)
    return (m.symbol, w.colorHex.flatMap { Waypoint.rgb(fromHex: $0) } ?? m.rgb, size)
}

/// Round markers of a file.
func drawWaypointMarkers(_ ctx: CGContext, _ f: GPXFile, _ v: ViewState, scale k: CGFloat, highlighted: Bool = false) {
    let hidden = MarkerDrag.hidden
    for w in markerWaypoints(f) {
        if let h = hidden, h.file == f.id, h.index == w.index { continue }
        let pt = v.screen(mx: w.x, my: w.y)
        if pt.x < -20 || pt.y < -20 || pt.x > Double(v.width) + 20 || pt.y > Double(v.height) + 20 { continue }
        let m = markerLook(f, w)
        drawMarker(ctx, at: pt, rgb: m.rgb, icon: m.symbol, k: k, highlighted: highlighted, sizeFactor: m.size)
    }
}
