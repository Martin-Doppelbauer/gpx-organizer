import SwiftUI
import AppKit
import BCCore

/// Editing state for a file that only contains waypoints: move (drag on the map), rename, change the symbol, add and delete.
@MainActor
final class WaypointEditSession: ObservableObject {
    let url: URL
    @Published private(set) var doc: GPXDocument
    @Published var selected: Int? = 0
    @Published private(set) var dirty = false
    @Published var addMode = false
    @Published var renameFile = false
    var onChange: (() -> Void)?
    private var undoStack: [GPXDocument] = []

    init(url: URL, doc: GPXDocument) {
        self.url = url; self.doc = doc
        selected = doc.waypoints.isEmpty ? nil : 0
    }

    var waypoints: [GPXWaypoint] { doc.waypoints }
    var canUndo: Bool { !undoStack.isEmpty }

    func pushUndo() { undoStack.append(doc); dirty = true; if undoStack.count > 100 { undoStack.removeFirst() } }
    func undo() {
        guard let d = undoStack.popLast() else { return }
        doc = d; dirty = true
        if let s = selected, s >= doc.waypoints.count { selected = doc.waypoints.indices.last }
        onChange?()
    }

    func move(_ i: Int, mx: Double, my: Double) {
        guard doc.waypoints.indices.contains(i) else { return }
        doc.waypoints[i].point.lat = Merc.lat(y: my); doc.waypoints[i].point.lon = Merc.lon(x: mx)
        onChange?()
    }

    func setName(_ i: Int, _ v: String) { edit(i) { $0.name = v } }
    func setDesc(_ i: Int, _ v: String) { edit(i) { $0.desc = v } }
    func setSym(_ i: Int, _ v: String) { edit(i) { $0.sym = v } }
    private func edit(_ i: Int, _ f: (inout GPXWaypoint) -> Void) {
        guard doc.waypoints.indices.contains(i) else { return }
        pushUndo(); f(&doc.waypoints[i]); onChange?()
    }

    func add(mx: Double, my: Double) {
        pushUndo()
        doc.waypoints.append(GPXWaypoint(point: GPXPoint(lat: Merc.lat(y: my), lon: Merc.lon(x: mx)), name: L("New waypoint"), sym: "Waypoint"))
        selected = doc.waypoints.count - 1
        addMode = false
        onChange?()
    }

    func deleteSelected() {
        guard let i = selected, doc.waypoints.indices.contains(i) else { return }
        pushUndo(); doc.waypoints.remove(at: i)
        selected = doc.waypoints.isEmpty ? nil : min(i, doc.waypoints.count - 1)
        onChange?()
    }

    func markSaved() { dirty = false; undoStack = [] }
}

/// Garmin symbols offered in the editor.
enum GarminSymbols {
    static let all = ["Waypoint", "Flag, Blue", "Flag, Red", "Flag, Green", "Pin, Blue", "Pin, Red", "Pin, Green",
                      "Circle, Blue", "Circle, Red", "Circle, Green", "Triangle, Blue", "Triangle, Red", "Triangle, Green",
                      "Navaid, Green", "Summit", "Trail Head", "Parking Area", "City (Small)", "City (Medium)", "City (Large)",
                      "Lodge", "Residence", "Campground", "Restaurant", "Shower", "Boat Ramp", "Park", "Scenic Area", "Bank"]
}

extension AppModel {
    /// Opens the waypoint editor for a waypoint-only file.
    func startWaypointEdit(_ id: String) {
        guard wptEdit == nil || wptEdit?.url.path == id else { return }
        guard let doc = GPXDocument.parse(URL(fileURLWithPath: id)), doc.tracks.isEmpty else { return }
        let s = WaypointEditSession(url: URL(fileURLWithPath: id), doc: doc)
        s.onChange = { [weak self] in self?.viewRevision += 1 }
        wptEdit = s
        showProfile = false; showPoints = false
        viewRevision += 1
    }

    /// Asks about unsaved changes. Returns false if the user cancelled.
    func confirmLeaveWaypointEdit() -> Bool {
        guard let e = wptEdit else { return true }
        if !e.dirty { wptEdit = nil; viewRevision += 1; return true }
        let a = NSAlert()
        a.messageText = L("Save changes to “%@”?", "\(e.url.lastPathComponent)")
        a.informativeText = L("The waypoints have been edited and not saved yet.")
        a.addButton(withTitle: L("Save")); a.addButton(withTitle: L("Discard")); a.addButton(withTitle: L("Cancel"))
        switch a.runModal() {
        case .alertFirstButtonReturn: return saveWaypointEdit()
        case .alertSecondButtonReturn: wptEdit = nil; viewRevision += 1; return true
        default: return false
        }
    }

    func exitWaypointEdit() { _ = confirmLeaveWaypointEdit() }

