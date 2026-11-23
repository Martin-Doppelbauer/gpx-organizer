import SwiftUI
import Charts
import UniformTypeIdentifiers
import BCCore

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView(tree: model.tree, displayedFolder: model.displayedFolder, foreground: model.foregroundPath,
                        dropTarget: model.dropTarget, renamingID: model.renamingID, fileRevision: model.fileRevision,
                        sort: model.fileSort, files: model.fileRows, model: model)
                .equatable()
                .navigationSplitViewColumnWidth(min: 240, ideal: 320, max: 560)
        } detail: {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        MapContainer()
                        InfoOverlay().padding(10)
                    }
                    .overlay(alignment: .top) { ToolHintOverlay() }
                    .overlay(alignment: .bottom) { NoticeOverlay() }
                    .overlay(alignment: .topTrailing) { PhotoStatusOverlay() }
                    .overlay(alignment: .bottomTrailing) {
                        VStack(alignment: .trailing, spacing: 6) {
                            VStack(spacing: 0) {
                                Button { model.zoomStep(2) } label: { Image(systemName: "plus").font(.system(size: 15, weight: .semibold)).frame(width: 30, height: 28).contentShape(Rectangle()) }
                                    .help("Zoom in (⌘+)")
                                Divider().frame(width: 30)
                                Button { model.zoomStep(0.5) } label: { Image(systemName: "minus").font(.system(size: 15, weight: .semibold)).frame(width: 30, height: 28).contentShape(Rectangle()) }
                                    .help("Zoom out (⌘−)")
                            }
                            .buttonStyle(.plain)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.35), lineWidth: 0.5))
                            if let s = model.selectedTileSource, !(model.aerialOn && model.aerialOpacity >= 0.99) {
                                Text(s.attribution).font(.caption2).padding(4)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                            }
                            if let im = model.activeImagery {
                                Text("Imagery: " + im.attribution).font(.caption2).padding(4)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .padding(8)
                    }
                    if let pl = model.plan {
                        Divider()
                        PlanPanel(plan: pl).frame(width: 300)
                    } else if let w = model.wptEdit {
                        Divider()
                        WaypointPanel(session: w).frame(width: 300)
                    } else if model.showPoints, let e = model.edit {
                        Divider()
                        PointsPanel(edit: e).frame(width: 300)
                    }
                }
                if let strip = model.photoStrip { Divider(); PhotoStripView(items: strip).frame(height: 190) }
                else if model.showProfile { Divider(); ProfileHost().frame(height: 210) }
            }
        }
        .toolbar { MainToolbar(model: model) }
        .onExitCommand { model.escape() }
        .modifier(KomootHook())
        .modifier(PhotoHook())
        .modifier(GarminHook())
        .modifier(ToolbarTweak())
        .background(WindowGrabber(model: model))
        .sheet(isPresented: $model.showPrefetch) { PrefetchSheet().environmentObject(model) }
        .sheet(isPresented: $model.iconPickerOpen) { IconPickerSheet().environmentObject(model) }
        .sheet(item: $model.markerDraft) { MarkerSheet(d: $0).environmentObject(model) }
        .sheet(item: $model.saveRouteDraft) { SaveRouteSheet(d: $0).environmentObject(model) }
        .sheet(item: $model.stagesDraft) { StagesSheet(d: $0).environmentObject(model) }
        .sheet(item: $model.elevationFix) { ElevationFixSheet(d: $0).environmentObject(model) }
        .onReceive(model.menuEvents(.fitAll)) { _ in model.fitAll() }
        .onReceive(model.menuEvents(.fitSelected)) { _ in model.fitForeground() }
        .onReceive(model.menuEvents(.reloadTree)) { _ in model.reloadTree() }
        .onReceive(NotificationCenter.default.publisher(for: .kindThresholdsChanged)) { _ in model.reclassify() }
        .onReceive(model.menuEvents(.printMap)) { _ in model.printMap() }
        .onReceive(model.menuEvents(.zoomIn)) { _ in model.zoomStep(2) }
        .modifier(AerialHook(model: model))
        .onReceive(model.menuEvents(.zoomOut)) { _ in model.zoomStep(0.5) }
        .onReceive(NotificationCenter.default.publisher(for: .markerSizeChanged)) { _ in model.viewRevision += 1 }
        .onReceive(NotificationCenter.default.publisher(for: .mapsFolderChanged)) { _ in model.mapsFolderChanged() }
        .onReceive(model.menuEvents(.editUndo)) { _ in model.edit?.undo(); model.updateProfileIfEditing() }
        .onReceive(model.menuEvents(.editRedo)) { _ in model.edit?.redo(); model.updateProfileIfEditing() }
    }
}

