import SwiftUI
import AppKit
import BCCore

/// Text field for renaming a row in place (Return = apply, Esc = cancel, click elsewhere = apply), like in Finder.
/// Takes the keyboard focus as soon as it is in a window (retrying, because the list may not have attached it yet);
/// without focus neither Return nor a click elsewhere could finish the rename.
final class RenameTextField: NSTextField {
    private var tries = 0
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); tries = 0; grabFocus() }
    private func grabFocus() {
        guard window != nil, tries < 20 else { return }
        tries += 1
        if currentEditor() == nil {
            window?.makeFirstResponder(self)
        }
        if let ed = currentEditor() {
            ed.selectedRange = NSRange(location: (stringValue as NSString).length, length: 0)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.grabFocus() }
        }
    }
}

struct InlineRenameField: NSViewRepresentable {
    let initial: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let f = RenameTextField(string: initial)
        f.delegate = context.coordinator
        f.isBordered = true; f.bezelStyle = .roundedBezel; f.focusRingType = .default
        f.lineBreakMode = .byTruncatingTail
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
        let w = DispatchWorkItem { [weak self] in
            guard let self, self.foregroundPath == id, self.multiSelected.isEmpty else { return }
            self.beginRename(id)
        }
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
        // the name stored inside a GPX file follows the file name (the modification date is kept)
        if new.pathExtension.lowercased() == "gpx", let data = try? Data(contentsOf: new), let text = String(data: data, encoding: .utf8),
           let patched = GPXIconTag.renameInside(text, to: new.deletingPathExtension().lastPathComponent), patched != text {
            let date = (try? FileManager.default.attributesOfItem(atPath: new.path)[.modificationDate]) as? Date
            if (try? patched.write(to: new, atomically: true, encoding: .utf8)) != nil, let date {
                try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: new.path)
            }
        }
        // keep per-file settings and caches consistent with the new path
        for (k, v) in styles where k == id || k.hasPrefix(id + "/") {
            styles[k] = nil
            styles[new.path + k.dropFirst(id.count)] = v
        }
        for (k, v) in fileIcons where k == id || k.hasPrefix(id + "/") {       // chosen icons follow a renamed file or folder
            fileIcons[k] = nil
            fileIcons[new.path + k.dropFirst(id.count)] = v
        }
        for k in cache.keys where k == id || k.hasPrefix(id + "/") { cache.removeValue(forKey: k) }
        if displayedFolder == id { displayedFolder = new.path }
        if foregroundPath == id { foregroundPath = nil }
        pendingSelect = new.path
        reloadTree()
    }
}
