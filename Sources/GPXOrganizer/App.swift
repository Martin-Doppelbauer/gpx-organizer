import SwiftUI
import AppKit

@main
struct GPXOrganizerApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("GPX Organizer") {
            ContentView().environmentObject(model)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true); DispatchQueue.main.async { model.firstStart() } }
        }
        Window("About GPX Organizer", id: "about") { AboutView() }
            .windowResizability(.contentSize)
        Window("GPX Organizer Help", id: "readme") { ReadmeView() }
            .defaultSize(width: 700, height: 720)
        Settings { SettingsView() }
        .commands {
            CommandGroup(replacing: .appInfo) { Button("About GPX Organizer") { openWindow(id: "about") } }
            CommandGroup(replacing: .help) { Button("GPX Organizer Help (README)") { openWindow(id: "readme") } }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { NotificationCenter.default.post(name: .editUndo, object: nil) }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Redo") { NotificationCenter.default.post(name: .editRedo, object: nil) }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandMenu("Map") {
                Button("Zoom to All Tracks") { NotificationCenter.default.post(name: .fitAll, object: nil) }
                    .keyboardShortcut("0", modifiers: .command)
                Button("Zoom to Selected Track") { NotificationCenter.default.post(name: .fitSelected, object: nil) }
                    .keyboardShortcut("9", modifiers: .command)
                Button("Reload Folders") { NotificationCenter.default.post(name: .reloadTree, object: nil) }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let fitAll = Notification.Name("fitAll")
    static let fitSelected = Notification.Name("fitSelected")
    static let reloadTree = Notification.Name("reloadTree")
    static let editUndo = Notification.Name("editUndo")
    static let editRedo = Notification.Name("editRedo")
}
