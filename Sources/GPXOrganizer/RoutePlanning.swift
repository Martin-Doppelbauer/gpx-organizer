import SwiftUI
import AppKit
import BCCore

// MARK: saving a planned route

enum RouteSaveMode: Hashable {
    case track          // complete route: track with all points
    case routePoints    // planned route: only the route points, the device calculates the way itself
    case routeWithVias  // planned route with additional via points along the way
}

final class SaveRouteDraft: ObservableObject, Identifiable {
    let id = UUID()
    @Published var name: String
    @Published var mode: RouteSaveMode = .track
    @Published var waypoints = true          // track: also keep the route points as waypoints
    @Published var viaEveryKm = 10.0
    init(name: String) { self.name = name }
}

/// A point of a saved route.
struct RtePoint { var lat: Double, lon: Double, ele: Double?, name: String }

extension PlanSession {
    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Distance from the route start to every route point, in metres.
    func cumulative(_ pts: [(lat: Double, lon: Double)]) -> [Double] {
        var c = [0.0]
        for i in 1..<max(1, pts.count) {
            let dy = (pts[i].lat - pts[i - 1].lat) * 111_320
            let dx = (pts[i].lon - pts[i - 1].lon) * 111_320 * cos(pts[i].lat * .pi / 180)
            c.append(c[i - 1] + hypot(dx, dy))
        }
        return c
    }

    /// The user's route points (and, for `.routeWithVias`, extra via points about every `everyKm` km), in route order.
    func routePoints(extraEveryKm: Double?) -> [RtePoint] {
        guard let r = result, r.viaIndex.count == vias.count else { return [] }
        func ele(_ k: Int) -> Double? { k < r.elevations.count ? r.elevations[k] : nil }
        var all: [(Int, RtePoint)] = vias.enumerated().map { i, v in
            (r.viaIndex[i], RtePoint(lat: v.lat, lon: v.lon, ele: ele(r.viaIndex[i]), name: title(i)))
        }
        if let every = extraEveryKm, every > 0, vias.count >= 2 {
            let cum = cumulative(r.points)
            var extra: [(Int, RtePoint)] = []
            var last = 0.0
            var next = 1
            var k = 1
            while k < r.points.count, next < r.viaIndex.count {
                if k >= r.viaIndex[next] { last = cum[r.viaIndex[next]]; next += 1; k += 1; continue }
                if cum[k] - last >= every * 1000, cum[r.viaIndex[next]] - cum[k] > every * 500 {
                    extra.append((k, RtePoint(lat: r.points[k].lat, lon: r.points[k].lon, ele: ele(k), name: "")))
                    last = cum[k]
                }
                k += 1
            }
            for (n, e) in extra.enumerated() { var p = e.1; p.name = "Via \(n + 1)"; all.append((e.0, p)) }
        }
        return all.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    /// GPX text of a planned route (`<rte>` with named route points).
    func routeXML(name: String, points: [RtePoint]) -> String {
        var o = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        o += "<gpx version=\"1.1\" creator=\"GPX Organizer\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n"
        o += "  <metadata><name>\(esc(name))</name></metadata>\n  <rte>\n    <name>\(esc(name))</name>\n"
        for p in points {
            o += "    <rtept lat=\"\(String(format: "%.7f", p.lat))\" lon=\"\(String(format: "%.7f", p.lon))\">"
            if let e = p.ele { o += "<ele>\(String(format: "%.1f", e))</ele>" }
            if !p.name.isEmpty { o += "<name>\(esc(p.name))</name>" }
            o += "</rtept>\n"
        }
        o += "  </rte>\n</gpx>\n"
        return o
    }

    /// Text to save for the chosen mode; nil when there is no route.
    func gpxText(_ d: SaveRouteDraft) -> String? {
        switch d.mode {
        case .track: return document(name: d.name, waypoints: d.waypoints)?.xml()
        case .routePoints: let p = routePoints(extraEveryKm: nil); return p.isEmpty ? nil : routeXML(name: d.name, points: p)
        case .routeWithVias: let p = routePoints(extraEveryKm: d.viaEveryKm); return p.isEmpty ? nil : routeXML(name: d.name, points: p)
        }
    }
}

struct SaveRouteSheet: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var d: SaveRouteDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Route").font(.headline)
            TextField("Name", text: $d.name)
            Picker("", selection: $d.mode) {
                Text("Complete route (a track with all points)").tag(RouteSaveMode.track)
                Text("Planned route (only my route points; the device calculates the way itself)").tag(RouteSaveMode.routePoints)
                Text("Planned route with additional via points along the way").tag(RouteSaveMode.routeWithVias)
            }
            .pickerStyle(.radioGroup).labelsHidden()
            if d.mode == .track {
                Toggle("For the track: also keep my route points as waypoints", isOn: $d.waypoints).padding(.leading, 20)
            }
            if d.mode == .routeWithVias {
                HStack {
                    Text("A via point about every").padding(.leading, 20)
                    TextField("", value: $d.viaEveryKm, format: .number).frame(width: 50).multilineTextAlignment(.trailing)
                    Text("km")
                }
            }
            Text(d.mode == .track ? "A GPX track: the route exactly as calculated here. Large, but every device shows it unchanged."
                 : "A GPX route: small. A device or app that supports routes calculates the way between the points itself, with its own maps.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { model.saveRouteDraft = nil; dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save …") { model.writePlannedRoute(d) }.keyboardShortcut(.defaultAction).disabled(d.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 460)
    }
}

