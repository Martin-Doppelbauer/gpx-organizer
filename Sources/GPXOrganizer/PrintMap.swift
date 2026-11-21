import SwiftUI
import AppKit
import BCCore

/// Prints the map as it is shown: same centre and same scale across the window width, paper in landscape when the map is wider than
/// high (portrait otherwise), the map extended up and down (or left and right) so that the whole sheet is filled; a scale bar at the
/// bottom right.
extension AppModel {
    @MainActor func printMap() {
        let v = view
        guard v.width > 0, v.height > 0 else { return }
        let pi = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        pi.orientation = v.width >= v.height ? .landscape : .portrait
        pi.topMargin = 0; pi.bottomMargin = 0; pi.leftMargin = 0; pi.rightMargin = 0
        pi.isHorizontallyCentered = true; pi.isVerticallyCentered = true
        pi.horizontalPagination = .fit; pi.verticalPagination = .fit
        var page = pi.imageablePageBounds.size
        if page.width < 100 || page.height < 100 { page = pi.paperSize }
        let k = Double(page.width) / Double(v.width)                      // page points per window point
        var s = v
        s.width = Int(ceil(Double(page.width) / k)); s.height = Int(ceil(Double(page.height) / k))

        let data = PrintMapView.Content(state: s, k: k, tracks: tracks, styles: styles, foreground: foregroundPath,
                                        selected: multiSelected, tileSource: selectedTileSource,
                                        attribution: selectedTileSource?.attribution)
        let pv = PrintMapView(frame: NSRect(origin: .zero, size: page), content: data)
        let map = selectedMap
        Task { @MainActor in
            if let ts = selectedTileSource { await pv.loadTiles(ts) }
            else if let m = map { pv.mapImage = await Task.detached { PrintMapView.renderGarmin(m, s, scale: CGFloat(k) * 200.0 / 72.0) }.value }
            let op = NSPrintOperation(view: pv, printInfo: pi)
            op.jobTitle = "GPX Organizer map"
            op.showsPrintPanel = true
            op.showsProgressPanel = true
            op.run()
        }
    }
}

final class PrintMapView: NSView {
    struct Content {
        var state: ViewState            // in window points, already extended to the page's aspect ratio
        var k: Double                   // page points per window point
        var tracks: [GPXFile]
        var styles: [String: TrackStyle]
        var foreground: String?
        var selected: Set<String>
        var tileSource: TileSource?
        var attribution: String?
    }

    let c: Content
    var mapImage: CGImage?
    override var isFlipped: Bool { true }

    init(frame: NSRect, content: Content) { c = content; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }

    nonisolated static func renderGarmin(_ m: GarminMap, _ s: ViewState, scale: CGFloat) -> CGImage? {
        MapRenderer.render(map: m, view: s, scale: scale)
    }

    // MARK: tiles

    private var tileLevel: Int {
        guard let ts = c.tileSource else { return 0 }
        let scale = UserDefaults.standard.bool(forKey: "sharpTiles") ? 2.0 : 1.0
        return max(0, min(ts.maxZoom, Int(ceil(log2(max(1, c.state.worldSize * scale / 256))))))
    }

    private func tileRange() -> (z: Int, x0: Int, x1: Int, y0: Int, y1: Int)? {
        let z = tileLevel, n = Double(1 << z), s = c.state
        let (wx0, wy0) = s.world(.zero), (wx1, wy1) = s.world(CGPoint(x: s.width, y: s.height))
        let x0 = max(0, Int(floor(wx0 * n))), x1 = min(Int(n) - 1, Int(floor(wx1 * n)))
        let y0 = max(0, Int(floor(wy0 * n))), y1 = min(Int(n) - 1, Int(floor(wy1 * n)))
        guard x1 >= x0, y1 >= y0, (x1 - x0 + 1) * (y1 - y0 + 1) <= 600 else { return nil }
        return (z, x0, x1, y0, y1)
    }

