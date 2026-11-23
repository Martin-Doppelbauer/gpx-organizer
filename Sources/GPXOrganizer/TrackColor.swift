import SwiftUI
import AppKit
import BCCore

// Optional coloring of the selected track by speed or by gradient, and small direction arrows along the tracks.

enum TrackColorMode: String, CaseIterable {
    case off, speed, gradient, heartRate, power, cadence
    var title: String {
        switch self {
        case .off: return "Normal"; case .speed: return "By Speed"; case .gradient: return "By Gradient"
        case .heartRate: return "By Heart Rate"; case .power: return "By Power"; case .cadence: return "By Cadence"
        }
    }
    /// The graph curve that holds the values (nil for "Normal" and gradient).
    var channel: ProfileChannel? {
        switch self { case .speed: return .speed; case .heartRate: return .heartRate; case .power: return .power; case .cadence: return .cadence; default: return nil }
    }
}

/// Color ramp: slow / descent = blue, middle = green, fast / steep ascent = red.
enum ColorRamp {
    static let bins = 32
    private static let stops: [(Double, [Double])] = [(0, [0.15, 0.35, 0.95]), (0.25, [0.10, 0.75, 0.90]), (0.5, [0.25, 0.80, 0.30]),
                                                      (0.75, [0.98, 0.85, 0.10]), (1, [0.90, 0.12, 0.12])]
    static func rgb(_ t: Double) -> [Double] {
        let t = min(max(t, 0), 1)
        for k in 1..<stops.count where t <= stops[k].0 {
            let a = stops[k - 1], b = stops[k]
            let u = (t - a.0) / (b.0 - a.0)
            return (0..<3).map { a.1[$0] + (b.1[$0] - a.1[$0]) * u }
        }
        return stops.last!.1
    }
    static let cgColors: [CGColor] = (0..<bins).map { let c = rgb(Double($0) / Double(bins - 1)); return CGColor(red: c[0], green: c[1], blue: c[2], alpha: 1) }
    static let colors: [Color] = (0..<bins).map { let c = rgb(Double($0) / Double(bins - 1)); return Color(red: c[0], green: c[1], blue: c[2]) }
}

/// The selected track as a polyline with one color bin per piece.
final class ColorTrack {
    let path: String
    let mode: TrackColorMode
    let x: [Double], y: [Double]        // Web-Mercator
    let bin: [UInt8]                    // piece i runs from point i to i+1
    let low: String, high: String

    init?(path: String, mode: TrackColorMode, profile p: Profile) {
        guard mode != .off, p.dist.count >= 3 else { return nil }
        let n = p.dist.count
        var value = [Double](repeating: 0, count: n)
        var lo = 0.0, hi = 1.0
        var low = "", high = ""
        switch mode {
        case .speed:
            guard p.hasSpeed, p.speed.count == n else { return nil }
            for i in 0..<n { value[i] = (p.speed[max(0, i - 1)] + p.speed[i] + p.speed[min(n - 1, i + 1)]) / 3 }
            let s = value.sorted()
            lo = max(0, s[Int(Double(n - 1) * 0.05)]); hi = max(lo + 5, s[Int(Double(n - 1) * 0.95)])
            low = String(format: "%.0f km/h", lo); high = String(format: "%.0f km/h", hi)
        case .gradient:
            guard p.hasElevation, p.ele.count == n else { return nil }
            for i in 0..<n {                                    // slope over about 60 m around the point
                var a = i, b = i
                while a > 0, p.dist[i] - p.dist[a] < 30 { a -= 1 }
                while b < n - 1, p.dist[b] - p.dist[i] < 30 { b += 1 }
                let d = max(p.dist[b] - p.dist[a], 20)
                value[i] = max(-10, min(10, (p.ele[b] - p.ele[a]) / d * 100))
            }
            lo = -10; hi = 10
            low = "−10 %"; high = "+10 %"
        case .heartRate, .power, .cadence:
            guard let ch = mode.channel, ch.available(p), ch.values(p).count == n else { return nil }
            let raw = ch.values(p)
            for i in 0..<n { value[i] = (raw[max(0, i - 1)] + raw[i] + raw[min(n - 1, i + 1)]) / 3 }
            let s = value.sorted()
            lo = s[Int(Double(n - 1) * 0.05)]; hi = max(lo + 1, s[Int(Double(n - 1) * 0.95)])
            low = String(format: "%.0f %@", lo, ch.unit); high = String(format: "%.0f %@", hi, ch.unit)
        case .off: return nil
        }
        var bins = [UInt8](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            let v = (value[i] + value[i + 1]) / 2
            bins[i] = UInt8(min(Double(ColorRamp.bins - 1), max(0, (v - lo) / (hi - lo) * Double(ColorRamp.bins - 1)).rounded()))
        }
        self.path = path; self.mode = mode; self.bin = bins; self.low = low; self.high = high
        self.x = p.lon.map { Merc.x(lon: $0) }; self.y = p.lat.map { Merc.y(lat: $0) }
    }
}

