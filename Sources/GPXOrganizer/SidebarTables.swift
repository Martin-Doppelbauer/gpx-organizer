import SwiftUI
import AppKit
import Combine
import BCCore

// The folder tree and the file list are real AppKit views (NSOutlineView / NSTableView), like in the Finder:
// the system does the selection (⇧ / ⌘ / arrow keys / ⌘A), the drag image at the pointer, the "+" cursor for copying,
// the drag threshold and the opening of folders under a resting drag.

// MARK: shared helpers

private final class TableMenuItem: NSMenuItem {
    private let block: () -> Void
    init(_ title: String, checked: Bool = false, enabled: Bool = true, _ block: @escaping () -> Void) {
        self.block = block
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
        isEnabled = enabled
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { block() }
}

/// The same entries as `StyleMenu`, as an AppKit menu (icon color, track color, width, reset).
@MainActor
private func styleMenuItems(model: AppModel, ids: [String]) -> [NSMenuItem] {
    func sub(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let m = NSMenu(title: title); items.forEach { m.addItem($0) }
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: ""); i.submenu = m; return i
    }
    let curIcon = model.commonColor(ids, icon: true), curTrack = model.commonColor(ids, icon: false)
    let icon = ColorPalette.items(defaultEntry: (L("Default (the icon's own color)"), curIcon.same && curIcon.rgb == nil, { model.setIconColor(ids, rgb: nil) }),
                                  current: curIcon.rgb, same: curIcon.same, pick: { model.setIconColor(ids, rgb: $0) }, other: { model.pickColor(ids, forIcon: true) })
    let track = ColorPalette.items(current: curTrack.rgb, same: curTrack.same, pick: { model.setColor(ids, rgb: $0) }, other: { model.pickColor(ids) })
    let curWidth = model.commonWidth(ids)
    let width: [NSMenuItem] = StylePresets.widths.map { w in
        TableMenuItem(L("%@ pt", "\(Int(w))"), checked: curWidth.same && curWidth.width.map { abs($0 - w) < 0.01 } == true) { model.setWidth(ids, width: w) }
    }
    return [sub(L("Icon Color"), icon), sub(L("Track Color"), track), sub(L("Track Width"), width), TableMenuItem(L("Reset Style")) { model.resetStyle(ids) }]
}

/// Picture of a row's icon (symbol, tint, optional disc), white when the row is selected.
@MainActor
private func rowIconImage(_ ic: (name: String, color: Color, disc: Bool), selected: Bool) -> NSImage {
    let size = NSSize(width: 22, height: 22)
    let tint = NSColor(ic.color)
    func glyph(_ pt: CGFloat) -> NSImage? {
        if CustomIcons.isCustom(ic.name) { return CustomIcons.image(ic.name) }
        return NSImage(systemSymbolName: ic.name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pt, weight: .semibold))
    }
    return NSImage(size: size, flipped: false) { r in
        if ic.disc {
            tint.setFill(); NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5)).fill()
            if selected { NSColor.white.setStroke(); let p = NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)); p.lineWidth = 1.5; p.stroke() }
        }
        guard let g = glyph(ic.disc ? 11 : 14) else { return true }
        let gs = g.size, scale = min(1, (ic.disc ? 14 : 20) / max(gs.width, gs.height))
        let gr = NSRect(x: (r.width - gs.width * scale) / 2, y: (r.height - gs.height * scale) / 2, width: gs.width * scale, height: gs.height * scale)
        let color = ic.disc || selected ? NSColor.white : tint
        let t = NSImage(size: gr.size, flipped: false) { rr in
            g.draw(in: rr); color.setFill(); rr.fill(using: .sourceAtop); return true
        }
        t.draw(in: gr)
        return true
    }
}

/// The picture at the pointer while dragging: icon and name on a light plate, readable on any background.
@MainActor
private func dragImage(title: String, icon: NSImage?, count: Int) -> NSImage {
    let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    let text = count > 1 ? L("%@ items", "\(count)") : title
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    let ts = (text as NSString).size(withAttributes: attrs)
    let w = min(260, ts.width + 22 + 28), h: CGFloat = 28
    return NSImage(size: NSSize(width: w, height: h), flipped: false) { r in
        NSColor(white: 0.97, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7).fill()
        NSColor(white: 0, alpha: 0.25).setStroke()
        let b = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7); b.lineWidth = 1; b.stroke()
        icon?.draw(in: NSRect(x: 6, y: 3, width: 22, height: 22))
        (text as NSString).draw(in: NSRect(x: 32, y: (h - ts.height) / 2, width: w - 38, height: ts.height), withAttributes: attrs)
        return true
    }
}