    /// Requests every tile of the page and waits (at most ~15 s) until they are there.
    @MainActor func loadTiles(_ ts: TileSource) async {
        guard let r = tileRange() else { return }
        let cache = TileCache.shared
        func missing() -> Int {
            var n = 0
            for ty in r.y0...r.y1 { for tx in r.x0...r.x1 where cache.cached(ts, r.z, tx, ty) == nil { n += 1 } }
            return n
        }
        let start = Date()
        while missing() > 0, Date().timeIntervalSince(start) < 15 {
            for ty in r.y0...r.y1 { for tx in r.x0...r.x1 where cache.cached(ts, r.z, tx, ty) == nil { cache.fetch(ts, r.z, tx, ty) {} } }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    private func drawTiles(_ ctx: CGContext, _ ts: TileSource) {
        guard let r = tileRange() else { return }
        let n = Double(1 << r.z), s = c.state, size = s.worldSize / n
        let cache = TileCache.shared
        func put(_ img: CGImage, _ rect: CGRect) {
            ctx.saveGState()
            ctx.translateBy(x: rect.minX, y: rect.maxY); ctx.scaleBy(x: 1, y: -1)
            ctx.interpolationQuality = .high
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
            ctx.restoreGState()
        }
        for ty in r.y0...r.y1 {
            for tx in r.x0...r.x1 {
                let tl = s.screen(mx: Double(tx) / n, my: Double(ty) / n)
                let rect = CGRect(x: tl.x - 0.3, y: tl.y - 0.3, width: size + 0.6, height: size + 0.6)
                if let img = cache.cached(ts, r.z, tx, ty) { put(img, rect); continue }
                for dz in 1...4 where r.z - dz >= 0 {          // a tile that did not arrive: a coarser one, scaled up
                    let px = tx >> dz, py = ty >> dz
                    if let img = cache.cached(ts, r.z - dz, px, py) {
                        let f = Double(1 << dz)
                        let pr = CGRect(x: tl.x - Double(tx - (px << dz)) * size, y: tl.y - Double(ty - (py << dz)) * size, width: size * f, height: size * f)
                        ctx.saveGState(); ctx.clip(to: rect); put(img, pr); ctx.restoreGState()
                        break
                    }
                }
            }
        }
    }

    // MARK: tracks

    private var boost: CGFloat {
        let z = log2(max(1, c.state.worldSize / 256))
        return CGFloat(min(1.5, 1 + max(0, 14 - z) * 0.07))
    }

    private func path(_ f: GPXFile) -> CGPath? {
        let s = c.state
        let (wx0, wy0) = s.world(CGPoint(x: -20, y: -20)), (wx1, wy1) = s.world(CGPoint(x: Double(s.width) + 20, y: Double(s.height) + 20))
        guard f.maxX >= wx0, f.minX <= wx1, f.maxY >= wy0, f.minY <= wy1 else { return nil }
        let p = CGMutablePath()
        for seg in f.lodSegments(step: 0.6 / s.worldSize) {
            var i = 0, started = false
            var last = CGPoint(x: -1e9, y: -1e9)
            while i + 1 < seg.count {
                let pt = s.screen(mx: seg[i], my: seg[i + 1]); i += 2
                if !started { p.move(to: pt); started = true; last = pt; continue }
                if abs(pt.x - last.x) < 0.8 && abs(pt.y - last.y) < 0.8 { continue }
                p.addLine(to: pt); last = pt
            }
        }
        return p
    }

    private func drawTracks(_ ctx: CGContext) {
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        let marked = c.selected.union(c.foreground.map { [$0] } ?? [])
        for f in c.tracks where !marked.contains(f.id) {
            if f.isWaypointFile { drawWaypointMarkers(ctx, f, c.state, scale: 1); continue }
            guard let p = path(f) else { continue }
            let st = c.styles[f.id], col = st?.cgColor ?? f.color
            ctx.setStrokeColor(col.copy(alpha: 0.78) ?? col); ctx.setLineWidth(CGFloat(st?.width ?? 2.2))
            ctx.addPath(p); ctx.strokePath()
        }
        for f in c.tracks where marked.contains(f.id) {
            if f.isWaypointFile {
                drawWaypointMarkers(ctx, f, c.state, scale: 1.3, highlighted: true)
                for w in f.waypoints where !w.name.isEmpty {
                    let pt = c.state.screen(mx: w.x, my: w.y)
                    let a: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: NSColor.black,
                                                           .backgroundColor: NSColor.white.withAlphaComponent(0.8)]
                    NSAttributedString(string: " \(w.name) ", attributes: a).draw(at: CGPoint(x: pt.x + 12, y: pt.y - 8))
                }
                continue
            }
            guard let p = path(f) else { continue }
            let st = c.styles[f.id]
            let line = (CGFloat(st?.width ?? 2.2) + 2.6) * boost
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95)); ctx.setLineWidth(line + 4.5)
            ctx.addPath(p); ctx.strokePath()
            ctx.setStrokeColor(st?.cgColor ?? f.color); ctx.setLineWidth(line)
            ctx.addPath(p); ctx.strokePath()
            if let a = f.segments.first, a.count >= 2, let b = f.segments.last, b.count >= 2 {
                for (pt, col) in [(c.state.screen(mx: a[0], my: a[1]), CGColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 1)),
                                  (c.state.screen(mx: b[b.count - 2], my: b[b.count - 1]), CGColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1))] {
                    let k = min(boost, 1.8)
                    ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fillEllipse(in: CGRect(x: pt.x - 7 * k, y: pt.y - 7 * k, width: 14 * k, height: 14 * k))
                    ctx.setFillColor(col); ctx.fillEllipse(in: CGRect(x: pt.x - 5 * k, y: pt.y - 5 * k, width: 10 * k, height: 10 * k))
                }
            }
        }
    }

    // MARK: scale bar and credits (in page points)

    private func drawScaleBar(_ ctx: CGContext) {
        let lat = Merc.lat(y: c.state.my) * .pi / 180
        let perPagePt = 40_075_016.686 * cos(lat) / (c.state.worldSize * c.k)          // metres per page point
        guard perPagePt.isFinite, perPagePt > 0 else { return }
        let target = perPagePt * 130
        let mag = pow(10, floor(log10(target)))
        let nice = [5.0, 2.0, 1.0].map { $0 * mag }.first { $0 <= target } ?? mag
        let len = CGFloat(nice / perPagePt)
        let text = nice >= 1000 ? (nice.truncatingRemainder(dividingBy: 1000) == 0 ? "\(Int(nice / 1000)) km" : String(format: "%.1f km", nice / 1000))
                                : "\(Int(nice)) m"
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.black]
        let str = NSAttributedString(string: text, attributes: a)
        let margin: CGFloat = 26, pad: CGFloat = 7
        let boxW = max(len, str.size().width) + pad * 2, boxH: CGFloat = 27
        let box = CGRect(x: bounds.maxX - margin - boxW, y: bounds.maxY - margin - boxH, width: boxW, height: boxH)
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.55))
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: 4, cornerHeight: 4, transform: nil)); ctx.fillPath()
        let x1 = box.maxX - pad, x0 = x1 - len, y = box.maxY - 7
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 1)); ctx.setLineWidth(1.6); ctx.setLineCap(.butt)
        ctx.move(to: CGPoint(x: x0, y: y)); ctx.addLine(to: CGPoint(x: x1, y: y))
        for x in [x0, (x0 + x1) / 2, x1] { ctx.move(to: CGPoint(x: x, y: y - 4)); ctx.addLine(to: CGPoint(x: x, y: y + 4)) }
        ctx.strokePath()
        str.draw(at: CGPoint(x: x1 - str.size().width, y: box.minY + 3))
    }

    private func drawCredits(_ ctx: CGContext) {
        guard let t = c.attribution else { return }
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 6.5), .foregroundColor: NSColor.black]
        let str = NSAttributedString(string: t, attributes: a)
        let w = min(str.size().width + 8, bounds.width * 0.6)
        let r = CGRect(x: bounds.minX + 12, y: bounds.maxY - 12 - 14, width: w, height: 14)
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.8)); ctx.fill(r)
        str.draw(with: r.insetBy(dx: 4, dy: 2), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    override func draw(_ dirty: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(MapStyle.background); ctx.fill(bounds)
        ctx.saveGState()
        ctx.clip(to: bounds)
        ctx.scaleBy(x: CGFloat(c.k), y: CGFloat(c.k))                      // from here on everything is in window points
        if let ts = c.tileSource { drawTiles(ctx, ts) }
        else if let img = mapImage {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: CGFloat(c.state.height)); ctx.scaleBy(x: 1, y: -1)
            ctx.interpolationQuality = .high
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: c.state.width, height: c.state.height))
            ctx.restoreGState()
        }
        drawTracks(ctx)
        ctx.restoreGState()
        drawScaleBar(ctx)
        drawCredits(ctx)
    }
}