extension AppModel {
    func rebuildColorTrack() {
        guard trackColorMode != .off, edit == nil, plan == nil, let id = foregroundPath, let p = profile else { colorTrack = nil; return }
        colorTrack = ColorTrack(path: id, mode: trackColorMode, profile: p)
    }
}

/// Small button menu for the toolbar.
struct TrackColorMenu: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Menu {
            Picker("Color Track", selection: Binding(get: { model.trackColorMode }, set: { model.trackColorMode = $0 })) {
                ForEach(TrackColorMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.inline)
            Divider()
            Toggle("Direction Arrows", isOn: $model.directionArrows)
        } label: { ToolIcon(systemImage: "paintpalette") }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .onHover { ToolHint.shared.text = $0 ? "Color the selected track by speed or gradient; direction arrows" : nil }
    }
}

// MARK: drawing

extension MapNSView {
    /// White squares with an arrow in the color of the track, every ~140 points along the line.
    func drawArrows(_ ctx: CGContext, lines: [[CGPoint]], color: (Int, Int) -> CGColor) {
        let spacing: CGFloat = 140
        let vis = bounds.insetBy(dx: -20, dy: -20)
        var carried: CGFloat = spacing / 2
        for (li, pts) in lines.enumerated() where pts.count >= 2 {
            for i in 1..<pts.count {
                let a = pts[i - 1], b = pts[i]
                let len = hypot(b.x - a.x, b.y - a.y)
                if len < 0.01 { continue }
                var d = spacing - carried
                if carried + len < spacing { carried += len; continue }
                while d <= len {
                    let t = d / len
                    let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                    if vis.contains(p) { drawArrow(ctx, at: p, angle: atan2(b.y - a.y, b.x - a.x), color: color(li, i - 1)) }
                    d += spacing
                }
                carried = len - (d - spacing)
            }
            carried = spacing / 2
        }
    }

    private func drawArrow(_ ctx: CGContext, at p: CGPoint, angle: CGFloat, color: CGColor) {
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        ctx.rotate(by: angle + .pi / 2)
        let r = CGRect(x: -8, y: -8, width: 16, height: 16)
        let sq = CGPath(roundedRect: r, cornerWidth: 3.5, cornerHeight: 3.5, transform: nil)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.addPath(sq); ctx.fillPath()
        ctx.setStrokeColor(color); ctx.setLineWidth(1.6); ctx.addPath(sq); ctx.strokePath()
        ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.setLineWidth(1.9)
        ctx.move(to: CGPoint(x: 0, y: 4.2)); ctx.addLine(to: CGPoint(x: 0, y: -4.2)); ctx.strokePath()
        ctx.move(to: CGPoint(x: -3.2, y: -1.2)); ctx.addLine(to: CGPoint(x: 0, y: -4.4)); ctx.addLine(to: CGPoint(x: 3.2, y: -1.2)); ctx.strokePath()
        ctx.restoreGState()
    }

    /// Color legend at the top left of the map.
    func drawColorLegend(_ ctx: CGContext, _ ct: ColorTrack) {
        let r = CGRect(x: 14, y: 14, width: 190, height: 40)
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.88)); ctx.addPath(CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: nil)); ctx.fillPath()
        let bar = CGRect(x: r.minX + 10, y: r.minY + 8, width: r.width - 20, height: 9)
        let w = bar.width / CGFloat(ColorRamp.bins)
        for i in 0..<ColorRamp.bins { ctx.setFillColor(ColorRamp.cgColors[i]); ctx.fill(CGRect(x: bar.minX + CGFloat(i) * w, y: bar.minY, width: w + 0.5, height: bar.height)) }
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.black]
        NSAttributedString(string: ct.low, attributes: a).draw(at: CGPoint(x: bar.minX, y: bar.maxY + 3))
        let hs = NSAttributedString(string: ct.high, attributes: a)
        hs.draw(at: CGPoint(x: bar.maxX - hs.size().width, y: bar.maxY + 3))
        let ts = NSAttributedString(string: ct.mode == .gradient ? "Gradient" : (ct.mode.channel?.title ?? ""), attributes: [.font: NSFont.boldSystemFont(ofSize: 9), .foregroundColor: NSColor.darkGray])
        ts.draw(at: CGPoint(x: bar.midX - ts.size().width / 2, y: bar.maxY + 4))
    }
}