private func fileURLs(_ pb: NSPasteboard) -> [URL] {
    (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
}

/// Text field of a row that is edited in place (Return = apply, Esc = cancel, click elsewhere = apply).
private func beginEditing(_ field: NSTextField, text: String, delegate: NSTextFieldDelegate) {
    field.stringValue = text
    field.isEditable = true; field.isSelectable = true
    field.isBezeled = true; field.bezelStyle = .roundedBezel; field.drawsBackground = true
    field.backgroundColor = .textBackgroundColor; field.textColor = .labelColor
    field.delegate = delegate
    field.window?.makeFirstResponder(field)
    field.currentEditor()?.selectAll(nil)
}

private func endEditing(_ field: NSTextField) {
    field.isEditable = false; field.isSelectable = false; field.isBezeled = false; field.drawsBackground = false; field.textColor = .labelColor
    field.delegate = nil
}

// MARK: file list

private final class FileCell: NSTableCellView {
    let name = NSTextField(labelWithString: "")
    let caption = NSTextField(labelWithString: "")
    let icon = NSImageView()
    var iconInfo: (name: String, color: Color, disc: Bool)?
    private var nameAbove: NSLayoutConstraint!
    private var nameMiddle: NSLayoutConstraint!

    /// While the name is edited the field sits in the middle of the row (the caption line is hidden then).
    func setEditing(_ on: Bool) {
        caption.isHidden = on
        nameAbove.isActive = !on; nameMiddle.isActive = on
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        name.font = .systemFont(ofSize: 13); name.lineBreakMode = .byTruncatingTail
        caption.font = .systemFont(ofSize: 10); caption.textColor = .secondaryLabelColor; caption.lineBreakMode = .byTruncatingTail
        for v in [icon, name, caption] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        textField = name; imageView = icon
        nameAbove = name.bottomAnchor.constraint(equalTo: centerYAnchor, constant: 1)
        nameMiddle = name.centerYAnchor.constraint(equalTo: centerYAnchor)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2), icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22), icon.heightAnchor.constraint(equalToConstant: 22),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8), name.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            nameAbove,
            caption.leadingAnchor.constraint(equalTo: name.leadingAnchor), caption.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            caption.topAnchor.constraint(equalTo: centerYAnchor, constant: 1),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// On the blue bar all texts and the icon are white (the gray caption could not be read there).
    func applySelection(_ on: Bool) {
        caption.textColor = on ? .white : .secondaryLabelColor
        name.textColor = on ? .white : .labelColor
        if let i = iconInfo { MainActor.assumeIsolated { icon.image = rowIconImage(i, selected: on) } }
    }

}

/// Marked rows stay blue while the window is active, also when the keyboard is in the map (the system would turn them gray).
final class AlwaysBlueRow: NSTableRowView {
    override var isEmphasized: Bool { get { window?.isKeyWindow ?? false } set {} }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { isSelected && (window?.isKeyWindow ?? false) ? .emphasized : .normal }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for v in subviews { (v as? FileCell)?.applySelection(isSelected && (window?.isKeyWindow ?? false)) }
    }
    override var isSelected: Bool {
        didSet { for v in subviews { (v as? FileCell)?.applySelection(isSelected && (window?.isKeyWindow ?? false)) } }
    }
}

final class FileNSTableView: NSTableView {
    var onRepeatClick: ((Int) -> Void)?
    var onReturn: (() -> Void)?
    var contextMenuProvider: ((Int) -> NSMenu?)?
    var dragStarted = false

    override func mouseDown(with event: NSEvent) {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        let was = row >= 0 && selectedRowIndexes == [row]
        dragStarted = false
        super.mouseDown(with: event)
        if was, !dragStarted, event.clickCount == 1, event.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty { onRepeatClick?(row) }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { onReturn?(); return }
        super.keyDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0, !selectedRowIndexes.contains(row) { selectRowIndexes([row], byExtendingSelection: false) }
        return row >= 0 ? contextMenuProvider?(row) : nil
    }
}

