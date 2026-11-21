import SwiftUI
import AppKit
import BCCore

@MainActor
final class AppModel: ObservableObject {
    static var mapsRoot: URL { AppSettings.mapsRoot }

    @Published var rootURL: URL
    @Published var tree: FolderNode?
    @Published var maps: [GarminMap] = []
    @Published var extraMapPaths: [String] = UserDefaults.standard.stringArray(forKey: "extraMaps") ?? []
    @Published var selectedMapID: String?
    @Published var selection: String?            // FolderNode id (path)
    @Published var displayedFolder: String?      // folder whose GPX files (recursive) are shown
    @Published var foregroundPath: String? {      // GPX file drawn on top
        didSet { profileHighlight = nil; if showProfile { updateProfile() } }
    }
    /// Off by default (and not remembered): only tracks directly inside the selected folder are read and shown.
    /// When switched on, the tracks of all sub-folders are read and shown as well.
    @Published var includeSubfolders = false {
        didSet { if oldValue != includeSubfolders { refreshTracks(fit: false) } }
    }
    @Published var plan: PlanSession?
    /// Files of the selected folder as shown in the lower list (sorted).
    @Published var fileRows: [FolderNode] = []
    @Published var fileRevision = 0
    @Published var fileSort: FileSort = FileSort(rawValue: UserDefaults.standard.string(forKey: "fileSort") ?? "") ?? .name {
        didSet { UserDefaults.standard.set(fileSort.rawValue, forKey: "fileSort"); applySort() }
    }
    var fileNodes: [FolderNode] = []
    @Published var wptEdit: WaypointEditSession?
    @Published var profileMode: ProfileMode = ProfileMode(rawValue: UserDefaults.standard.string(forKey: "profileMode") ?? "") ?? .elevation {
        didSet { UserDefaults.standard.set(profileMode.rawValue, forKey: "profileMode") }
    }
    @Published var showPrefetch = false
    @Published var iconPickerOpen = false
    var iconPickerIDs: [String] = []
    var fileIcons: [String: String] = [:]        // icon name per file, read from the files (gpxorg:icon); never stored in the preferences
    var trackKinds: [String: TrackKind] = [:]                          // detected kind per loaded track file
    @Published var multiSelected: Set<String> = []   // files marked in the list (when more than one)
    @Published var dropTarget: String?          // folder row currently highlighted as drop target
    @Published var renamingID: String?          // row currently being renamed in place
    var renameWork: DispatchWorkItem?
    var renameRestore: String?
    var lastClickTime = Date.distantPast
    var lastClickID: String?
    var fileIconColors: [String: [Double]] = [:]   // icon colour chosen in the file (gpxorg:iconcolor)
    var waypointIcons: [String: String] = [:]      // path -> SF Symbol name
    var pendingFit: String?                         // file whose full extent is shown once it has loaded
    var searchQuery = ""                           // text of the search field (empty = show the selected folder)
    var waypointRank: [String: Int] = [:]          // path -> colour order, for waypoint-only files
    var waypointColors: [String: [Double]] = [:]   // path -> marker colour, for files that only contain waypoints
    var dragSources: [String] = []              // all rows moved by the current drag (multi-selection)
    var dragSource: String?                     // path of a row being dragged inside the list
    var pendingSelect: String?
    /// Load sharper tiles (one zoom level deeper: ~4x the data).
    @Published var sharpTiles: Bool = UserDefaults.standard.bool(forKey: "sharpTiles") {
        didSet { UserDefaults.standard.set(sharpTiles, forKey: "sharpTiles"); viewRevision += 1 }
    }
    var pendingOpen: String?
    @Published var showPoints = false
    @Published var showProfile = false { didSet { if showProfile { updateProfile() } } }
    @Published var profile: Profile?
    @Published var profileCursor: Int?
    var profileAnchor: Double?
    @Published var profileLiveRange: (Double, Double)?     // while dragging in the profile
    @Published var profileHighlight: (Double, Double)?     // range selected in the profile (no edit session)
    @Published var edit: EditSession?
    @Published var styles: [String: TrackStyle] = [:]          // read from the files (gpxorg:color / width), never stored in the preferences
    let colorHelper = ColorPanelHelper()
    @Published var tracks: [GPXFile] = []        // currently displayed, in draw order (foreground last)
    @Published var loadingCount = 0
    /// Not @Published: the map updates it on every mouse event and must not re-render the whole UI.
    var view = ViewState(mx: Merc.x(lon: 9.0), my: Merc.y(lat: 49.1), worldSize: 4_194_304, width: 800, height: 600)
    @Published var viewRevision = 0
    @Published var fitRequest = 0