/// The Map menu item "Aerial Imagery On/Off" (kept apart so the big view body stays quick to compile).
struct AerialHook: ViewModifier {
    let model: AppModel
    func body(content: Content) -> some View {
        content.onReceive(model.menuEvents(.toggleAerial)) { _ in model.aerialOn.toggle() }
    }
}

final class FlagState: ObservableObject { @Published var on = false }

struct AerialPanel: View {
    @EnvironmentObject var model: AppModel
    private var percentText: String { let p = Int((model.aerialOpacity * 100).rounded()); return "\(p) %" }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Show aerial imagery", isOn: $model.aerialOn).toggleStyle(.switch)
            Picker("Source", selection: Binding(get: { model.aerialSource?.id ?? "" }, set: { model.aerialID = $0 })) {
                ForEach(model.imagerySources) { Text($0.name).tag($0.id) }
            }
            .disabled(model.imagerySources.isEmpty)
            HStack {
                Text("Opacity")
                Slider(value: $model.aerialOpacity, in: 0.1...1)
                Text(percentText).monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            Text("At 100 % the images replace the map. Lower values show the map through the images, so roads and names stay visible.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let s = model.aerialSource { Text(s.attribution).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            Text("The list of sources is in Settings → Aerial.").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 320)
    }
}

// MARK: toolbar: four groups like the Finder (map view, track, editing, route)

/// One toolbar icon: flat, with a soft highlight while it is switched on.
/// Icon of a toolbar button, with a small text below it when "Show Toolbar Labels" is on.
struct ToolIcon: View {
    let systemImage: String
    var label: String? = nil
    @AppStorage("toolbarLabels") private var labels = false
    private static let names: [String: String] = [
        "arrow.up.left.and.arrow.down.right": "All", "scope": "Track", "ruler": "Measure", "chart.xyaxis.line": "Profile",
        "arrow.triangle.turn.up.right.diamond": "Route", "photo": "Aerial", "photo.fill": "Aerial", "pencil.and.scribble": "Edit",
        "arrow.uturn.backward": "Undo", "arrow.uturn.forward": "Redo", "plus.circle": "Add", "minus.circle": "Delete",
        "arrow.left.arrow.right": "Reverse", "square.and.arrow.down": "Save", "square.and.arrow.down.on.square": "Save As",
        "checkmark.circle": "Done", "photo.stack": "Photos", "photo.stack.fill": "Photos", "square.and.arrow.up": "Export",
        "plus.rectangle.on.folder": "Maps", "cable.connector": "Garmin", "scissors": "Tools", "paintpalette": "Color"]
    var body: some View {
        let text = label ?? Self.names[systemImage] ?? ""
        VStack(spacing: 1) {
            Image(systemName: systemImage).imageScale(.large).frame(height: 24)
            if labels, !text.isEmpty { Text(text).font(.system(size: 9)).lineLimit(1).fixedSize() }
        }
        .frame(minWidth: 30, minHeight: labels ? 36 : 26)
        .padding(.horizontal, labels ? 2 : 0)
    }
}

struct ToolButton: View {
    let systemImage: String
    let help: String
    var on = false
    var action: () -> Void
    init(_ systemImage: String, _ help: String, on: Bool = false, action: @escaping () -> Void) {
        self.systemImage = systemImage; self.help = help; self.on = on; self.action = action
    }
    var body: some View {
        Button(action: action) {
            ToolIcon(systemImage: systemImage)
                .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.accentColor.opacity(0.28) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { ToolHint.shared.text = help }
            else if ToolHint.shared.text == help { ToolHint.shared.text = nil }
        }
        .onDisappear { if ToolHint.shared.text == help { ToolHint.shared.text = nil } }
    }
}

/// Instant tooltip for the toolbar: the system tooltips are slow and sometimes show stale text there.
final class ToolHint: ObservableObject {
    static let shared = ToolHint()
    @Published var text: String?
}

struct ToolHintOverlay: View {
    @ObservedObject var hint = ToolHint.shared
    var body: some View {
        if let t = hint.text {
            Text(t).font(.callout).padding(.horizontal, 10).padding(.vertical, 5)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
                .padding(.top, 8).allowsHitTesting(false)
        }
    }
}

/// A rounded group of tools on a soft glass background (macOS 26) or a material background (older macOS).
struct ToolGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        let inner = HStack(spacing: 2) { content }.padding(.horizontal, 8).padding(.vertical, 3)
        if #available(macOS 26.0, *) {
            inner.glassEffect(.regular, in: Capsule())
        } else {
            inner.background(.regularMaterial, in: Capsule()).overlay(Capsule().stroke(Color.secondary.opacity(0.25), lineWidth: 0.5))
        }
    }
}

