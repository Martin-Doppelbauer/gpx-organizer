import SwiftUI
import BCCore

/// Speed limits for the automatic track icons and the default track colors per kind; stored in the user defaults
/// and applied to the track classifier.
final class KindSettings: ObservableObject {
    static let shared = KindSettings()
    @Published var t: KindThresholds { didSet { if t != oldValue { apply() } } }
    @Published var colors: [TrackKind: [Double]] { didSet { applyColors() } }

    /// The kinds that have a color of their own in Settings ("Planned" shares the color of "Track").
    static let colored: [TrackKind] = [.hike, .run, .bike, .car, .other]

    init() {
        let d = UserDefaults.standard
        var k = KindThresholds()
        if d.object(forKey: "kind.hikeMax") != nil {
            k.hikeMax = d.double(forKey: "kind.hikeMax"); k.bikeMin = d.double(forKey: "kind.bikeMin")
            k.bikeMax = d.double(forKey: "kind.bikeMax"); k.carMin = d.double(forKey: "kind.carMin")
            if d.object(forKey: "kind.runMax") != nil { k.runMax = d.double(forKey: "kind.runMax") }
            k.runMax = max(k.runMax, k.hikeMax); k.bikeMin = max(k.bikeMin, k.runMax)
            k.bikeMax = max(k.bikeMax, k.bikeMin); k.carMin = max(k.carMin, k.bikeMax)
        }
        t = k
        GPXFile.kindThresholds = k
        var c = GPXFile.defaultKindColors
        for kind in TrackKind.allCases { if let v = d.array(forKey: "kind.color.\(kind.rawValue)") as? [Double], v.count == 3 { c[kind] = v } }
        colors = c
        GPXFile.kindColors = c
    }

    private func apply() {
        var k = t                                   // keep the limits in order
        k.runMax = max(k.runMax, k.hikeMax)
        k.bikeMin = max(k.bikeMin, k.runMax)
        k.bikeMax = max(k.bikeMax, k.bikeMin)
        k.carMin = max(k.carMin, k.bikeMax)
        if k != t { t = k; return }
        let d = UserDefaults.standard
        d.set(k.hikeMax, forKey: "kind.hikeMax"); d.set(k.runMax, forKey: "kind.runMax"); d.set(k.bikeMin, forKey: "kind.bikeMin")
        d.set(k.bikeMax, forKey: "kind.bikeMax"); d.set(k.carMin, forKey: "kind.carMin")
        GPXFile.kindThresholds = k
        NotificationCenter.default.post(name: .kindThresholdsChanged, object: nil)
    }

    private func applyColors() {
        var c = colors
        c[.planned] = c[.other]                       // planned tracks use the color of "Track"
        let d = UserDefaults.standard
        for kind in Self.colored { if let v = c[kind] { d.set(v, forKey: "kind.color.\(kind.rawValue)") } }
        GPXFile.kindColors = c
        NotificationCenter.default.post(name: .kindColorsChanged, object: nil)
    }

    func color(_ kind: TrackKind) -> Color {
        let v = colors[kind] ?? GPXFile.defaultKindColors[kind] ?? [0.5, 0.5, 0.5]
        return Color(red: v[0], green: v[1], blue: v[2])
    }
    func setColor(_ kind: TrackKind, _ c: Color) {
        guard let n = NSColor(c).usingColorSpace(.sRGB) else { return }
        colors[kind] = [Double(n.redComponent), Double(n.greenComponent), Double(n.blueComponent)]
    }
    func resetColors() {
        var c = colors
        for kind in Self.colored { c[kind] = GPXFile.defaultKindColors[kind] }
        colors = c
    }
}

extension Notification.Name { static let markerSizeChanged = Notification.Name("markerSizeChanged"); static let mapsFolderChanged = Notification.Name("mapsFolderChanged"); static let kindThresholdsChanged = Notification.Name("kindThresholdsChanged"); static let kindColorsChanged = Notification.Name("kindColorsChanged") }

