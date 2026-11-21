import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BCCore

extension AppModel {
    /// Handles files dropped on a folder row: copied by default, moved when Option was held (only for rows dragged from the list).
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
            guard ForeignTracks.isSupported(src) else { skipped += 1; continue }
            let fromList = internalSource == src.path || dragSourcesSnapshot.contains(src.path) || listedPaths.contains(src.path)
            let isMove = fromList && move
            if src.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL, fromList { continue }   // dropped on its own folder
            if isMove, edit?.url.path == src.path {
                let a = NSAlert(); a.messageText = "“\(src.lastPathComponent)” is currently being edited."
                a.informativeText = "Finish editing first (Esc), then you can move the file."; a.runModal(); continue
            }
            var dst = folder.appendingPathComponent(src.lastPathComponent)
            if fm.fileExists(atPath: dst.path) {
                var choice = decision
                if choice == nil {
                    let a = NSAlert()
                    a.messageText = "“\(src.lastPathComponent)” already exists in this folder."
                    a.informativeText = "What should happen to the file?"
                    a.addButton(withTitle: "Keep Both"); a.addButton(withTitle: "Replace"); a.addButton(withTitle: "Skip")
                    if urls.count > 1 { a.showsSuppressionButton = true; a.suppressionButton?.title = "Apply to all remaining files" }
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
                if isMove { try fm.moveItem(at: src, to: dst); cache.removeValue(forKey: src.path); styles[dst.path] = styles.removeValue(forKey: src.path) }
                else { try fm.copyItem(at: src, to: dst) }
                imported.append(dst.path)
            } catch {
                let a = NSAlert(); a.messageText = "“\(src.lastPathComponent)” could not be placed"
                a.informativeText = error.localizedDescription; a.runModal()
            }
        }
        if imported.isEmpty {
            if skipped > 0 {
                let a = NSAlert(); a.messageText = "Only track files (GPX, TRC, IKT, PTM, AXE, OVL, TRAIL) can be dropped here."
                a.informativeText = "\(skipped) file(s) were skipped."; a.runModal()
            }
            return
        }
        saveStyles()
        pendingSelect = imported.last
        reloadTree()
    }
}
