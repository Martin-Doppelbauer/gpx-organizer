import SwiftUI
import AppKit
import CoreServices

/// Watches a folder tree for changes made by other programs (FSEvents); reports the changed paths on the main queue.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    fileprivate var handler: (([String]) -> Void)?

    func start(path: String, handler: @escaping ([String]) -> Void) {
        stop()
        self.handler = handler
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let w = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []
            w.handler?(list)
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        guard let s = FSEventStreamCreate(nil, callback, &ctx, [path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, flags) else { return }
        stream = s
        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
    }

    func stop() {
        handler = nil
        guard let s = stream else { return }
        FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s)
        stream = nil
    }

    deinit { stop() }
}

extension AppModel {
    /// While the app is in the background the shown folder is watched; files added, removed or renamed by other programs
    /// then refresh the view. Coming back to the app stops the watching (the view is up to date by then).
    func installFocusWatch() {
        ZoomKeys.install()
        let nc = NotificationCenter.default
        focusObservers.append(nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.startWatching()
        })
        focusObservers.append(nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.folderWatcher.stop()
            self.externalWork?.cancel()
            if self.externalDirty { self.externalDirty = false; self.refreshFromDisk() }
        })
    }

    private func startWatching() {
        guard !AppSettings.needsFirstStart else { return }
        let maps = AppSettings.mapsRoot.standardizedFileURL.path
        folderWatcher.start(path: rootURL.path) { [weak self] paths in
            guard let self else { return }
            // ignore the tile cache / maps folder and invisible files (.DS_Store …)
            let relevant = paths.contains { p in
                !(p == maps || p.hasPrefix(maps + "/")) && !(p as NSString).lastPathComponent.hasPrefix(".")
            }
            guard relevant else { return }
            self.externalWork?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.refreshFromDisk() }
            self.externalWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: w)      // collect a burst of changes
        }
    }

    /// Re-reads the folder tree and the shown files. Not while a track, waypoints or a name are being edited:
    /// that is done when the app is activated again.
    func refreshFromDisk() {
        if edit != nil || wptEdit != nil || plan != nil || renamingID != nil { externalDirty = true; return }
        if let f = foregroundPath, !FileManager.default.fileExists(atPath: f) {        // the selected file is gone
            foregroundPath = nil; showProfile = false
            if selection == f { selection = nil }
        }
        reloadTree()
    }
}

/// ⌘= also zooms in (on keyboards where "+" needs Shift); ⌘+ and ⌘− are menu shortcuts.
enum ZoomKeys {
    private static var monitor: Any?
    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = e.modifierFlags.intersection([.command, .option, .control])
            guard mods == .command else { return e }
            // layout independent: "+", "=" (⌘⇧= on US), "-" and the numeric keypad (keyCodes 69 / 78)
            let ch = e.charactersIgnoringModifiers ?? ""
            if ch == "+" || ch == "=" || e.keyCode == 69 || e.keyCode == 30 && ch == "+" {
                NotificationCenter.default.post(name: .zoomIn, object: nil); return nil
            }
            if ch == "-" || e.keyCode == 78 {
                NotificationCenter.default.post(name: .zoomOut, object: nil); return nil
            }
            return e
        }
    }
}