struct ToolbarGroups: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 16) {
            // Garmin device (import / send)
            ToolGroup {
                ToolButton("cable.connector", "Garmin device: import activities from it, send tracks and routes to it") {
                    model.garminSendMode = false; model.showGarminImport = true
                }
            }
            // map view
            ToolGroup {
                MapChoicePicker()
                AerialButton()
                PhotoButton()
                MapsMenuButton()
            }
            // track
            ToolGroup {
                ToolButton("arrow.up.left.and.arrow.down.right", "Zoom to all displayed tracks (⌘0)") { model.fitAll() }
                ToolButton("scope", "Zoom to the selected track (⌘9)") { model.fitForeground() }
                    .disabled(model.foreground == nil)
                ToolButton("ruler", "Measure distances: click points on the map (Esc ends, right-click removes the last point)", on: model.measure != nil) { model.toggleMeasure() }
                TrackColorMenu()
                ToolButton("chart.xyaxis.line", "Elevation profile of the selected track (double-click a track)", on: model.showProfile) { model.showProfile.toggle() }
                Menu {
                    ForEach(ExportFormat.allCases, id: \.self) { f in Button(f.rawValue + " …") { model.exportTrack(f) } }
                } label: { ToolIcon(systemImage: "square.and.arrow.up") }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .disabled(model.foreground == nil && model.edit == nil)
                    .onHover { ToolHint.shared.text = $0 ? "Export the selected track (GPX, KML, CSV)" : nil }
            }
            // editing the track
            ToolGroup { EditControls() }
            // route
            ToolGroup {
                ToolButton("arrow.triangle.turn.up.right.diamond", "Plan a route: hiking, road bike, mountain bike, car, motorcycle (or right-click the map: Start Route Here)",
                           on: model.plan != nil) { model.plan != nil ? model.stopPlanning() : model.startPlanning() }
            }
        }
        .fixedSize()
    }
}

struct MainToolbar: ToolbarContent {
    let model: AppModel
    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .principal) { ToolbarGroups().environmentObject(model) }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) { ToolbarGroups().environmentObject(model) }
        }
    }
}

/// Toolbar button for the aerial imagery panel.
struct AerialButton: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var open = FlagState()
    var body: some View {
        ToolButton(model.aerialOn ? "photo.fill" : "photo", "Aerial imagery (⇧⌘I)", on: model.aerialOn) { open.on.toggle() }
            .popover(isPresented: $open.on) { AerialPanel().environmentObject(model) }
    }
}

struct MapChoicePicker: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Picker("Map", selection: Binding(get: { model.selectedMapID ?? "" }, set: { model.selectMap($0) })) {
            Section("Online") {
                ForEach(model.onlineSources) { s in Text("\(s.name)  ·  routing (online)").tag(s.id) }
            }
            Section("Garmin Maps (offline)") {
                ForEach(model.maps) { m in
                    Text(m.isSupported ? m.name + (model.routableMaps[m.id] == true ? "  ·  routing" : "") : "\(m.name) – not supported").tag(m.id).disabled(!m.isSupported)
                }
            }
        }
        .pickerStyle(.menu)
        .frame(minWidth: 260)
        .onHover { ToolHint.shared.text = $0 ? "Switch map" : nil }
    }
}

struct MapsMenuButton: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Menu {
            Button("Add Map …") { model.chooseMapFiles() }
            Button("Download Area for Offline Use …") { model.showPrefetch = true }
            Button("Routing Rules of This Map …") { model.showRoutingRules() }
            Toggle("Sharper online tiles (more data)", isOn: $model.sharpTiles)
            Button("Show Online Tile Folder in Finder") { NSWorkspace.shared.activateFileViewerSelecting([TileCache.shared.root]) }
            Button("Delete Online Tiles …") {
                let a = NSAlert()
                a.messageText = "Delete stored online tiles?"
                a.informativeText = "Only the cached map images in “Online Maps” are deleted. They are downloaded again when needed."
                a.addButton(withTitle: "Delete"); a.addButton(withTitle: "Cancel")
                if a.runModal() == .alertFirstButtonReturn { TileCache.shared.clearAll() }
            }
            if !model.extraMapPaths.isEmpty {
                Divider()
                ForEach(model.extraMapPaths, id: \.self) { p in
                    Button("Remove: \(URL(fileURLWithPath: p).lastPathComponent)") { model.removeExtraMap(p) }
                }
            }
        } label: { ToolIcon(systemImage: "plus.rectangle.on.folder") }
        .menuIndicator(.hidden)
        .menuStyle(.button).buttonStyle(.plain)
        .fixedSize()
        .onHover { ToolHint.shared.text = $0 ? "Maps: add Garmin maps, download an area for offline use, tile cache" : nil }
    }
}

