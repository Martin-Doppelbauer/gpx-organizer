import SwiftUI
import AppKit

/// Icons that do not exist as SF Symbols are drawn here (template images, so they take any colour).
/// Their "symbol" name starts with `custom.`.
enum CustomIcons {
    static func isCustom(_ name: String) -> Bool { name.hasPrefix("custom.") }

    /// `size` is the edge length in points; the drawing is designed on a 24 × 24 grid.
    static func image(_ name: String, size: CGFloat = 24) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let k = rect.width / 24
            NSColor.black.setStroke(); NSColor.black.setFill()
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * k, y: y * k) }
            func line(_ pts: [(CGFloat, CGFloat)], width: CGFloat = 1.7, close: Bool = false) {
                let b = NSBezierPath(); b.lineWidth = width * k; b.lineCapStyle = .round; b.lineJoinStyle = .round
                b.move(to: p(pts[0].0, pts[0].1))
                for q in pts.dropFirst() { b.line(to: p(q.0, q.1)) }
                if close { b.close() }
                b.stroke()
            }
            switch name {
            case "custom.transmitter-tower":                      // Funkturm: lattice mast with antenna and radio waves
                line([(7.2, 1.5), (12, 15.5), (16.8, 1.5)], width: 1.8)                   // legs
                line([(8.6, 5.7), (15.4, 5.7)], width: 1.5)
                line([(10.1, 10.3), (13.9, 10.3)], width: 1.5)
                line([(8.6, 5.7), (13.9, 10.3)], width: 1.3); line([(15.4, 5.7), (10.1, 10.3)], width: 1.3)
                line([(12, 15.5), (12, 18.6)], width: 1.8)                                // antenna
                NSBezierPath(ovalIn: NSRect(x: 10.6 * k, y: 17.9 * k, width: 2.8 * k, height: 2.8 * k)).fill()
                for r in [4.2, 7.2] as [CGFloat] {                                        // waves left and right
                    let a = NSBezierPath(); a.lineWidth = 1.5 * k; a.lineCapStyle = .round
                    a.appendArc(withCenter: p(12, 19.3), radius: r * k, startAngle: 142, endAngle: 218, clockwise: false)
                    a.stroke()
                    let b = NSBezierPath(); b.lineWidth = 1.5 * k; b.lineCapStyle = .round
                    b.appendArc(withCenter: p(12, 19.3), radius: r * k, startAngle: -38, endAngle: 38, clockwise: false)
                    b.stroke()
                }
            case "custom.lookout-tower":                          // Aussichtsturm: four-legged tower with platform, rail and roof
                line([(7, 1.5), (8.6, 14.2)], width: 1.8); line([(17, 1.5), (15.4, 14.2)], width: 1.8)    // legs
                line([(7.6, 6.3), (16.4, 6.3)], width: 1.4)
                line([(7.6, 6.3), (15.9, 11.2)], width: 1.3); line([(16.4, 6.3), (8.2, 11.2)], width: 1.3)  // braces
                line([(5.8, 14.2), (18.2, 14.2)], width: 2.0)                                              // platform
                line([(7.2, 14.2), (7.2, 17.4)], width: 1.4); line([(16.8, 14.2), (16.8, 17.4)], width: 1.4) // posts
                line([(5.4, 17.4), (12, 22.4), (18.6, 17.4)], width: 1.8, close: true)                       // roof
            case "custom.coal-plant":                             // Kohlekraftwerk: plant hall with two chimneys and smoke
                NSBezierPath(rect: NSRect(x: 2 * k, y: 2 * k, width: 20 * k, height: 7 * k)).fill()
                NSBezierPath(rect: NSRect(x: 4.5 * k, y: 9 * k, width: 4 * k, height: 8 * k)).fill()
                NSBezierPath(rect: NSRect(x: 11 * k, y: 9 * k, width: 4 * k, height: 5.5 * k)).fill()
                NSBezierPath(rect: NSRect(x: 17 * k, y: 9 * k, width: 3.2 * k, height: 2.6 * k)).fill()
                for (x, y, r) in [(7.2, 19.0, 1.7), (10.4, 20.6, 1.5), (13.4, 17.2, 1.5), (16.6, 18.8, 1.3)] as [(CGFloat, CGFloat, CGFloat)] {
                    NSBezierPath(ovalIn: NSRect(x: (x - r) * k, y: (y - r) * k, width: 2 * r * k, height: 2 * r * k)).fill()
                }
            case "custom.wind-turbine":                           // Windkraftanlage: tower with three rotor blades
                line([(12, 1.5), (12, 12.5)], width: 1.8)
                for a in [90.0, 210.0, 330.0] {
                    let t = a * .pi / 180, c = (x: 12.0, y: 13.5), L = 10.5, w = 1.3
                    let tip = p(c.x + L * cos(t), c.y + L * sin(t))
                    let n = (x: -sin(t) * w, y: cos(t) * w)
                    let b = NSBezierPath()
                    b.move(to: tip); b.line(to: p(c.x + n.x, c.y + n.y)); b.line(to: p(c.x - n.x, c.y - n.y)); b.close(); b.fill()
                }
                NSBezierPath(ovalIn: NSRect(x: 10.4 * k, y: 11.9 * k, width: 3.2 * k, height: 3.2 * k)).fill()
                line([(8.5, 1.5), (15.5, 1.5)], width: 1.8)
            case "custom.solar-plant":                            // PV-Anlage: tilted solar panel on a stand
                line([(3.5, 9), (7.5, 20), (20.5, 20), (16.5, 9)], width: 1.7, close: true)
                line([(5.5, 14.5), (18.5, 14.5)], width: 1.2)
                line([(10, 9), (11.5, 20)], width: 1.2); line([(13.2, 9), (14.2, 20)], width: 1.2)
                line([(12, 9), (12, 3.5)], width: 1.8); line([(7.5, 2.5), (16.5, 2.5)], width: 1.8)
            case "custom.nuclear-plant":                          // Atomkraftwerk: radiation trefoil in a ring
                let ring = NSBezierPath(ovalIn: NSRect(x: 1.8 * k, y: 1.8 * k, width: 20.4 * k, height: 20.4 * k))
                ring.lineWidth = 1.5 * k; ring.stroke()
                for a in [90.0, 210.0, 330.0] {
                    let b = NSBezierPath(), c = p(12, 12)
                    b.appendArc(withCenter: c, radius: 8.2 * k, startAngle: a - 30, endAngle: a + 30)
                    b.appendArc(withCenter: c, radius: 3.0 * k, startAngle: a + 30, endAngle: a - 30, clockwise: true)
                    b.close(); b.fill()
                }
                NSBezierPath(ovalIn: NSRect(x: 10.3 * k, y: 10.3 * k, width: 3.4 * k, height: 3.4 * k)).fill()
            case "custom.mountain-hut":                           // Berghütte: low-roofed chalet in front of a mountain peak
                line([(2.5, 12), (12, 22.6), (21.5, 12)], width: 1.6)                       // peak behind
                let roof = NSBezierPath()
                roof.move(to: p(0.8, 9.6)); roof.line(to: p(12, 16.4)); roof.line(to: p(23.2, 9.6)); roof.close(); roof.fill()
                line([(4.2, 9.4), (4.2, 2.2), (19.8, 2.2), (19.8, 9.4)], width: 1.9)
                NSBezierPath(rect: NSRect(x: 9.6 * k, y: 2.2 * k, width: 4.8 * k, height: 5.6 * k)).fill()
            case "custom.waterfall":                              // Wasserfall: rock ledge, falling water, splash
                NSBezierPath(rect: NSRect(x: 1.5 * k, y: 18.2 * k, width: 21 * k, height: 3.2 * k)).fill()
                for x in [7.5, 12, 16.5] as [CGFloat] { line([(x, 18.2), (x, 8.2)], width: 2.3) }
                line([(10, 16.5), (10, 11)], width: 1.3)
                for (cx, dir) in [(7.5, -1.0), (16.5, 1.0)] as [(CGFloat, CGFloat)] {
                    let a = NSBezierPath(); a.lineWidth = 1.5 * k; a.lineCapStyle = .round
                    a.appendArc(withCenter: p(cx + dir * 2.6, 6.2), radius: 2.6 * k, startAngle: dir < 0 ? 20 : 160, endAngle: dir < 0 ? 100 : 80, clockwise: dir > 0)
                    a.stroke()
                }
                line([(2, 3.2), (5, 4.6), (8, 3.2), (11, 4.6), (14, 3.2), (17, 4.6), (20, 3.2), (22, 4.2)], width: 1.5)
            case "custom.church":                                 // Kirche: nave with a pointed tower and cross
                let tw = NSBezierPath()
                tw.move(to: p(4, 2)); tw.line(to: p(4, 12)); tw.line(to: p(8, 17)); tw.line(to: p(12, 12)); tw.line(to: p(12, 2)); tw.close(); tw.fill()
                let nave = NSBezierPath()
                nave.move(to: p(12.8, 2)); nave.line(to: p(12.8, 10)); nave.line(to: p(17.4, 12.6)); nave.line(to: p(22, 10)); nave.line(to: p(22, 2)); nave.close(); nave.fill()
                line([(8, 17), (8, 22.4)], width: 1.6); line([(6, 20.2), (10, 20.2)], width: 1.6)          // cross
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(rect: NSRect(x: 6.6 * k, y: 2 * k, width: 2.8 * k, height: 4.6 * k)).fill()    // door
                NSBezierPath(ovalIn: NSRect(x: 16.2 * k, y: 5.2 * k, width: 2.4 * k, height: 2.4 * k)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
            case "custom.cathedral":                              // Dom: two spired towers with a gabled nave between
                for x in [2.5, 15.5] as [CGFloat] {
                    let t = NSBezierPath()
                    t.move(to: p(x, 2)); t.line(to: p(x, 14)); t.line(to: p(x + 3, 19.6)); t.line(to: p(x + 6, 14)); t.line(to: p(x + 6, 2)); t.close(); t.fill()
                }
                let mid = NSBezierPath()
                mid.move(to: p(9, 2)); mid.line(to: p(9, 12)); mid.line(to: p(12, 15)); mid.line(to: p(15, 12)); mid.line(to: p(15, 2)); mid.close(); mid.fill()
                for x in [5.5, 18.5] as [CGFloat] { line([(x, 19.6), (x, 23)], width: 1.4); line([(x - 1.4, 21.6), (x + 1.4, 21.6)], width: 1.4) }
                NSGraphicsContext.current?.compositingOperation = .clear
                for x in [4.3, 17.3] as [CGFloat] { NSBezierPath(rect: NSRect(x: x * k, y: 8 * k, width: 2.4 * k, height: 4 * k)).fill() }
                let door = NSBezierPath(); door.move(to: p(10.6, 2)); door.line(to: p(10.6, 6.6)); door.appendArc(withCenter: p(12, 6.6), radius: 1.4 * k, startAngle: 180, endAngle: 0, clockwise: true)
                door.line(to: p(13.4, 2)); door.close(); door.fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
            case "custom.monastery":                              // Kloster: long building with arched cloister, small bell turret and cross
                NSBezierPath(rect: NSRect(x: 1.5 * k, y: 2 * k, width: 21 * k, height: 9 * k)).fill()
                let roof = NSBezierPath(); roof.move(to: p(0.8, 11)); roof.line(to: p(12, 15)); roof.line(to: p(23.2, 11)); roof.close(); roof.fill()
                NSBezierPath(rect: NSRect(x: 10.2 * k, y: 14 * k, width: 3.6 * k, height: 4 * k)).fill()
                line([(12, 18), (12, 22.6)], width: 1.6); line([(10.2, 21), (13.8, 21)], width: 1.6)
                NSGraphicsContext.current?.compositingOperation = .clear
                for x in [3.6, 8.2, 12.8, 17.4] as [CGFloat] {                                                 // arched openings
                    let a = NSBezierPath(); a.move(to: p(x, 2)); a.line(to: p(x, 6)); a.appendArc(withCenter: p(x + 1.0, 6), radius: 1.0 * k, startAngle: 180, endAngle: 0, clockwise: true)
                    a.line(to: p(x + 2.0, 2)); a.close(); a.fill()
                }
                NSGraphicsContext.current?.compositingOperation = .sourceOver
            case "custom.summit-cross":                           // Gipfelkreuz: Latin cross on a rocky summit
                line([(12, 22.4), (12, 7)], width: 2.3)
                line([(7.6, 18), (16.4, 18)], width: 2.3)
                let m = NSBezierPath()
                m.move(to: p(1.5, 2)); m.line(to: p(6.5, 6.6)); m.line(to: p(9, 5.4)); m.line(to: p(12, 8)); m.line(to: p(15.2, 5.6))
                m.line(to: p(17.6, 6.8)); m.line(to: p(22.5, 2)); m.close(); m.fill()
            case "custom.mountain-pass":                          // Pass: two peaks with a saddle between and a trail winding up to it
                let m = NSBezierPath()
                m.move(to: p(0.8, 2)); m.line(to: p(6.2, 16.5)); m.line(to: p(8.4, 13)); m.line(to: p(12, 10)); m.line(to: p(15.4, 14.2))
                m.line(to: p(18.2, 20)); m.line(to: p(23.2, 2)); m.close(); m.fill()
                NSGraphicsContext.current?.compositingOperation = .clear
                line([(12, 1.5), (8.8, 4), (14.6, 5.6), (10.8, 7.6), (12, 10.4)], width: 1.5)
                NSGraphicsContext.current?.compositingOperation = .sourceOver
            default: break
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}

/// An icon by its drawing name: an SF Symbol or one of the custom icons.
struct IconImage: View {
    let name: String
    var body: some View {
        if CustomIcons.isCustom(name) { Image(nsImage: CustomIcons.image(name)).renderingMode(.template) }
        else { Image(systemName: name) }
    }
}
