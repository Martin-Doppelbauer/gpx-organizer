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
                            if let s = model.selectedTileSource {
                                Text(s.attribution).font(.caption2).padding(4)
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
                if model.showProfile { Divider(); ProfileHost().frame(height: 210) }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) { MapPicker() }
            ToolbarItemGroup {
                Button { model.fitAll() } label: { Label("Zoom All", systemImage: "arrow.up.left.and.arrow.down.right") }
                    .help("Zoom to all displayed tracks (⌘0)")
                Button { model.fitForeground() } label: { Label("Zoom Track", systemImage: "scope") }
                    .help("Zoom to the selected track (⌘9)")
                    .disabled(model.foreground == nil)
                Menu {
                    ForEach(ExportFormat.allCases, id: \.self) { f in Button(f.rawValue + " …") { model.exportTrack(f) } }
                } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .disabled(model.foreground == nil && model.edit == nil)
                    .help("Export the selected track (GPX, KML, CSV)")
                Toggle(isOn: Binding(get: { model.plan != nil }, set: { $0 ? model.startPlanning() : model.stopPlanning() })) {
                    Label("Route Planning", systemImage: "arrow.triangle.turn.up.right.diamond")
                }
                .help("Plan a route: hiking, road bike, mountain bike, car/motorcycle")
                Toggle(isOn: $model.showProfile) { Label("Elevation Profile", systemImage: "chart.xyaxis.line") }
                    .help("Elevation profile of the selected track (double-click a track)")
            }
            ToolbarItemGroup {
                if let e = model.edit {
                    EditToolbar(edit: e)
                } else {
                    Button { model.startEdit() } label: { Label("Edit", systemImage: "pencil.and.scribble") }
                        .help("Edit the selected track: move, insert, delete points")
                        .disabled(model.foreground == nil)
                }
            }
        }
        .onExitCommand { model.escape() }
        .sheet(isPresented: $model.showPrefetch) { PrefetchSheet().environmentObject(model) }
        .sheet(isPresented: $model.iconPickerOpen) { IconPickerSheet().environmentObject(model) }
        .onReceive(NotificationCenter.default.publisher(for: .fitAll)) { _ in model.fitAll() }
        .onReceive(NotificationCenter.default.publisher(for: .fitSelected)) { _ in model.fitForeground() }
        .onReceive(NotificationCenter.default.publisher(for: .reloadTree)) { _ in model.reloadTree() }
        .onReceive(NotificationCenter.default.publisher(for: .kindThresholdsChanged)) { _ in model.reclassify() }
        .onReceive(NotificationCenter.default.publisher(for: .printMap)) { _ in model.printMap() }
        .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in model.zoomStep(2) }
        .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in model.zoomStep(0.5) }
        .onReceive(NotificationCenter.default.publisher(for: .markerSizeChanged)) { _ in model.viewRevision += 1 }
        .onReceive(NotificationCenter.default.publisher(for: .mapsFolderChanged)) { _ in model.mapsFolderChanged() }
        .onReceive(NotificationCenter.default.publisher(for: .editUndo)) { _ in model.edit?.undo(); model.updateProfileIfEditing() }
        .onReceive(NotificationCenter.default.publisher(for: .editRedo)) { _ in model.edit?.redo(); model.updateProfileIfEditing() }
    }
}

struct MapPicker: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Picker("Map", selection: Binding(get: { model.selectedMapID ?? "" }, set: { model.selectMap($0) })) {
            Section("Online") {
                ForEach(AppModel.onlineSources) { s in Text("\(s.name)  ·  routing (online)").tag(s.id) }
            }
            Section("Garmin Maps (offline)") {
                ForEach(model.maps) { m in
                    Text(m.isSupported ? m.name + (model.routableMaps[m.id] == true ? "  ·  routing" : "") : "\(m.name) – not supported").tag(m.id).disabled(!m.isSupported)
                }
            }
        }
        .pickerStyle(.menu)
        .frame(minWidth: 260)
        .help("Switch Garmin map")
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
        } label: { Label("Maps", systemImage: "plus.rectangle.on.folder") }
        .help("Add or remove Garmin .img maps")
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


