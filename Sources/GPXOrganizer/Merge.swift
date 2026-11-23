import AppKit
import BCCore

extension AppModel {
    /// Joins several track files (in the given order) into one new GPX file; asks for the name in a save dialog.
    func mergeFiles(_ urls: [URL]) {
        let docs = urls.compactMap { GPXDocument.parse($0) }
        guard docs.count > 1 else { return }
        let p = NSSavePanel()
        if let d = displayedFolder { p.directoryURL = URL(fileURLWithPath: d) }
        p.nameFieldStringValue = (urls[0].deletingPathExtension().lastPathComponent + " + \(docs.count - 1)") + ".gpx"
        p.message = L("Name of the combined route")
        p.prompt = L("Merge")
        guard p.runModal() == .OK, let url = p.url else { return }
        var out = GPXDocument(name: url.deletingPathExtension().lastPathComponent)
        var segs: [[GPXPoint]] = []
        for d in docs {
            for t in d.tracks { segs.append(contentsOf: t.segments) }
            out.waypoints.append(contentsOf: d.waypoints)
        }
        out.tracks = [GPXTrackData(name: out.name, isRoute: false, segments: segs)]
        do { try out.xml().write(to: url, atomically: true, encoding: .utf8) }
        catch { let a = NSAlert(); a.messageText = L("Saving failed"); a.informativeText = error.localizedDescription; a.runModal(); return }
        pendingOpen = url.path
        reloadTree()
    }
}

extension AppModel {
    /// Creates a new sub-folder (in the file system) after asking for its name, then selects it.
    func newFolder(in parent: URL) {
        let a = NSAlert()
        a.messageText = L("New folder in “%@”", "\(parent.lastPathComponent)")
        a.informativeText = L("Name of the new folder:")
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        f.stringValue = L("New Folder")
        a.accessoryView = f
        a.addButton(withTitle: L("Create")); a.addButton(withTitle: L("Cancel"))
        a.window.initialFirstResponder = f
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let name = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !name.isEmpty else { return }
        let url = parent.appendingPathComponent(name, isDirectory: true)
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
        catch { let e = NSAlert(); e.messageText = L("The folder could not be created"); e.informativeText = error.localizedDescription; e.runModal(); return }
        pendingSelect = url.path
        reloadTree()
    }
}

extension AppModel {
    /// Moves the given files to the Trash after asking (they can be restored from the Trash).
    func trashFiles(_ ids: [String]) {
        let urls = ids.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return }
        if let e = edit?.url.path, ids.contains(e) {
            let a = NSAlert(); a.messageText = L("“%@” is currently being edited.", "\(URL(fileURLWithPath: e).lastPathComponent)")
            a.informativeText = L("Finish editing first (Esc), then you can delete the file."); a.runModal(); return
        }
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = urls.count == 1 ? L("Move “%@” to the Trash?", "\(urls[0].lastPathComponent)") : L("Move %@ files to the Trash?", "\(urls.count)")
        a.informativeText = L("You can restore them from the Trash.")
        a.addButton(withTitle: L("Move to Trash")); a.addButton(withTitle: L("Cancel"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        var notTrashed: [String] = []
        for u in urls {
            do { try FileManager.default.trashItem(at: u, resultingItemURL: nil) } catch { notTrashed.append(u.lastPathComponent) }
        }
        for id in ids {
            cache.removeValue(forKey: id); failed.remove(id)
            styles[id] = nil; fileIcons[id] = nil
            if foregroundPath == id { foregroundPath = nil; showProfile = false }
            if selection == id { selection = nil }
        }
        if !notTrashed.isEmpty {
            let f = NSAlert(); f.messageText = L("Some files could not be moved to the Trash")
            f.informativeText = notTrashed.joined(separator: ", "); f.runModal()
        }
        reloadTree()
    }

}