struct InfoOverlay: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let pl = model.plan {
                Text("Route planning: \(pl.profile.title)").font(.headline)
                Text("Click to set points · drag a point or the route to reshape").font(.caption)
            } else if let e = model.edit {
                Text("Editing: \(e.url.deletingPathExtension().lastPathComponent)").font(.headline).lineLimit(2)
                Text("Drag a point · click the line or map to insert points · ⌫ deletes · \(e.pointCount) points").font(.caption)
            } else if let f = model.foreground {
                Text(f.url.deletingPathExtension().lastPathComponent).font(.headline).lineLimit(2)
                Text(String(format: "%.1f km  ·  ↑ %.0f m", f.distance / 1000, f.ascent)).font(.caption).monospacedDigit()
            } else {
                Text("\(model.tracks.count) tracks visible").font(.caption)
            }
            if let m = model.selectedMap, m.isSupported == false { Text(m.unsupportedReason ?? "").font(.caption2).foregroundStyle(.red) }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}


/// The "Edit" button, and while a track is edited its tools.
struct EditControls: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let e = model.edit { EditActiveControls(edit: e) }
        else {
            ToolButton("pencil.and.scribble", "Edit the selected track: move, insert, delete points") { model.startEdit() }
                .disabled(model.foreground == nil)
        }
    }
}

struct EditActiveControls: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var edit: EditSession
    var body: some View {
        Group {
            ToolButton("arrow.uturn.backward", "Undo (⌘Z)") { edit.undo(); model.updateProfileIfEditing() }.disabled(!edit.canUndo)
            ToolButton("arrow.uturn.forward", "Redo (⇧⌘Z)") { edit.redo(); model.updateProfileIfEditing() }.disabled(!edit.canRedo)
            Divider().frame(height: 18)
            ToolButton("plus.circle", "Clicking the map inserts a point after the selected one (or at the end)", on: edit.addMode) { edit.addMode.toggle() }
            ToolButton("minus.circle", "Delete selected points (⌫)") { edit.deleteSelected(); model.updateProfileIfEditing() }.disabled(edit.selection.isEmpty)
            ToolButton("arrow.left.arrow.right", "Reverse direction") { edit.reverse(); model.updateProfileIfEditing() }
            TrackToolsMenu(edit: edit)
            Divider().frame(height: 18)
            ToolButton("square.and.arrow.down", "Save: overwrite the original (the original goes to the Trash first)") { model.saveEdit() }.disabled(!edit.dirty)
            ToolButton("square.and.arrow.down.on.square", "Save as a new file") { model.saveEditAs() }
            ToolButton("checkmark.circle", "Finish editing") { _ = model.confirmLeaveEdit() }
        }
    }
}

final class ProfileDragState: ObservableObject {
    @Published var range: (Double, Double)?
    var dragging = false
    var shiftAtStart = false
}

struct ProfileHost: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let e = model.edit { EditProfileView(edit: e) } else { ProfileView(selected: []) }
    }
}

struct EditProfileView: View {
    @ObservedObject var edit: EditSession
    var body: some View { ProfileView(selected: edit.selectedRows) }
}

struct ProfileView: View {
    @EnvironmentObject var model: AppModel
    let selected: [EditSession.Row]
    @StateObject private var drag = ProfileDragState()

    /// The curves that are selected and exist in this file; if none of the selected ones exist, the first one that does.
    private func shown(_ p: Profile) -> [ProfileChannel] {
        let s = ProfileChannel.allCases.filter { model.profileChannels.contains($0) && $0.available(p) }
        if !s.isEmpty { return s }
        return ProfileChannel.allCases.first(where: { $0.available(p) }).map { [$0] } ?? []
    }

