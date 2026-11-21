import SwiftUI
import AppKit
import BCCore

/// Route planning state: via points, routing profile and the computed route.
@MainActor
final class PlanSession: ObservableObject {
    struct Via: Identifiable, Equatable { let id = UUID(); var lat: Double; var lon: Double }
    private final class Token { var cancelled = false }

    @Published var vias: [Via] = []
    @Published var profile: RouteProfile = .hiking { didSet { recompute() } }
    @Published private(set) var result: RouteResult?
    @Published private(set) var status = "Click the map to set start and destination."
    @Published private(set) var busy = false
    var onChange: (() -> Void)?         // the result changed (elevation profile)
    var dragging: UUID?                 // row being dragged in the list
    var map: GarminMap? { didSet { recompute() } }
    /// Online map selected: route on OpenStreetMap data through brouter.de instead of a Garmin map.
    var online = false { didSet { if online != oldValue { recompute() } } }
    private var token = Token()

    init(map: GarminMap?, online: Bool = false) { self.map = map; self.online = online }

    @discardableResult
    func addVia(lat: Double, lon: Double) -> Int {
        vias.append(Via(lat: lat, lon: lon)); recompute(); return vias.count - 1
    }

    func insertVia(at index: Int, lat: Double, lon: Double) -> Int {
        let i = max(0, min(index, vias.count))
        vias.insert(Via(lat: lat, lon: lon), at: i); return i
    }

    func moveVia(_ i: Int, lat: Double, lon: Double) {
        guard vias.indices.contains(i) else { return }
        vias[i].lat = lat; vias[i].lon = lon
    }

    /// Reorders the points (drag in the list); the first one becomes the start, the last one the destination.
    func moveVias(from: IndexSet, to: Int) {
        vias.move(fromOffsets: from, toOffset: to); recompute()
    }

    func removeVia(_ id: UUID) { vias.removeAll { $0.id == id }; recompute() }
    func clear() { vias = []; recompute() }
    func reverse() { vias.reverse(); recompute() }

    func recompute() {
        token.cancelled = true
        let t = Token(); token = t
        guard vias.count >= 2 else {
            result = nil; busy = false
            status = vias.isEmpty ? "Click the map to set start and destination." : "Set another point (destination)."
            onChange?()
            return
        }
        let pts = vias.map { (lat: $0.lat, lon: $0.lon) }
        let prof = profile
        let map = online ? nil : self.map
        if !online {
            guard let map, map.isSupported else { result = nil; status = "No routable map selected."; onChange?(); return }
            if let r = map.routingRules, !r.isRoutable { result = nil; status = "This map has no routable roads or paths."; onChange?(); return }
        }
        busy = true; status = "Calculating …"
        Task.detached(priority: .userInitiated) {
            let outcome: Result<RouteResult, Error>
            do {
                if let map { outcome = .success(try Router.plan(map: map, vias: pts, profile: prof, cancelled: { t.cancelled })) }
                else { outcome = .success(try await OnlineRouter.plan(vias: pts, profile: prof, cancelled: { t.cancelled })) }
            } catch { outcome = .failure(error) }
            await MainActor.run {
                guard !t.cancelled else { return }
                self.busy = false
                switch outcome {
                case .success(let r): self.result = r; self.status = ""; self.onChange?(); self.fetchElevations(for: r, token: t)
                case .failure(let e): self.result = nil; self.status = e.localizedDescription; self.onChange?()
                }
            }
        }
    }

    /// Maps without heights (Garmin): ask an elevation service for the route's heights, then refresh the profile.
    private func fetchElevations(for r: RouteResult, token t: Token) {
        guard r.elevations.isEmpty, r.points.count >= 2 else { return }
        let pts = r.points
        Task.detached(priority: .utility) {
            let e = await ElevationService.elevations(for: pts, cancelled: { t.cancelled })
            await MainActor.run {
                guard !t.cancelled, let e, self.result?.points.count == pts.count else { return }
                self.result?.elevations = e
                self.onChange?()
            }
        }
    }

    /// The planned route as a document (with heights when known).
    func routeDocument() -> GPXDocument? {
        guard let r = result, !r.points.isEmpty else { return nil }
        var d = GPXDocument(name: "Route")
        d.tracks = [GPXTrackData(name: "Route", isRoute: false, segments: [pointsWithHeights(r)])]
        return d
    }

    private func pointsWithHeights(_ r: RouteResult) -> [GPXPoint] {
        r.points.enumerated().map { GPXPoint(lat: $0.element.lat, lon: $0.element.lon, ele: $0.offset < r.elevations.count ? r.elevations[$0.offset] : nil) }
    }

    /// Document for saving: the planned route as a track plus the via points as waypoints.
    func document(name: String) -> GPXDocument? {
        guard let r = result, !r.points.isEmpty else { return nil }
        var d = GPXDocument(name: name)
        d.tracks = [GPXTrackData(name: name, isRoute: false, segments: [pointsWithHeights(r)])]
        for (i, v) in vias.enumerated() {
            let label = i == 0 ? "Start" : (i == vias.count - 1 ? "End" : "Via \(i)")
            d.waypoints.append(GPXWaypoint(point: GPXPoint(lat: v.lat, lon: v.lon), name: label, desc: "", sym: ""))
        }
        return d
    }
}

