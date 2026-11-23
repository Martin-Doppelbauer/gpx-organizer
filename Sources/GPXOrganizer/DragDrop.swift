import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BCCore

extension AppModel {
    /// Handles files dropped on a folder row: moved by default, copied when Option was held (only rows dragged from the list can be moved; files from elsewhere are always copied).
    func handleDrop(_ providers: [NSItemProvider], into folder: URL, move: Bool = false) -> Bool {
        let typeID = UTType.fileURL.identifier
        let items = providers.filter { $0.hasItemConformingToTypeIdentifier(typeID) }
        guard !items.isEmpty else { return false }
        var urls: [URL] = []
        let lock = NSLock()
        let group = DispatchGroup()
        for p in items {
            group.enter()
            p.loadItem(forTypeIdentifier: typeID, options: nil) { item, _ in
                var u: URL?
                if let d = item as? Data { u = URL(dataRepresentation: d, relativeTo: nil) }
                else if let x = item as? URL { u = x }
                else if let x = item as? NSURL { u = x as URL }
                if let u { lock.lock(); urls.append(u); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            // a drag of several selected rows moves all of them
            if let src = self.dragSource, self.dragSources.count > 1, urls.contains(where: { $0.path == src }) {
                self.performDrop(self.dragSources.map { URL(fileURLWithPath: $0) }, into: folder, move: move)
            } else { self.performDrop(urls, into: folder, move: move) }
        }
        return true
    }

    /// Same as `handleDrop`, for file URLs that are already known (drops from the AppKit lists).
    func handleDropURLs(_ urls: [URL], into folder: URL, move: Bool) -> Bool {
        guard !urls.isEmpty else { return false }
        if let src = dragSource, dragSources.count > 1, urls.contains(where: { $0.path == src }) {
            performDrop(dragSources.map { URL(fileURLWithPath: $0) }, into: folder, move: move)
        } else { performDrop(urls, into: folder, move: move) }
        return true
    }

    /// A folder was moved: per-file caches and the current selection follow its new path.
    func folderMoved(from old: String, to new: String) {
        func remap(_ k: String) -> String? { k == old || k.hasPrefix(old + "/") ? new + k.dropFirst(old.count) : nil }
        for (k, v) in styles { if let n = remap(k) { styles[k] = nil; styles[n] = v } }
        for (k, v) in fileIcons { if let n = remap(k) { fileIcons[k] = nil; fileIcons[n] = v } }
        remapFileState(from: old, to: new)
        for k in Array(cache.keys) where remap(k) != nil { cache.removeValue(forKey: k) }
        if let d = displayedFolder, let n = remap(d) { displayedFolder = n }
        if let f = foregroundPath, remap(f) != nil { foregroundPath = nil; showProfile = false }
        if let s = selection, remap(s) != nil { selection = nil }
    }

    /// Moves a folder (with everything in it) to the Trash after asking.
    func trashFolder(_ url: URL) {
        guard url.path != rootURL.path else { return }
        if let e = edit?.url.path, e.hasPrefix(url.path + "/") {
            let a = NSAlert(); a.messageText = L("A file in “%@” is currently being edited.", "\(url.lastPathComponent)")
            a.informativeText = L("Finish editing first (Esc), then you can delete the folder."); a.runModal(); return
        }
        let count = FolderNode.build(url).totalFileCount
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = L("Move the folder “%@” to the Trash?", "\(url.lastPathComponent)")
        a.informativeText = (count > 0 ? (count == 1 ? L("It contains 1 track file, which goes with it. ") : L("It contains %@ track files, which go with it. ", "\(count)")) : "") + L("You can restore it from the Trash.")
        a.addButton(withTitle: L("Move to Trash")); a.addButton(withTitle: L("Cancel"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        catch { let e = NSAlert(); e.messageText = L("The folder could not be moved to the Trash"); e.informativeText = error.localizedDescription; e.runModal(); return }
        let parent = url.deletingLastPathComponent().path
        if let d = displayedFolder, d == url.path || d.hasPrefix(url.path + "/") { displayedFolder = parent }
        for k in Array(cache.keys) where k.hasPrefix(url.path + "/") { cache.removeValue(forKey: k) }
        if let f = foregroundPath, f.hasPrefix(url.path + "/") { foregroundPath = nil; showProfile = false }
        if let s = selection, s == url.path || s.hasPrefix(url.path + "/") { selection = parent }
        pendingSelect = parent
        reloadTree()
    }

    private func uniqueName(_ name: String, in folder: URL) -> URL {
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var n = 2
        while true {
            let u = folder.appendingPathComponent("\(base) \(n)" + (ext.isEmpty ? "" : ".\(ext)"))
            if !FileManager.default.fileExists(atPath: u.path) { return u }
            n += 1
        }
    }

    private func performDrop(_ urls: [URL], into folder: URL, move: Bool) {
        let internalSource = dragSource
        let dragSourcesSnapshot = dragSources
        let listedPaths = Set(fileNodes.map(\.id))          // files shown in the list count as dragged from the list
        dragSources = []
        dragSource = nil; dropTarget = nil
        let fm = FileManager.default
        var imported: [String] = []
        var skipped = 0
        var decision: NSApplication.ModalResponse?
        for src in urls {
            var dirFlag: ObjCBool = false
            let isDir = fm.fileExists(atPath: src.path, isDirectory: &dirFlag) && dirFlag.boolValue
            guard isDir || ForeignTracks.isSupported(src) else { skipped += 1; continue }
            // a folder dragged inside the folder tree moves (copied with Option); folders from elsewhere are copied
            let fromList = isDir ? internalSource == src.path
                                 : (internalSource == src.path || dragSourcesSnapshot.contains(src.path) || listedPaths.contains(src.path))
            let isMove = fromList && move
            if src.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL, fromList { continue }   // dropped on its own folder
            if isDir {
                let s = src.standardizedFileURL.path, d = folder.standardizedFileURL.path
                if d == s { continue }                       // dropped on itself (a slip of the mouse): nothing happens
                if d.hasPrefix(s + "/") {
                    let a = NSAlert(); a.messageText = L("A folder cannot be placed inside itself.")
                    a.informativeText = L("“%@” was not moved.", "\(src.lastPathComponent)"); a.runModal(); continue
                }
                if let e = edit?.url.path, e.hasPrefix(s + "/") {
                    let a = NSAlert(); a.messageText = L("A file in “%@” is currently being edited.", "\(src.lastPathComponent)")
                    a.informativeText = L("Finish editing first (Esc), then you can move the folder."); a.runModal(); continue
                }
            }
            if isMove, edit?.url.path == src.path {
                let a = NSAlert(); a.messageText = L("“%@” is currently being edited.", "\(src.lastPathComponent)")
                a.informativeText = L("Finish editing first (Esc), then you can move the file."); a.runModal(); continue
            }
            var dst = folder.appendingPathComponent(src.lastPathComponent)
            if fm.fileExists(atPath: dst.path) {
                var choice = decision
                if choice == nil {
                    let a = NSAlert()
                    a.messageText = L("“%@” already exists in this folder.", "\(src.lastPathComponent)")
                    a.informativeText = L("What should happen to the file?")
                    a.addButton(withTitle: L("Keep Both")); a.addButton(withTitle: L("Replace")); a.addButton(withTitle: L("Skip"))
                    if urls.count > 1 { a.showsSuppressionButton = true; a.suppressionButton?.title = L("Apply to all remaining files") }
                    choice = a.runModal()
                    if urls.count > 1, a.suppressionButton?.state == .on { decision = choice }
                }
                switch choice {
                case .alertFirstButtonReturn: dst = uniqueName(src.lastPathComponent, in: folder)
                case .alertSecondButtonReturn:
                    do { try fm.trashItem(at: dst, resultingItemURL: nil) } catch { skipped += 1; continue }
                default: continue
                }
            }
            do {
                if isMove && isDir { try fm.moveItem(at: src, to: dst); folderMoved(from: src.path, to: dst.path) }
                else if isMove { try fm.moveItem(at: src, to: dst); remapFileState(from: src.path, to: dst.path); cache.removeValue(forKey: src.path); styles[dst.path] = styles.removeValue(forKey: src.path); fileIcons[dst.path] = fileIcons.removeValue(forKey: src.path) }
                else { try fm.copyItem(at: src, to: dst) }
                imported.append(dst.path)
            } catch {
                let a = NSAlert(); a.messageText = L("“%@” could not be placed", "\(src.lastPathComponent)")
                a.informativeText = error.localizedDescription; a.runModal()
            }
        }
        if imported.isEmpty {
            if skipped > 0 {
                let a = NSAlert(); a.messageText = L("Only track files (GPX, FIT, TRC, IKT, PTM, AXE, OVL, TRAIL) can be dropped here.")
                a.informativeText = L("%@ file(s) were skipped.", "\(skipped)"); a.runModal()
            }
            return
        }
        // moving or copying into another folder: the folder shown stays as it is (so more files can be moved from it);
        // only a drop into the folder shown selects the new file
        let shownDir = displayedFolder.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        pendingSelect = (shownDir == nil || shownDir == folder.standardizedFileURL.path) ? imported.last : nil
        reloadTree()
    }
}
