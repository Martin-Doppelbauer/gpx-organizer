import SwiftUI
import AppKit
import BCCore

/// "Replace Elevation Data": the heights of tracks are replaced by values from a terrain model.
final class ElevationFixDraft: ObservableObject, Identifiable {
    struct Item: Identifiable {
        enum State { case waiting, working(Double), done, failed(String), skipped(String) }
        let id: String
        var name: String { URL(fileURLWithPath: id).deletingPathExtension().lastPathComponent }
        var state: State = .waiting
        var before: (up: Double, down: Double)?
        var after: (up: Double, down: Double)?
    }
    let id = UUID()
    @Published var items: [Item]
    @Published var running = false
    @Published var finished = false
    var cancelled = false
    init(ids: [String]) { items = ids.map { Item(id: $0) } }
}

extension AppModel {
    func startElevationFix(_ ids: [String]) {
        let gpx = ids.filter { $0.lowercased().hasSuffix(".gpx") }
        guard !gpx.isEmpty else {
            let a = NSAlert(); a.messageText = "Only GPX files can get new elevation data."; a.runModal(); return
        }
        elevationFix = ElevationFixDraft(ids: gpx)
    }

    /// Runs through the files one after the other.
    func runElevationFix(_ d: ElevationFixDraft) {
        guard !d.running else { return }
        d.running = true; d.cancelled = false
        Task.detached(priority: .userInitiated) { [weak self] in
            var changed = false
            for idx in d.items.indices {
                if d.cancelled { break }
                let path = await MainActor.run { d.items[idx].id }
                func set(_ s: ElevationFixDraft.Item.State, before: (Double, Double)? = nil, after: (Double, Double)? = nil) async {
                    await MainActor.run {
                        d.items[idx].state = s
                        if let b = before { d.items[idx].before = b }
                        if let a = after { d.items[idx].after = a }
                    }
                }
                let url = URL(fileURLWithPath: path)
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { await set(.failed("The file cannot be read")); continue }
                let pts = TrackPointText.points(in: text)
                guard pts.count >= 2 else { await set(.skipped("No track points")); continue }
                var known: [Double] = []
                var last: Double?
                for p in pts { if let e = p.ele { last = e }; if let l = last { known.append(l) } }
                let b = TrackPointText.climb(known)
                await set(.working(0), before: (b.up, b.down))
                let coords = pts.map { (lat: $0.lat, lon: $0.lon) }
                let heights = await ElevationService.elevations(for: coords, spacing: 90, maxSamples: 4000, progress: { done, total in
                    Task { await set(.working(Double(done) / Double(max(1, total)))) }
                }, cancelled: { d.cancelled })
                guard let heights else { await set(d.cancelled ? .skipped("Cancelled") : .failed("The elevation service could not be reached")); continue }
                let values = heights.map { $0 ?? 0 }
                let a = TrackPointText.climb(values)
                let patched = TrackPointText.setHeights(values, of: pts, in: text)
                guard WptText.wellFormed(patched) else { await set(.failed("The result would not be valid XML; the file was left unchanged")); continue }
                let ok: Bool = await MainActor.run { self?.trashCopyOfOriginal(url) ?? false }
                guard ok else { await set(.failed("The original could not be moved to the Trash; the file was left unchanged")); continue }
                do { try patched.write(to: url, atomically: true, encoding: .utf8) } catch { await set(.failed(error.localizedDescription)); continue }
                changed = true
                await set(.done, before: (b.up, b.down), after: (a.up, a.down))
            }
            await MainActor.run {
                d.running = false; d.finished = true
                if changed, let self {
                    for it in d.items { self.cache.removeValue(forKey: it.id); self.failed.remove(it.id) }
                    self.reloadTree()
                    if self.showProfile { self.updateProfile() }
                }
            }
        }
    }
}

struct ElevationFixSheet: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var d: ElevationFixDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Replace Elevation Data").font(.headline)
            Text("The heights of the track points are replaced by values from a terrain model (about 90 m resolution) and ascent and descent are calculated again. The coordinates of the track points are sent to open-meteo.com. Before a file is changed, its original goes to the Trash.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List(d.items) { it in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(it.name).lineLimit(1)
                        Spacer()
                        status(it)
                    }
                    if case .working(let f) = it.state { ProgressView(value: f) }
                    if case .done = it.state, let b = it.before, let a = it.after {
                        Text(String(format: "Ascent %.0f → %.0f m, descent %.0f → %.0f m", b.up, a.up, b.down, a.down))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 220)
            HStack {
                if d.running { Button("Stop") { d.cancelled = true } }
                Spacer()
                Button(d.finished ? "Done" : "Cancel") { model.elevationFix = nil; dismiss() }.keyboardShortcut(.cancelAction).disabled(d.running)
                if !d.finished {
                    Button("Replace Elevations") { model.runElevationFix(d) }.keyboardShortcut(.defaultAction).disabled(d.running)
                }
            }
        }
        .padding(16)
        .frame(width: 520)
    }

    @ViewBuilder private func status(_ it: ElevationFixDraft.Item) -> some View {
        switch it.state {
        case .waiting: Text("waiting").foregroundStyle(.secondary).font(.caption)
        case .working: Text("working …").foregroundStyle(.secondary).font(.caption)
        case .done: Label("done", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
        case .failed(let m): Text(m).foregroundStyle(.red).font(.caption).lineLimit(2)
        case .skipped(let m): Text(m).foregroundStyle(.orange).font(.caption)
        }
    }
}