    private func hasAnyData(_ p: Profile) -> Bool { ProfileChannel.allCases.contains { $0.available(p) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.foreground?.url.deletingPathExtension().lastPathComponent ?? "Elevation Profile").font(.headline).lineLimit(1)
                Spacer()
                if let p = model.profile, p.totalDistance > 0 {
                    Text(String(format: "%.1f km", p.totalDistance / 1000))
                    shown(p).enumerated().reduce(Text("")) { acc, e in
                        acc + Text((e.offset > 0 ? "   " : "") + e.element.stats(p)).foregroundColor(e.element == .elevation ? Color.primary : e.element.color)
                    }
                    .minimumScaleFactor(0.55)
                }
                Button { model.showProfile = false } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
            }
            .font(.caption).monospacedDigit().lineLimit(1)
            if let p = model.profile, hasAnyData(p) { chart(p) }
            else if model.profile != nil {
                Text("No elevation, speed, heart rate, power or cadence data in this file.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(model.plan != nil ? "The elevation profile appears when a route is calculated." : "Select a track (double-click) to see its elevation profile.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Text("Click: select point and center map · Drag: mark a range · ⇧-click: range up to the last point")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if let p = model.profile, hasAnyData(p) { ProfileContentButton(profile: p) }
            }
        }
        .padding(8)
        .background(.background)
    }

    private func norm(_ c: ProfileChannel, _ v: Double, _ r: (lo: Double, hi: Double)) -> Double { (v - r.lo) / max(1e-9, r.hi - r.lo) }

    /// Readout of all shown curves at one sample.
    private func readout(_ p: Profile, _ chans: [ProfileChannel], _ i: Int) -> String {
        var s = String(format: "%.2f km", p.dist[i] / 1000)
        for c in chans {
            let v = c.values(p)[i]
            s += c == .elevation ? String(format: " · %.0f m", v) : (c == .speed ? String(format: " · %.1f km/h", v) : String(format: " · %.0f %@", v, c.unit))
        }
        return s
    }

    private func nearest(_ p: Profile, _ d: Double) -> Int {
        guard let i = p.dist.firstIndex(where: { $0 >= d }) else { return max(0, p.dist.count - 1) }
        if i == 0 { return 0 }
        return abs(p.dist[i] - d) < abs(p.dist[i - 1] - d) ? i : i - 1
    }

    @ViewBuilder
    private func chart(_ p: Profile) -> some View {
        let chans = shown(p)
        let ranges = Dictionary(uniqueKeysWithValues: chans.map { ($0, $0.range(p)) })
        let showEle = chans.contains(.elevation)
        let primary = chans.first
        let leftCh = chans.first(where: { $0 != .elevation })
        let pts = Array(p.dist.enumerated())
        let ticks: [Double] = [0, 0.25, 0.5, 0.75, 1]
        // optional coloring of one line by speed, gradient, heart rate … (same colors as on the map)
        let ct: ColorTrack? = model.colorTrack.flatMap { $0.path == model.foregroundPath && $0.bin.count == p.dist.count - 1 ? $0 : nil }
        let colorTarget: ProfileChannel? = ct == nil ? nil : (showEle ? .elevation : (ct!.mode.channel.flatMap { chans.contains($0) ? $0 : nil } ?? primary))
        let cstep = max(1, p.dist.count / 700)
        Chart {
            if let pr = primary, let r = ranges[pr] {
                let v = pr.values(p)
                ForEach(pts, id: \.offset) { i, d in
                    AreaMark(x: .value("km", d / 1000), yStart: .value("min", 0.0), yEnd: .value(pr.unit, norm(pr, v[i], r)))
                        .foregroundStyle(.linearGradient(colors: [pr.color.opacity(0.4), pr.color.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                }
            }
            ForEach(chans) { c in
                let v = c.values(p), r = ranges[c]!
                if let ct, colorTarget == c {
                    ForEach(Array(stride(from: 0, to: p.dist.count - 1, by: cstep)), id: \.self) { i in
                        let j = min(i + cstep, p.dist.count - 1)
                        LineMark(x: .value("km", p.dist[i] / 1000), y: .value(c.unit, norm(c, v[i], r)), series: .value("s", "\(c.rawValue)c\(i)"))
                            .foregroundStyle(ColorRamp.colors[Int(ct.bin[i])]).lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        LineMark(x: .value("km", p.dist[j] / 1000), y: .value(c.unit, norm(c, v[j], r)), series: .value("s", "\(c.rawValue)c\(i)"))
                            .foregroundStyle(ColorRamp.colors[Int(ct.bin[i])]).lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    }
                } else {
                    ForEach(pts, id: \.offset) { i, d in
                        LineMark(x: .value("km", d / 1000), y: .value(c.unit, norm(c, v[i], r)), series: .value("s", c.rawValue)).foregroundStyle(c.color)
                    }
                }
            }
            if let r = drag.range {
                RectangleMark(xStart: .value("a", min(r.0, r.1) / 1000), xEnd: .value("b", max(r.0, r.1) / 1000),
                              yStart: .value("lo", 0.0), yEnd: .value("hi", 1.0))
                    .foregroundStyle(.yellow.opacity(0.35))
            }
            if selected.count >= 2, let f = selected.first, let l = selected.last {
                RectangleMark(xStart: .value("a", f.dist / 1000), xEnd: .value("b", l.dist / 1000),
                              yStart: .value("lo", 0.0), yEnd: .value("hi", 1.0))
                    .foregroundStyle(.blue.opacity(0.18))
            }
            if let pr = primary, let r = ranges[pr] {
                ForEach(selected.prefix(80), id: \.id) { row in
                    PointMark(x: .value("km", row.dist / 1000), y: .value("y", norm(pr, pr.values(p)[nearest(p, row.dist)], r)))
                        .foregroundStyle(.red).symbolSize(selected.count == 1 ? 90 : 28)
                }
            }
            if selected.count == 1, let r = selected.first {
                RuleMark(x: .value("km", r.dist / 1000)).foregroundStyle(.red.opacity(0.6))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Point \(r.n) · " + readout(p, chans, nearest(p, r.dist)))
                            .font(.caption2).padding(3).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                    }
            }
            if let c = model.profileCursor, c < p.dist.count {
                RuleMark(x: .value("km", p.dist[c] / 1000)).foregroundStyle(.orange.opacity(0.7))
                    .annotation(position: .top, alignment: .leading, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Text(readout(p, chans, c)).font(.caption2).padding(3).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                    }
            }
        }
        .chartYScale(domain: 0...1)
        .chartYAxis {
            // elevation: scale and unit on the right; the first other curve: scale and unit on the left (the further curves are drawn to fit)
            if showEle, let r = ranges[.elevation] {
                AxisMarks(position: .trailing, values: ticks) { v in
                    AxisGridLine()
                    AxisValueLabel { if let y = v.as(Double.self) { Text(String(format: "%.0f", r.lo + y * (r.hi - r.lo))).foregroundStyle(ProfileChannel.elevation.color) } }
                }
            }
            if let l = leftCh, let r = ranges[l] {
                AxisMarks(position: .leading, values: ticks) { v in
                    AxisGridLine().foregroundStyle(showEle ? l.color.opacity(0.15) : Color.gray.opacity(0.25))
                    AxisValueLabel { if let y = v.as(Double.self) { Text(String(format: "%.0f", r.lo + y * (r.hi - r.lo))).foregroundStyle(l.color) } }
                }
            }
        }
        .chartYAxisLabel(position: .leading) { if let l = leftCh { Text(l.unit).foregroundStyle(l.color) } }
        .chartYAxisLabel(position: .trailing) { if showEle { Text("m").foregroundStyle(ProfileChannel.elevation.color) } }
        .chartXAxisLabel("km", alignment: .trailing)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            if let d = dist(proxy, geo, loc.x, p) { model.profileCursor = nearest(p, d) }
                        case .ended: model.profileCursor = nil
                        }
                    }
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            if !drag.dragging { drag.dragging = true; drag.shiftAtStart = NSEvent.modifierFlags.contains(.shift) }
                            if abs(v.translation.width) > 3,
                               let a = dist(proxy, geo, v.startLocation.x, p), let b = dist(proxy, geo, v.location.x, p) {
                                drag.range = (a, b); model.profileLiveRange = (a, b)
                            }
                        }
                        .onEnded { v in
                            let shift = drag.shiftAtStart
                            drag.dragging = false; drag.shiftAtStart = false; drag.range = nil; model.profileLiveRange = nil
                            guard let a = dist(proxy, geo, v.startLocation.x, p), let b = dist(proxy, geo, v.location.x, p) else { return }
                            if abs(v.translation.width) > 3 {
                                model.profileAnchor = a; model.profileRange(a, b)
                            } else {
                                model.profileClick(distance: b, extend: shift)
                            }
                        })
            }
        }
    }

    private func dist(_ proxy: ChartProxy, _ geo: GeometryProxy, _ x: CGFloat, _ p: Profile) -> Double? {
        guard let km: Double = proxy.value(atX: x - geo[proxy.plotAreaFrame].origin.x) else { return nil }
        return max(0, min(p.totalDistance, km * 1000))
    }
}