/// Size limit of the online map tile cache on disk.
final class MapsFolderSettings: ObservableObject {
    @Published var path = AppSettings.mapsRoot.path
    func choose() {
        let p = NSOpenPanel()
        p.message = L("Choose the folder for your maps (Garmin maps and the online map tile cache)")
        p.prompt = L("Use This Folder")
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.directoryURL = AppSettings.mapsRoot
        if p.runModal() == .OK, let u = p.url { set(u) }
    }
    func set(_ u: URL) {
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        AppSettings.prepareMapsFolder(u)
        UserDefaults.standard.set(u.path, forKey: "mapsFolder")
        path = u.path
        TileCache.shared.reconfigure()
        NotificationCenter.default.post(name: .mapsFolderChanged, object: nil)
    }
}

/// Where the tiles of the online maps are cached (default: "Online Maps" inside the maps folder).
final class TilesFolderSettings: ObservableObject {
    @Published var path = TileCache.shared.root.path
    @Published var isCustom = AppSettings.customTilesFolder != nil
    var onChange: (() -> Void)?
    private var obs: NSObjectProtocol?
    init() {
        obs = NotificationCenter.default.addObserver(forName: .mapsFolderChanged, object: nil, queue: .main) { [weak self] _ in
            self?.path = TileCache.shared.root.path
        }
    }

    func choose() {
        let p = NSOpenPanel()
        p.message = L("Choose the folder for the cache of the online maps")
        p.prompt = L("Use This Folder")
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.directoryURL = TileCache.shared.root.deletingLastPathComponent()
        if p.runModal() == .OK, let u = p.url { set(u) }
    }

    func useDefault() {
        UserDefaults.standard.removeObject(forKey: "tilesFolder")
        apply(from: TileCache.shared.root, to: AppSettings.defaultTilesRoot)
    }

    private func set(_ u: URL) {
        let old = TileCache.shared.root
        guard u.standardizedFileURL.path != old.standardizedFileURL.path else { return }
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        UserDefaults.standard.set(u.path, forKey: "tilesFolder")
        apply(from: old, to: u)
    }

    private func apply(from old: URL, to new: URL) {
        TileCache.shared.reconfigure()
        path = TileCache.shared.root.path
        isCustom = AppSettings.customTilesFolder != nil
        let fm = FileManager.default
        let subs = ((try? fm.contentsOfDirectory(atPath: old.path)) ?? []).filter { !$0.hasPrefix(".") }
        if old.standardizedFileURL.path != new.standardizedFileURL.path, !subs.isEmpty {
            let a = NSAlert()
            a.messageText = L("Move the tiles already downloaded?")
            a.informativeText = L("The cache in the old folder can be moved to the new one, so it is not downloaded again. Otherwise the old tiles stay where they are.")
            a.addButton(withTitle: L("Move Tiles")); a.addButton(withTitle: L("Leave Them"))
            if a.runModal() == .alertFirstButtonReturn {
                let dest = TileCache.shared.root
                for n in subs {
                    let from = old.appendingPathComponent(n), to = dest.appendingPathComponent(n)
                    if fm.fileExists(atPath: to.path) { continue }
                    try? fm.moveItem(at: from, to: to)
                }
            }
        }
        onChange?()
    }
}

final class MarkerSettings: ObservableObject {
    @Published var index = MarkerSize.index {
        didSet { MarkerSize.index = index; NotificationCenter.default.post(name: .markerSizeChanged, object: nil) }
    }
}

final class CacheSettings: ObservableObject {
    static let steps = [100, 250, 500, 1000, 2000, 5000, 10000]            // MB
    @Published var index: Int {
        didSet {
            let mb = Self.steps[max(0, min(Self.steps.count - 1, index))]
            UserDefaults.standard.set(mb, forKey: "tileCacheLimitMB")
            TileCache.shared.setLimit(megabytes: mb)
        }
    }
    @Published var usage = "…"
    var limitText: String { Self.text(Self.steps[index]) }
    static func text(_ mb: Int) -> String { mb >= 1000 ? "\(mb / 1000) GB" : "\(mb) MB" }

