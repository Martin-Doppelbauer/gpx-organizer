import SwiftUI
import AppKit
import BCCore

/// Distance measuring on the map: click points, the total is shown at the last point.
final class MeasureSession: ObservableObject {
    @Published private(set) var points: [(lat: Double, lon: Double)] = []

    func add(lat: Double, lon: Double) { points.append((lat, lon)); objectWillChange.send() }
    func removeLast() { if !points.isEmpty { points.removeLast() } }
    func clear() { points = [] }

    /// Length of the line in metres up to point `i`.
    func distance(upTo i: Int) -> Double {
        guard i > 0, i < points.count else { return 0 }
        var d = 0.0
        for k in 1...i { d += haversineMeters(GPXPoint(lat: points[k - 1].lat, lon: points[k - 1].lon), GPXPoint(lat: points[k].lat, lon: points[k].lon)) }
        return d
    }

    static func text(_ m: Double) -> String { m < 1000 ? String(format: "%.0f m", m) : String(format: "%.2f km", m / 1000) }
}

extension AppModel {
    func toggleMeasure() {
        if measure != nil { measure = nil; return }
        guard edit == nil, plan == nil, wptEdit == nil else { return }
        measure = MeasureSession()
    }

    /// Cuts the track being edited in two new files next to the original; the original stays unchanged.
    func splitTrack() {
        guard let e = edit else { return }
        guard let (a, b) = e.splitParts() else {
            let n = NSAlert(); n.messageText = L("Select the point where the track should be split.")
            n.informativeText = L("Click a point inside the track (not the first or last one)."); n.runModal(); return
        }
        let base = e.url.deletingPathExtension().lastPathComponent
        let dir = e.url.deletingLastPathComponent()
        let q = NSAlert()
        q.messageText = L("Split “%@” at the selected point?", "\(base)")
        q.informativeText = L("Two new files “%@ (1).gpx” and “%@ (2).gpx” are created in the same folder. The original file stays unchanged.", "\(base)", "\(base)")
        q.addButton(withTitle: L("Split")); q.addButton(withTitle: L("Cancel"))
        guard q.runModal() == .alertFirstButtonReturn else { return }
        func free(_ name: String) -> URL {
            var u = dir.appendingPathComponent(name + ".gpx"); var k = 2
            while FileManager.default.fileExists(atPath: u.path) { u = dir.appendingPathComponent("\(name) \(k).gpx"); k += 1 }
            return u
        }
        do {
            try a.xml().write(to: free("\(base) (1)"), atomically: true, encoding: .utf8)
            try b.xml().write(to: free("\(base) (2)"), atomically: true, encoding: .utf8)
        } catch {
            let f = NSAlert(); f.messageText = L("Splitting failed"); f.informativeText = error.localizedDescription; f.runModal(); return
        }
        reloadTree()
    }
}

/// Menu with the editing tools of the track (crop, split, smooth).
struct TrackToolsMenu: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var edit: EditSession
    var body: some View {
        Menu {
            Button("Crop to Selected Range") { edit.cropToSelection(); model.updateProfileIfEditing() }
                .disabled(!edit.canCrop)
            Button("Split at Selected Point …") { model.splitTrack() }
                .disabled(edit.selection.isEmpty)
            Divider()
            Menu("Smooth (selected range or whole track)") {
                Button("Light") { edit.smooth(window: 3); model.updateProfileIfEditing() }
                Button("Medium") { edit.smooth(window: 7); model.updateProfileIfEditing() }
                Button("Strong") { edit.smooth(window: 15); model.updateProfileIfEditing() }
            }
        } label: { ToolIcon(systemImage: "scissors") }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .onHover { ToolHint.shared.text = $0 ? L("Track tools: crop, split, smooth (select points on the map or in the elevation profile first)") : nil }
    }
}