struct FileTableView: NSViewRepresentable {
    let files: [FolderNode]
    let fileRevision: Int
    let renamingID: String?
    let foreground: String?
    let model: AppModel

    func makeCoordinator() -> FileTableController { FileTableController(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let t = FileNSTableView()
        t.style = .inset
        t.headerView = nil
        t.rowHeight = 38
        t.allowsMultipleSelection = true
        t.allowsEmptySelection = true
        t.usesAlternatingRowBackgroundColors = false
        t.intercellSpacing = NSSize(width: 0, height: 0)
        t.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let col = NSTableColumn(identifier: .init("file")); col.resizingMask = .autoresizingMask
        t.addTableColumn(col)
        t.dataSource = c; t.delegate = c
        t.target = c; t.doubleAction = #selector(FileTableController.doubleClicked)
        t.registerForDraggedTypes([.fileURL])
        t.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        t.setDraggingSourceOperationMask(.copy, forLocal: false)
        t.draggingDestinationFeedbackStyle = .regular
        t.onRepeatClick = { [weak c] row in c?.repeatClick(row) }
        t.onReturn = { [weak c] in c?.renameSelected() }
        t.contextMenuProvider = { [weak c] row in c?.menu(forRow: row) }
        c.table = t
        let s = NSScrollView(); s.documentView = t; s.hasVerticalScroller = true; s.autohidesScrollers = true; s.drawsBackground = false
        c.bind()
        return s
    }

    func updateNSView(_ s: NSScrollView, context: Context) {
        context.coordinator.update(files: files, revision: fileRevision, renamingID: renamingID, foreground: foreground)
    }
}

@MainActor
final class FileTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    var model: AppModel
    weak var table: FileNSTableView?
    private var files: [FolderNode] = []
    private var revision = -1
    private var syncing = false
    private var editingID: String?
    private var finishing = false
    private var bag = Set<AnyCancellable>()

    init(model: AppModel) { self.model = model }

