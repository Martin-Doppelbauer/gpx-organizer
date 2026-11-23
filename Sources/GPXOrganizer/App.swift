import SwiftUI
import AppKit

@main
struct GPXOrganizerApp: App {
    @Environment(\.openWindow) private var openWindow
    @AppStorage("toolbarLabels") private var toolbarLabels = false
    init() { Appearance.apply() }

    var body: some Scene {
        WindowGroup("GPX Organizer") { RootView() }
        Window("About GPX Organizer", id: "about") { AboutView() }
            .windowResizability(.contentSize)
        Window("Track Statistics", id: "stats") { StatisticsView() }
            .defaultSize(width: 900, height: 640)
        Window("Duplicate Tracks", id: "duplicates") { DuplicatesWindow() }
            .defaultSize(width: 900, height: 640)
        Window("GPX Organizer User Guide", id: "guide") { ReadmeView(resource: "UserGuide") }.defaultSize(width: 780, height: 860)
        Window("GPX Organizer Technical Reference", id: "readme") { ReadmeView() }.defaultSize(width: 780, height: 860)
            .defaultSize(width: 700, height: 720)
        Settings { SettingsView() }
        .commands {
            CommandGroup(replacing: .appInfo) { Button("About GPX Organizer") { openWindow(id: "about") } }
            CommandGroup(replacing: .help) {
                Button("User Guide") { openWindow(id: "guide") }
                Button("Technical Reference") { openWindow(id: "readme") }
            }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) { Toggle("Show Toolbar Labels", isOn: $toolbarLabels) }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Connect to Komoot …") { NotificationCenter.default.post(name: .komootImport, object: nil) }
                Button("Connect to Garmin …") { NotificationCenter.default.post(name: .garminImport, object: nil) }
            }
            CommandGroup(replacing: .printItem) {
                Button("Print Map …") { NotificationCenter.default.post(name: .printMap, object: nil) }
                    .keyboardShortcut("p", modifiers: .command)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { NotificationCenter.default.post(name: .editUndo, object: nil) }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Redo") { NotificationCenter.default.post(name: .editRedo, object: nil) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandMenu("Statistics") {
                Button("Track Statistics …") { openWindow(id: "stats") }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                Button("Find Duplicate Tracks …") { openWindow(id: "duplicates") }
            }
            CommandMenu("Map") {
                Button("Zoom In") { NotificationCenter.default.post(name: .zoomIn, object: nil) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out") { NotificationCenter.default.post(name: .zoomOut, object: nil) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Aerial Imagery On/Off") { NotificationCenter.default.post(name: .toggleAerial, object: nil) }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Divider()
                Button("Zoom to All Tracks") { NotificationCenter.default.post(name: .fitAll, object: nil) }
                    .keyboardShortcut("0", modifiers: .command)
                Button("Zoom to Selected Track") { NotificationCenter.default.post(name: .fitSelected, object: nil) }
                    .keyboardShortcut("9", modifiers: .command)
                Button("Rescan Photos") { PhotoStore.shared.rescan() }
                Button("Reload Folders") { NotificationCenter.default.post(name: .reloadTree, object: nil) }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let komootImport = Notification.Name("komootImport")
    static let komootExport = Notification.Name("komootExport")
    static let printMap = Notification.Name("printMap")
    static let toggleAerial = Notification.Name("toggleAerial")
    static let zoomIn = Notification.Name("zoomIn")
    static let zoomOut = Notification.Name("zoomOut")
    static let fitAll = Notification.Name("fitAll")
    static let fitSelected = Notification.Name("fitSelected")
    static let reloadTree = Notification.Name("reloadTree")
    static let editUndo = Notification.Name("editUndo")
    static let editRedo = Notification.Name("editRedo")
}


/// One window (or tab): it has its own model, so every tab keeps its own folder, selection and map.
struct RootView: View {
    @StateObject private var model = AppModel()
    private static var appStarted = false
    var body: some View {
        ContentView().environmentObject(model)
            .frame(minWidth: 900, minHeight: 560)
            .onAppear {
                NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
                DispatchQueue.main.async {
                    model.firstStart(); model.observePhotoSetting()
                    if !Self.appStarted { Self.appStarted = true; model.photos.start(); model.askPhotoFolderIfNeeded() }
                }
            }
    }
}
