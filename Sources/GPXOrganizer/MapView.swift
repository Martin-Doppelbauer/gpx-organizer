import SwiftUI
import AppKit
import Combine
import BCCore

struct MapContainer: NSViewRepresentable {
    @EnvironmentObject var model: AppModel

    func makeNSView(context: Context) -> MapNSView {
        let v = MapNSView()
        v.onViewChange = { [weak model] s in model?.view = s }
        v.onPick = { [weak model] id in model?.selectFromMap(id) }
        v.onOpenProfile = { [weak model] id in model?.openTrack(id, fit: false) }
        v.styleMenu = { [weak model] id in model?.makeStyleMenu(for: [id]) }
        v.onEditChanged = { [weak model] in model?.updateProfileIfEditing() }
        v.onExitEdit = { [weak model] in model?.escape() }
        return v
    }

    /// Part of the track to highlight: live profile drag, selected points (edit), or the last range chosen in the profile.
    static func highlightPoints(_ model: AppModel) -> [(Double, Double)]? {
        guard let p = model.profile, !p.dist.isEmpty else { return nil }
        var range = model.profileLiveRange
        if range == nil, let e = model.edit {
            let rows = e.selectedRows
            if rows.count >= 2, let f = rows.first, let l = rows.last { range = (f.dist, l.dist) }
        }
        if range == nil { range = model.profileHighlight }
        guard let r = range else { return nil }
        let lo = min(r.0, r.1), hi = max(r.0, r.1)
        var out: [(Double, Double)] = []
        for i in p.dist.indices where p.dist[i] >= lo && p.dist[i] <= hi {
            out.append((Merc.x(lon: p.lon[i]), Merc.y(lat: p.lat[i])))
        }
        return out.count >= 2 ? out : nil
    }

    func updateNSView(_ v: MapNSView, context: Context) {
        var cur: (Double, Double)?
        if let p = model.profile, let c = model.profileCursor, c < p.lat.count {
            cur = (Merc.x(lon: p.lon[c]), Merc.y(lat: p.lat[c]))
        }
        v.highlight = Self.highlightPoints(model)
        v.styles = model.styles
        v.multiSelected = model.multiSelected
        _ = model.viewRevision   // re-evaluate when the view is changed programmatically (fit)
        v.tileSource = model.selectedTileSource
        v.update(map: model.selectedMap, tracks: model.tracks, foreground: model.foregroundPath, externalView: model.view,
                 edit: model.edit, cursor: cur, plan: model.plan, wptEdit: model.wptEdit)
    }
}

final class MapNSView: NSView {
    var onViewChange: ((ViewState) -> Void)?
    var onPick: ((String) -> Void)?
    var onOpenProfile: ((String) -> Void)?
    var onEditChanged: (() -> Void)?
    var onExitEdit: (() -> Void)?
    var styleMenu: ((String) -> NSMenu?)?
    var styles: [String: TrackStyle] = [:]
    var highlight: [(Double, Double)]?
    var multiSelected: Set<String> = []     // further files marked in the list (drawn like the foreground track)
    var tileSource: TileSource? {
        didSet { if tileSource != oldValue { mapLayer.clear(); needsDisplay = true } }
    }
    private var edit: EditSession?
    private var tilesMissing = 0
    private var retryTimer: Timer?
    private var wptEdit: WaypointEditSession?
    private var dragWpt: Int?
    private var wptPushed = false
    private var editSink: AnyCancellable?
    private var cursor: (Double, Double)?
    private var dragVertex: EditSession.Vertex?
    private var plan: PlanSession?
    private var planSink: AnyCancellable?
    private var dragVia: Int?
    private var hoverTimer: Timer?
    private var hoverLines: [String] = []
    private var hoverPoint: CGPoint = .zero
    private var dragPushed = false

    private(set) var state = ViewState(mx: 0.5, my: 0.5, worldSize: 4_194_304, width: 800, height: 600)
    private var map: GarminMap?
    private var tracks: [GPXFile] = []
    private var foreground: String?

