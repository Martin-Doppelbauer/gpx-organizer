import SwiftUI
import AppKit
import BCCore

/// Downloads the tiles of an area for offline use (throttled, with a hard cap).
@MainActor
final class PrefetchJob: ObservableObject {
    @Published var total = 0
    @Published var done = 0
    @Published var failed = 0
    @Published var running = false
    @Published var message = ""
    @Published var maxZoomText = ""
    @Published var useTracks = false
    private var cancelled = false

    static let maxTiles = 8000

    struct Area { var x0: Double, y0: Double, x1: Double, y1: Double }   // Web-Mercator 0…1

    static func tileCount(_ a: Area, zMin: Int, zMax: Int) -> Int {
        guard zMax >= zMin else { return 0 }
        var n = 0
        for z in zMin...zMax {
            let c = Double(1 << z)
            let xs = Int(floor(a.x1 * c)) - Int(floor(a.x0 * c)) + 1
            let ys = Int(floor(a.y1 * c)) - Int(floor(a.y0 * c)) + 1
            n += max(0, xs) * max(0, ys)
        }
        return n
    }

    static func tiles(_ a: Area, zMin: Int, zMax: Int) -> [(Int, Int, Int)] {
        var out: [(Int, Int, Int)] = []
        for z in zMin...zMax {
            let c = Double(1 << z), lim = (1 << z) - 1
            for x in max(0, Int(floor(a.x0 * c)))...min(lim, Int(floor(a.x1 * c))) {
                for y in max(0, Int(floor(a.y0 * c)))...min(lim, Int(floor(a.y1 * c))) { out.append((z, x, y)) }
            }
        }
        return out
    }

    func cancel() { cancelled = true }

    func start(source: TileSource, area: Area, zMin: Int, zMax: Int) {
        guard !running else { return }
        let list = Self.tiles(area, zMin: zMin, zMax: zMax)
        guard list.count <= Self.maxTiles else { message = "Too many tiles (\(list.count)). Choose a lower detail level or a smaller area."; return }
        total = list.count; done = 0; failed = 0; running = true; cancelled = false; message = ""
        Task {
            var consecutiveBad = 0
            var i = 0
            let batch = 24
            while i < list.count, !cancelled {
                let chunk = Array(list[i..<min(i + batch, list.count)])
                i += batch
                let results: [(Bool, Int)] = await withCheckedContinuation { cont in
                    let g = DispatchGroup()
                    let lock = NSLock()
                    var res: [(Bool, Int)] = []
                    for t in chunk {
                        g.enter()
                        TileCache.shared.prefetch(source, t.0, t.1, t.2) { ok, code in
                            lock.lock(); res.append((ok, code)); lock.unlock(); g.leave()
                        }
                    }
                    g.notify(queue: .main) { cont.resume(returning: res) }
                }
                for (ok, code) in results {
                    if ok { done += 1; consecutiveBad = 0 } else {
                        failed += 1; consecutiveBad += 1
                        if code == 429 || code == 403 { cancelled = true; message = "The map server rejected the requests (status \(code)). Cancelled – please try again later or with a smaller area." }
                    }
                }
                if consecutiveBad > 40 { cancelled = true; if message.isEmpty { message = "Too many errors (no connection?). Cancelled." } }
            }
            running = false
            if message.isEmpty { message = cancelled ? "Abgebrochen." : "Fertig: \(done) Kacheln gespeichert\(failed > 0 ? ", \(failed) fehlgeschlagen" : "")." }
        }
    }
}

struct PrefetchSheet: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var job = PrefetchJob()
    @Environment(\.dismiss) private var dismiss

    private var source: TileSource? { model.selectedTileSource }

    private func area() -> PrefetchJob.Area {
        if job.useTracks, !model.tracks.isEmpty {
            let f = model.tracks.filter { $0.minX.isFinite }
            if !f.isEmpty {
                let pad = 1000.0 / 40_075_016.0 / max(0.2, cos(Merc.lat(y: f[0].minY) * .pi / 180))
                return .init(x0: f.map(\.minX).min()! - pad, y0: f.map(\.minY).min()! - pad, x1: f.map(\.maxX).max()! + pad, y1: f.map(\.maxY).max()! + pad)
            }
        }
        let v = model.view
        let (ax, ay) = v.world(.zero), (bx, by) = v.world(CGPoint(x: v.width, y: v.height))
        let px = (bx - ax) * 0.1, py = (by - ay) * 0.1
        return .init(x0: ax - px, y0: ay - py, x1: bx + px, y1: by + py)
    }

    var body: some View {
        let src = source
        let maxZ = Int(job.maxZoomText) ?? min(src?.maxZoom ?? 15, 15)
        let zMin = 8
        let a = area()
        let count = PrefetchJob.tileCount(a, zMin: zMin, zMax: maxZ)
        VStack(alignment: .leading, spacing: 10) {
            Text("Download Area for Offline Use").font(.title3).bold()
            if let src {
                Text("Map: \(src.name)").foregroundStyle(.secondary)
                Picker("Gebiet", selection: $job.useTracks) {
                    Text("Aktuelle Kartenansicht").tag(false)
                    Text("Displayed tracks (+1 km margin)").tag(true)
                }
                .pickerStyle(.radioGroup)
                Stepper("Maximum detail level: \(maxZ)", onIncrement: { job.maxZoomText = String(min(src.maxZoom, maxZ + 1)) },
                        onDecrement: { job.maxZoomText = String(max(9, maxZ - 1)) })
                Text("Level 12 ≈ overview, 14 ≈ hiking map, 16 ≈ very detailed.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("\(count) Kacheln, etwa \(String(format: "%.0f", Double(count) * 30 / 1024)) MB")
                        .foregroundStyle(count > PrefetchJob.maxTiles ? Color.red : Color.primary)
                    if count > PrefetchJob.maxTiles { Text("(max. \(PrefetchJob.maxTiles) je Vorgang)").font(.caption).foregroundStyle(.red) }
                }
                if job.running || job.total > 0 {
                    ProgressView(value: Double(job.done + job.failed), total: Double(max(1, job.total)))
                    Text("\(job.done) of \(job.total) downloaded" + (job.failed > 0 ? ", \(job.failed) errors" : "")).font(.caption).monospacedDigit()
                }
                if !job.message.isEmpty { Text(job.message).font(.caption).foregroundStyle(.orange) }
                Text("Please use only for personal needs and small areas: the providers (OpenStreetMap, OpenTopoMap) do not allow bulk downloads. Tiles are downloaded at a throttled rate.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Choose an online map at the top first.").foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                if job.running { Button("Cancel") { job.cancel() } }
                else {
                    Button("Close") { dismiss() }
                    if let src {
                        Button("Laden") { job.start(source: src, area: a, zMin: zMin, zMax: maxZ) }
                            .keyboardShortcut(.defaultAction).disabled(count == 0 || count > PrefetchJob.maxTiles)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 460)
    }
}