// MARK: stages (trip planner light)

final class StagesDraft: ObservableObject, Identifiable {
    enum Basis: String, CaseIterable { case distance = "By distance", ascent = "By ascent" }
    struct Stage: Identifiable {
        let id: Int
        let startIndex: Int, endIndex: Int          // route point indices
        let km: Double, up: Double, down: Double
    }
    let id = UUID()
    @Published var name: String
    @Published var basis: Basis = .distance { didSet { recompute() } }
    @Published var limitKm = 25.0 { didSet { recompute() } }
    @Published var limitUp = 800.0 { didSet { recompute() } }
    @Published private(set) var stages: [Stage] = []
    @Published private(set) var note = ""
    let points: [(lat: Double, lon: Double)]
    let elevations: [Double?]
    let cum: [Double]

    init(name: String, points: [(lat: Double, lon: Double)], elevations: [Double?], cum: [Double]) {
        self.name = name; self.points = points; self.elevations = elevations; self.cum = cum
        recompute()
    }

    var hasElevation: Bool { elevations.contains { $0 != nil } }

    /// Ascent and descent of route points a…b with a 4 m hysteresis (small noise does not count).
    func climb(_ a: Int, _ b: Int) -> (up: Double, down: Double) {
        var e: [Double] = []
        var lastKnown: Double?
        for i in a...b { if let v = i < elevations.count ? elevations[i] : nil { lastKnown = v }; if let l = lastKnown { e.append(l) } }
        guard let first = e.first else { return (0, 0) }
        var base = first, up = 0.0, down = 0.0
        for v in e {
            if v - base >= 4 { up += v - base; base = v } else if base - v >= 4 { down += base - v; base = v }
        }
        return (up, down)
    }

    func recompute() {
        guard points.count >= 2, let total = cum.last, total > 0 else { stages = []; note = "No route yet."; return }
        var cutIdx: [Int] = []
        switch basis {
        case .distance:
            let n = max(1, Int((total / 1000 / max(1, limitKm)).rounded(.up)))
            for k in 1..<max(1, n) { let t = total * Double(k) / Double(n); cutIdx.append(cum.firstIndex { $0 >= t } ?? points.count - 1) }
            note = n == 1 ? "The whole route fits into one day." : "\(n) days of about " + String(format: "%.1f km", total / 1000 / Double(n))
        case .ascent:
            guard hasElevation else { stages = []; note = "No elevation data for this route yet (wait a moment or use another map)."; return }
            var cumUp = [0.0]
            var e = 0.0, base: Double?
            var lastKnown: Double?
            for i in 1..<points.count {
                if let v = elevations[i] ?? lastKnown { lastKnown = v
                    if base == nil { base = v }
                    if v - base! >= 4 { e += v - base!; base = v } else if base! - v >= 4 { base = v }
                }
                cumUp.append(e)
            }
            let totalUp = cumUp.last ?? 0
            let n = max(1, Int((totalUp / max(1, limitUp)).rounded(.up)))
            for k in 1..<max(1, n) { let t = totalUp * Double(k) / Double(n); cutIdx.append(cumUp.firstIndex { $0 >= t } ?? points.count - 1) }
            note = n == 1 ? "The whole route fits into one day." : "\(n) days of about " + String(format: "%.0f m ascent", totalUp / Double(n))
        }
        var edges = [0] + cutIdx + [points.count - 1]
        edges = edges.enumerated().filter { i, v in i == 0 || v > edges[i - 1] }.map { $0.element }      // no empty days
        stages = (1..<edges.count).map { i in
            let a = edges[i - 1], b = edges[i]
            let c = climb(a, b)
            return Stage(id: i, startIndex: a, endIndex: b, km: (cum[b] - cum[a]) / 1000, up: c.up, down: c.down)
        }
    }
}

