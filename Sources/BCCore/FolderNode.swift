import Foundation

/// Mirror of the on-disk folder structure (folders + track files: GPX, TRC, IKT, PTM, AXE, OVL, TRAIL).
/// Sub-folders are read lazily when they are first opened, so even large folders appear instantly.
public final class FolderNode: Identifiable, Hashable {
    public let url: URL
    public let id: String            // path (computed once)
    public let numericID: Int        // cheap, unique identity for list diffing
    public let isFolder: Bool
    public let modified: Date?       // modification date (files)
    private var loadedChildren: [FolderNode]?
    private var loaded = false
    private let lock = NSLock()
    public var name: String { url.lastPathComponent }

    /// nil for files; for folders the (lazily read, cached) entries.
    public var children: [FolderNode]? {
        guard isFolder else { return nil }
        lock.lock(); defer { lock.unlock() }
        if !loaded { loadedChildren = Self.readChildren(url); loaded = true }
        return loadedChildren
    }

    private static let counterLock = NSLock()
    private static var counter = 0

    init(url: URL, isFolder: Bool, modified: Date? = nil) {
        self.url = url; self.isFolder = isFolder; self.modified = modified
        self.id = url.path
        Self.counterLock.lock(); Self.counter += 1; numericID = Self.counter; Self.counterLock.unlock()
    }

    public static func == (a: FolderNode, b: FolderNode) -> Bool { a.url == b.url }
    public func hash(into h: inout Hasher) { h.combine(url) }

    public static func build(_ url: URL) -> FolderNode { FolderNode(url: url, isFolder: true) }

    private static func readChildren(_ url: URL) -> [FolderNode] {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .contentModificationDateKey],
                                                 options: [.skipsHiddenFiles])) ?? []
        // In the home folder, never touch the folders macOS protects for other apps (Music, Photos …):
        // listing or counting them would make macOS ask the user for access that this program does not need.
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL
        let skipInHome: Set<String> = ["Music", "Pictures", "Movies", "Library", "Applications", "Public"]
        let isHome = url.standardizedFileURL == home
        var kids: [FolderNode] = []
        for u in items {
            if isHome, skipInHome.contains(u.lastPathComponent) { continue }
            let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            if v?.isDirectory == true, v?.isPackage != true { kids.append(FolderNode(url: u, isFolder: true)) }
            else if ForeignTracks.isSupported(u) {
                let m = try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                kids.append(FolderNode(url: u, isFolder: false, modified: m))
            }
        }
        kids.sort {
            if $0.isFolder != $1.isFolder { return $0.isFolder }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return kids
    }

    /// Sub-folders only (nil when there are none, so the list shows no disclosure arrow).
    public var folderChildren: [FolderNode]? {
        let f = (children ?? []).filter { $0.isFolder }
        return f.isEmpty ? nil : f
    }

    /// Number of track files directly inside this folder.
    public var fileCount: Int { (children ?? []).reduce(0) { $0 + ($1.isFolder ? 0 : 1) } }

    private var cachedTotal: Int?
    /// Number of track files in this folder and all folders below it, at any depth (cached).
    public var totalFileCount: Int {
        lock.lock(); let c = cachedTotal; lock.unlock()
        if let c { return c }
        let n = isFolder ? (children ?? []).reduce(0) { $0 + ($1.isFolder ? $1.totalFileCount : 1) } : 1
        lock.lock(); cachedTotal = n; lock.unlock()
        return n
    }

    /// All track files below this folder as nodes (reads the whole subtree).
    public func fileNodesRecursive() -> [FolderNode] {
        guard isFolder else { return [self] }
        return (children ?? []).flatMap { $0.fileNodesRecursive() }
    }

    /// Track files directly inside this folder (no sub-folders).
    public func directGPXURLs() -> [URL] {
        guard isFolder else { return [url] }
        return (children ?? []).filter { !$0.isFolder }.map { $0.url }
    }

    /// All track files below this folder (reads the whole subtree).
    public func gpxURLs() -> [URL] {
        guard isFolder else { return [url] }
        return (children ?? []).flatMap { $0.gpxURLs() }
    }

    /// Finds a node by path, reading only the folders on the way.
    public func find(_ path: String) -> FolderNode? {
        if id == path { return self }
        guard isFolder, path.hasPrefix(id.hasSuffix("/") ? id : id + "/") else { return nil }
        for c in children ?? [] { if let r = c.find(path) { return r } }
        return nil
    }
}