struct EditToolbar: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var edit: EditSession
    var body: some View {
        Group {
            Button { edit.undo(); model.updateProfileIfEditing() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .disabled(!edit.canUndo).help("Undo (⌘Z)")
            Button { edit.redo(); model.updateProfileIfEditing() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                .disabled(!edit.canRedo).help("Redo (⇧⌘Z)")
            Button { edit.deleteSelected(); model.updateProfileIfEditing() } label: { Label("Delete Point", systemImage: "minus.circle") }
                .disabled(edit.selection.isEmpty).help("Delete selected points (⌫)")
            Toggle(isOn: $edit.addMode) { Label("Add Points", systemImage: "plus.circle") }
                .help("Clicking the map inserts a point after the selected one (or at the end)")
            Button { edit.reverse(); model.updateProfileIfEditing() } label: { Label("Reverse", systemImage: "arrow.left.arrow.right") }
                .help("Reverse direction")
            Button { model.saveEdit() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                .disabled(!edit.dirty).help("Overwrite the original (a backup copy is made)")
            Button { model.saveEditAs() } label: { Label("Save As", systemImage: "square.and.arrow.down.on.square") }
                .help("Save as a new file")
            Button { _ = model.confirmLeaveEdit() } label: { Label("Done", systemImage: "checkmark.circle") }
                .help("Finish editing")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.foreground?.url.deletingPathExtension().lastPathComponent ?? "Elevation Profile").font(.headline).lineLimit(1)
                Spacer()
                if let p = model.profile, p.totalDistance > 0 {
                    Text(String(format: "%.1f km", p.totalDistance / 1000))
                    if p.hasElevation {
                        Text(String(format: "↑ %.0f m   ↓ %.0f m   %.0f–%.0f m", p.ascent, p.descent, p.minEle, p.maxEle))
                    }
                    if p.hasSpeed {
                        Text(String(format: "Ø %.1f km/h   max %.0f km/h", p.avgSpeed, p.maxSpeed))
                    }
                }
                Button { model.showProfile = false } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
            }
            .font(.caption).monospacedDigit()
            if let p = model.profile, p.hasElevation || p.hasSpeed { chart(p) }
            else if model.profile != nil {
                Text("No elevation or speed data in this file.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(model.plan != nil ? "The elevation profile appears when a route is calculated." : "Select a track (double-click) to see its elevation profile.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Text("Click: select point and center map · Drag: mark a range · ⇧-click: range up to the last point")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if let p = model.profile, p.hasElevation || p.hasSpeed {
                    Picker("Show", selection: $model.profileMode) {
                        ForEach(ProfileMode.allCases) { m in Text(m.title).tag(m) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 230).controlSize(.small)
                    .help("Elevation, speed (needs time stamps in the file) or both")
                }
            }
        }
        .padding(8)
        .background(.background)
    }

    /// The mode that can actually be shown for this file.
    private func effectiveMode(_ p: Profile) -> ProfileMode {
        var m = model.profileMode
        if m != .speed && !p.hasElevation { m = .speed }
        if m != .elevation && !p.hasSpeed { m = .elevation }
        return m
    }

    private func niceCeil(_ v: Double) -> Double {
        let step = v > 60 ? 20.0 : (v > 30 ? 10.0 : 5.0)
        return max(step, ceil(v / step) * step)
    }

    @ViewBuilder
    private func chart(_ p: Profile) -> some View {
        let m = effectiveMode(p)
        let showEle = m != .speed && p.hasElevation
        let showSpd = m != .elevation && p.hasSpeed
        let eLo = p.hasElevation ? floor(p.minEle / 10) * 10 - 10 : 0, eHi = p.hasElevation ? ceil(p.maxEle / 10) * 10 + 10 : 1
        let sMax = niceCeil(max(p.maxSpeed, 5))
        let lo = showEle ? eLo : 0, hi = showEle ? eHi : sMax
        // speed drawn on the elevation scale when both are shown (its own axis on the left)
        let sy: (Double) -> Double = { showEle ? eLo + $0 / sMax * (eHi - eLo) : $0 }
        let pts = Array(p.dist.enumerated())
        Chart {
            if showEle {
                ForEach(pts, id: \.offset) { i, d in
                    AreaMark(x: .value("km", d / 1000), yStart: .value("min", lo), yEnd: .value("m", p.ele[i]))
                        .foregroundStyle(.linearGradient(colors: [.green.opacity(0.45), .green.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("km", d / 1000), y: .value("m", p.ele[i]), series: .value("s", "ele")).foregroundStyle(.green)
                }
            }
            if showSpd {
                ForEach(pts, id: \.offset) { i, d in
                    if !showEle {
                        AreaMark(x: .value("km", d / 1000), yStart: .value("min", 0), yEnd: .value("km/h", p.speed[i]))
                            .foregroundStyle(.linearGradient(colors: [.blue.opacity(0.35), .blue.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                    }
                    LineMark(x: .value("km", d / 1000), y: .value("v", sy(p.speed[i])), series: .value("s", "spd")).foregroundStyle(.blue)
                }
            }
            if let r = drag.range {
                RectangleMark(xStart: .value("a", min(r.0, r.1) / 1000), xEnd: .value("b", max(r.0, r.1) / 1000),
                              yStart: .value("lo", lo), yEnd: .value("hi", hi))
                    .foregroundStyle(.yellow.opacity(0.35))
            }
            if selected.count >= 2, let f = selected.first, let l = selected.last {
                RectangleMark(xStart: .value("a", f.dist / 1000), xEnd: .value("b", l.dist / 1000),
                              yStart: .value("lo", lo), yEnd: .value("hi", hi))
                    .foregroundStyle(.blue.opacity(0.18))
            }
            ForEach(selected.prefix(80), id: \.id) { r in
                if let y = showEle ? (r.ele ?? interpolate(p, r.dist)) : interpolateSpeed(p, r.dist) {
                    PointMark(x: .value("km", r.dist / 1000), y: .value("y", y)).foregroundStyle(.red).symbolSize(selected.count == 1 ? 90 : 28)
                }
            }
            if selected.count == 1, let r = selected.first {
                RuleMark(x: .value("km", r.dist / 1000)).foregroundStyle(.red.opacity(0.6))
                    .annotation(position: .top, alignment: .leading) {
                        Text(String(format: "Point %d · %.2f km", r.n, r.dist / 1000)
                             + (r.ele.map { String(format: " · %.0f m", $0) } ?? "")
                             + (interpolateSpeed(p, r.dist).map { String(format: " · %.1f km/h", $0) } ?? ""))
                            .font(.caption2).padding(3).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                    }
            }
            if let c = model.profileCursor, c < p.dist.count {
                RuleMark(x: .value("km", p.dist[c] / 1000)).foregroundStyle(.orange.opacity(0.7))
                    .annotation(position: .top, alignment: .leading, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Text(String(format: "%.1f km", p.dist[c] / 1000)
                             + (p.hasElevation ? String(format: " · %.0f m", p.ele[c]) : "")
                             + (p.hasSpeed ? String(format: " · %.1f km/h", p.speed[c]) : ""))
                            .font(.caption2).padding(3).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                    }
            }
        }
        .chartYScale(domain: lo...hi)
        .chartYAxis {
            if showEle {
                AxisMarks(position: .trailing)
                if showSpd {
                    AxisMarks(position: .leading, values: stride(from: 0.0, through: sMax, by: sMax / 4).map { sy($0) }) { v in
                        AxisGridLine().foregroundStyle(.blue.opacity(0.15))
                        AxisValueLabel {
                            if let y = v.as(Double.self) { Text(String(format: "%.0f", (y - eLo) / (eHi - eLo) * sMax)).foregroundStyle(.blue) }
                        }
                    }
                }
            } else {
                AxisMarks(position: .trailing) { v in
                    AxisGridLine()
                    AxisValueLabel { if let y = v.as(Double.self) { Text(String(format: "%.0f", y)).foregroundStyle(.blue) } }
                }
            }
        }
        .chartYAxisLabel(showEle ? (showSpd ? "m · km/h" : "m") : "km/h", position: .trailing)
        .chartXAxisLabel("km", alignment: .trailing)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            if let d = dist(proxy, geo, loc.x, p) {
                                var best = 0, bd = Double.infinity
                                for (i, v) in p.dist.enumerated() where abs(v - d) < bd { bd = abs(v - d); best = i }
                                model.profileCursor = best
                            }
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

    private func interpolateSpeed(_ p: Profile, _ d: Double) -> Double? {
        guard p.hasSpeed else { return nil }
        guard let i = p.dist.firstIndex(where: { $0 >= d }) else { return p.speed.last }
        if i == 0 { return p.speed.first }
        let t = (d - p.dist[i - 1]) / max(1e-9, p.dist[i] - p.dist[i - 1])
        return p.speed[i - 1] + t * (p.speed[i] - p.speed[i - 1])
    }

    private func interpolate(_ p: Profile, _ d: Double) -> Double? {
        guard let i = p.dist.firstIndex(where: { $0 >= d }) else { return p.ele.last }
        if i == 0 { return p.ele.first }
        let t = (d - p.dist[i - 1]) / max(1e-9, p.dist[i] - p.dist[i - 1])
        return p.ele[i - 1] + t * (p.ele[i] - p.ele[i - 1])
    }
}

struct PointsPanel: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var edit: EditSession

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
