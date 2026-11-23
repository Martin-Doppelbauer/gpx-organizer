import SwiftUI
import AppKit
import BCCore
import Combine

/// The online maps in the map menu. They are kept in the preferences; "Reset" brings back the original four.
final class OnlineMapStore: ObservableObject {
    static let mapDefaults: [TileSource] = [
        TileSource(id: "online:opentopomap", name: "OpenTopoMap (Topo, worldwide)",
                   template: "https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png", subdomains: ["a", "b", "c"], maxZoom: 17,
                   attribution: "Map data © OpenStreetMap contributors, SRTM | Rendering © OpenTopoMap (CC-BY-SA)"),
        TileSource(id: "online:topplusopen", name: "TopPlusOpen (Topo, Germany/Europe)",
                   template: "https://sgx.geodatenzentrum.de/wmts_topplus_open/tile/1.0.0/web/default/WEBMERCATOR/{z}/{y}/{x}.png", subdomains: [], maxZoom: 18,
                   attribution: "© Federal Agency for Cartography and Geodesy (TopPlusOpen), data sources: sg.geodatenzentrum.de"),
        TileSource(id: "online:topplusopen-grau", name: "TopPlusOpen gray",
                   template: "https://sgx.geodatenzentrum.de/wmts_topplus_open/tile/1.0.0/web_grau/default/WEBMERCATOR/{z}/{y}/{x}.png", subdomains: [], maxZoom: 18,
                   attribution: "© Federal Agency for Cartography and Geodesy (TopPlusOpen), data sources: sg.geodatenzentrum.de"),
        TileSource(id: "online:osm", name: "OpenStreetMap (Standard)",
                   template: "https://tile.openstreetmap.org/{z}/{x}/{y}.png", subdomains: [], maxZoom: 19,
                   attribution: "© OpenStreetMap contributors")
    ]

    static let imageryDefaults: [TileSource] = [
        TileSource(id: "online:img-esri", name: "Esri World Imagery", template: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
                   subdomains: [], maxZoom: 19, attribution: "Tiles © Esri — Source: Esri, Maxar, Earthstar Geographics, and the GIS User Community"),
        TileSource(id: "online:img-eox", name: "Sentinel-2 cloudless (EOX)", template: "https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2024_3857/default/g/{z}/{y}/{x}.jpg",
                   subdomains: [], maxZoom: 13, attribution: "Sentinel-2 cloudless 2024 by EOX IT Services GmbH (contains modified Copernicus Sentinel data 2024), CC BY-NC-SA 4.0")
    ]

    /// The list of online maps, and the list of aerial imagery.
    static let shared = OnlineMapStore(key: "onlineMaps", defaults: mapDefaults, idPrefix: "online:c-", kind: "maps")
    static let imagery = OnlineMapStore(key: "aerialMaps", defaults: imageryDefaults, idPrefix: "online:img-c-", kind: "imagery")

    @Published private(set) var sources: [TileSource]
    let key: String, defaults: [TileSource], idPrefix: String, kind: String

    init(key: String, defaults: [TileSource], idPrefix: String, kind: String) {
        self.key = key; self.defaults = defaults; self.idPrefix = idPrefix; self.kind = kind
        if let d = UserDefaults.standard.data(forKey: key), let list = try? JSONDecoder().decode([TileSource].self, from: d), !list.isEmpty { sources = list }
        else { sources = defaults }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(sources) { UserDefaults.standard.set(d, forKey: key) }
    }

    /// A folder-safe id that is not used yet; a map keeps its id (and so its tile cache) as long as its address stays the same.
    func newID(for template: String) -> String {
        var h: UInt64 = 1469598103934665603
        for b in template.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        var id = idPrefix + String(h, radix: 16).prefix(8)
        var n = 2
        while sources.contains(where: { $0.id == id }) { id = idPrefix + String(h, radix: 16).prefix(8) + "-\(n)"; n += 1 }
        return id
    }

    func contains(template: String) -> Bool { sources.contains { $0.template == template } }

    func add(_ s: TileSource) { sources.append(s); save() }
    func replace(_ oldID: String, with s: TileSource) { if let i = sources.firstIndex(where: { $0.id == oldID }) { sources[i] = s; save() } }
    func update(_ s: TileSource) { if let i = sources.firstIndex(where: { $0.id == s.id }) { sources[i] = s; save() } }
    func remove(_ id: String) { sources.removeAll { $0.id == id }; save() }
    func move(_ id: String, by delta: Int) {
        guard let i = sources.firstIndex(where: { $0.id == id }), sources.indices.contains(i + delta) else { return }
        sources.swapAt(i, i + delta); save()
    }
    func move(_ id: String, before target: String) {
        guard let i = sources.firstIndex(where: { $0.id == id }), let j = sources.firstIndex(where: { $0.id == target }), i != j else { return }
        let s = sources.remove(at: i); sources.insert(s, at: j); save()
    }
    func reset() { sources = defaults; save() }
}

