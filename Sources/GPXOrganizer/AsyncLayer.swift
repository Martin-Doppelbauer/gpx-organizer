import Foundation
import CoreGraphics
import BCCore

/// A bitmap layer rendered on a background queue. At most one render runs at a time; requests that arrive meanwhile
/// are coalesced so only the latest one is rendered afterwards. Must be used from the main thread.
final class AsyncLayer {
    private(set) var image: CGImage?
    private(set) var imageState: ViewState?
    private(set) var key = ""
    /// True when the finished bitmap contains nothing but background (e.g. a Garmin map without data at this place or zoom level).
    private(set) var blank = false
    private var gen = 0
    private var busy = false
    private var pending: (ViewState, CGFloat, String)?
    private let queue: DispatchQueue
    private let onDone: () -> Void
    private let work: (ViewState, CGFloat, @escaping () -> Bool) -> CGImage?

    init(label: String, onDone: @escaping () -> Void, work: @escaping (ViewState, CGFloat, @escaping () -> Bool) -> CGImage?) {
        queue = DispatchQueue(label: label, qos: .userInitiated)
        self.onDone = onDone; self.work = work
    }

    func clear() { gen += 1; image = nil; imageState = nil; key = ""; pending = nil; blank = false }

    /// True if the current bitmap shows the same scale and fully covers `state`.
    func covers(_ state: ViewState, key k: String) -> Bool {
        guard let s = imageState, image != nil, k == key, s.worldSize == state.worldSize else { return false }
        let hw = Double(s.width) / 2 / s.worldSize, hh = Double(s.height) / 2 / s.worldSize
        let vw = Double(state.width) / 2 / state.worldSize, vh = Double(state.height) / 2 / state.worldSize
        return abs(state.mx - s.mx) + vw <= hw && abs(state.my - s.my) + vh <= hh
    }

    func request(_ state: ViewState, scale: CGFloat, key k: String) {
        gen += 1
        pending = (state, scale, k)
        if !busy { start() }
    }

    private func start() {
        guard let (st, sc, k) = pending else { return }
        pending = nil; busy = true
        let g = gen
        queue.async { [weak self] in
            guard let self else { return }
            let img = self.work(st, sc, { [weak self] in self?.gen != g })
            DispatchQueue.main.async {
                self.busy = false
                if let img, self.gen == g { self.image = img; self.imageState = st; self.key = k; self.blank = AsyncLayer.isBlank(img); self.onDone() }
                if self.pending != nil { self.start() }
            }
        }
    }

    /// Looks at a small averaged copy of the bitmap: blank if every pixel is (almost) the map background or transparent.
    static func isBlank(_ img: CGImage) -> Bool {
        let w = 48, h = 36
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let bg = MapStyle.background.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components ?? [1, 1, 1, 1]
        let drawn: Bool = buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return false }
        let r = UInt8(max(0, min(255, bg[0] * 255))), g = UInt8(max(0, min(255, bg[1] * 255))), b = UInt8(max(0, min(255, bg[2] * 255)))
        for i in stride(from: 0, to: buf.count, by: 4) {
            if buf[i + 3] < 8 { continue }                               // transparent: nothing drawn
            let a = Int(buf[i + 3])
            let pr = Int(buf[i]) * 255 / max(1, a), pg = Int(buf[i + 1]) * 255 / max(1, a), pb = Int(buf[i + 2]) * 255 / max(1, a)
            if abs(pr - Int(r)) > 2 || abs(pg - Int(g)) > 2 || abs(pb - Int(b)) > 2 { return false }
        }
        return true
    }
}