    func bind() {
        // marked rows follow the window: blue while it is active, gray otherwise
        for n in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.publisher(for: n).sink { [weak self] note in
                guard let self, let t = self.table, (note.object as? NSWindow) === t.window else { return }
                self.syncing = true; t.reloadData(forRowIndexes: t.selectedRowIndexes, columnIndexes: [0]); self.syncing = false
            }.store(in: &bag)
        }
        model.menuEvents(.fileSelectAll).sink { [weak self] _ in
            guard let t = self?.table else { return }
            t.window?.makeFirstResponder(t); t.selectAll(nil)
        }.store(in: &bag)
        // a track picked on the map: only its row is marked
        model.menuEvents(.fileKeySelect).sink { [weak self] n in
            guard let self, let id = n.object as? String, let i = self.files.firstIndex(where: { $0.id == id }) else { return }
            self.setSelection([i])
        }.store(in: &bag)
    }

    // MARK: updating

    func update(files new: [FolderNode], revision: Int, renamingID: String?, foreground: String?) {
        guard let t = table else { return }
        let changed = new.count != files.count || zip(new, files).contains { $0.numericID != $1.numericID } || revision != self.revision || renamingID != editingID
        if changed {
            files = new; self.revision = revision
            if editingID != nil, renamingID != editingID { editingID = nil }
            syncing = true; t.reloadData(); syncing = false
        }
        syncSelectionFromModel(foreground: foreground)
        if let r = renamingID, editingID != r, let i = files.firstIndex(where: { $0.id == r }) {
            editingID = r
            t.scrollRowToVisible(i)
            DispatchQueue.main.async { [weak self] in
                guard let self, let t = self.table, let cell = t.view(atColumn: 0, row: i, makeIfNecessary: true) as? FileCell else { return }
                self.finishing = false
                self.syncing = true; t.deselectAll(nil); self.syncing = false          // no blue bar behind the text field
                if let cell = t.view(atColumn: 0, row: i, makeIfNecessary: true) as? FileCell { cell.setEditing(true); beginEditing(cell.name, text: self.files[i].url.deletingPathExtension().lastPathComponent, delegate: self) }
            }
        }
    }

    private func desiredRows(foreground: String?) -> IndexSet {
        if model.multiSelected.count > 1 {
            return IndexSet(files.indices.filter { model.multiSelected.contains(files[$0].id) })
        }
        if let f = foreground, let i = files.firstIndex(where: { $0.id == f }) { return [i] }
        return []
    }

    private func syncSelectionFromModel(foreground: String?) {
        guard let t = table, editingID == nil else { return }
        let want = desiredRows(foreground: foreground)
        // only differences made from outside (map click, search …) are applied; the user's own marking is the source of truth
        if want == t.selectedRowIndexes { return }
        if model.multiSelected.count <= 1, t.selectedRowIndexes.count > 1, foreground == nil { return }
        if model.multiSelected.count <= 1, t.selectedRowIndexes.count > 1 { return }      // several marked, one is in the foreground: keep the marking
        setSelection(want)
    }

    private func setSelection(_ rows: IndexSet) {
        guard let t = table else { return }
        syncing = true; t.selectRowIndexes(rows, byExtendingSelection: false); syncing = false
    }

    // MARK: data source / delegate

    func numberOfRows(in tableView: NSTableView) -> Int { files.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { AlwaysBlueRow() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("fileCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? FileCell) ?? { let c = FileCell(frame: .zero); c.identifier = id; return c }()
        let node = files[row]
        cell.name.stringValue = node.url.deletingPathExtension().lastPathComponent
        cell.caption.stringValue = caption(node); cell.setEditing(false)
        endEditing(cell.name)
        let info = model.rowIcon(node.id)
        cell.iconInfo = info
        cell.applySelection(tableView.selectedRowIndexes.contains(row) && tableView.isRowSelectedAndEmphasized)
        return cell
    }

    private func caption(_ n: FolderNode) -> String {
        var parts = [n.url.pathExtension.uppercased()]
        if let d = n.modified { parts.append(d.formatted(date: .numeric, time: .omitted)) }
        if model.includeSubfolders, let dir = model.displayedFolder {
            let parent = n.url.deletingLastPathComponent().path
            if parent != dir { parts.append(parent.replacingOccurrences(of: dir + "/", with: "")) }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: selection

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !syncing, let t = table else { return }
        let rows = t.selectedRowIndexes
        let ids = Set(rows.compactMap { $0 < files.count ? files[$0].id : nil })
        if NSApp.keyWindow?.firstResponder is NSText, editingID == nil { NSApp.keyWindow?.makeFirstResponder(t) }
        if ids.count == 1, let id = ids.first {
            model.setMultiSelected([])
            if NSApp.currentEvent?.type == .keyDown { model.select(id) } else { model.rowClicked(id) }
        } else if ids.count > 1 {
            model.setMultiSelected(ids)
        }
    }

    func repeatClick(_ row: Int) {
        guard row >= 0, row < files.count else { return }
        model.rowClicked(files[row].id)          // a slow second click on the marked row starts renaming
    }

    @objc func doubleClicked() {
        guard let t = table, t.clickedRow >= 0, t.clickedRow < files.count else { return }
        if NSEvent.modifierFlags.intersection([.shift, .command]).isEmpty { model.openTrack(files[t.clickedRow].id) }
    }

    func renameSelected() {
        guard let t = table, t.selectedRowIndexes.count == 1, let i = t.selectedRowIndexes.first, model.renamingID == nil else { return }
        model.beginRename(files[i].id)
    }

    // MARK: rename

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) { finishRename(control, commit: true); return true }
        if sel == #selector(NSResponder.cancelOperation(_:)) { finishRename(control, commit: false); return true }
        return false
    }
    func controlTextDidEndEditing(_ obj: Notification) { if let f = obj.object as? NSTextField { finishRename(f, commit: true) } }

    private func finishRename(_ control: NSControl, commit: Bool) {
        guard !finishing, let id = editingID, let f = control as? NSTextField else { return }
        finishing = true
        let text = f.stringValue
        editingID = nil
        endEditing(f)
        table?.window?.makeFirstResponder(table)
        if commit { model.commitRename(id, text: text) } else {
            model.cancelRename()
            // the row shows the old name again (the field still holds what was typed)
            if let i = files.firstIndex(where: { $0.id == id }) { syncing = true; table?.reloadData(forRowIndexes: [i], columnIndexes: [0]); syncing = false }
        }
    }

    // MARK: context menu

    func menu(forRow row: Int) -> NSMenu? {
        guard let t = table, row < files.count else { return nil }
        let node = files[row]
        let sel = Set(t.selectedRowIndexes.compactMap { $0 < files.count ? files[$0].id : nil })
        let ids = sel.contains(node.id) ? files.filter { sel.contains($0.id) }.map(\.id) : [node.id]
        let m = NSMenu()
        m.addItem(TableMenuItem(L("Rename …")) { [model] in model.beginRename(node.id) })
        if ids.count > 1 { m.addItem(TableMenuItem(L("Merge %@ Files …", "\(ids.count)")) { [model, files] in model.mergeFiles(files.filter { ids.contains($0.id) }.map(\.url)) }) }
        m.addItem(TableMenuItem(ids.count > 1 ? L("Delete %@ Files …", "\(ids.count)") : L("Delete …")) { [model] in model.trashFiles(ids) })
        m.addItem(.separator())
        m.addItem(TableMenuItem(L("Choose Icon …")) { [model] in model.showIconPicker(for: ids) })
        styleMenuItems(model: model, ids: ids).forEach { m.addItem($0) }
        m.addItem(.separator())
        m.addItem(TableMenuItem(ids.count > 1 ? L("Send %@ Files to Garmin Device …", "\(ids.count)") : L("Send to Garmin Device …")) { [model] in model.sendToGarmin(ids) })
        m.addItem(TableMenuItem(ids.count > 1 ? L("Replace Elevation Data of %@ Files …", "\(ids.count)") : L("Replace Elevation Data …"),
                                  enabled: ids.contains { $0.lowercased().hasSuffix(".gpx") }) { [model] in model.startElevationFix(ids) })
        return m
    }

    // MARK: drag source

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        row < files.count ? files[row].url as NSURL : nil
    }

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
        (tableView as? FileNSTableView)?.dragStarted = true
        let nodes = rowIndexes.compactMap { $0 < files.count ? files[$0] : nil }
        model.dragSources = nodes.map(\.id)
        model.dragSource = nodes.first?.id
        guard let first = nodes.first else { return }
        let img = dragImage(title: first.url.deletingPathExtension().lastPathComponent, icon: rowIconImage(model.rowIcon(first.id), selected: false), count: nodes.count)
        var n = 0
        session.enumerateDraggingItems(options: [], for: tableView, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in
            if n == 0 { item.setDraggingFrame(NSRect(origin: NSPoint(x: item.draggingFrame.minX, y: item.draggingFrame.minY), size: img.size), contents: img) }
            else { item.imageComponentsProvider = { [] } }
            n += 1
        }
    }

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        model.dragSource = nil; model.dragSources = []
    }

    // MARK: drop (anywhere on the list: into the folder shown)

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        guard model.displayedFolder != nil, !fileURLs(info.draggingPasteboard).isEmpty else { return [] }
        tableView.setDropRow(-1, dropOperation: .on)
        return FolderDropRules.operation(model: model, urls: fileURLs(info.draggingPasteboard), target: URL(fileURLWithPath: model.displayedFolder!))
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let f = model.displayedFolder else { return false }
        return model.handleDropURLs(fileURLs(info.draggingPasteboard), into: URL(fileURLWithPath: f), move: !NSEvent.modifierFlags.contains(.option))
    }
}