/// "Content" button below the graph: which curves are drawn and how the track is colored.
struct ProfileContentButton: View {
    @EnvironmentObject var model: AppModel
    let profile: Profile
    @StateObject private var open = FlagState()
    var body: some View {
        Button { open.on.toggle() } label: { Label("Content", systemImage: "slider.horizontal.3") }
            .controlSize(.small)
            .help("Choose the curves of the graph and the coloring of the track")
            .popover(isPresented: $open.on, arrowEdge: .top) { ProfileContentPanel(profile: profile).environmentObject(model) }
    }
}

struct ProfileContentPanel: View {
    @EnvironmentObject var model: AppModel
    let profile: Profile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Curves in the graph").font(.headline)
            ForEach(ProfileChannel.allCases) { c in
                let ok = c.available(profile)
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(get: { model.profileChannels.contains(c) && ok },
                                             set: { if $0 { model.profileChannels.insert(c) } else { model.profileChannels.remove(c) } }))
                        .labelsHidden().toggleStyle(.checkbox).disabled(!ok)
                    Circle().fill(c.color).frame(width: 10, height: 10).opacity(ok ? 1 : 0.3)
                    Text(c.title)
                    Spacer()
                    Text(ok ? rangeText(c) : "not in this file").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("All Available") { model.profileChannels = Set(ProfileChannel.allCases.filter { $0.available(profile) }) }
                Button("Elevation Only") { model.profileChannels = [.elevation] }
            }.controlSize(.small)
            Text("The first curve that is not the elevation gets the scale on the left; the others are drawn to fit the same height.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(width: 340)
    }

    private func rangeText(_ c: ProfileChannel) -> String {
        let v = c.values(profile)
        guard let lo = v.min(), let hi = v.max() else { return "" }
        return String(format: "%.0f–%.0f %@", lo, hi, c.unit)
    }
}

