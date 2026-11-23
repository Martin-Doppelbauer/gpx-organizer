import SwiftUI
import AppKit
import CoreImage

/// Light / dark appearance of the app (Settings → General), and dark map pictures.
enum Appearance {
    static var mode: Int { UserDefaults.standard.integer(forKey: "appearanceMode") }            // 0 system, 1 light, 2 dark
    static var darkMaps: Bool { UserDefaults.standard.object(forKey: "darkMaps") as? Bool ?? true }

    @MainActor static func apply() {
        NSApplication.shared.appearance = mode == 1 ? NSAppearance(named: .aqua) : mode == 2 ? NSAppearance(named: .darkAqua) : nil
    }
}

/// Dark versions of map pictures: the brightness is turned over and every color keeps its hue (water stays blue, forest green). Tiles are converted once and kept.
enum DarkMap {
    static let background = CGColor(red: 0.13, green: 0.14, blue: 0.15, alpha: 1)
    private static let ci = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: NSNull()])      // no color management: the sums below work on the pixel values as they are
    private final class Box { let image: CGImage; init(_ i: CGImage) { image = i } }
    private static let cache: NSCache<NSString, Box> = { let c = NSCache<NSString, Box>(); c.totalCostLimit = 200 * 1024 * 1024; return c }()
    private static let lock = NSLock()

    static func convert(_ img: CGImage) -> CGImage {
        let input = CIImage(cgImage: img, options: [.colorSpace: NSNull()])
        guard let m = CIFilter(name: "CIColorMatrix"), let tone = CIFilter(name: "CIColorControls") else { return img }
        // Brightness is turned over (light becomes dark) while every color keeps its hue: out = in + (1 − 2·luma),
        // then compressed into a dark range with a warm base, so that paper white becomes a medium-dark brown, not black.
        let k = 0.75
        func v(_ r: Double, _ g: Double, _ b: Double) -> CIVector { CIVector(x: k * r, y: k * g, z: k * b, w: 0) }
        m.setValue(input, forKey: kCIInputImageKey)
        m.setValue(v(0.402, -1.174, -0.228), forKey: "inputRVector")
        m.setValue(v(-0.598, -0.174, -0.228), forKey: "inputGVector")
        m.setValue(v(-0.598, -1.174, 0.772), forKey: "inputBVector")
        m.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        m.setValue(CIVector(x: k + 0.28, y: k + 0.25, z: k + 0.22, w: 0), forKey: "inputBiasVector")
        tone.setValue(m.outputImage, forKey: kCIInputImageKey)
        tone.setValue(0.92, forKey: kCIInputSaturationKey)
        guard let out = tone.outputImage, let r = ci.createCGImage(out, from: input.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return img }
        return r
    }

    /// Tile picture, converted once per tile.
    static func tile(_ img: CGImage, key: String) -> CGImage {
        lock.lock(); let hit = cache.object(forKey: key as NSString); lock.unlock()
        if let hit { return hit.image }
        let d = convert(img)
        lock.lock(); cache.setObject(Box(d), forKey: key as NSString, cost: d.width * d.height * 4); lock.unlock()
        return d
    }
}