private extension NSTableView {
    var isRowSelectedAndEmphasized: Bool { window?.isKeyWindow == true }
}

/// What a drop on a folder does: moves (copies with ⌥ or for files from outside); nothing when it makes no sense.
enum FolderDropRules {
    @MainActor
    static func operation(model: AppModel, urls: [URL], target: URL) -> NSDragOperation {
        let t = target.standardizedFileURL.path
        var inner = true
        for u in urls {
            let s = u.standardizedFileURL.path
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: s, isDirectory: &isDir), isDir.boolValue, t == s || t.hasPrefix(s + "/") { return [] }      // a folder into itself
            if u.deletingLastPathComponent().standardizedFileURL.path != t { inner = false }
        }
        let internalDrag = model.dragSource != nil
        if internalDrag && inner { return [] }                                  // nothing changes
        return internalDrag && !NSEvent.modifierFlags.contains(.option) ? .move : .copy
    }
}

// MARK: folder tree

private final class FolderCell: NSTableCellView {
    let name = NSTextField(labelWithString: "")
    let count = NSTextField(labelWithString: "")
    let icon = NSImageView()
    override init(frame: NSRect) {
        super.init(frame: frame)
        name.lineBreakMode = .byTruncatingTail
        count.font = .systemFont(ofSize: 11); count.textColor = .secondaryLabelColor; count.alignment = .right
        icon.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        icon.contentTintColor = .systemBlue
        for v in [icon, name, count] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        textField = name; imageView = icon
        count.setContentCompressionResistancePriority(.required, for: .horizontal)
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2), icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6), name.centerYAnchor.constraint(equalTo: centerYAnchor),
            count.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor, constant: 4),
            count.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4), count.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            let sel = backgroundStyle == .emphasized
            count.textColor = sel ? NSColor.white.withAlphaComponent(0.8) : .secondaryLabelColor
            icon.contentTintColor = sel ? .white : .systemBlue
        }
    }
}

