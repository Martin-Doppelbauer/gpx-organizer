import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BCCore

enum FileSort: String, CaseIterable, Identifiable {
    case name, icon, type, dateAsc, dateDesc
    var id: String { rawValue }
    var title: String {
        switch self { case .name: return "Name (alphabetical)"; case .icon: return "Icon group, then name"; case .type: return "Type"
        case .dateAsc: return "Date ascending"; case .dateDesc: return "Date descending" }
    }
    /// Waypoint files first, then all routes; each group sorted by the chosen criterion.
    func sorted(_ n: [FolderNode], waypointRank: (FolderNode) -> Int?, iconKey: (FolderNode) -> String) -> [FolderNode] {
        func byName(_ a: FolderNode, _ b: FolderNode) -> Bool { a.name.localizedStandardCompare(b.name) == .orderedAscending }
        if self == .name { return n.sorted(by: byName) }
        if self == .icon {
            return n.sorted {
                let ra = waypointRank($0) ?? 99, rb = waypointRank($1) ?? 99
                if ra != rb { return ra < rb }
                let a = iconKey($0), b = iconKey($1)
                return a != b ? a < b : byName($0, $1)
            }
        }
        let wp = n.filter { waypointRank($0) != nil }, rest = n.filter { waypointRank($0) == nil }
        // waypoints: grouped by color (red … grey), inside a color by the chosen criterion
        var byColor: [Int: [FolderNode]] = [:]
        for w in wp { byColor[waypointRank(w) ?? 99, default: []].append(w) }
        let ordered = byColor.keys.sorted().flatMap { sortedGroup(byColor[$0] ?? []) }
        return ordered + sortedGroup(rest)
    }

    private func sortedGroup(_ n: [FolderNode]) -> [FolderNode] {
        func byName(_ a: FolderNode, _ b: FolderNode) -> Bool { a.name.localizedStandardCompare(b.name) == .orderedAscending }
        switch self {
        case .name, .icon: return n.sorted(by: byName)
        case .type:
            return n.sorted {
                let a = $0.url.pathExtension.lowercased(), b = $1.url.pathExtension.lowercased()
                return a != b ? a < b : byName($0, $1)
            }
        case .dateAsc:
            return n.sorted {
                let a = $0.modified ?? .distantPast, b = $1.modified ?? .distantPast
                return a != b ? a < b : byName($0, $1)
            }
        case .dateDesc:
            return n.sorted {
                let a = $0.modified ?? .distantPast, b = $1.modified ?? .distantPast
                return a != b ? a > b : byName($0, $1)
            }
        }
    }
}

extension Notification.Name {
    static let fileKeySelect = Notification.Name("fileKeySelect")
    static let fileSelectAll = Notification.Name("fileSelectAll")
}

/// Scrolls the file list so that the row of `id` is at the very top (as far as the list allows).
@MainActor func scrollFileListToTop(_ id: String, rows: [FolderNode], offsetFraction: CGFloat = 0, window: NSWindow? = nil) {
    guard let idx = rows.firstIndex(where: { $0.id == id }), let root = window?.contentView ?? NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView,
          let table = findTable(in: root, rows: rows.count), let clip = table.enclosingScrollView?.contentView else { return }
    let y = table.rect(ofRow: idx).minY - clip.bounds.height * offsetFraction
    var o = clip.constrainBoundsRect(NSRect(origin: NSPoint(x: 0, y: y), size: clip.bounds.size)).origin
    o.x = clip.bounds.origin.x
    clip.scroll(to: o)
    table.enclosingScrollView?.reflectScrolledClipView(clip)
    table.needsLayout = true; table.layoutSubtreeIfNeeded(); table.setNeedsDisplay(table.visibleRect)      // no half-drawn rows
}

private func findTable(in v: NSView, rows: Int) -> NSTableView? {
    if let t = v as? NSTableView, t.numberOfRows == rows { return t }
    for c in v.subviews { if let t = findTable(in: c, rows: rows) { return t } }
    return nil
}

