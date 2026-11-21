import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BCCore

enum FileSort: String, CaseIterable, Identifiable {
    case name, type, dateAsc, dateDesc
    var id: String { rawValue }
    var title: String {
        switch self { case .name: return "Name"; case .type: return "Type"
        case .dateAsc: return "Date ascending"; case .dateDesc: return "Date descending" }
    }
    /// Waypoint files first, then all routes; each group sorted by the chosen criterion.
    func sorted(_ n: [FolderNode], waypointRank: (FolderNode) -> Int?) -> [FolderNode] {
        let wp = n.filter { waypointRank($0) != nil }, rest = n.filter { waypointRank($0) == nil }
        // waypoints: grouped by colour (red … grey), inside a colour by the chosen criterion
        var byColor: [Int: [FolderNode]] = [:]
        for w in wp { byColor[waypointRank(w) ?? 99, default: []].append(w) }
        let ordered = byColor.keys.sorted().flatMap { sortedGroup(byColor[$0] ?? []) }
        return ordered + sortedGroup(rest)
    }

    private func sortedGroup(_ n: [FolderNode]) -> [FolderNode] {
        func byName(_ a: FolderNode, _ b: FolderNode) -> Bool { a.name.localizedStandardCompare(b.name) == .orderedAscending }
        switch self {
        case .name: return n.sorted(by: byName)
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

/// Modifier keys at the last mouse-down (taken from the event itself, so Shift/Cmd are reliable in tap handlers).
enum ClickMods {
    static var flags: NSEvent.ModifierFlags = []
    static var clicks = 1
    private static var monitor: Any?
    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { e in
            flags = e.modifierFlags; clicks = e.clickCount
            return e
        }
    }
}

final class RootOpen: ObservableObject { @Published var open = true }

/// true after a click in the file list: arrow keys then move the selection through it
enum FileListState { static var active = false }
extension Notification.Name { static let fileKeySelect = Notification.Name("fileKeySelect") }

final class MultiSelection: ObservableObject {
    @Published var ids: Set<String> = []
    @Published var scrollTo: String?
    var anchor: String?
}

private func findTable(in v: NSView, rows: Int) -> NSTableView? {
    if let t = v as? NSTableView, t.numberOfRows == rows { return t }
    for c in v.subviews { if let t = findTable(in: c, rows: rows) { return t } }
    return nil
}

/// Arrow / Page keys step through the file list (like selecting the next row), when it was clicked last.
enum FileKeys {
    private static var monitor: Any?
    static func install(model: AppModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak model] e in
            guard let model, FileListState.active,
                  e.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  !(NSApp.keyWindow?.firstResponder is NSText), model.renamingID == nil else { return e }
            let step: Int
            switch e.keyCode {
            case 125: step = 1        // down
            case 126: step = -1       // up
            case 121: step = 10       // page down
            case 116: step = -10      // page up
            default: return e
            }
            let rows = model.fileRows
            guard !rows.isEmpty else { return e }
            let cur = model.foregroundPath.flatMap { p in rows.firstIndex { $0.id == p } }
            let next = cur.map { min(max($0 + step, 0), rows.count - 1) } ?? (step > 0 ? 0 : rows.count - 1)
            let id = rows[next].id
            NotificationCenter.default.post(name: .fileKeySelect, object: id)
            // keep the new row in view: the file list is an NSTableView with one row per file
            if let root = NSApp.keyWindow?.contentView, let table = findTable(in: root, rows: rows.count) { table.scrollRowToVisible(next) }
            model.select(id)
            return nil
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
    @StateObject private var multi = MultiSelection()
    @StateObject private var rootOpen = RootOpen()
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

    private func dropBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { model.dropTarget == id },
                set: { on in if on { model.dropTarget = id } else if model.dropTarget == id { model.dropTarget = nil } })
    }

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
                List(selection: Binding(get: { model.displayedFolder }, set: { if let v = $0 { model.select(v) } })) {
                    DisclosureGroup(isExpanded: $rootOpen.open) {
                        OutlineGroup(tree.folderChildren ?? [], id: \.id, children: \.folderChildren) { node in
                            folderRow(node, isRoot: false)
                        }
                    } label: {
                        folderRow(tree, isRoot: true)
                    }
                }
                .listStyle(.inset)
                .environment(\.defaultMinListRowHeight, 27)
                .onKeyPress(.return) {
                    if let f = model.displayedFolder, f != tree.id, model.renamingID == nil { model.beginRename(f); return .handled }
                    return .ignored
                }
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
            Divider()
            SidebarFooter(chooseFolder: chooseFolder).environmentObject(model)
                .background(Color.blue.opacity(0.06))
        }
    }

    @ViewBuilder
    private func folderRow(_ node: FolderNode, isRoot: Bool) -> some View {
        Group {
            if renamingID == node.id {
                InlineRenameField(initial: node.name, onCommit: { model.commitRename(node.id, text: $0) }, onCancel: { model.cancelRename() })
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "folder.fill").font(.system(size: 16))
                        .foregroundStyle(Color.blue)
                    Text(node.name).font(.system(size: 13, weight: isRoot ? .semibold : .medium)).lineLimit(1)
                    Spacer(minLength: 4)
                    let n = node.totalFileCount
                    if n > 0 { Text("\(n)").font(.caption).monospacedDigit().foregroundStyle(.secondary) }
                }
            }
        }
        .tag(node.id)
        .contentShape(Rectangle())
        .background(dropTarget == node.id ? Color.accentColor.opacity(0.3) : Color.clear)
        .onDrop(of: [UTType.fileURL], delegate: FolderDropDelegate(model: model, folder: node.url, targeted: dropBinding(node.id)))
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.enterFolder(node.url) })
        .simultaneousGesture(TapGesture(count: 1).onEnded { FileListState.active = false; model.rowClicked(node.id) })
        .contextMenu {
            Button("New Folder …") { model.newFolder(in: node.url) }
            if !isRoot {
                Button("Rename …") { model.beginRename(node.id) }
            }
            Divider()
            StyleMenu(ids: (node.children ?? []).filter { !$0.isFolder }.map { $0.id }).environmentObject(model)
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
                Text(folderTitle).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("\(files.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Picker("Sort by", selection: Binding(get: { sort }, set: { model.fileSort = $0 })) {
                        ForEach(FileSort.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(sort.title, systemImage: "arrow.up.arrow.down").font(.caption)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Sort files: name, type, date ascending, date descending")
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.secondary.opacity(0.12))
            Divider()
            List {
                ForEach(files, id: \.numericID) { node in fileRow(node) }
            }
            .listStyle(.inset)
            .onChange(of: displayedFolder) { _ in multi.ids = [] }
            .onAppear { ClickMods.install(); FileKeys.install(model: model) }
            .onReceive(NotificationCenter.default.publisher(for: .fileKeySelect)) { n in
                if let id = n.object as? String { multi.ids = [id]; multi.anchor = id; multi.scrollTo = id }
            }
            .onKeyPress(.return) {
                if let s = model.foregroundPath, model.renamingID == nil { model.beginRename(s); return .handled }
                return .ignored
            }
            .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                guard let f = displayedFolder else { return false }
                return model.handleDrop(providers, into: URL(fileURLWithPath: f))
            }
        }
    }

    private var selectedIDs: Set<String> {
        return multi.ids.count > 1 ? multi.ids : Set(model.foregroundPath.map { [$0] } ?? [])
    }

    @ViewBuilder
    private func fileRow(_ node: FolderNode) -> some View {
        let isSel = selectedIDs.contains(node.id)
        Group {
            if renamingID == node.id {
                InlineRenameField(initial: node.url.deletingPathExtension().lastPathComponent,
                                  onCommit: { model.commitRename(node.id, text: $0) }, onCancel: { model.cancelRename() })
            } else {
                HStack(spacing: 8) {
                    let ic = model.rowIcon(node.id)
                    if ic.disc {
                        Image(systemName: ic.name)
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(ic.color))
                            .overlay(Circle().stroke(isSel ? Color.white : Color.clear, lineWidth: 1.5))
                    } else {
                        Image(systemName: ic.name).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSel ? Color.white : ic.color).frame(width: 22)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.url.deletingPathExtension().lastPathComponent).lineLimit(1)
                            .foregroundStyle(isSel ? Color.white : Color.primary)
                        Text(caption(node)).font(.caption2)
                            .foregroundStyle(isSel ? Color.white.opacity(0.8) : Color.secondary).lineLimit(1)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .listRowBackground(isSel ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor).padding(.horizontal, 4) : nil)
        .onDrag {
            model.dragSource = node.id
            model.dragSources = selectedIDs.contains(node.id) && selectedIDs.count > 1
                ? files.filter { selectedIDs.contains($0.id) }.map(\.id) : [node.id]
            return NSItemProvider(object: node.url as NSURL)
        }
        .simultaneousGesture(TapGesture(count: 1).onEnded {
            // Shift/Cmd extend the multi-selection (handled here: the row gestures swallow List's own handling)
            FileListState.active = true
            let mods = ClickMods.flags
            if ClickMods.clicks >= 2, mods.intersection([.shift, .command]).isEmpty { model.openTrack(node.id); return }
            if mods.contains(.command) {
                var cur = multi.ids.count > 1 ? multi.ids : Set(model.foregroundPath.map { [$0] } ?? [])
                if cur.contains(node.id) { cur.remove(node.id) } else { cur.insert(node.id) }
                multi.ids = cur; multi.anchor = node.id
                return
            }
            if mods.contains(.shift) {
                let a = multi.anchor ?? model.foregroundPath ?? node.id
                if let i = files.firstIndex(where: { $0.id == a }), let j = files.firstIndex(where: { $0.id == node.id }) {
                    multi.ids = Set(files[min(i, j)...max(i, j)].map(\.id))
                }
                return
            }
            multi.ids = [node.id]; multi.anchor = node.id
            model.rowClicked(node.id)
        })
        .contextMenu {
            if multi.ids.count > 1 && multi.ids.contains(node.id) {
                Button("Merge \(multi.ids.count) Files …") {
                    model.mergeFiles(files.filter { multi.ids.contains($0.id) }.map(\.url))
                }
                Divider()
            }
            Button("Rename …") { model.beginRename(node.id) }
            Button("Choose Icon …") { model.showIconPicker(for: selectedIDs.contains(node.id) ? Array(selectedIDs) : [node.id]) }
            Divider()
            Button(selectedIDs.contains(node.id) && selectedIDs.count > 1 ? "Delete \(selectedIDs.count) Files …" : "Delete …", role: .destructive) {
                model.trashFiles(selectedIDs.contains(node.id) ? files.filter { selectedIDs.contains($0.id) }.map(\.id) : [node.id])
            }
            Divider()
            StyleMenu(ids: multi.ids.count > 1 && multi.ids.contains(node.id) ? Array(multi.ids) : [node.id]).environmentObject(model)
        }
    }

    private func caption(_ n: FolderNode) -> String {
        var parts = [n.url.pathExtension.uppercased()]
        if let d = n.modified { parts.append(d.formatted(date: .numeric, time: .omitted)) }
        if model.includeSubfolders, let dir = displayedFolder {
            let parent = n.url.deletingLastPathComponent().path
            if parent != dir { parts.append(parent.replacingOccurrences(of: dir + "/", with: "")) }
        }
        return parts.joined(separator: " · ")
    }

    func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.directoryURL = model.rootURL
        p.prompt = "Choose"
        if p.runModal() == .OK, let u = p.url { model.chooseRoot(u) }
    }
}


/// Drop target for a folder row. Like the Finder, but inverted: dragging copies (cursor shows +), holding Option moves.
struct FolderDropDelegate: DropDelegate {
    let model: AppModel
    let folder: URL
    let targeted: Binding<Bool>

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [UTType.fileURL]) }
    func dropEntered(info: DropInfo) { targeted.wrappedValue = true }
    func dropExited(info: DropInfo) { targeted.wrappedValue = false }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: NSEvent.modifierFlags.contains(.option) ? .move : .copy)
    }
    func performDrop(info: DropInfo) -> Bool {
        targeted.wrappedValue = false
        return model.handleDrop(info.itemProviders(for: [UTType.fileURL]), into: folder,
                                move: NSEvent.modifierFlags.contains(.option))
    }
}