struct StagesSheet: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var d: StagesDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plan Stages").font(.headline)
            Picker("", selection: $d.basis) {
                ForEach(StagesDraft.Basis.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            HStack {
                if d.basis == .distance {
                    Text("At most"); TextField("", value: $d.limitKm, format: .number).frame(width: 60).multilineTextAlignment(.trailing); Text("km per day")
                } else {
                    Text("At most"); TextField("", value: $d.limitUp, format: .number).frame(width: 60).multilineTextAlignment(.trailing); Text("m of ascent per day")
                }
                Spacer()
            }
            Text(d.note).font(.caption).foregroundStyle(.secondary)
            List(d.stages) { s in
                HStack {
                    Text("Day \(s.id)").bold().frame(width: 50, alignment: .leading)
                    Text(String(format: "%.1f km", s.km)).monospacedDigit().frame(width: 70, alignment: .trailing)
                    if d.hasElevation { Text(String(format: "↑ %.0f m  ↓ %.0f m", s.up, s.down)).monospacedDigit().foregroundStyle(.secondary) }
                    Spacer()
                    Text(String(format: "ends at km %.1f", d.cum[s.endIndex] / 1000)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(height: 180)
            HStack {
                TextField("Name", text: $d.name)
            }
            HStack {
                Button("Add Overnight Points to the Route") { model.addOvernightPoints(d); dismiss() }
                    .disabled(d.stages.count < 2)
                    .help("Inserts a route point named “Overnight 1”, “Overnight 2” … where each day ends")
                Button("Save Days as Files …") { model.saveStageFiles(d) }.disabled(d.stages.count < 2)
                Spacer()
                Button("Close") { model.stagesDraft = nil; dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 520)
    }
}

extension AppModel {
    func startSaveRoute() {
        guard let plan, plan.result != nil else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        saveRouteDraft = SaveRouteDraft(name: "Route \(plan.profile.title) \(f.string(from: Date()))")
    }

    /// Asks where to save, then writes the route in the chosen form.
    func writePlannedRoute(_ d: SaveRouteDraft) {
        guard let plan, let text = plan.gpxText(d) else { return }
        let p = NSSavePanel()
        if let dir = displayedFolder { p.directoryURL = URL(fileURLWithPath: dir) }
        p.nameFieldStringValue = d.name + ".gpx"
        p.prompt = "Save"
        guard p.runModal() == .OK, let url = p.url else { return }
        do { try text.write(to: url, atomically: true, encoding: .utf8) }
        catch { let a = NSAlert(); a.messageText = "Saving failed"; a.informativeText = error.localizedDescription; a.runModal(); return }
        saveRouteDraft = nil
        pendingOpen = url.path
        reloadTree()
    }

    func startStages() {
        guard let plan, let r = plan.result, r.points.count >= 2 else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        stagesDraft = StagesDraft(name: "Route \(plan.profile.title) \(f.string(from: Date()))", points: r.points,
                                  elevations: r.elevations, cum: plan.cumulative(r.points))
    }

    /// Inserts a route point where each day ends; the route itself does not change (they lie on it).
    func addOvernightPoints(_ d: StagesDraft) {
        guard let plan, let r = plan.result, r.viaIndex.count == plan.vias.count else { return }
        var n = d.stages.count - 1
        for s in d.stages.dropLast().reversed() {
            let k = s.endIndex
            var leg = 0
            for i in 0..<(r.viaIndex.count - 1) where k >= r.viaIndex[i] { leg = i }
            plan.insertNamed(at: leg + 1, lat: r.points[k].lat, lon: r.points[k].lon, name: "Overnight \(n)")
            n -= 1
        }
        stagesDraft = nil
        plan.recompute()
    }

    /// One GPX track per day in a folder to choose.
    func saveStageFiles(_ d: StagesDraft) {
        let p = NSOpenPanel()
        p.message = "Choose the folder for the files of the days"
        p.prompt = "Save Here"
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        if let dir = displayedFolder { p.directoryURL = URL(fileURLWithPath: dir) }
        guard p.runModal() == .OK, let folder = p.url else { return }
        let fm = FileManager.default
        var last: URL?
        for s in d.stages {
            let name = "\(d.name) – Day \(s.id)"
            var doc = GPXDocument(name: name)
            let seg = (s.startIndex...s.endIndex).map { i in
                GPXPoint(lat: d.points[i].lat, lon: d.points[i].lon, ele: i < d.elevations.count ? d.elevations[i] : nil)
            }
            doc.tracks = [GPXTrackData(name: name, isRoute: false, segments: [seg])]
            doc.waypoints = [GPXWaypoint(point: seg.first!, name: s.id == 1 ? "Start" : "Day \(s.id) start"),
                             GPXWaypoint(point: seg.last!, name: s.id == d.stages.count ? "End" : "Day \(s.id) end")]
            var url = folder.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-") + ".gpx")
            var n = 2
            while fm.fileExists(atPath: url.path) { url = folder.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-") + " \(n).gpx"); n += 1 }
            do { try doc.xml().write(to: url, atomically: true, encoding: .utf8); last = url }
            catch { let a = NSAlert(); a.messageText = "Saving failed"; a.informativeText = error.localizedDescription; a.runModal(); return }
        }
        stagesDraft = nil
        if let last { pendingOpen = last.path }
        reloadTree()
    }

    /// Menu: start/finish a route at a point (a marker's position and heading when a marker was clicked).
    func startRoute(lat: Double, lon: Double, name: String, finish: Bool) {
        if plan == nil { startPlanning() }
        guard let plan else { return }
        if finish { plan.finishAt(lat: lat, lon: lon, name: name) } else { plan.startAt(lat: lat, lon: lon, name: name) }
    }
}
