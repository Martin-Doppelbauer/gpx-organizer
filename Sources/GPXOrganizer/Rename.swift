import SwiftUI
import AppKit
import BCCore

/// Text field for renaming a row in place (Return = apply, Esc = cancel, click elsewhere = apply), like in Finder.
struct InlineRenameField: NSViewRepresentable {
    let initial: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField(string: initial)
        f.delegate = context.coordinator
        f.isBordered = true; f.bezelStyle = .roundedBezel; f.focusRingType = .default
        f.lineBreakMode = .byTruncatingTail
        DispatchQueue.main.async {
            f.window?.makeFirstResponder(f)
            let n = (initial as NSString).length
            f.currentEditor()?.selectedRange = NSRange(location: n, length: 0)
        }
        return f
    }

    func updateNSView(_ nsView: NSTextField, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineRenameField
        private var finished = false
        init(_ p: InlineRenameField) { parent = p }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) { finish(control, commit: true); return true }
            if sel == #selector(NSResponder.cancelOperation(_:)) { finish(control, commit: false); return true }
            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            if let f = obj.object as? NSControl { finish(f, commit: true) }
        }

        private func finish(_ c: NSControl, commit: Bool) {
            guard !finished else { return }
            finished = true
            let text = c.stringValue
            DispatchQueue.main.async { commit ? self.parent.onCommit(text) : self.parent.onCancel() }
        }
    }
}

extension AppModel {
    func beginRename(_ id: String) {
        renameWork?.cancel()
        guard id != rootURL.path else { return }
        if edit?.url.path == id {
            let a = NSAlert(); a.messageText = "“\(URL(fileURLWithPath: id).lastPathComponent)” is currently being edited."
            a.informativeText = "Finish editing first (Esc), then you can rename the file."; a.runModal(); return
        }
        renameRestore = selection
        selection = nil                    // no blue row highlight behind the text field
        renamingID = id
    }

    func cancelRename() {
        renamingID = nil
        if let r = renameRestore { selection = r }
        renameRestore = nil
    }

    /// Called for every click on a row: a slow second click on the already selected row starts renaming (as in Finder).
    func rowClicked(_ id: String) {
        renameWork?.cancel()
        let now = Date()
        let gap = now.timeIntervalSince(lastClickTime)
        let sameRow = lastClickID == id
        lastClickTime = now; lastClickID = id
        let wasSelected = selection == id
        select(id)
        guard wasSelected, sameRow, gap > 0.6, renamingID == nil, id != rootURL.path else { return }
        let w = DispatchWorkItem { [weak self] in self?.beginRename(id) }
        renameWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: w)
    }

    func commitRename(_ id: String, text: String) {
        renamingID = nil
        defer { if renameRestore != nil, pendingSelect == nil { selection = renameRestore }; renameRestore = nil }
        let old = URL(fileURLWithPath: id)
        let isFolder = (try? old.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        var name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if !isFolder {
            let ext = old.pathExtension
            if !ext.isEmpty, (name as NSString).pathExtension.lowercased() != ext.lowercased() { name += "." + ext }
        }
        if name == old.lastPathComponent { return }
        if name.contains("/") || name.contains(":") {
            let a = NSAlert(); a.messageText = "The name must not contain “/” or “:”."; a.runModal(); return
        }
        let new = old.deletingLastPathComponent().appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: new.path) {
            let a = NSAlert(); a.messageText = "“\(name)” already exists in this folder."
            a.informativeText = "Choose a different name."; a.runModal(); return
        }
        do { try FileManager.default.moveItem(at: old, to: new) }
        catch {
            let a = NSAlert(); a.messageText = "Renaming failed"; a.informativeText = error.localizedDescription; a.runModal(); return
        }
        // keep per-file settings and caches consistent with the new path
        for (k, v) in styles where k == id || k.hasPrefix(id + "/") {
            styles[k] = nil
            styles[new.path + k.dropFirst(id.count)] = v
        }
        saveStyles()
        for k in cache.keys where k == id || k.hasPrefix(id + "/") { cache.removeValue(forKey: k) }
        if displayedFolder == id { displayedFolder = new.path }
        if foregroundPath == id { foregroundPath = nil }
        pendingSelect = new.path
        reloadTree()
    }
}