final class FolderNSOutlineView: NSOutlineView {
    var onRepeatClick: ((Int) -> Void)?
    var onReturn: (() -> Void)?
    var contextMenuProvider: ((Int) -> NSMenu?)?
    var dragStarted = false

    override func mouseDown(with event: NSEvent) {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        let was = row >= 0 && selectedRowIndexes == [row]
        dragStarted = false
        super.mouseDown(with: event)
        if was, !dragStarted, event.clickCount == 1, event.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty { onRepeatClick?(row) }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { onReturn?(); return }
        super.keyDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        if !selectedRowIndexes.contains(row) { selectRowIndexes([row], byExtendingSelection: false) }
        return contextMenuProvider?(row)
    }
}

struct FolderOutlineView: NSViewRepresentable {
    let tree: FolderNode
    let displayedFolder: String?
    let renamingID: String?
    let fileRevision: Int
    let model: AppModel

    func makeCoordinator() -> FolderOutlineController { FolderOutlineController(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let o = FolderNSOutlineView()
        o.style = .inset
        o.headerView = nil
        o.rowHeight = 27
        o.indentationPerLevel = 14
        o.allowsMultipleSelection = false
        o.allowsEmptySelection = true
        o.floatsGroupRows = false
        let col = NSTableColumn(identifier: .init("folder")); col.resizingMask = .autoresizingMask
        o.addTableColumn(col); o.outlineTableColumn = col
        o.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        o.dataSource = c; o.delegate = c
        o.target = c; o.doubleAction = #selector(FolderOutlineController.doubleClicked)
        o.registerForDraggedTypes([.fileURL])
        o.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        o.setDraggingSourceOperationMask(.copy, forLocal: false)
        o.draggingDestinationFeedbackStyle = .regular
        o.onRepeatClick = { [weak c] row in c?.repeatClick(row) }
        o.onReturn = { [weak c] in c?.renameSelected() }
        o.contextMenuProvider = { [weak c] row in c?.menu(forRow: row) }
        c.outline = o
        let s = NSScrollView(); s.documentView = o; s.hasVerticalScroller = true; s.autohidesScrollers = true; s.drawsBackground = false
        return s
    }

    func updateNSView(_ s: NSScrollView, context: Context) {
        context.coordinator.update(tree: tree, displayed: displayedFolder, renamingID: renamingID, revision: fileRevision)
    }
}

@MainActor
final class FolderOutlineController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate {
    var model: AppModel
    weak var outline: FolderNSOutlineView?
    private var tree: FolderNode?
    private var revision = -1
    private var open: Set<String> = []
    private var restoring = false
    private var syncing = false
    private var editingID: String?
    private var finishing = false
    private var hoverID: String?
    private var hoverSince = Date()
    private var firstLoad = true
    private var lastDisplayed: String?

    init(model: AppModel) { self.model = model }

    // MARK: updating