extension AppModel {
    /// Keeps the menus in step with Settings → Maps / Aerial; a removed map that was shown is replaced.
    func observeOnlineMaps() {
        NotificationCenter.default.addObserver(forName: .onlineMapIDChanged, object: nil, queue: .main) { [weak self] n in
            guard let self, let old = n.userInfo?["old"] as? String, let new = n.userInfo?["new"] as? String else { return }
            if (n.userInfo?["kind"] as? String) == "imagery" { if self.aerialID == old { self.aerialID = new } }
            else if self.selectedMapID == old { self.selectedMapID = new; UserDefaults.standard.set(new, forKey: "mapID") }
        }
        onlineMapsSink = OnlineMapStore.shared.$sources.dropFirst().sink { [weak self] list in
            DispatchQueue.main.async {
                guard let self else { return }
                self.onlineSources = list
                if let id = self.selectedMapID, id.hasPrefix("online:"), !list.contains(where: { $0.id == id }) {
                    if let first = list.first { self.selectMap(first.id) }
                    else if let g = self.maps.first(where: { $0.isSupported }) { self.selectMap(g.id) }
                }
                self.viewRevision += 1
            }
        }
        imagerySink = OnlineMapStore.imagery.$sources.dropFirst().sink { [weak self] list in
            DispatchQueue.main.async {
                guard let self else { return }
                self.imagerySources = list
                if let id = self.aerialID, !list.contains(where: { $0.id == id }) { self.aerialID = list.first?.id }
                self.viewRevision += 1
            }
        }
    }
}

// MARK: Settings page

final class MapsPageState: ObservableObject {
    @Published var selection: String?
    @Published var editing: TileSource?
    @Published var adding = false
    static var dragging: String?
}

struct MapsSettingsView: View {
    @ObservedObject var store: OnlineMapStore
    let heading: String
    let intro: String
    let footer: String
    let suggestions: (Continent) -> [CatalogMap]
    @StateObject private var st = MapsPageState()