/// While a row is dragged over another row the dragged point takes that row's place at once (live reordering),
/// so releasing anywhere between two rows puts the point exactly there.
struct ViaDrop: DropDelegate {
    let plan: PlanSession
    let target: UUID
    func dropEntered(info: DropInfo) {
        guard let d = plan.dragging, d != target,
              let from = plan.vias.firstIndex(where: { $0.id == d }),
              let to = plan.vias.firstIndex(where: { $0.id == target }) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            plan.moveVias(from: IndexSet(integer: from), to: to > from ? to + 1 : to)
        }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { plan.dragging = nil; return true }
}

/// Drops in the gaps between the rows or below the last row are accepted too (the order was already changed).
struct ViaListDrop: DropDelegate {
    let plan: PlanSession
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { plan.dragging = nil; return true }
}

struct PlanPanel: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var plan: PlanSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Route Planning").font(.headline)
                Spacer()
                Button { model.stopPlanning() } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
            }
            Picker("Profile", selection: $plan.profile) {
                ForEach(RouteProfile.allCases) { p in Label(p.title, systemImage: p.symbol).tag(p) }
            }
            .pickerStyle(.menu)
            if plan.online {
                Text("Online routing (OpenStreetMap data, \(OnlineRouter.host))").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            } else if let m = plan.map {
                Text("Map: \(m.name)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 6) {
                if plan.busy { ProgressView().controlSize(.small) }
                if let r = plan.result {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.1f km", r.distance / 1000)).font(.title3).bold()
                        Text(durationText(r.duration) + " (\(plan.profile.title))").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(plan.status).font(.caption).foregroundStyle(plan.busy ? Color.secondary : Color.orange)
                }
            }
            Divider()
            List {
                ForEach(Array(plan.vias.enumerated()), id: \.element.id) { i, v in
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).help("Drag to change the order")
                        Text("\(i + 1)").font(.caption.bold()).foregroundStyle(.white).frame(width: 18, height: 18)
                            .background(Circle().fill(badge(i)))
                        Text(label(i)).bold().frame(width: 40, alignment: .leading)
                        Text(String(format: "%.4f, %.4f", v.lat, v.lon)).font(.caption).monospacedDigit()
                        Spacer()
                        Button { plan.removeVia(v.id) } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.center(on: v.lat, v.lon) }
                    .onDrag {
                        plan.dragging = v.id
                        return NSItemProvider(object: v.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: ViaDrop(plan: plan, target: v.id))
                }
            }
            .onDrop(of: [.text], delegate: ViaListDrop(plan: plan))
            HStack {
                Button("Reset") { plan.clear() }
                Button("Reverse") { plan.reverse() }.disabled(plan.vias.count < 2)
            }
            .controlSize(.small)
            Button { model.savePlannedRoute() } label: { Label("Save as GPX …", systemImage: "square.and.arrow.down") }
                .disabled(plan.result == nil)
            Text("Click the map to set points. Drag a point or the route to reshape it. Drag the rows to change the order.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.background)
    }

    /// Same colours as the numbered markers in the map.
    private func badge(_ i: Int) -> Color {
        i == 0 ? .green : (i == plan.vias.count - 1 ? .red : .blue)
    }

    private func label(_ i: Int) -> String {
        i == 0 ? "Start" : (i == plan.vias.count - 1 ? "End" : "Via \(i)")
    }

    private func durationText(_ s: Double) -> String {
        let m = Int((s / 60).rounded())
        return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
    }
}

extension AppModel {
    func startPlanning() {
        guard plan == nil else { return }
        guard confirmLeaveEdit() else { return }
        showPoints = false
        profileBeforePlan = showProfile
        let p = PlanSession(map: routingMap, online: routingOnline)
        p.onChange = { [weak self] in self?.updateProfile() }
        plan = p
        showProfile = true                 // the elevation profile of the planned route appears under the map
    }

    func stopPlanning() { plan = nil; showProfile = profileBeforePlan; if showProfile { updateProfile() } }

    /// Shows how the routing rules of the selected map were derived (for checking).
    func showRoutingRules() {
        let a = NSAlert()
        if selectedTileSource != nil {
            a.messageText = "Online map"
            a.informativeText = "Routes are calculated on OpenStreetMap data by \(OnlineRouter.host) (BRouter profiles: hiking-mountain, fastbike, mtb, car-fast). The coordinates of the route points are sent to that server."
        } else if let m = selectedMap, let r = m.routingRules {
            a.messageText = "\(m.name): routing rules"
            a.informativeText = (r.isRoutable ? "Routable. " : "Not routable. ") + "Rules are derived from the map's data at every start.\n\n" + r.summary
        } else {
            a.messageText = "Routing rules"
            a.informativeText = "The map is still being analysed or has no usable data."
        }
        a.runModal()
    }

    func savePlannedRoute() {
        guard let plan else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let name = "Route \(plan.profile.title) \(f.string(from: Date()))"
        guard let doc = plan.document(name: name) else { return }
        let p = NSSavePanel()
        if let d = displayedFolder { p.directoryURL = URL(fileURLWithPath: d) }
        p.nameFieldStringValue = name + ".gpx"
        p.prompt = "Save"
        guard p.runModal() == .OK, let url = p.url else { return }
        do { try doc.xml().write(to: url, atomically: true, encoding: .utf8) }
        catch { let a = NSAlert(); a.messageText = "Saving failed"; a.informativeText = error.localizedDescription; a.runModal(); return }
        pendingOpen = url.path
        reloadTree()
    }
}