    func update(tree new: FolderNode, displayed: String?, renamingID: String?, revision rev: Int) {
        guard let o = outline else { return }
        if tree !== new || rev != revision || renamingID != editingID {
            tree = new; revision = rev
            if firstLoad { open.insert(new.id); firstLoad = false }
            if editingID != nil, renamingID != editingID { editingID = nil }
            let keep = o.enclosingScrollView?.contentView.bounds.origin          // the list stays where the user scrolled it
            restoring = true; syncing = true
            o.reloadData()
            restoreExpansion(new)
            restoring = false; syncing = false
            if let keep, let sv = o.enclosingScrollView { sv.contentView.scroll(to: keep); sv.reflectScrolledClipView(sv.contentView) }
        }
        // the folder shown is marked (its parents are opened)
        if renamingID == nil, editingID == nil, let d = displayed, let node = new.find(d) {
            var path = node.url.deletingLastPathComponent().path
            var chain: [FolderNode] = []
            while path.count >= new.id.count, let p = new.find(path) { chain.append(p); path = (path as NSString).deletingLastPathComponent; if p === new { break } }
            for p in chain.reversed() where !o.isItemExpanded(p) && p.folderChildren != nil { restoring = true; o.expandItem(p); restoring = false; open.insert(p.id) }
            let row = o.row(forItem: node)
            if row >= 0, o.selectedRow != row {
                syncing = true; o.selectRowIndexes([row], byExtendingSelection: false); syncing = false
                if displayed != lastDisplayed { o.scrollRowToVisible(row) }          // only a newly chosen folder is brought into view, not every redraw
            }
            lastDisplayed = displayed
        }
        if let r = renamingID, editingID != r, let node = new.find(r), !node.url.path.isEmpty {
            let row = o.row(forItem: node)
            if row >= 0 {
                editingID = r
                DispatchQueue.main.async { [weak self] in
                    guard let self, let o = self.outline, let cell = o.view(atColumn: 0, row: row, makeIfNecessary: true) as? FolderCell else { return }
                    self.finishing = false
                    self.syncing = true; o.deselectAll(nil); self.syncing = false          // no blue bar behind the text field
                    if let cell = o.view(atColumn: 0, row: o.row(forItem: node), makeIfNecessary: true) as? FolderCell { beginEditing(cell.name, text: node.name, delegate: self) }
                }
            }
        }
    }

    private func restoreExpansion(_ n: FolderNode) {
        guard open.contains(n.id), let o = outline else { return }
        o.expandItem(n)
        for c in n.folderChildren ?? [] { restoreExpansion(c) }
    }

    func outlineViewItemDidExpand(_ n: Notification) { if !restoring, let i = n.userInfo?["NSObject"] as? FolderNode { open.insert(i.id) } }
    func outlineViewItemDidCollapse(_ n: Notification) { if !restoring, let i = n.userInfo?["NSObject"] as? FolderNode { open.remove(i.id) } }

    // MARK: data source

