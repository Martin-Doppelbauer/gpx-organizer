import SwiftUI
import AppKit

/// Where maps live and what happens on the very first start.
enum AppSettings {
    /// Folder Garmin BaseCamp uses; kept as the default for people who already have maps there.
    static let legacyMapsRoot = URL(fileURLWithPath: "/Library/Application Support/Garmin/Maps")
    static let onlineFolderName = "Online Maps"
    static let onlineSourceFolders = ["opentopomap", "topplusopen", "topplusopen-grau", "osm"]

    static var mapsRoot: URL {
        UserDefaults.standard.string(forKey: "mapsFolder").map { URL(fileURLWithPath: $0) } ?? legacyMapsRoot
    }
    static var onlineTilesRoot: URL { mapsRoot.appendingPathComponent(onlineFolderName, isDirectory: true) }
    static var defaultMapsFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GPX Organizer/Maps", isDirectory: true)
    }
    static var documentsFolder: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    /// Folder shown at the left when nothing was chosen yet.
    static var defaultRouteFolder: URL { documentsFolder }

    /// Creates the maps folder with one sub-folder per built-in online map (their tile cache) and a short README.
    static func prepareMapsFolder(_ root: URL) {
        let fm = FileManager.default
        let online = root.appendingPathComponent(onlineFolderName, isDirectory: true)
        for s in onlineSourceFolders { try? fm.createDirectory(at: online.appendingPathComponent(s), withIntermediateDirectories: true) }
        let readme = root.appendingPathComponent("README.txt")
        if !fm.fileExists(atPath: readme.path) {
            let text = """
            GPX Organizer – maps folder

            • Put Garmin maps here (.gmap folders or .img files); they appear in the map menu.
            • "\(onlineFolderName)" holds the downloaded tiles of the built-in online maps
              (OpenTopoMap, TopPlusOpen, TopPlusOpen gray, OpenStreetMap). It is only a cache:
              you can delete it at any time, tiles are downloaded again when needed.
            """
            try? text.write(to: readme, atomically: true, encoding: .utf8)
        }
    }

    /// First start of a fresh installation: asks where the maps go, then shows the Documents folder on the left.
    /// Installations that already have settings are left untouched.
    /// True on a fresh installation that has not been set up yet.
    static var needsFirstStart: Bool {
        let d = UserDefaults.standard
        return !d.bool(forKey: "firstRunDone") && d.object(forKey: "rootPath") == nil && d.object(forKey: "mapID") == nil
    }

    @MainActor static func runFirstStartIfNeeded() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "firstRunDone") else { return }
        defer { d.set(true, forKey: "firstRunDone") }
        guard needsFirstStart else { return }                                                      // existing installation

        NSApplication.shared.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Welcome to GPX Organizer"
        a.informativeText = """
        Where should your maps be stored?

        A maps folder holds Garmin maps and the downloaded tiles of the four built-in online maps \
        (OpenTopoMap, TopPlusOpen, TopPlusOpen gray, OpenStreetMap).
        """
        a.addButton(withTitle: "Create Default Folder")
        a.addButton(withTitle: "Choose Folder …")
        var folder = defaultMapsFolder
        if a.runModal() == .alertSecondButtonReturn {
            let p = NSOpenPanel()
            p.message = "Choose the folder for your maps (an existing Garmin maps folder works too)"
            p.prompt = "Use This Folder"
            p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
            if p.runModal() == .OK, let u = p.url { folder = u }
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        prepareMapsFolder(folder)
        d.set(folder.path, forKey: "mapsFolder")
        d.set(documentsFolder.path, forKey: "rootPath")        // the Documents folder is what the left side shows first
        d.set("online:osm", forKey: "mapID")                    // works without any Garmin map
    }
}
