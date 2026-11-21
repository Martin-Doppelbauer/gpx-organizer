import SwiftUI
import BCCore

/// Speed limits for the automatic track icons; stored in the user defaults and applied to the track classifier.
final class KindSettings: ObservableObject {
    static let shared = KindSettings()
    @Published var t: KindThresholds { didSet { if t != oldValue { apply() } } }

    init() {
        let d = UserDefaults.standard
        var k = KindThresholds()
        if d.object(forKey: "kind.hikeMax") != nil {
            k.hikeMax = d.double(forKey: "kind.hikeMax"); k.bikeMin = d.double(forKey: "kind.bikeMin")
            k.bikeMax = d.double(forKey: "kind.bikeMax"); k.carMin = d.double(forKey: "kind.carMin")
        }
        t = k
        GPXFile.kindThresholds = k
    }

    private func apply() {
        var k = t                                   // keep the limits in order
        k.bikeMin = max(k.bikeMin, k.hikeMax)
        k.bikeMax = max(k.bikeMax, k.bikeMin)
        k.carMin = max(k.carMin, k.bikeMax)
        if k != t { t = k; return }
        let d = UserDefaults.standard
        d.set(k.hikeMax, forKey: "kind.hikeMax"); d.set(k.bikeMin, forKey: "kind.bikeMin")
        d.set(k.bikeMax, forKey: "kind.bikeMax"); d.set(k.carMin, forKey: "kind.carMin")
        GPXFile.kindThresholds = k
        NotificationCenter.default.post(name: .kindThresholdsChanged, object: nil)
    }
}

extension Notification.Name { static let markerSizeChanged = Notification.Name("markerSizeChanged"); static let mapsFolderChanged = Notification.Name("mapsFolderChanged"); static let kindThresholdsChanged = Notification.Name("kindThresholdsChanged") }

/// Size limit of the online map tile cache on disk.
final class MapsFolderSettings: ObservableObject {
    @Published var path = AppSettings.mapsRoot.path
    func choose() {
        let p = NSOpenPanel()
        p.message = "Choose the folder for your maps (Garmin maps and the online map tile cache)"
        p.prompt = "Use This Folder"
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
            DispatchQueue.main.async { self.usage = "\(size) in \(u.files) tiles" }
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

    var body: some View {
        Form {
            Section {
                Text("The track icon (hike, bike ride, car/motorcycle) is chosen from the average speed while moving. Speeds between two classes are shown with the neutral track icon.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                row("Hike up to", $k.t.hikeMax, 1...15)
                row("Bike ride from", $k.t.bikeMin, 3...25)
                row("Bike ride up to", $k.t.bikeMax, 15...60)
                row("Car / motorcycle from", $k.t.carMin, 20...120)
                HStack {
                    Spacer()
                    Button("Reset to Defaults") { k.t = KindThresholds.standard }
                }
            } header: { Text("Track icons by speed").font(.headline) }
            Section {
                HStack {
                    Text("Symbol Size")
                    Slider(value: Binding(get: { Double(marker.index) }, set: { marker.index = Int($0.rounded()) }),
                           in: 0...Double(MarkerSize.factors.count - 1), step: 1)
                    Text(MarkerSize.titles[marker.index]).frame(width: 60, alignment: .trailing)
                }
            } header: { Text("Map symbols").font(.headline) }
            Section {
                Text("Garmin maps (.gmap, .img) are found in this folder; the tiles of the online maps are cached in its \"\(AppSettings.onlineFolderName)\" sub-folder.")
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
                    Text("Currently " + cache.usage).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear Cache") { cache.clear() }
                }
            } header: { Text("Online map cache").font(.headline) }
        }
        .formStyle(.grouped)
        .onAppear { cache.refreshUsage() }
        .frame(width: 460, height: 670)
    }

    private func row(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        Stepper(value: value, in: range, step: 0.5) {
            HStack { Text(title); Spacer(); Text(String(format: "%.1f km/h", value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary) }
        }
    }
}