struct PointsPanel: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var edit: EditSession

    /// "→ 0.31 km · 1:12 · 15.5 km/h · 54° NE": distance, time, speed and direction of the leg from this point to the next (none for the last point).
    static func legText(_ r: EditSession.Row) -> String? {
        var parts: [String] = []
        if let d = r.legDist { parts.append(d < 1000 ? String(format: "%.0f m", d) : String(format: "%.2f km", d / 1000)) }
        if let t = r.legTime {
            let s = Int(t.rounded())
            parts.append(s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60))
        }
        if let v = r.legSpeed { parts.append(String(format: "%.1f km/h", v)) }
        if let b = r.legBearing {
            let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
            parts.append(String(format: "%.0f° ", b) + names[Int((b + 22.5) / 45) % 8])
        }
        return parts.isEmpty ? nil : "→ " + parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Waypoints").font(.headline)
                Text("\(edit.pointCount)").foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button { model.exitEditor() } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                    .help("Close waypoint editor (Esc)")
            }
            HStack {
                Button { edit.selection = Set(edit.rows.map { $0.id }) } label: { Text("All") }
                Button { edit.selection = [] } label: { Text("None") }
                Spacer()
                Button(role: .destructive) { edit.deleteSelected(); model.updateProfileIfEditing() } label: {
                    Label("Delete (\(edit.selection.count))", systemImage: "trash")
                }.disabled(edit.selection.isEmpty)
            }
            .controlSize(.small)
            ScrollViewReader { proxy in
            List(edit.rows, selection: Binding(get: { edit.selection }, set: { edit.selection = $0 })) { r in
                HStack(spacing: 8) {
                    Text("\(r.n)").frame(width: 42, alignment: .trailing).monospacedDigit().foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(format: "%.5f, %.5f", r.lat, r.lon)).monospacedDigit()
                        Text(String(format: "%.2f km", r.dist / 1000) + (r.ele.map { String(format: " · %.0f m", $0) } ?? ""))
                            .font(.caption2).foregroundStyle(.secondary)
                        if let leg = Self.legText(r) { Text(leg).font(.caption2).foregroundStyle(.secondary).monospacedDigit() }
                    }
                }
                .tag(r.id)
                .onTapGesture(count: 2) { model.center(on: r.lat, r.lon) }
            }
            .onDeleteCommand { edit.deleteSelected(); model.updateProfileIfEditing() }
            .onChange(of: edit.selection) { _, sel in
                if let first = edit.selectedRows.first, sel.count >= 1 { proxy.scrollTo(first.id) }
            }
            }
            Text("Double-click a point to center the map. ⇧-click selects several points on the map.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.background)
    }
}


/// Folder name, load progress and the "Ordner…" button. Observes the model itself so that progress updates
/// never force the (large) track list to be diffed.
struct SidebarFooter: View {
    @EnvironmentObject var model: AppModel
    let chooseFolder: () -> Void