    /// Writes the waypoints back (a copy of the original goes to the Trash).
    @discardableResult
    func saveWaypointEdit() -> Bool {
        guard let e = wptEdit else { return true }
        guard trashCopyOfOriginal(e.url) else {
            let f = NSAlert(); f.messageText = L("The original could not be moved to the Trash – not saved."); f.runModal(); return false
        }
        var dst = e.url
        do {
            try e.doc.xml().write(to: dst, atomically: true, encoding: .utf8)
            if e.renameFile, let name = e.waypoints.first?.name.trimmingCharacters(in: .whitespaces), !name.isEmpty,
               e.waypoints.count == 1 {
                let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
                let target = e.url.deletingLastPathComponent().appendingPathComponent(safe + ".gpx")
                if target.path != e.url.path, !FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.moveItem(at: e.url, to: target); dst = target
                }
            }
        } catch {
            let a = NSAlert(); a.messageText = L("Saving failed"); a.informativeText = error.localizedDescription; a.runModal(); return false
        }
        cache.removeValue(forKey: e.url.path); failed.remove(e.url.path)
        // the list shows the symbol and color of the (possibly changed) first waypoint, also for a renamed file
        for key in [e.url.path, dst.path] {
            if let w = e.waypoints.first {
                waypointColors[key] = w.rgb; waypointRank[key] = Waypoint.colorRank(forSymbol: w.sym); waypointIcons[key] = w.iconName
            }
        }
        if dst.path != e.url.path { waypointColors[e.url.path] = nil; waypointRank[e.url.path] = nil; waypointIcons[e.url.path] = nil }
        e.markSaved()
        wptEdit = nil
        pendingSelect = dst.path
        reloadTree()
        return true
    }
}

struct WaypointPanel: View {
    @ObservedObject var session: WaypointEditSession
    @EnvironmentObject var model: AppModel

    private func binding<T>(_ i: Int, _ get: @escaping (GPXWaypoint) -> T, _ set: @escaping (Int, T) -> Void) -> Binding<T> {
        Binding(get: { session.waypoints.indices.contains(i) ? get(session.waypoints[i]) : get(GPXWaypoint(point: GPXPoint(lat: 0, lon: 0), name: "")) },
                set: { set(i, $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Waypoints").font(.headline)
                Text("\(session.waypoints.count)").foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button { model.exitWaypointEdit() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).help("Close the waypoint editor (Esc)")
            }
            if session.waypoints.count > 1 {
                List(selection: $session.selected) {
                    ForEach(Array(session.waypoints.enumerated()), id: \.offset) { i, w in
                        HStack {
                            Image(systemName: w.iconName).foregroundStyle(Color(red: w.rgb[0], green: w.rgb[1], blue: w.rgb[2]))
                            Text(w.name.isEmpty ? L("(no name)") : w.name).lineLimit(1)
                        }.tag(i)
                    }
                }
                .frame(minHeight: 90, maxHeight: 160)
            }
            if let i = session.selected, session.waypoints.indices.contains(i) {
                let w = session.waypoints[i]
                Form {
                    TextField("Name", text: binding(i, { $0.name }, { session.setName($0, $1) }))
                    TextField("Description", text: binding(i, { $0.desc }, { session.setDesc($0, $1) }))
                    Picker("Symbol", selection: binding(i, { $0.sym.isEmpty ? "Waypoint" : $0.sym }, { session.setSym($0, $1) })) {
                        ForEach(GarminSymbols.all, id: \.self) { s in
                            Label {
                                Text(s)
                            } icon: {
                                Image(systemName: Waypoint.iconName(forSymbol: s))
                                    .foregroundStyle(Color(red: Waypoint.rgb(forSymbol: s)[0], green: Waypoint.rgb(forSymbol: s)[1], blue: Waypoint.rgb(forSymbol: s)[2]))
                            }.tag(s)
                        }
                    }
                    LabeledContent("Position") {
                        Text(String(format: "%.5f, %.5f", w.point.lat, w.point.lon)).monospacedDigit().textSelection(.enabled)
                    }
                    if let e = w.point.ele { LabeledContent("Elevation") { Text(String(format: "%.0f m", e)).monospacedDigit() } }
                }
                .formStyle(.columns)
                Text("Drag the marker on the map to move the waypoint.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No waypoint selected.").foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Toggle(isOn: $session.addMode) { Label("Add", systemImage: "plus.circle") }
                    .toggleStyle(.button).help("Click the map to add a waypoint")
                Button { session.deleteSelected() } label: { Label("Delete", systemImage: "minus.circle") }
                    .disabled(session.selected == nil)
                Button { session.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .disabled(!session.canUndo)
            }
            .controlSize(.small)
            if session.waypoints.count == 1 {
                Toggle("Rename the file to the waypoint name", isOn: $session.renameFile).font(.caption)
            }
            HStack {
                Spacer()
                Button("Close") { model.exitWaypointEdit() }
                Button("Save") { model.saveWaypointEdit() }.keyboardShortcut(.defaultAction).disabled(!session.dirty)
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.background)
    }
}
