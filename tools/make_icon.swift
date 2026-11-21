// Generates AppIcon.icns: swift tools/make_icon.swift <output-dir>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func render(_ px: Int) -> CGImage {
    let S = 1024.0
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(px) / S, y: CGFloat(px) / S)
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // soft shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(shape); ctx.setFillColor(CGColor(gray: 0.2, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()

    // background gradient
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let grad = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.20, green: 0.62, blue: 0.48, alpha: 1),
                                                    CGColor(red: 0.05, green: 0.30, blue: 0.38, alpha: 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 300, y: 924), end: CGPoint(x: 700, y: 100), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // contour lines around a "summit"
    let cx = 430.0, cy = 600.0
    for i in 0..<9 {
        let R = 50.0 + Double(i) * 48
        let path = CGMutablePath()
        let steps = 120
        for k in 0...steps {
            let th = Double(k) / Double(steps) * 2 * .pi
            let r = R * (1 + 0.13 * sin(3 * th + 0.8) + 0.07 * sin(5 * th + 0.3) + 0.04 * sin(2 * th))
            let p = CGPoint(x: cx + r * cos(th) * 1.15, y: cy + r * sin(th))
            if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: i % 4 == 0 ? 0.45 : 0.22))
        ctx.setLineWidth(i % 4 == 0 ? 7 : 4)
        ctx.strokePath()
    }

    // track
    let track = CGMutablePath()
    track.move(to: CGPoint(x: 215, y: 250))
    track.addCurve(to: CGPoint(x: 470, y: 380), control1: CGPoint(x: 300, y: 210), control2: CGPoint(x: 330, y: 400))
    track.addCurve(to: CGPoint(x: 640, y: 560), control1: CGPoint(x: 590, y: 360), control2: CGPoint(x: 520, y: 520))
    track.addCurve(to: CGPoint(x: 800, y: 790), control1: CGPoint(x: 740, y: 600), control2: CGPoint(x: 700, y: 760))
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.addPath(track); ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95)); ctx.setLineWidth(46); ctx.strokePath()
    ctx.addPath(track); ctx.setStrokeColor(CGColor(red: 1.0, green: 0.45, blue: 0.1, alpha: 1)); ctx.setLineWidth(28); ctx.strokePath()

    func dot(_ p: CGPoint, _ c: CGColor) {
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fillEllipse(in: CGRect(x: p.x - 38, y: p.y - 38, width: 76, height: 76))
        ctx.setFillColor(c); ctx.fillEllipse(in: CGRect(x: p.x - 26, y: p.y - 26, width: 52, height: 52))
    }
    dot(CGPoint(x: 215, y: 250), CGColor(red: 0.15, green: 0.75, blue: 0.3, alpha: 1))
    dot(CGPoint(x: 800, y: 790), CGColor(red: 0.9, green: 0.15, blue: 0.15, alpha: 1))
    ctx.restoreGState()

    // subtle rim
    ctx.addPath(shape); ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.25)); ctx.setLineWidth(3); ctx.strokePath()
    return ctx.makeImage()!
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let set = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                              ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
                              ("icon_512x512", 512), ("icon_512x512@2x", 1024)]
for (name, px) in sizes {
    let img = render(px)
    let dst = CGImageDestinationCreateWithURL(set.appendingPathComponent(name + ".png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, img, nil)
    CGImageDestinationFinalize(dst)
}
print("iconset written to \(set.path)")