    /// Current folder first, then its parents up to the volume root.
    private var ancestors: [URL] {
        var out = [model.rootURL]
        var u = model.rootURL
        while u.path != "/", out.count < 40 {
            let parent = u.deletingLastPathComponent()
            if parent.path == u.path { break }
            u = parent; out.append(u)
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
        HStack {
            Button { model.goUp() } label: { Image(systemName: "arrow.up") }
                .disabled(!model.canGoUp)
                .help("Go to parent folder: \(model.rootURL.deletingLastPathComponent().lastPathComponent)")
            Menu {
                // path of the current folder up to the volume, like Finder's path bar
                ForEach(ancestors, id: \.path) { u in
                    Button {
                        model.chooseRoot(u)
                    } label: {
                        Label(FileManager.default.displayName(atPath: u.path), systemImage: u.path == model.rootURL.path ? "checkmark" : (u.path == "/" ? "internaldrive" : "folder"))
                    }
                }
                let subs = (model.tree?.children ?? []).filter { $0.isFolder }
                if !subs.isEmpty {
                    Divider()
                    Section("Subfolders") {
                        ForEach(Array(subs.prefix(60)), id: \.numericID) { n in
                            Button { model.chooseRoot(n.url) } label: { Label(n.name, systemImage: "folder") }
                        }
                    }
                }
            } label: {
                Image(systemName: "folder.fill").foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Show folder hierarchy and switch folders")
            Text(model.rootURL.lastPathComponent).lineLimit(1).font(.caption).help(model.rootURL.path)
            Spacer()
            if model.loadingCount > 0 { ProgressView().controlSize(.small); Text("\(model.loadingCount)").font(.caption).monospacedDigit() }
            Button("Folder…") { chooseFolder() }.controlSize(.small)
        }
        }
        .padding(8)
    }
}




/// Bottom bar of the sidebar: controls the route list / map overlay.
struct RouteListFooter: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack {
            Toggle("Show tracks in subfolders", isOn: $model.includeSubfolders)
                .toggleStyle(.switch).controlSize(.small)
                .help("Also shows the routes of all subfolders in the list and on the map")
            Spacer()
        }
        .padding(8)
    }
}


/// One dialog for Komoot: Import / Export are switched inside it.
struct KomootDialog: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var session = KomootSession()          // one login for both tabs
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.komootExportMode) { Text("Import").tag(false); Text("Export").tag(true) }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220).padding(.top, 14)
            if model.komootExportMode { KomootExportSheet(session: session) } else { KomootImportSheet(session: session) }
        }
    }
}

/// Sheet and menu notifications for Komoot (the menu entry opens the dialog; the notification .komootExport opens it on "Export").
struct KomootHook: ViewModifier {
    @EnvironmentObject var model: AppModel
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $model.showKomootImport) { KomootDialog().environmentObject(model) }
            .onReceive(model.menuEvents(.komootImport)) { _ in model.komootExportMode = false; model.showKomootImport = true }
            .onReceive(model.menuEvents(.komootExport)) { _ in model.komootExportMode = true; model.showKomootImport = true }
    }
}


/// Turns off the system's own "Icon and Text / Text only" choice of the toolbar; the labels are offered as View > Show Toolbar Labels.
struct ToolbarTweak: ViewModifier {
    func body(content: Content) -> some View {
        content.onAppear {
            for delay in [0.1, 0.6, 1.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    for w in NSApp.windows {
                        if #available(macOS 15.0, *) { w.toolbar?.allowsDisplayModeCustomization = false }
                        w.toolbar?.displayMode = .iconOnly
                    }
                }
            }
        }
    }
}


/// Tells the model which window (tab) it belongs to.
struct WindowGrabber: NSViewRepresentable {
    let model: AppModel
    final class Coordinator { var observer: NSObjectProtocol? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async {
            model.window = v.window
            AppModel.all.add(model)
            if context.coordinator.observer == nil, let w = v.window {
                AppModel.lastActive = model
                context.coordinator.observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: w, queue: .main) { [weak model] _ in
                    AppModel.lastActive = model
                }
            }
        }
    }
}


/// Short notice at the bottom of the map (e.g. that an original went to the Trash).
struct NoticeOverlay: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let t = model.noticeText {
            HStack(spacing: 6) { Image(systemName: "trash"); Text(t) }
                .font(.callout).padding(.horizontal, 12).padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
                .padding(.bottom, 40).allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}