/// ⌘A while the keyboard is neither in a text field nor in the file list selects all files of the list.
enum FileKeys {
    private static var monitor: Any?
    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { e in
            if e.keyCode == 0, e.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
               !(NSApp.keyWindow?.firstResponder is NSText), !(NSApp.keyWindow?.firstResponder is FileNSTableView),
               AppModel.keyModel() != nil, NSApp.keyWindow?.sheets.isEmpty ?? true {
                NotificationCenter.default.post(name: .fileSelectAll, object: nil)
                return nil
            }
            return e
        }
    }
}

/// Left column: folder structure on top, files of the selected folder below, movable divider between them.
struct SidebarView: View, Equatable {
    let tree: FolderNode?
    let displayedFolder: String?
    let foreground: String?
    let dropTarget: String?
    let renamingID: String?
    let fileRevision: Int
    let sort: FileSort
    let files: [FolderNode]
    @StateObject private var search = SearchState()
    let model: AppModel          // plain reference: not observed, so frequent model changes do not rebuild the lists

    static func == (a: SidebarView, b: SidebarView) -> Bool {
        a.tree === b.tree && a.displayedFolder == b.displayedFolder && a.foreground == b.foreground && a.dropTarget == b.dropTarget
            && a.renamingID == b.renamingID && a.fileRevision == b.fileRevision && a.sort == b.sort
    }

    var body: some View {
        VStack(spacing: 0) {
            VSplitView {
                folderPane
                    .frame(minHeight: 130, idealHeight: 260)
                filePane
                    .frame(minHeight: 130, idealHeight: 340)
            }
            Divider()
            RouteListFooter().environmentObject(model)
        }
    }

    // MARK: folders (top)

    private var folderPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill.badge.gearshape").foregroundStyle(.blue)
                Text("Folders").font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.blue.opacity(0.10))
            Divider()
            if let tree {
                FolderOutlineView(tree: tree, displayedFolder: displayedFolder, renamingID: renamingID, fileRevision: fileRevision, model: model)
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
            Divider()
            SidebarFooter(chooseFolder: chooseFolder).environmentObject(model)
                .background(Color.blue.opacity(0.06))
        }
    }

    // MARK: files (bottom)

    private var folderTitle: String {
        guard let f = displayedFolder else { return "Files" }
        return (f as NSString).lastPathComponent
    }

    private var filePane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(model.searchQuery.isEmpty ? folderTitle : "Search results").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("\(files.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Picker("Sort by", selection: Binding(get: { sort }, set: { model.fileSort = $0 })) {
                        ForEach(FileSort.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Toggle("Reverse Order", isOn: Binding(get: { model.fileSortReversed }, set: { model.fileSortReversed = $0 }))
                } label: {
                    Label(sort.title + (model.fileSortReversed ? " ↑" : ""), systemImage: "arrow.up.arrow.down").font(.caption)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Sort files: name, type, date ascending, date descending")
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.secondary.opacity(0.12))
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                TextField("Search all folders", text: $search.text).textFieldStyle(.plain).font(.callout)
                    .help("Searches file names, folders, track type, track names, waypoint names and symbols in all folders")
                if !search.text.isEmpty {
                    Button { search.text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.secondary.opacity(0.06))
            .onChange(of: search.text) { text in
                let q = text
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { if q == search.text { model.setSearch(q) } }
            }
            .onReceive(model.menuEvents(.searchCleared)) { _ in if !search.text.isEmpty { search.text = "" } }
            Divider()
            FileTableView(files: files, fileRevision: fileRevision, renamingID: renamingID, foreground: foreground, model: model)
                .onAppear { FileKeys.install() }
        }
    }

    func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.directoryURL = model.rootURL
        p.prompt = "Choose"
        if p.runModal() == .OK, let u = p.url { model.chooseRoot(u) }
    }
}