    init() {
        let mb = UserDefaults.standard.object(forKey: "tileCacheLimitMB") as? Int ?? 2000
        index = Self.steps.lastIndex { $0 <= mb } ?? 4
    }

    func refreshUsage() {
        DispatchQueue.global(qos: .utility).async {
            let u = TileCache.shared.diskUsage()
            let size = ByteCountFormatter.string(fromByteCount: u.bytes, countStyle: .file)
            DispatchQueue.main.async { self.usage = L("%@ in %@ tiles", "\(size)", "\(u.files)") }
        }
    }

    func clear() {
        TileCache.shared.clearAll()
        refreshUsage()
    }
}

struct SettingsView: View {
    @StateObject private var k = KindSettings.shared
    @StateObject private var cache = CacheSettings()
    @StateObject private var mapsFolder = MapsFolderSettings()
    @StateObject private var marker = MarkerSettings()
    @StateObject private var tilesFolder = TilesFolderSettings()
    @AppStorage("appearanceMode") private var appearanceMode = 0
    @StateObject private var langState = LanguageState()
    private var languageNote: Bool { get { langState.changed } nonmutating set { langState.changed = newValue } }
    @AppStorage("darkMaps") private var darkMaps = true

    var body: some View {
        TabView {
        Form {
            Section {
                Picker("Language", selection: Binding(get: { AppLanguage.chosen }, set: { AppLanguage.chosen = $0; languageNote = true })) {
                    ForEach(AppLanguage.available) { l in
                        if l == .system { Text("Same as the system").tag(l) } else { Text(l.nativeName).tag(l) }
                    }
                }
                Text(languageNote ? L("The language changes when you quit the program and open it again.") : L("The program starts in the language of the system unless you choose another one here."))
                    .font(.caption).foregroundStyle(languageNote ? Color.orange : Color.secondary).fixedSize(horizontal: false, vertical: true)
            } header: { Text("Language").font(.headline) }
            Section {
                Picker("Appearance", selection: $appearanceMode) {
                    Text("Same as the system").tag(0); Text("Light").tag(1); Text("Dark").tag(2)
                }
                .pickerStyle(.radioGroup)
                .onChange(of: appearanceMode) { _ in Appearance.apply() }
                Toggle("Show the maps dark as well", isOn: $darkMaps)
                Text("In dark appearance the map colors are inverted (water stays blue, forests green); aerial images stay as they are.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } header: { Text("Appearance").font(.headline) }
            Section {
                Text("The track icon and the track color (hike, jogging, bike ride, car/motorcycle) are chosen from the average speed while moving. Speeds between two classes are shown with the neutral track icon. A color you set for a file yourself always wins.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                row(L("Hike up to"), $k.t.hikeMax, 1...15, kind: .hike)
                row(L("Jogging up to"), $k.t.runMax, 3...25, kind: .run)
                row(L("Bike ride from"), $k.t.bikeMin, 3...25, kind: .bike)
                row(L("Bike ride up to"), $k.t.bikeMax, 15...60)
                row(L("Car / motorcycle from"), $k.t.carMin, 20...120, kind: .car)
                HStack {                                          // the color of everything that is none of the above
                    Text("Other and planned tracks")
                    Spacer()
                    colorButton(.other)
                    Color.clear.frame(width: 80 + 31, height: 1)
                }
                HStack {
                    Spacer()
                    Button("Reset Speeds") { k.t = KindThresholds.standard }
                }
                HStack {
                    Spacer()
                    Button("Reset Colors") { k.resetColors() }
                }
            } header: { Text("Track icons and colors by speed").font(.headline) }
            Section {
                HStack {
                    Text("Size")
                    Slider(value: Binding(get: { Double(marker.index) }, set: { marker.index = Int($0.rounded()) }),
                           in: 0...Double(MarkerSize.factors.count - 1), step: 1)
                    Text(MarkerSize.titles[marker.index]).frame(width: 60, alignment: .trailing)
                }
            } header: { Text("Marker size").font(.headline) }
            Section {
                Text(L("Garmin maps (.gmap, .img) are found in this folder; the tiles of the online maps are cached in its \"%@\" sub-folder.", "\(AppSettings.onlineFolderName)"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(mapsFolder.path).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Spacer()
                    Button("Choose …") { mapsFolder.choose() }
                }
                HStack {
                    Spacer()
                    Button("Use Default Folder") { mapsFolder.set(AppSettings.defaultMapsFolder) }
                }
            } header: { Text("Maps folder").font(.headline) }
        }
        .formStyle(.grouped)
        .tabItem { Label("General", systemImage: "gearshape") }
        Form {
            Section {
                Text("Tiles of the online maps are kept on disk, so they load at once next time and also work offline. When the limit is reached, the oldest tiles are removed.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("Online Map Cache")
                    Slider(value: Binding(get: { Double(cache.index) }, set: { cache.index = Int($0.rounded()) }),
                           in: 0...Double(CacheSettings.steps.count - 1), step: 1)
                    Text(cache.limitText).monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                HStack {
                    Text(tilesFolder.path).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Spacer()
                    Button("Choose …") { tilesFolder.choose() }
                }
                HStack {
                    Text(tilesFolder.isCustom ? L("Own folder") : L("Default: \"%@\" in the maps folder", "\(AppSettings.onlineFolderName)"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Use Default Folder") { tilesFolder.useDefault() }.disabled(!tilesFolder.isCustom)
                }
                HStack {
                    Text(L("Currently ") + cache.usage).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear Cache") { cache.clear() }
                }
            } header: { Text("Online map cache").font(.headline) }
            PhotoSettingsSection()
        }
        .formStyle(.grouped)
        .tabItem { Label("Storage", systemImage: "externaldrive") }
        .onAppear { cache.refreshUsage(); tilesFolder.onChange = { cache.refreshUsage() } }
        MapsSettingsView(store: .shared, heading: L("Online maps"),
                         intro: L("The online maps in the map menu. Drag to change the order, or select a map and use the buttons."),
                         footer: L("The map is loaded from the server as small tiles, and kept on this Mac (Storage). Please respect the terms of use of each server; many free servers ask for an attribution, which is shown at the bottom of the map."),
                         suggestions: { MapCatalog.suggestions(for: $0) })
            .tabItem { Label("Maps", systemImage: "map") }
        MapsSettingsView(store: .imagery, heading: L("Aerial imagery"),
                         intro: L("Aerial and satellite images you can show above the map (like BirdsEye). Drag to change the order, or select an entry and use the buttons."),
                         footer: L("The images come from free servers. Their terms of use differ: some allow private use only, many ask for an attribution, which is shown at the bottom of the map."),
                         suggestions: { MapCatalog.imagerySuggestions(for: $0) })
            .tabItem { Label("Aerial", systemImage: "photo") }
        }
        .frame(width: 560, height: 620)
    }

    private let speedWidth: CGFloat = 96, colorWidth: CGFloat = 112

    private func colorButton(_ kind: TrackKind) -> some View {
        PaletteButton(rgb: k.colors[kind] ?? GPXFile.defaultKindColors[kind] ?? [0.5, 0.5, 0.5], width: colorWidth) { k.colors[kind] = $0 }
    }

    /// Name, color of the kind (all buttons equally wide) and the speed.
    private func row(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, kind: TrackKind? = nil) -> some View {
        Stepper(value: value, in: range, step: 0.5) {
            HStack {
                Text(title)
                Spacer()
                if let kind { colorButton(kind) } else { Color.clear.frame(width: colorWidth, height: 1) }
                Text(String(format: "%.1f km/h", value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
            }
        }
    }
}

/// Remembers that the language was changed in this session (to show the hint to restart).
final class LanguageState: ObservableObject { @Published var changed = false }