    var body: some View {
        Form {
            Section {
                Text(intro)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                List {
                    ForEach(store.sources) { s in
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.name).lineLimit(1)
                                Text(s.template).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(st.selection == s.id ? Color.accentColor.opacity(0.25) : Color.clear))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { st.selection = s.id; st.editing = s }
                        .onTapGesture { st.selection = s.id }
                        .onDrag { MapsPageState.dragging = s.id; return NSItemProvider(object: s.id as NSString) }
                        .onDrop(of: [.text], delegate: MapRowDrop(store: store, target: s.id))
                    }
                }
                .frame(height: 230)
                HStack {
                    Button { st.adding = true } label: { Label("Add …", systemImage: "plus") }
                    Button { if let s = store.sources.first(where: { $0.id == st.selection }) { st.editing = s } } label: { Label("Edit …", systemImage: "pencil") }
                        .disabled(st.selection == nil)
                    Button { remove() } label: { Label("Remove", systemImage: "minus") }.disabled(st.selection == nil)
                    Spacer()
                    Button { if let id = st.selection { store.move(id, by: -1) } } label: { Image(systemName: "chevron.up") }.disabled(st.selection == nil)
                    Button { if let id = st.selection { store.move(id, by: 1) } } label: { Image(systemName: "chevron.down") }.disabled(st.selection == nil)
                }
                .controlSize(.small)
                HStack {
                    Text("\(store.sources.count) entries").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset to Original List …") { reset() }
                }
            } header: { Text(heading).font(.headline) }
            Section {
                Text(footer)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $st.editing) { MapEditSheet(source: $0, store: store) }
        .sheet(isPresented: $st.adding) { AddMapSheet(store: store, title: heading, suggestions: suggestions) }
    }

    private func remove() {
        guard let id = st.selection, let s = store.sources.first(where: { $0.id == id }) else { return }
        let a = NSAlert()
        a.messageText = "Remove “\(s.name)” from the list?"
        a.informativeText = "The tiles already downloaded stay on disk (Settings → Storage). You can add the map again later."
        a.addButton(withTitle: "Remove"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        store.remove(id); st.selection = nil
    }

    private func reset() {
        let a = NSAlert()
        a.messageText = "Restore the original list of maps?"
        a.informativeText = "Your own entries are removed and the original ones come back: " + store.defaults.map(\.name).joined(separator: ", ") + "."
        a.addButton(withTitle: "Reset"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        store.reset(); st.selection = nil
    }
}

struct MapRowDrop: DropDelegate {
    let store: OnlineMapStore
    let target: String
    func dropEntered(info: DropInfo) {
        guard let d = MapsPageState.dragging, d != target else { return }
        withAnimation(.easeInOut(duration: 0.15)) { store.move(d, before: target) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { MapsPageState.dragging = nil; return true }
}

// MARK: edit one map

final class MapEditState: ObservableObject {
    @Published var name: String
    @Published var template: String
    @Published var subdomains: String
    @Published var maxZoom: Int
    @Published var attribution: String
    @Published var testResult = ""
    @Published var testImage: NSImage?
    @Published var testing = false
    let original: TileSource?
    init(_ s: TileSource?) {
        original = s
        name = s?.name ?? ""; template = s?.template ?? "https://"; subdomains = (s?.subdomains ?? []).joined(separator: ","); maxZoom = s?.maxZoom ?? 18; attribution = s?.attribution ?? ""
    }
    var subs: [String] { subdomains.split { $0 == "," || $0 == " " }.map(String.init) }
}

struct MapEditSheet: View {
    let source: TileSource
    let store: OnlineMapStore
    @StateObject private var e: MapEditState
    @Environment(\.dismiss) private var dismiss
    init(source: TileSource, store: OnlineMapStore) { self.source = source; self.store = store; _e = StateObject(wrappedValue: MapEditState(source)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit Map").font(.headline)
            Form {
                TextField("Name", text: $e.name)
                TextField("Address", text: $e.template, axis: .vertical).lineLimit(2...4)
                TextField("Subdomains", text: $e.subdomains, prompt: Text("a,b,c (only for {s})"))
                Stepper("Highest zoom level: \(e.maxZoom)", value: $e.maxZoom, in: 1...22)
                TextField("Attribution", text: $e.attribution, axis: .vertical).lineLimit(1...3)
            }
            .formStyle(.columns)
            Text("In the address: {z} zoom level, {x} column, {y} row (or {-y} when the rows count from the bottom), {s} one of the subdomains.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Test") { test() }.disabled(e.testing)
                if e.testing { ProgressView().controlSize(.small) }
                Text(e.testResult).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let i = e.testImage { Image(nsImage: i).resizable().frame(width: 64, height: 64).cornerRadius(4) }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction)
                    .disabled(e.name.trimmingCharacters(in: .whitespaces).isEmpty || MapDiscovery.normalize(e.template) == nil)
            }
        }
        .padding(16)
        .frame(width: 520)
    }

    private func test() {
        guard let n = MapDiscovery.normalize(e.template) else { e.testResult = "The address needs {z}, {x} and {y}."; return }
        e.testing = true; e.testResult = ""; e.testImage = nil
        let subs = e.subs.isEmpty ? n.subdomains : e.subs
        Task {
            let d = await MapDiscovery.probe(n.template, subs)
            await MainActor.run {
                e.testing = false
                if let d { e.testResult = "Tiles load."; e.testImage = NSImage(data: d) } else { e.testResult = "No test tile could be loaded." }
            }
        }
    }

    private func save() {
        guard let n = MapDiscovery.normalize(e.template) else { return }
        var s = source
        let changedAddress = n.template != source.template
        s.name = e.name.trimmingCharacters(in: .whitespaces); s.template = n.template
        s.subdomains = n.template.contains("{s}") ? (e.subs.isEmpty ? (n.subdomains.isEmpty ? ["a", "b", "c"] : n.subdomains) : e.subs) : []
        s.maxZoom = e.maxZoom; s.attribution = e.attribution
        if changedAddress {          // another address means other pictures: a new cache folder, so old and new tiles never mix
            let oldID = s.id
            s.id = store.newID(for: n.template)
            NotificationCenter.default.post(name: .onlineMapIDChanged, object: nil, userInfo: ["old": oldID, "new": s.id, "kind": store.kind])
            store.replace(oldID, with: s)
        } else { store.update(s) }
        dismiss()
    }
}

extension Notification.Name { static let onlineMapIDChanged = Notification.Name("onlineMapIDChanged") }

// MARK: add maps

final class AddMapState: ObservableObject {
    @Published var continent: Continent = .europe
    @Published var chosen: Set<String> = []          // templates
    @Published var address = ""
    @Published var searching = false
    @Published var status = ""
    @Published var found: [MapCandidate] = []
    @Published var notes: [String] = []
    @Published var filter = ""
    var task: Task<Void, Never>?
}

struct AddMapSheet: View {
    @StateObject private var a = AddMapState()
    @ObservedObject var store: OnlineMapStore
    let title: String
    let suggestions: (Continent) -> [CatalogMap]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add to “\(title)”").font(.headline)
            HStack(alignment: .top, spacing: 12) {
                List(Continent.allCases, selection: Binding(get: { a.continent }, set: { if let c = $0 { a.continent = c } })) { c in
                    Text(c.title).tag(c)
                }
                .frame(width: 170)
                VStack(alignment: .leading, spacing: 6) {
                    if !a.found.isEmpty {
                        TextField("Filter the \(a.found.count) found maps", text: $a.filter).textFieldStyle(.roundedBorder)
                    }
                    List {
                        if !a.found.isEmpty {
                            Section("Found at the address") {
                                ForEach(a.found.filter { a.filter.isEmpty || ($0.name + $0.template).localizedCaseInsensitiveContains(a.filter) }) { c in
                                    row(name: c.name, detail: c.note.isEmpty ? c.template : "\(c.note) · \(c.template)", template: c.template, preview: c.preview)
                                }
                            }
                        }
                        Section("Suggestions for \(a.continent.title)") {
                            ForEach(suggestions(a.continent)) { m in
                                row(name: m.name, detail: m.note, template: m.template, preview: nil)
                            }
                        }
                    }
                }
            }
            .frame(height: 300)
            VStack(alignment: .leading, spacing: 4) {
                Text("Or a web address").font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    TextField("Address of a map, a tile server, or a web page with a map (typing errors are tolerated)", text: $a.address)
                        .textFieldStyle(.roundedBorder).onSubmit { search() }
                    Button(a.searching ? "Stop" : "Search") { a.searching ? stop() : search() }.disabled(!a.searching && a.address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if a.searching { HStack { ProgressView().controlSize(.small); Text(a.status).font(.caption).foregroundStyle(.secondary) } }
                ForEach(a.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            }
            HStack {
                Text(a.chosen.isEmpty ? "Tick the maps to add" : "\(a.chosen.count) selected").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { stop(); dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add Selected") { addSelected() }.keyboardShortcut(.defaultAction).disabled(a.chosen.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 740)
    }

    private func row(name: String, detail: String, template: String, preview: Data?) -> some View {
        let have = store.contains(template: template)
        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { a.chosen.contains(template) || have }, set: { on in if on { a.chosen.insert(template) } else { a.chosen.remove(template) } }))
                .labelsHidden().disabled(have)
            if let p = preview, let img = NSImage(data: p) { Image(nsImage: img).resizable().frame(width: 36, height: 36).cornerRadius(3) }
            VStack(alignment: .leading, spacing: 1) {
                Text(name).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if have { Text("in your list").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func search() {
        a.searching = true; a.found = []; a.notes = []; a.status = "Starting …"; a.filter = ""
        let addr = a.address
        a.task = Task {
            let r = await MapDiscovery.discover(addr, progress: { msg in DispatchQueue.main.async { a.status = msg } })
            await MainActor.run {
                if Task.isCancelled { return }
                a.found = r.candidates; a.notes = r.notes; a.searching = false
                if r.candidates.count == 1 { a.chosen.insert(r.candidates[0].template) }       // one result: ticked, still asked
                else if r.candidates.isEmpty && r.notes.isEmpty { a.notes = ["Nothing found at that address."] }
            }
        }
    }

    private func stop() { a.task?.cancel(); a.searching = false }

    private func addSelected() {
        let sug = MapCatalog.entries + MapCatalog.imageryEntries
        for t in a.chosen where !store.contains(template: t) {
            if let c = a.found.first(where: { $0.template == t }) {
                store.add(TileSource(id: store.newID(for: t), name: c.name, template: t, subdomains: c.subdomains, maxZoom: c.maxZoom,
                                     attribution: c.attribution.isEmpty ? "© " + (URL(string: t.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: ""))?.host ?? "map server") : c.attribution))
            } else if let m = sug.first(where: { $0.template == t }) {
                // the four original maps keep their old ids (and their tile folders)
                let orig = store.defaults.first { $0.template == t }
                store.add(TileSource(id: orig?.id ?? store.newID(for: t), name: m.name, template: t, subdomains: m.subdomains, maxZoom: m.maxZoom, attribution: m.attribution))
            }
        }
        stop(); dismiss()
    }
}