    // background-rendered layers (map and the track overlay)
    private lazy var mapLayer = AsyncLayer(label: "map.render", onDone: { [weak self] in self?.needsDisplay = true }) { [weak self] st, scale, cancelled in
        guard let map = self?.mapForRender else { return nil }
        return MapRenderer.render(map: map, view: st, scale: scale, cancelled: cancelled)
    }
    private lazy var trackLayer = AsyncLayer(label: "track.render", onDone: { [weak self] in self?.needsDisplay = true }) { [weak self] st, scale, cancelled in
        guard let self, let job = self.trackJob else { return nil }
        return TrackOverlay.render(tracks: job.tracks, styles: job.styles, skip: job.skip, view: st, scale: scale, cancelled: cancelled)
    }
    private var mapForRender: GarminMap?
    private var trackJob: (tracks: [GPXFile], styles: [String: TrackStyle], skip: Set<String>)?
    private var downPoint: CGPoint = .zero
    private var dragged = false
    private var trackingArea: NSTrackingArea?
    private var cursorText = ""

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func update(map: GarminMap?, tracks: [GPXFile], foreground: String?, externalView: ViewState,
                edit: EditSession?, cursor: (Double, Double)?, plan: PlanSession?, wptEdit: WaypointEditSession? = nil) {
        if wptEdit !== self.wptEdit { self.wptEdit = wptEdit; dragWpt = nil }
        if plan !== self.plan {
            self.plan = plan
            planSink = plan?.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.needsDisplay = true } }
            dragVia = nil
        }
        if edit !== self.edit {
            self.edit = edit
            editSink = edit?.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.needsDisplay = true } }
            dragVertex = nil
        }
        self.cursor = cursor
        if map?.id != self.map?.id { self.map = map; mapLayer.clear() }
        self.tracks = tracks
        self.foreground = foreground
        var ext = externalView
        ext.width = state.width; ext.height = state.height
        if ext != state { state = ext }
        refreshLayers()
        needsDisplay = true
    }

    private var overlayKey: String {
        var x = 0
        for t in tracks { x ^= ObjectIdentifier(t).hashValue &+ (t.iconOverride?.hashValue ?? 0) &+ (t.embeddedIconColor?.hashValue ?? 0) }
        return "\(tracks.count)|\(x)|\(foreground ?? "")|\(multiSelected.sorted().joined(separator: ","))|\(edit?.url.path ?? "")|\(styles.hashValue)|\(MarkerSize.index)"
    }

    /// Margin factor: layers are rendered larger than the view so small pans need no new render.
    private func expanded(_ s: ViewState) -> ViewState {
        var e = s
        e.width = Int(Double(s.width) * 1.35); e.height = Int(Double(s.height) * 1.35)
        return e
    }

    /// Request new bitmaps only when the current ones do not cover the view (or the content changed).
    private func refreshLayers() {
        guard state.width > 0 else { return }
        let scale = window?.backingScaleFactor ?? 2
        if tileSource == nil, let m = map {
            let k = m.id
            if !mapLayer.covers(state, key: k) { mapForRender = m; mapLayer.request(expanded(state), scale: scale, key: k) }
        }
        let k = overlayKey
        if !trackLayer.covers(state, key: k) {
            let skip: Set<String> = edit.map { [$0.url.path] } ?? Set(foreground.map { [$0] } ?? []).union(multiSelected)
            trackJob = (tracks, styles, skip)
            trackLayer.request(expanded(state), scale: scale, key: k)
        }
    }

    override func layout() {
        super.layout()
        let w = Int(bounds.width), h = Int(bounds.height)
        if w != state.width || h != state.height, w > 0, h > 0 {
            state.width = w; state.height = h
            notify(); refreshLayers()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(trackingArea!)
    }

    private func notify() { onViewChange?(state) }

    // MARK: drawing

    private func drawLayer(_ ctx: CGContext, _ layer: AsyncLayer) {
        guard let img = layer.image, let s = layer.imageState else { return }
        let k = state.worldSize / s.worldSize
        let c = state.screen(mx: s.mx, my: s.my)
        let w = Double(s.width) * k, h = Double(s.height) * k
        ctx.saveGState()
        // bitmap is top-left origin; view is flipped, so flip locally to draw upright
        let r = CGRect(x: Double(c.x) - w / 2, y: Double(c.y) - h / 2, width: w, height: h)
        ctx.translateBy(x: r.minX, y: r.maxY); ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .medium
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
        ctx.restoreGState()
    }

    /// Selected routes get a little thicker the further the map is zoomed out (1.0 from zoom ~14, at most 1.5x).
    private var selectionBoost: CGFloat {
        let z = log2(max(1, state.worldSize / 256))
        return CGFloat(min(1.5, 1 + max(0, 14 - z) * 0.07))
    }

    /// Range chosen in the elevation profile: bright yellow band with a dark edge, drawn on top of the route.
    private func drawHighlight(_ ctx: CGContext, width: CGFloat) {
        guard let h = highlight, h.count >= 2 else { return }
        let hp = CGMutablePath()
        for (k, q) in h.enumerated() {
            let pt = state.screen(mx: q.0, my: q.1)
            if k == 0 { hp.move(to: pt) } else { hp.addLine(to: pt) }
        }
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.6)); ctx.setLineWidth(width + 3.5)
        ctx.addPath(hp); ctx.strokePath()
        ctx.setStrokeColor(CGColor(red: 1, green: 0.88, blue: 0.1, alpha: 1)); ctx.setLineWidth(width)
        ctx.addPath(hp); ctx.strokePath()
    }

    // MARK: online tiles

    private func drawTiles(_ ctx: CGContext, _ ts: TileSource) {
        let scale = UserDefaults.standard.bool(forKey: "sharpTiles") ? Double(window?.backingScaleFactor ?? 2) : 1.0
        let z = max(0, min(ts.maxZoom, Int(ceil(log2(max(1, state.worldSize * scale / 256))))))
        let n = Double(1 << z)
        let (wx0, wy0) = state.world(.zero), (wx1, wy1) = state.world(CGPoint(x: state.width, y: state.height))
        let x0 = max(0, Int(floor(wx0 * n))), x1 = min(Int(n) - 1, Int(floor(wx1 * n)))
        let y0 = max(0, Int(floor(wy0 * n))), y1 = min(Int(n) - 1, Int(floor(wy1 * n)))
        guard x1 >= x0, y1 >= y0, (x1 - x0 + 1) * (y1 - y0 + 1) <= 400 else { return }
        let size = state.worldSize / n
        let cache = TileCache.shared
        var missing = 0
        func put(_ img: CGImage, _ r: CGRect) {
            ctx.saveGState()
            ctx.translateBy(x: r.minX, y: r.maxY); ctx.scaleBy(x: 1, y: -1)
            ctx.interpolationQuality = .high
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
            ctx.restoreGState()
        }
        for ty in y0...y1 {
            for tx in x0...x1 {
                let tl = state.screen(mx: Double(tx) / n, my: Double(ty) / n)
                let rect = CGRect(x: tl.x - 0.3, y: tl.y - 0.3, width: size + 0.6, height: size + 0.6)
                if let img = cache.cached(ts, z, tx, ty) { put(img, rect); continue }
                missing += 1
                cache.fetch(ts, z, tx, ty) { [weak self] in self?.needsDisplay = true }
                // placeholder: a coarser tile that is already loaded, scaled up
                for dz in 1...4 where z - dz >= 0 {
                    let px = tx >> dz, py = ty >> dz
                    if let img = cache.cached(ts, z - dz, px, py) {
                        let f = Double(1 << dz)
                        let pr = CGRect(x: tl.x - Double(tx - (px << dz)) * size, y: tl.y - Double(ty - (py << dz)) * size, width: size * f, height: size * f)
                        ctx.saveGState(); ctx.clip(to: rect); put(img, pr); ctx.restoreGState()
                        break
                    }
                }
            }
        }
        tilesMissing = missing
        // warm the cache for one ring of tiles around the view so panning feels instant
        if (x1 - x0 + 1) * (y1 - y0 + 1) <= 120 {
            let lim = Int(n) - 1
            for ty in max(0, y0 - 1)...min(lim, y1 + 1) {
                for tx in max(0, x0 - 1)...min(lim, x1 + 1) where tx < x0 || tx > x1 || ty < y0 || ty > y1 {
                    if cache.cached(ts, z, tx, ty) == nil { cache.fetch(ts, z, tx, ty) {} }
                }
            }
        }
    }

    /// Explains an empty map: no connection for online tiles, or a local map that has nothing here / at this zoom level.
    private func drawMapNotice(_ ctx: CGContext) {
        var text: String?
        if tileSource != nil {
            if tilesMissing > 0 {
                if TileCache.shared.networkTrouble { text = "Online map tiles are not loading – check the internet connection. Trying again …" }
                if retryTimer == nil {                               // look again soon: failed tiles are retried after a short pause
                    retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in self?.retryTimer = nil; self?.needsDisplay = true }
                }
            }
        } else if map == nil {
            text = "No map selected – choose one in the map menu at the top."
        } else if mapLayer.image != nil, mapLayer.blank {
            text = "This map has no data here or at this zoom level – zoom in, move to its area, or choose another map (for example an online map)."
        }
        guard let text else { return }
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor]
        let str = NSAttributedString(string: text, attributes: a)
        let w = min(bounds.width - 40, str.size().width + 24), h: CGFloat = str.size().width + 24 > w ? 40 : 28
        let r = CGRect(x: (bounds.width - w) / 2, y: 14, width: w, height: h)
        ctx.saveGState()
        ctx.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 8, cornerHeight: 8, transform: nil)); ctx.fillPath()
        ctx.restoreGState()
        str.draw(with: r.insetBy(dx: 12, dy: 6), options: [.usesLineFragmentOrigin])
    }

    override func draw(_ dirty: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(MapStyle.background)
        ctx.fill(bounds)
        if let ts = tileSource { drawTiles(ctx, ts) } else { drawLayer(ctx, mapLayer) }
        drawMapNotice(ctx)
        drawLayer(ctx, trackLayer)
        drawTracks(ctx)
        drawHover(ctx)
    }

    /// A selected track: white casing, its colour on top, start/end markers; only the primary one carries the profile highlight.
    private func drawSelectedTrack(_ ctx: CGContext, _ f: GPXFile, _ p: CGPath, primary: Bool) {
        let st = styles[f.id]
        let w = CGFloat(st?.width ?? 2.2)
        let line = (w + 2.6) * selectionBoost
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95)); ctx.setLineWidth(line + 4.5)
        ctx.addPath(p); ctx.strokePath()
        ctx.setStrokeColor(st?.cgColor ?? f.color); ctx.setLineWidth(line)
        ctx.addPath(p); ctx.strokePath()
        if primary { drawHighlight(ctx, width: line + 3) }
        if let s = f.segments.first, s.count >= 2, let e = f.segments.last, e.count >= 2 {
            for (pt, col) in [(state.screen(mx: s[0], my: s[1]), CGColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 1)),
                              (state.screen(mx: e[e.count - 2], my: e[e.count - 1]), CGColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1))] {
                let k = min(selectionBoost, 1.8)
                ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fillEllipse(in: CGRect(x: pt.x - 7 * k, y: pt.y - 7 * k, width: 14 * k, height: 14 * k))
                ctx.setFillColor(col); ctx.fillEllipse(in: CGRect(x: pt.x - 5 * k, y: pt.y - 5 * k, width: 10 * k, height: 10 * k))
            }
        }
    }

    private func drawTracks(_ ctx: CGContext) {
        let vis = CGRect(x: -20, y: -20, width: Double(state.width) + 40, height: Double(state.height) + 40)
        let (wx0, wy0) = state.world(CGPoint(x: vis.minX, y: vis.minY))
        let (wx1, wy1) = state.world(CGPoint(x: vis.maxX, y: vis.maxY))
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        func path(_ f: GPXFile) -> CGPath? {
            guard f.maxX >= wx0, f.minX <= wx1, f.maxY >= wy0, f.minY <= wy1 else { return nil }
            let p = CGMutablePath()
            for seg in f.lodSegments(step: 0.6 / state.worldSize) {
                var i = 0
                var last = CGPoint(x: -1e9, y: -1e9)
                var started = false
                var lastSkipped: CGPoint?
                while i + 1 < seg.count {
                    let pt = state.screen(mx: seg[i], my: seg[i + 1])
                    i += 2
                    if !started { p.move(to: pt); started = true; last = pt; continue }
                    if abs(pt.x - last.x) < 0.8 && abs(pt.y - last.y) < 0.8 { lastSkipped = pt; continue }
                    p.addLine(to: pt); last = pt; lastSkipped = nil
                }
                if let s = lastSkipped { p.addLine(to: s) }
            }
            return p
        }
        let fg = foreground
        let editedPath = edit?.url.path
        if let we = wptEdit {
            for (i, w) in we.waypoints.enumerated() {
                let pt = state.screen(mx: Merc.x(lon: w.point.lon), my: Merc.y(lat: w.point.lat))
                let m = IconStyle.marker(file: tracks.first(where: { $0.id == fg }), sym: w.sym)
                drawMarker(ctx, at: pt, rgb: m.rgb, icon: m.symbol, k: i == we.selected ? 1.3 : 1.0, highlighted: i == we.selected)
                if !w.name.isEmpty {
                    let a: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: NSColor.labelColor,
                                                           .backgroundColor: NSColor.white.withAlphaComponent(0.8)]
                    NSAttributedString(string: " \(w.name) ", attributes: a).draw(at: CGPoint(x: pt.x + 14, y: pt.y - 8))
                }
            }
        } else if editedPath == nil, let f = tracks.first(where: { $0.id == fg }), f.isWaypointFile {
            drawWaypointMarkers(ctx, f, state, scale: 1.3, highlighted: true)
            for w in f.waypoints where !w.name.isEmpty {
                let pt = state.screen(mx: w.x, my: w.y)
                let a: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: NSColor.labelColor,
                                                       .backgroundColor: NSColor.white.withAlphaComponent(0.8)]
                NSAttributedString(string: " \(w.name) ", attributes: a).draw(at: CGPoint(x: pt.x + 12, y: pt.y - 8))
            }
        } else if editedPath == nil, let f = tracks.first(where: { $0.id == fg }), let p = path(f) {
            drawSelectedTrack(ctx, f, p, primary: true)
        }
        if editedPath == nil && wptEdit == nil {
            for f in tracks where multiSelected.contains(f.id) && f.id != fg {
                if f.isWaypointFile { drawWaypointMarkers(ctx, f, state, scale: 1.3, highlighted: true) }
                else if let p = path(f) { drawSelectedTrack(ctx, f, p, primary: false) }
            }
        }
        if let e = edit { drawEdit(ctx, e, color: styles[e.url.path]?.cgColor ?? tracks.first(where: { $0.id == e.url.path })?.color) }
        if let c = cursor {
            let pt = state.screen(mx: c.0, my: c.1)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fillEllipse(in: CGRect(x: pt.x - 7, y: pt.y - 7, width: 14, height: 14))
            ctx.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1)); ctx.fillEllipse(in: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10))
        }
        if let pl = plan { drawPlan(ctx, pl) }
        // waypoints of the foreground track (or all when zoomed in)
        if state.worldSize > 32768 {
            let list = tracks.filter { !$0.isWaypointFile && ($0.id == fg || tracks.count <= 30) }
            for f in list {
                for w in f.waypoints where w.x >= wx0 && w.x <= wx1 && w.y >= wy0 && w.y <= wy1 {
                    let pt = state.screen(mx: w.x, my: w.y)
                    ctx.setFillColor(CGColor(red: 0.95, green: 0.5, blue: 0.1, alpha: 1))
                    ctx.fillEllipse(in: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8))
                    if state.worldSize > 131072, !w.name.isEmpty {
                        let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.labelColor]
                        NSAttributedString(string: w.name, attributes: a).draw(at: CGPoint(x: pt.x + 6, y: pt.y - 6))
                    }
                }
            }
        }
    }

    // MARK: route planning

    private func drawPlan(_ ctx: CGContext, _ pl: PlanSession) {
        if let r = pl.result, r.points.count >= 2 {
            let path = CGMutablePath()
            var last = CGPoint(x: -1e9, y: -1e9)
            for (k, p) in r.points.enumerated() {
                let pt = state.screen(mx: Merc.x(lon: p.lon), my: Merc.y(lat: p.lat))
                if k == 0 { path.move(to: pt) } else if abs(pt.x - last.x) >= 0.8 || abs(pt.y - last.y) >= 0.8 || k == r.points.count - 1 { path.addLine(to: pt) } else { continue }
                last = pt
            }
            ctx.setLineCap(.round); ctx.setLineJoin(.round)
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95)); ctx.setLineWidth(9); ctx.addPath(path); ctx.strokePath()
            ctx.setStrokeColor(CGColor(red: 0.12, green: 0.42, blue: 0.95, alpha: 1)); ctx.setLineWidth(5.5); ctx.addPath(path); ctx.strokePath()
        }
        for (i, v) in pl.vias.enumerated() {
            let pt = state.screen(mx: Merc.x(lon: v.lon), my: Merc.y(lat: v.lat))
            let col: CGColor = i == 0 ? CGColor(red: 0.1, green: 0.65, blue: 0.2, alpha: 1)
                : (i == pl.vias.count - 1 ? CGColor(red: 0.85, green: 0.12, blue: 0.12, alpha: 1) : CGColor(red: 0.12, green: 0.42, blue: 0.95, alpha: 1))
            ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fillEllipse(in: CGRect(x: pt.x - 12, y: pt.y - 12, width: 24, height: 24))
            ctx.setFillColor(col); ctx.fillEllipse(in: CGRect(x: pt.x - 9.5, y: pt.y - 9.5, width: 19, height: 19))
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: NSColor.white]
            let str = NSAttributedString(string: "\(i + 1)", attributes: a)
            let sz = str.size()
            str.draw(at: CGPoint(x: pt.x - sz.width / 2, y: pt.y - sz.height / 2))
        }
    }

    private func viaNear(_ p: CGPoint) -> Int? {
        guard let pl = plan else { return nil }
        var best: (Int, Double)?
        for (i, v) in pl.vias.enumerated() {
            let q = state.screen(mx: Merc.x(lon: v.lon), my: Merc.y(lat: v.lat))
            let d = Double(hypot(q.x - p.x, q.y - p.y))
            if d <= 14, best == nil || d < best!.1 { best = (i, d) }
        }
        return best?.0
    }

    /// Nearest point on the planned route: returns the leg it belongs to and the position (Mercator).
    private func routeHit(_ p: CGPoint) -> (Int, Double, Double)? {
        guard let r = plan?.result, r.points.count >= 2, r.viaIndex.count >= 2 else { return nil }
        var best: (Int, Double, Double, Double)?
        var a = state.screen(mx: Merc.x(lon: r.points[0].lon), my: Merc.y(lat: r.points[0].lat))
        for k in 1..<r.points.count {
            let b = state.screen(mx: Merc.x(lon: r.points[k].lon), my: Merc.y(lat: r.points[k].lat))
            let dx = b.x - a.x, dy = b.y - a.y
            let l2 = dx * dx + dy * dy
            var t = l2 == 0 ? 0 : ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2
            t = max(0, min(1, t))
            let d = Double(hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy)))
            if d <= 8, best == nil || d < best!.3 {
                let mx = Merc.x(lon: r.points[k - 1].lon) + Double(t) * (Merc.x(lon: r.points[k].lon) - Merc.x(lon: r.points[k - 1].lon))
                let my = Merc.y(lat: r.points[k - 1].lat) + Double(t) * (Merc.y(lat: r.points[k].lat) - Merc.y(lat: r.points[k - 1].lat))
                var leg = 0
                for i in 0..<(r.viaIndex.count - 1) where k - 1 >= r.viaIndex[i] { leg = i }
                best = (leg, mx, my, d)
            }
            a = b
        }
        return best.map { ($0.0, $0.1, $0.2) }
    }

    // MARK: editing

    private func drawEdit(_ ctx: CGContext, _ e: EditSession, color: CGColor?) {
        let col = color ?? CGColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1)
        let area = CGRect(x: -30, y: -30, width: Double(state.width) + 60, height: Double(state.height) + 60)
        var handles: [(CGPoint, Bool)] = []
        for seg in e.segs {
            let path = CGMutablePath()
            var last = CGPoint(x: -1e9, y: -1e9)
            for k in 0..<seg.xs.count {
                let pt = state.screen(mx: seg.xs[k], my: seg.ys[k])
                if k == 0 { path.move(to: pt) } else if abs(pt.x - last.x) >= 0.8 || abs(pt.y - last.y) >= 0.8 || k == seg.xs.count - 1 { path.addLine(to: pt) } else { continue }
                last = pt
                if area.contains(pt) {
                    let sel = e.selection.contains(EditSession.Vertex(t: seg.t, s: seg.s, i: k))
                    handles.append((pt, sel))
                }
            }
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95)); ctx.setLineWidth(4.8 * selectionBoost + 4)
            ctx.addPath(path); ctx.strokePath()
            ctx.setStrokeColor(col); ctx.setLineWidth(4.8 * selectionBoost)
            ctx.addPath(path); ctx.strokePath()
        }
        drawHighlight(ctx, width: 4.8 * selectionBoost + 3)
        if handles.count <= 6000 {
            for (pt, sel) in handles {
                let r: CGFloat = sel ? 6 : 3.5
                ctx.setFillColor(sel ? CGColor(red: 0.95, green: 0.1, blue: 0.1, alpha: 1) : CGColor(gray: 1, alpha: 1))
                ctx.setStrokeColor(CGColor(gray: 0.15, alpha: 1)); ctx.setLineWidth(1)
                ctx.fillEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
                ctx.strokeEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
            }
        }
    }

    private func nearestVertex(_ p: CGPoint, tol: Double = 9) -> EditSession.Vertex? {
        guard let e = edit else { return nil }
        var best: (EditSession.Vertex, Double)?
        for seg in e.segs {
            for k in 0..<seg.xs.count {
                let q = state.screen(mx: seg.xs[k], my: seg.ys[k])
                let d = Double(hypot(q.x - p.x, q.y - p.y))
                if d <= tol, best == nil || d < best!.1 { best = (EditSession.Vertex(t: seg.t, s: seg.s, i: k), d) }
            }
        }
        return best?.0
    }

    /// Closest point on any segment: returns the vertex before it, the fraction along the segment and its Mercator position.
    private func nearestSegment(_ p: CGPoint, tol: Double = 7) -> (EditSession.Vertex, Double, Double, Double)? {
        guard let e = edit else { return nil }
        var best: (EditSession.Vertex, Double, Double, Double, Double)?
        for seg in e.segs where seg.xs.count >= 2 {
            var a = state.screen(mx: seg.xs[0], my: seg.ys[0])
            for k in 1..<seg.xs.count {
                let b = state.screen(mx: seg.xs[k], my: seg.ys[k])
                let dx = b.x - a.x, dy = b.y - a.y
                let l2 = dx * dx + dy * dy
                var t = l2 == 0 ? 0 : ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2
                t = max(0, min(1, t))
                let d = Double(hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy)))
                if d <= tol, best == nil || d < best!.4 {
                    let mx = seg.xs[k - 1] + Double(t) * (seg.xs[k] - seg.xs[k - 1])
                    let my = seg.ys[k - 1] + Double(t) * (seg.ys[k] - seg.ys[k - 1])
                    best = (EditSession.Vertex(t: seg.t, s: seg.s, i: k - 1), Double(t), mx, my, d)
                }
                a = b
            }
        }
        guard let b = best else { return nil }
        return (b.0, b.1, b.2, b.3)
    }

    // MARK: interaction

    private func zoom(by factor: Double, at p: CGPoint) {
        let (wx, wy) = state.world(p)
        let ws = max(1024.0, min(134217728.0, state.worldSize * factor))
        state.worldSize = ws
        // keep the point under the cursor fixed
        state.mx = wx - (Double(p.x) - Double(state.width) / 2) / ws
        state.my = wy - (Double(p.y) - Double(state.height) / 2) / ws
        notify(); refreshLayers(); needsDisplay = true
    }

    private func pan(dx: Double, dy: Double) {
        state.mx -= dx / state.worldSize; state.my -= dy / state.worldSize
        state.my = max(0.001, min(0.999, state.my))
        notify(); refreshLayers(); needsDisplay = true
    }

    private var pendingAdd = false

    override func mouseDown(with e: NSEvent) {
        hideHover()
        downPoint = convert(e.locationInWindow, from: nil); dragged = false
        window?.makeFirstResponder(self)
        pendingAdd = false
        if let pl = plan {
            dragVia = nil
            if let i = viaNear(downPoint) { dragVia = i; return }
            if let (leg, mx, my) = routeHit(downPoint) {
                dragVia = pl.insertVia(at: leg + 1, lat: Merc.lat(y: my), lon: Merc.lon(x: mx))
                return
            }
            pendingAdd = true
            return
        }
        if let we = wptEdit {
            dragWpt = nil; wptPushed = false
            var best: (Int, Double)?
            for (i, w) in we.waypoints.enumerated() {
                let q = state.screen(mx: Merc.x(lon: w.point.lon), my: Merc.y(lat: w.point.lat))
                let d = hypot(q.x - downPoint.x, q.y - downPoint.y)
                if d <= 16, best == nil || d < best!.1 { best = (i, d) }
            }
            if let (i, _) = best { we.selected = i; dragWpt = i; needsDisplay = true; return }
            if we.addMode { pendingAdd = true; return }
            if e.clickCount == 2 { zoom(by: 2, at: downPoint) }
            return
        }
        if let ed = edit {
            dragVertex = nil; dragPushed = false
            if let v = nearestVertex(downPoint) {
                if e.modifierFlags.contains(.shift) {
                    if ed.selection.contains(v) { ed.selection.remove(v) } else { ed.selection.insert(v) }
                } else if !ed.selection.contains(v) { ed.selection = [v] }
                dragVertex = v; needsDisplay = true; return
            }
            if let (a, frac, mx, my) = nearestSegment(downPoint) {
                ed.pushUndo()
                dragVertex = ed.insert(after: a, fraction: frac, mx: mx, my: my)
                dragPushed = true
                onEditChanged?()
                return
            }
            if ed.addMode { pendingAdd = true; return }          // a click (without dragging) adds a point
            ed.selection = []
            if e.clickCount == 2 { zoom(by: 2, at: downPoint) }
            return
        }
        if e.clickCount == 2 {
            if let id = pickTrack(downPoint) { onOpenProfile?(id) } else { zoom(by: 2, at: downPoint) }
        }
    }
    override func mouseDragged(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if hypot(p.x - downPoint.x, p.y - downPoint.y) > 3 { dragged = true }
        if let pl = plan, let i = dragVia {
            let (mx, my) = state.world(p)
            pl.moveVia(i, lat: Merc.lat(y: my), lon: Merc.lon(x: mx))
            return
        }
        if let we = wptEdit, let i = dragWpt {
            if !wptPushed { we.pushUndo(); wptPushed = true }
            let (mx, my) = state.world(p)
            we.move(i, mx: mx, my: my)
            return
        }
        if let ed = edit, let v = dragVertex {
            if !dragPushed { ed.pushUndo(); dragPushed = true }
            let (mx, my) = state.world(p)
            ed.move(v, mx: mx, my: my)
            return
        }
        if dragged { pan(dx: Double(e.deltaX), dy: Double(e.deltaY)) }
    }
    override func mouseUp(with e: NSEvent) {
        if let pl = plan {
            if dragVia != nil { dragVia = nil; pl.recompute() }
            else if pendingAdd, !dragged {
                let (mx, my) = state.world(downPoint)
                pl.addVia(lat: Merc.lat(y: my), lon: Merc.lon(x: mx))
            }
            pendingAdd = false
            return
        }
        if let we = wptEdit {
            if dragWpt != nil { dragWpt = nil }
            else if pendingAdd, !dragged {
                let (mx, my) = state.world(downPoint)
                we.add(mx: mx, my: my)
            } else if dragged, !pendingAdd { /* panned */ }
            pendingAdd = false
            return
        }
        if let ed = edit {
            if dragVertex != nil { dragVertex = nil; ed.commitMove(); onEditChanged?() }
            else if pendingAdd, !dragged {
                let (mx, my) = state.world(downPoint)
                ed.addPoint(mx: mx, my: my)
                onEditChanged?()
            }
            pendingAdd = false
            return
        }
        guard !dragged, e.clickCount == 1 else { return }
        if let id = pickTrack(downPoint) { onPick?(id) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard edit == nil, plan == nil, wptEdit == nil else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        guard let id = pickTrack(p) else { return nil }
        onPick?(id)
        return styleMenu?(id)
    }
    override func keyDown(with e: NSEvent) {
        if e.keyCode == 53 { onExitEdit?(); return }          // ESC: editor first, then the profile
        if let we = wptEdit, e.keyCode == 51 || e.keyCode == 117 { we.deleteSelected(); return }
        if let ed = edit {
            switch e.keyCode {
            case 51, 117: ed.deleteSelected(); onEditChanged?(); return
            default: break
            }
        }
        super.keyDown(with: e)
    }
    override func scrollWheel(with e: NSEvent) {
        hideHover()
        let p = convert(e.locationInWindow, from: nil)
        if e.modifierFlags.contains(.option) {
            // Option + scroll pans (useful with a trackpad)
            pan(dx: Double(e.scrollingDeltaX), dy: Double(e.scrollingDeltaY))
        } else {
            // Mouse wheel / two-finger scroll zooms around the cursor
            let dy = Double(e.scrollingDeltaY)
            guard dy != 0 else { return }
            let d = dy * (e.hasPreciseScrollingDeltas ? 0.006 : 0.12)
            zoom(by: exp(max(-0.6, min(0.6, d))), at: p)
        }
    }
    override func magnify(with e: NSEvent) {
        hideHover()
        zoom(by: 1 + Double(e.magnification), at: convert(e.locationInWindow, from: nil)) }
    // MARK: hover tooltip (all tracks under the pointer)

    private func hideHover() {
        hoverTimer?.invalidate(); hoverTimer = nil
        if !hoverLines.isEmpty { hoverLines = []; needsDisplay = true }
    }

    override func mouseMoved(with e: NSEvent) {
        hideHover()
        guard edit == nil, plan == nil else { return }
        let p = convert(e.locationInWindow, from: nil)
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            guard let self else { return }
            let lines = self.tracksDescription(at: p)
            if !lines.isEmpty { self.hoverLines = lines; self.hoverPoint = p; self.needsDisplay = true }
        }
    }

    override func mouseExited(with e: NSEvent) { hideHover() }

    private func tracksDescription(at p: CGPoint) -> [String] {
        let tol = 6.0
        let (x0, y0) = state.world(CGPoint(x: p.x - tol, y: p.y - tol))
        let (x1, y1) = state.world(CGPoint(x: p.x + tol, y: p.y + tol))
        let step = 0.6 / state.worldSize
        var hits: [(GPXFile, Double)] = []
        for f in tracks {
            guard f.maxX >= x0, f.minX <= x1, f.maxY >= y0, f.minY <= y1 else { continue }
            var best = Double.infinity
            if f.isWaypointFile {
                for w in f.waypoints { best = min(best, hypot(state.screen(mx: w.x, my: w.y).x - p.x, state.screen(mx: w.x, my: w.y).y - p.y)) }
                if best <= 9 { hits.append((f, best)) }
                continue
            }
            for seg in f.lodSegments(step: step) {
                var i = 0
                var prev: CGPoint?
                while i + 1 < seg.count {
                    let q = state.screen(mx: seg[i], my: seg[i + 1]); i += 2
                    if let a = prev, max(a.x, q.x) >= p.x - tol, min(a.x, q.x) <= p.x + tol, max(a.y, q.y) >= p.y - tol, min(a.y, q.y) <= p.y + tol {
                        best = min(best, distToSegment(p, a, q))
                    }
                    prev = q
                }
            }
            if best <= tol { hits.append((f, best)) }
        }
        // sorted by file name (natural order: "Tour 2" before "Tour 10")
        hits.sort { $0.0.url.lastPathComponent.localizedStandardCompare($1.0.url.lastPathComponent) == .orderedAscending }
        var lines = hits.prefix(12).map { (f, _) -> String in
            let name = f.url.deletingPathExtension().lastPathComponent
            if f.isWaypointFile { return "\(name) — waypoint" + (f.waypoints.first.map { $0.sym.isEmpty ? "" : " (\($0.sym))" } ?? "") }
            return "\(name) — " + String(format: "%.1f km", f.distance / 1000) + (f.ascent > 0 ? String(format: ", ↑ %.0f m", f.ascent) : "")
        }
        if hits.count > 12 { lines.append("… and \(hits.count - 12) more") }
        return lines
    }

    private func drawHover(_ ctx: CGContext) {
        guard !hoverLines.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: 12)
        let head = hoverLines.count > 1 ? "\(hoverLines.count) Tracks" : ""
        var rows = hoverLines
        if !head.isEmpty { rows.insert(head, at: 0) }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let strings = rows.enumerated().map { NSAttributedString(string: $0.element, attributes: (hoverLines.count > 1 && $0.offset == 0) ? [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.labelColor] : attrs) }
        let w = (strings.map { $0.size().width }.max() ?? 100) + 16
        let lh: CGFloat = 17
        let h = CGFloat(strings.count) * lh + 10
        var x = hoverPoint.x + 14, y = hoverPoint.y + 18
        if x + w > bounds.width - 4 { x = max(4, hoverPoint.x - w - 8) }
        if y + h > bounds.height - 4 { y = max(4, hoverPoint.y - h - 8) }
        let r = CGRect(x: x, y: y, width: w, height: h)
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill(); path.fill()
        NSColor.separatorColor.setStroke(); path.lineWidth = 0.8; path.stroke()
        for (i, str) in strings.enumerated() { str.draw(at: CGPoint(x: r.minX + 8, y: r.minY + 5 + CGFloat(i) * lh)) }
    }

    /// Nearest visible track within a few pixels of `p` (foreground track has priority).
    private func pickTrack(_ p: CGPoint) -> String? {
        let tol = 7.0
        var best: (String, Double)?
        let order = tracks.reversed()          // top-most first
        for f in order {
            let (x0, y0) = state.world(CGPoint(x: p.x - tol, y: p.y - tol))
            let (x1, y1) = state.world(CGPoint(x: p.x + tol, y: p.y + tol))
            guard f.maxX >= x0, f.minX <= x1, f.maxY >= y0, f.minY <= y1 else { continue }
            var d = Double.infinity
            if f.isWaypointFile {
                for w in f.waypoints { let q = state.screen(mx: w.x, my: w.y); d = min(d, hypot(q.x - p.x, q.y - p.y) - 3) }
            }
            for seg in f.segments {
                var i = 0
                var prev: CGPoint?
                while i + 1 < seg.count {
                    let q = state.screen(mx: seg[i], my: seg[i + 1]); i += 2
                    if let a = prev { d = min(d, distToSegment(p, a, q)) }
                    prev = q
                }
            }
            if d <= tol {
                if f.id == foreground { return f.id }       // keep the top one when clicking on it
                if best == nil || d < best!.1 - 0.5 { best = (f.id, d) }
            }
        }
        return best?.0
    }

    private func distToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let l2 = dx * dx + dy * dy
        var t = l2 == 0 ? 0 : ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2
        t = max(0, min(1, t))
        return Double(hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy)))
    }
}