    func outlineView(_ o: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let tree else { return 0 }
        if item == nil { return 1 }
        return (item as? FolderNode)?.folderChildren?.count ?? 0
    }
    func outlineView(_ o: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return tree! }
        return (item as! FolderNode).folderChildren![index]
    }
    func outlineView(_ o: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? FolderNode)?.folderChildren != nil }

    func outlineView(_ o: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FolderNode else { return nil }
        let id = NSUserInterfaceItemIdentifier("folderCell")
        let cell = (o.makeView(withIdentifier: id, owner: nil) as? FolderCell) ?? { let c = FolderCell(frame: .zero); c.identifier = id; return c }()
        cell.name.stringValue = node.name
        cell.name.font = .systemFont(ofSize: 13, weight: node === tree ? .semibold : .medium)
        endEditing(cell.name)
        let n = node.totalFileCount
        cell.count.stringValue = n > 0 ? "\(n)" : ""
        return cell
    }

    // MARK: selection

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !syncing, let o = outline, o.selectedRow >= 0, let node = o.item(atRow: o.selectedRow) as? FolderNode else { return }
        if NSApp.keyWindow?.firstResponder is NSText, editingID == nil { NSApp.keyWindow?.makeFirstResponder(o) }
        model.rowClicked(node.id)
    }

    func repeatClick(_ row: Int) {
        guard row >= 0, let node = outline?.item(atRow: row) as? FolderNode else { return }
        model.rowClicked(node.id)
    }

    @objc func doubleClicked() {
        guard let o = outline, o.clickedRow >= 0, let node = o.item(atRow: o.clickedRow) as? FolderNode else { return }
        model.enterFolder(node.url)
    }

    func renameSelected() {
        guard let o = outline, o.selectedRow >= 0, let node = o.item(atRow: o.selectedRow) as? FolderNode, node !== tree, model.renamingID == nil else { return }
        model.beginRename(node.id)
    }

    // MARK: rename

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) { finishRename(control, commit: true); return true }
        if sel == #selector(NSResponder.cancelOperation(_:)) { finishRename(control, commit: false); return true }
        return false
    }
    func controlTextDidEndEditing(_ obj: Notification) { if let f = obj.object as? NSTextField { finishRename(f, commit: true) } }

    private func finishRename(_ control: NSControl, commit: Bool) {
        guard !finishing, let id = editingID, let f = control as? NSTextField else { return }
        finishing = true
        let text = f.stringValue
        editingID = nil
        endEditing(f)
        outline?.window?.makeFirstResponder(outline)
        if commit { model.commitRename(id, text: text) } else {
            model.cancelRename()
            if let o = outline, let n = tree?.find(id) { syncing = true; o.reloadItem(n); syncing = false }
        }
    }

    // MARK: context menu

    func menu(forRow row: Int) -> NSMenu? {
        guard let o = outline, let node = o.item(atRow: row) as? FolderNode else { return nil }
        let isRoot = node === tree
        let m = NSMenu()
        m.addItem(TableMenuItem(L("New Folder …")) { [model] in model.newFolder(in: node.url) })
        if !isRoot {
            m.addItem(TableMenuItem(L("Rename …")) { [model] in model.beginRename(node.id) })
            m.addItem(TableMenuItem(L("Delete …")) { [model] in model.trashFolder(node.url) })
        }
        m.addItem(.separator())
        styleMenuItems(model: model, ids: (node.children ?? []).filter { !$0.isFolder }.map { $0.id }).forEach { m.addItem($0) }
        return m
    }

    // MARK: drag source

    func outlineView(_ o: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let n = item as? FolderNode, n !== tree else { return nil }
        return n.url as NSURL
    }

    func outlineView(_ o: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {
        (o as? FolderNSOutlineView)?.dragStarted = true
        guard let n = draggedItems.first as? FolderNode else { return }
        model.dragSource = n.id; model.dragSources = [n.id]
        let folderIcon = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular).applying(.init(paletteColors: [.systemBlue])))
        let img = dragImage(title: n.name, icon: folderIcon, count: 1)
        var k = 0
        session.enumerateDraggingItems(options: [], for: o, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in
            if k == 0 { item.setDraggingFrame(NSRect(origin: item.draggingFrame.origin, size: img.size), contents: img) }
            k += 1
        }
    }

    func outlineView(_ o: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        model.dragSource = nil; model.dragSources = []
        hoverID = nil
    }

    // MARK: drop target

    func outlineView(_ o: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        let urls = fileURLs(info.draggingPasteboard)
        guard !urls.isEmpty, let tree else { return [] }
        let target = (item as? FolderNode) ?? tree
        o.setDropItem(target, dropChildIndex: NSOutlineViewDropOnItemIndex)
        let op = FolderDropRules.operation(model: model, urls: urls, target: target.url)
        // a closed folder opens when the drag rests on it for a second (the pointer may keep moving inside its row)
        if hoverID != target.id { hoverID = target.id; hoverSince = Date() }
        else if Date().timeIntervalSince(hoverSince) >= 1.0, o.isExpandable(target), !o.isItemExpanded(target) {
            o.animator().expandItem(target)
            hoverSince = Date()
        }
        return op
    }

    func outlineView(_ o: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let target = (item as? FolderNode) ?? tree
        guard let target else { return false }
        hoverID = nil
        return model.handleDropURLs(fileURLs(info.draggingPasteboard), into: target.url, move: !NSEvent.modifierFlags.contains(.option))
    }
}