    var cache: [String: GPXFile] = [:]
    private var lastTrackPublish = Date.distantPast
    var failed: Set<String> = []
    var loadGeneration = 0

    var selectedMap: GarminMap? { maps.first { $0.id == selectedMapID } }
    static let onlineSources = TileSource.all
    var selectedTileSource: TileSource? { Self.onlineSources.first { $0.id == selectedMapID } }
    private var lastGarminID: String?
    /// Garmin map used for route planning (the selected one, or the last Garmin map when an online map is shown).
    var routingMap: GarminMap? {
        if let m = selectedMap, m.isSupported { return m }
        return maps.first { $0.id == lastGarminID && $0.isSupported } ?? maps.first { $0.isSupported }
    }
    var foreground: GPXFile? { tracks.first { $0.id == foregroundPath } }

    init() {
        UserDefaults.standard.removeObject(forKey: "fileIcons")      // icons, colours and widths live in the GPX files only
        UserDefaults.standard.removeObject(forKey: "trackStyles")
        _ = KindSettings.shared                 // applies the stored speed limits for the track icons
        let d = UserDefaults.standard
        // a fresh installation shows the home folder until the first-start questions are answered
        rootURL = d.string(forKey: "rootPath").map { URL(fileURLWithPath: $0) }
            ?? AppSettings.defaultRouteFolder
        selectedMapID = d.string(forKey: "mapID")
        maps = Self.loadMaps(extra: extraMapPaths)
        if selectedTileSource == nil, selectedMap == nil || !(selectedMap!.isSupported) { selectedMapID = maps.first { $0.isSupported }?.id }
        // a fresh installation reads no folder before the first-start questions are answered (no needless macOS permission prompts)
        if !AppSettings.needsFirstStart { reloadTree() }
    }

    /// Fresh installation: asks about the maps folder, then switches to the Documents folder and the chosen maps folder.
    func firstStart() {
        guard AppSettings.needsFirstStart else { AppSettings.runFirstStartIfNeeded(); return }
        AppSettings.runFirstStartIfNeeded()
        let d = UserDefaults.standard
        if let p = d.string(forKey: "rootPath") { rootURL = URL(fileURLWithPath: p) }
        TileCache.shared.reconfigure()
        maps = Self.loadMaps(extra: extraMapPaths)
        selectedMapID = d.string(forKey: "mapID")
        displayedFolder = nil
        reloadTree()
    }

    func chooseRoot(_ url: URL) {
        guard url.path != rootURL.path || tree == nil else { return }
        guard confirmLeaveEdit() else { return }
        showPoints = false; showProfile = false
        rootURL = url
        UserDefaults.standard.set(url.path, forKey: "rootPath")
        selection = nil; foregroundPath = nil; displayedFolder = nil; tracks = []
        reloadTree()
    }

    /// Double-click on a folder: make it the list's root folder.
    func enterFolder(_ url: URL) { chooseRoot(url) }

    var canGoUp: Bool { rootURL.path != "/" && rootURL.deletingLastPathComponent().path != rootURL.path }

    /// Arrow at the bottom of the list: switch to the parent folder.
    func goUp() {
        guard canGoUp else { return }
        chooseRoot(rootURL.deletingLastPathComponent())
    }

