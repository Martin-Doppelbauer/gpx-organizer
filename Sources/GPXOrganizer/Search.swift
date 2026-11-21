import SwiftUI
import BCCore

extension Notification.Name { static let searchCleared = Notification.Name("searchCleared") }

final class SearchState: ObservableObject { @Published var text = "" }

extension AppModel {
    var searchActive: Bool { !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Called (debounced) when the search field changes. An empty query returns to the selected folder.
    func setSearch(_ q: String) {
        guard q != searchQuery else { return }
        searchQuery = q
        if wptEdit != nil || edit != nil { guard confirmLeaveAnyEdit() else { return } }
        foregroundPath = nil; showProfile = false
        if searchActive { refreshTracks(fit: true) } else { refreshTracks(fit: true) }
    }

    func clearSearch() {
        guard !searchQuery.isEmpty else { return }
        searchQuery = ""
        NotificationCenter.default.post(name: .searchCleared, object: nil)
    }

    func confirmLeaveAnyEdit() -> Bool { confirmLeaveWaypointEdit() && confirmLeaveEdit() }

    static func fold(_ s: String) -> String { s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }

    /// Searches the whole folder tree: file name, folder path, track kind, track name, waypoint names and symbols.
    /// Files not read yet are read first (fast: the whole tree takes about a second).
    func runSearch(fit doFit: Bool) {
        guard let tree else { return }
        let terms = Self.fold(searchQuery).split(separator: " ").map(String.init)
        loadGeneration += 1
        let gen = loadGeneration
        loadingCount = max(loadingCount, 1)
        let rootPath = tree.id
        Task.detached(priority: .userInitiated) {
            let all = tree.fileNodesRecursive()
            let missing: [URL] = await MainActor.run { all.filter { self.cache[$0.id] == nil && !self.failed.contains($0.id) }.map(\.url) }
            var parsed: [(String, GPXFile?)] = []
            var i = 0
            while i < missing.count {
                let chunk = Array(missing[i..<min(i + 32, missing.count)])
                let part = await withTaskGroup(of: (String, GPXFile?).self) { g -> [(String, GPXFile?)] in
                    for u in chunk { g.addTask { (u.path, GPXFile.load(u)) } }
                    var r: [(String, GPXFile?)] = []
                    for await x in g { r.append(x) }
                    return r
                }
                parsed.append(contentsOf: part)
                i += 32
                if await MainActor.run(body: { gen != self.loadGeneration }) { return }
            }
            await MainActor.run {
                guard gen == self.loadGeneration else { return }
                for (p, f) in parsed { if let f { self.cache[p] = f } else { self.failed.insert(p) } }
                var hits: [FolderNode] = []
                for n in all {
                    var hay = Self.fold(String(n.id.dropFirst(rootPath.count)) + " " + n.url.pathExtension)
                    if let f = self.cache[n.id] {
                        hay += " " + Self.fold(f.name + " " + (f.isWaypointFile ? "waypoint" : f.kind.title))
                        for w in f.waypoints { hay += " " + Self.fold(w.name + " " + w.sym) }
                    }
                    if terms.allSatisfy({ hay.contains($0) }) { hits.append(n) }
                }
                self.loadingCount = 0
                self.setFiles(hits)
                self.startLoading(urls: hits.map { $0.url }, fit: doFit)
            }
        }
    }
}