    func reloadTree() {
        let url = rootURL
        Task.detached {
            let t = FolderNode.build(url)
            _ = t.children          // read the first level in the background
            await MainActor.run {
                self.tree = t
                if self.searchActive { if let sel = self.pendingSelect ?? self.pendingOpen { self.cache.removeValue(forKey: sel) }; self.refreshTracks(fit: false) }
                if let s = self.selection, t.find(s) == nil { self.selection = nil }
                if let sel = self.pendingSelect, t.find(sel) != nil {
                    self.pendingSelect = nil
                    self.cache.removeValue(forKey: sel)
                    self.select(sel)
                    for delay in [0.25, 0.7] {          // the file may have moved in the list (renamed, merged, imported): show it there
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                            guard let self, self.foregroundPath == sel else { return }
                            scrollFileListToTop(sel, rows: self.fileRows, offsetFraction: 0.3)
                        }
                    }
                    return
                }
                if let open = self.pendingOpen, t.find(open) != nil {
                    self.pendingOpen = nil
                    self.plan = nil
                    self.displayedFolder = URL(fileURLWithPath: open).deletingLastPathComponent().path
                    self.cache.removeValue(forKey: open)
                    self.refreshTracks(fit: false)
                    self.openTrack(open)
                    return
                }
                if self.displayedFolder == nil { self.displayedFolder = t.id; self.refreshTracks(fit: true) }
                else { self.cache.removeAll(); self.refreshTracks(fit: false) }
            }
        }
    }

    /// The maps folder was changed in Settings: rescan it and keep a usable map selected.
    func mapsFolderChanged() {
        maps = Self.loadMaps(extra: extraMapPaths)
        if selectedTileSource == nil, selectedMap == nil || !(selectedMap!.isSupported) { selectedMapID = maps.first { $0.isSupported }?.id }
        fileRevision += 1
    }

    static func loadMaps(extra: [String]) -> [GarminMap] {
        var list = GarminMap.discover(in: mapsRoot)
        for p in extra where FileManager.default.fileExists(atPath: p) {
            let m = GarminMap(imgURL: URL(fileURLWithPath: p))
            if !list.contains(where: { $0.id == m.id }) { list.append(m) }
        }
        return list
    }

    /// Lets the user pick Garmin .img files (or folders containing them) and adds them to the map list.
    func chooseMapFiles() {
        let panel = NSOpenPanel()
        panel.message = "Choose a Garmin map (.img, e.g. gmapsupp.img) or a folder containing such files"
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        var found: [String] = []
        for u in panel.urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir)
            if isDir.boolValue {
                let en = FileManager.default.enumerator(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                while let f = en?.nextObject() as? URL { if f.pathExtension.lowercased() == "img" { found.append(f.path) } }
            } else { found.append(u.path) }
        }
        guard !found.isEmpty else { return }
        for f in found where !extraMapPaths.contains(f) { extraMapPaths.append(f) }
        UserDefaults.standard.set(extraMapPaths, forKey: "extraMaps")
        maps = Self.loadMaps(extra: extraMapPaths)
        if let first = found.compactMap({ p in maps.first { $0.id == "img:" + p && $0.isSupported } }).first { selectMap(first.id) }
    }

    func removeExtraMap(_ path: String) {
        extraMapPaths.removeAll { $0 == path }
        UserDefaults.standard.set(extraMapPaths, forKey: "extraMaps")
        maps = Self.loadMaps(extra: extraMapPaths)
        if selectedMap == nil, selectedTileSource == nil { selectedMapID = maps.first { $0.isSupported }?.id }
    }

    func selectMap(_ id: String) {
        selectedMapID = id
        if selectedMap != nil { lastGarminID = id }
        plan?.map = routingMap
        UserDefaults.standard.set(id, forKey: "mapID")
    }

    func select(_ id: String?) {
        renameWork?.cancel()               // a pending slow-click rename must not start after the selection moved on
        if wptEdit != nil, id != wptEdit?.url.path { guard confirmLeaveWaypointEdit() else { return } }
        if edit != nil, id != edit?.url.path {
            guard confirmLeaveEdit() else { return }
            // leaving the editor by picking another track: the editor closes, the profile follows the new track
            showPoints = false
        }
        selection = id
        guard let id, let tree, let node = tree.find(id) else { return }
        if node.isFolder {
            if searchActive { searchQuery = ""; NotificationCenter.default.post(name: .searchCleared, object: nil) }
            displayedFolder = id
            showProfile = false
            foregroundPath = nil
            refreshTracks(fit: true)
        } else {
            // keep the surrounding folder context; make sure the file belongs to what is displayed
            let parent = node.url.deletingLastPathComponent().path
            let inside = includeSubfolders && (displayedFolder.map { id.hasPrefix($0 + "/") } ?? false)
            if !searchActive, displayedFolder != parent && !inside { displayedFolder = parent }
            foregroundPath = id
            showProfile = !(cache[id]?.isWaypointFile == true || waypointColors[id] != nil)     // single click: show the elevation profile (not for waypoints)
            if searchActive { reorderTracks(); viewRevision += 1 } else { refreshTracks(fit: false) }
            fitSelection(id)
        }
    }

    /// Selecting a track on the map highlights its row in the folder tree as well.
    func selectFromMap(_ id: String) {
        selection = id
        foregroundPath = id
        showProfile = true                   // single click on the map: show the elevation profile
        reorderTracks()
        // the list follows: only this file is marked, and its row scrolls to the top
        NotificationCenter.default.post(name: .fileKeySelect, object: id, userInfo: ["extend": false])
        for delay in [0.15, 0.5] {         // again after the list has settled (it may scroll by itself when its selection changes)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.foregroundPath == id else { return }
                scrollFileListToTop(id, rows: self.fileRows)
            }
        }
    }

    /// A track picked in the file list (mouse or arrow keys) is shown completely right away; if it is not loaded yet, as soon as it is.
    /// Several files marked in the list: the whole group is brought into view.
    func setMultiSelected(_ ids: Set<String>) {
        let m: Set<String> = ids.count > 1 ? ids : []
        guard m != multiSelected else { return }
        multiSelected = m
        let files = m.compactMap { cache[$0] }
        if !files.isEmpty { fit(to: files) }
    }

    private func fitSelection(_ id: String) {
        guard let f = cache[id] else { pendingFit = id; return }
        pendingFit = nil
        func apply() {
            fit(to: [f])
            if f.isWaypointFile { view.worldSize = min(view.worldSize, 256.0 * 16384); viewRevision += 1 }      // single waypoints: not closer than zoom 14
        }
        apply()
        // the elevation profile may open with this selection and shrink the map: fit again once the new size is known
        let h0 = view.height
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.foregroundPath == id, self.multiSelected.isEmpty, self.view.height != h0 else { return }
            apply()
        }
    }

    // MARK: tracks

    func refreshTracks(fit doFit: Bool) {
        if searchActive { runSearch(fit: doFit); return }
        guard let tree, let folder = displayedFolder, let node = tree.find(folder) else { tracks = []; setFiles([]); return }
        if includeSubfolders {
            // reading a whole folder tree can take a moment: do it off the main thread
            loadGeneration += 1
            let gen = loadGeneration
            if loadingCount == 0 { loadingCount = 1 }
            Task.detached(priority: .userInitiated) {
                let nodes = node.fileNodesRecursive()
                await MainActor.run {
                    guard gen == self.loadGeneration else { return }
                    self.setFiles(nodes)
                    self.startLoading(urls: nodes.map { $0.url }, fit: doFit)
                }
            }
        } else {
            let nodes = (node.children ?? []).filter { !$0.isFolder }
            setFiles(nodes)
            startLoading(urls: nodes.map { $0.url }, fit: doFit)
        }
    }

    func setFiles(_ nodes: [FolderNode]) { fileNodes = nodes; applySort() }

    /// Notes which loaded files are waypoint-only files (they get their own icon and are sorted first); re-sorts when that changes.
    func refreshWaypointKinds() {
        if let p = pendingFit, p == foregroundPath, cache[p] != nil { fitSelection(p) }
        var changed = false
        var iconsFromFiles = false
        var newStyles = styles
        for f in tracks {
            let st = Self.style(of: f)
            if newStyles[f.id] != st { newStyles[f.id] = st }
            if fileIcons[f.id] != f.embeddedIcon { fileIcons[f.id] = f.embeddedIcon; iconsFromFiles = true }   // the file is the only source
            f.iconOverride = fileIcons[f.id]
            let ic = f.embeddedIconColor.flatMap { Waypoint.rgb(fromHex: $0) }
            if fileIconColors[f.id] != ic { fileIconColors[f.id] = ic; changed = true }
            if !f.isWaypointFile, trackKinds[f.id] == nil { trackKinds[f.id] = f.kind; changed = true }
        }
        if iconsFromFiles { changed = true }
        if newStyles != styles { styles = newStyles }
        for f in tracks where f.isWaypointFile {
            let m = IconStyle.marker(file: f, sym: f.waypoints.first?.sym ?? "")
            if waypointColors[f.id] != m.rgb || waypointIcons[f.id] != m.symbol {
                waypointColors[f.id] = m.rgb; waypointIcons[f.id] = m.symbol; waypointRank[f.id] = Waypoint.colorRank(rgb: m.rgb); changed = true
            }
        }
        if changed { applySort() }
    }

    func applySort() {
        fileRows = fileSort.sorted(fileNodes, waypointRank: { self.waypointRank[$0.id] },
                                    iconKey: { self.waypointIcons[$0.id] ?? self.fileIcons[$0.id] ?? (self.trackKinds[$0.id] ?? .other).iconName })
        fileRevision += 1
    }

    func startLoading(urls: [URL], fit doFit: Bool) {
        loadGeneration += 1
        let gen = loadGeneration
        let missing = urls.filter { cache[$0.path] == nil && !failed.contains($0.path) }
        tracks = urls.compactMap { cache[$0.path] }
        reorderTracks()
        refreshWaypointKinds()
        if missing.isEmpty { if doFit { fit(to: tracks) }; return }
        loadingCount = missing.count
        let wanted = foregroundPath
        Task.detached(priority: .userInitiated) {
            // Parse in parallel batches; publish progressively.
            let batch = 24
            var i = 0
            while i < missing.count {
                let chunk = Array(missing[i..<min(i + batch, missing.count)])
                let results = await withTaskGroup(of: (String, GPXFile?).self) { g -> [(String, GPXFile?)] in
                    for u in chunk { g.addTask { (u.path, GPXFile.load(u)) } }
                    var r: [(String, GPXFile?)] = []
                    for await x in g { r.append(x) }
                    return r
                }
                i += batch
                let done = i
                let stop: Bool = await MainActor.run {
                    for (p, f) in results { if let f { self.cache[p] = f } else { self.failed.insert(p) } }
                    guard gen == self.loadGeneration else { return true }
                    self.loadingCount = max(0, missing.count - done)
                    // publish the growing track list at most twice a second (each publish re-renders the overlay)
                    if Date().timeIntervalSince(self.lastTrackPublish) > 0.5 {
                        self.lastTrackPublish = Date()
                        self.tracks = urls.compactMap { self.cache[$0.path] }
                        self.reorderTracks()
                        self.refreshWaypointKinds()
                    }
                    return false
                }
                if stop { return }
            }
            await MainActor.run {
                guard gen == self.loadGeneration else { return }
                self.loadingCount = 0
                self.tracks = urls.compactMap { self.cache[$0.path] }
                self.reorderTracks()
                self.refreshWaypointKinds()
                if doFit { self.fit(to: self.tracks) }
                else if let w = wanted, let f = self.cache[w] { self.fitIfOffscreenLoaded(f) }
            }
        }
    }

    private func fitIfOffscreenLoaded(_ f: GPXFile) {
        let (x0, y0) = view.world(.zero), (x1, y1) = view.world(CGPoint(x: view.width, y: view.height))
        if f.maxX < x0 || f.minX > x1 || f.maxY < y0 || f.minY > y1 { fit(to: [f]) }
    }

    func reorderTracks() {
        guard let fg = foregroundPath else { return }
        var t = tracks.filter { $0.id != fg }
        if let f = tracks.first(where: { $0.id == fg }) { t.append(f) }
        tracks = t
    }

    func fit(to files: [GPXFile]) {
        let withData = files.filter { $0.minX.isFinite }
        guard !withData.isEmpty else { return }
        let x0 = withData.map(\.minX).min()!, x1 = withData.map(\.maxX).max()!
        let y0 = withData.map(\.minY).min()!, y1 = withData.map(\.maxY).max()!
        let w = max(x1 - x0, 1e-7), h = max(y1 - y0, 1e-7)
        let pad = 0.88
        let ws = min(Double(view.width) * pad / w, Double(view.height) * pad / h)
        view.mx = (x0 + x1) / 2; view.my = (y0 + y1) / 2
        view.worldSize = max(1024.0, min(67108864.0, ws))
        viewRevision += 1
    }

    func fitAll() { fit(to: tracks); fitRequest += 1 }
    func fitForeground() { if let f = foreground { fit(to: [f]) } }

    // MARK: open (double-click), profile

    /// Bring a GPX file into view: select it, zoom so the whole track is visible, show the elevation profile.
    func openTrack(_ id: String, fit doFit: Bool = true) {
        renameWork?.cancel()
        select(id)
        guard foregroundPath == id else { return }
        if cache[id]?.isWaypointFile == true { focusWaypoint(id); startWaypointEdit(id); return }
        showProfile = true
        showPoints = true
        startEdit()                       // points panel + direct editing (move / add / delete points)
        updateProfile()
        if !doFit { return }
        if let f = cache[id] { fit(to: [f]) }
        else {
            let url = URL(fileURLWithPath: id)
            Task.detached {
                let f = GPXFile.load(url)
                await MainActor.run {
                    guard let f else { return }
                    self.cache[id] = f
                    if f.isWaypointFile { self.showPoints = false; self.showProfile = false; self.focusWaypoint(id) } else { self.fit(to: [f]) }
                }
            }
        }
    }

    /// Waypoint files have no track to edit or profile to show: just centre on the waypoint(s) at a readable zoom.
    func focusWaypoint(_ id: String) {
        guard let f = cache[id], f.isWaypointFile else { return }
        showPoints = false; showProfile = false
        fit(to: [f])
        view.worldSize = min(view.worldSize, 256.0 * 16384)     // not closer than zoom 14
        viewRevision += 1
    }

    func updateProfileIfEditing() { if showProfile, edit != nil { updateProfile() } }

    func updateProfile() {
        profileCursor = nil
        if let e = edit { profile = e.document.profile(); return }
        guard let id = foregroundPath else { profile = nil; return }
        let url = URL(fileURLWithPath: id)
        Task.detached(priority: .userInitiated) {
            let p = GPXDocument.parse(url)?.profile()
            await MainActor.run { if self.foregroundPath == id, self.edit == nil { self.profile = p } }
        }
    }

    // MARK: editing

    func startEdit() {
        if let id = foregroundPath, cache[id]?.isWaypointFile == true { startWaypointEdit(id); return }
        guard edit == nil, let id = foregroundPath, let doc = GPXDocument.parse(URL(fileURLWithPath: id)) else { return }
        edit = EditSession(url: URL(fileURLWithPath: id), doc: doc)
        if showProfile { updateProfile() }
    }

    /// Closes the waypoint editor (asks first if there are unsaved changes). The elevation profile stays.
    func exitEditor() {
        guard edit != nil else { return }
        if confirmLeaveEdit() { showPoints = false }
    }

    /// ESC peels off one layer at a time: editor, then elevation profile, then the route selection itself.
    func escape() {
        if wptEdit != nil { exitWaypointEdit(); return }
        if edit != nil { exitEditor(); return }
        if showProfile { showProfile = false; return }
        if foregroundPath != nil || selection != nil {
            foregroundPath = nil          // route is drawn normally again
            selection = nil               // and no longer highlighted in the list
            profileHighlight = nil
        }
    }

    /// Returns true if it is fine to leave the current edit session (saved, discarded, or nothing changed).
    func confirmLeaveEdit() -> Bool {
        guard let e = edit else { return true }
        if !e.dirty { edit = nil; if showProfile { updateProfile() }; return true }
        let a = NSAlert()
        a.messageText = "Save changes to “\(e.url.lastPathComponent)”?"
        a.informativeText = "The track has been edited and not saved yet."
        a.addButton(withTitle: "Save")
        a.addButton(withTitle: "Discard")
        a.addButton(withTitle: "Cancel")
        switch a.runModal() {
        case .alertFirstButtonReturn: return saveEdit()
        case .alertSecondButtonReturn: discardEdit(); return true
        default: return false
        }
    }

    func discardEdit() {
        edit = nil
        if showProfile { updateProfile() }
    }

    /// Overwrites the original file (a backup copy is kept in Application Support).
    @discardableResult
    func saveEdit() -> Bool {
        guard let e = edit else { return true }
        if e.url.pathExtension.lowercased() != "gpx" {
            // other formats are never overwritten: the edited track is saved as a new GPX file
            let n = NSAlert()
            n.messageText = "“\(e.url.lastPathComponent)” is not a GPX file."
            n.informativeText = "The original stays unchanged; the edited track is saved as a new GPX file."
            n.addButton(withTitle: "Save as GPX …"); n.addButton(withTitle: "Cancel")
            guard n.runModal() == .alertFirstButtonReturn else { return false }
            saveEditAs()
            return edit == nil
        }
        let a = NSAlert()
        a.messageText = "Overwrite “\(e.url.lastPathComponent)”?"
        a.informativeText = "The file will be replaced with the edited track. Additional Garmin extensions (e.g. heart rate) are not kept. A backup copy of the original is made."
        a.addButton(withTitle: "Overwrite")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return false }
        if let bk = backup(e.url) { _ = bk } else {
            let f = NSAlert(); f.messageText = "Backup failed – not saved."; f.runModal(); return false
        }
        return write(e, to: e.url)
    }

    func saveEditAs() {
        guard let e = edit else { return }
        let p = NSSavePanel()
        p.directoryURL = e.url.deletingLastPathComponent()
        p.nameFieldStringValue = e.url.deletingPathExtension().lastPathComponent + " (edited).gpx"
        p.allowedContentTypes = []
        p.prompt = "Save"
        guard p.runModal() == .OK, let u = p.url else { return }
        _ = write(e, to: u)
    }

    func backup(_ url: URL) -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("GPXOrganizer/Backups") else { return nil }
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let dst = base.appendingPathComponent("\(f.string(from: Date()))-\(url.lastPathComponent)")
        do { try fm.copyItem(at: url, to: dst); return dst } catch { return nil }
    }

    private func write(_ e: EditSession, to url: URL) -> Bool {
        do {
            try e.document.xml().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let a = NSAlert(); a.messageText = "Saving failed"; a.informativeText = error.localizedDescription; a.runModal()
            return false
        }
        cache.removeValue(forKey: url.path); failed.remove(url.path)
        edit = nil
        let keep = url.path
        reloadTree()
        foregroundPath = keep
        selection = keep
        if showProfile { updateProfile() }
        return true
    }
}

/// What the lower chart shows.
enum ProfileMode: String, CaseIterable, Identifiable {
    case elevation, speed, both
    var id: String { rawValue }
    var title: String { switch self { case .elevation: return "Elevation"; case .speed: return "Speed"; case .both: return "Both" } }
}
