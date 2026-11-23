import SwiftUI
import AppKit
import BCCore

/// A marker (= GPX waypoint) being created or edited in the sheet.
final class MarkerDraft: ObservableObject, Identifiable {
    enum Target { case add, newFile }
    let id = UUID()
    let lat: Double, lon: Double
    @Published var name = ""
    @Published var desc = ""
    @Published var iconID = "waypoint"
    @Published var colorHex: String?          // nil = the default color of the icon
    @Published var sizeIndex = 1
    @Published var target: Target
    @Published var fileName = ""
    let addFile: String?                      // GPX file selected in the list (offered for "add")
    let editing: (file: String, index: Int)?  // set when an existing marker is edited
    var keptElement = ""                      // original <wpt> text of an edited marker (ele, time are kept)
    var keptSym = ""

    static let sizes: [Double] = [0.8, 1.0, 1.4]
    static let sizeTitles = [L("Small"), L("Medium"), L("Large")]

    init(lat: Double, lon: Double, addFile: String?, editing: (file: String, index: Int)? = nil) {
        self.lat = lat; self.lon = lon; self.addFile = addFile; self.editing = editing
        target = addFile != nil ? .add : .newFile       // a file selected in the list: add to it; otherwise a new file
    }

    var defaultColor: Color { IconCatalog.color(iconID) }
    var color: Color {
        get { colorHex.flatMap { Waypoint.rgb(fromHex: $0) }.map { Color(red: $0[0], green: $0[1], blue: $0[2]) } ?? defaultColor }
        set {
            if let c = NSColor(newValue).usingColorSpace(.sRGB) {
                colorHex = String(format: "%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
            }
        }
    }
}

extension AppModel {
    private var markerFolder: URL { URL(fileURLWithPath: displayedFolder ?? rootURL.path) }

    /// Right-click menu or ⌘-click on the map.
    func newMarker(lat: Double, lon: Double) {
        let gpx = foregroundPath.flatMap { $0.lowercased().hasSuffix(".gpx") ? $0 : nil }
        let d = MarkerDraft(lat: lat, lon: lon, addFile: gpx)
        markerDraft = d
    }

    func editMarker(file: String, index: Int) {
        guard let f = cache[file], let w = f.waypoints.first(where: { $0.index == index }) else { return }
        let lat = Merc.lat(y: w.y), lon = Merc.lon(x: w.x)
        let d = MarkerDraft(lat: lat, lon: lon, addFile: nil, editing: (file, index))
        d.name = w.name; d.desc = w.desc
        // start from what the map shows: the marker's own icon, else the file's icon, else the one of its Garmin symbol
        d.iconID = w.iconID ?? f.iconOverride ?? f.embeddedIcon ?? IconStyle.catalogID(forSymbol: w.sym)
        if let own = w.colorHex { d.colorHex = own }
        else {
            let shown = markerLook(f, w).rgb
            let def = IconStyle.rgb(ofIcon: d.iconID) ?? [0.95, 0.5, 0.1]
            if zip(shown, def).contains(where: { abs($0 - $1) > 0.02 }) {
                d.colorHex = String(format: "%02X%02X%02X", Int(round(shown[0] * 255)), Int(round(shown[1] * 255)), Int(round(shown[2] * 255)))
            }
        }
        d.sizeIndex = MarkerDraft.sizes.enumerated().min { abs($0.element - (w.size ?? 1)) < abs($1.element - (w.size ?? 1)) }?.offset ?? 1
        if let text = try? String(contentsOf: URL(fileURLWithPath: file), encoding: .utf8) {
            let r = WptText.ranges(in: text)
            if r.indices.contains(index) { d.keptElement = String(text[r[index]]) }
        }
        d.keptSym = w.sym
        markerDraft = d
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private func wptXML(_ d: MarkerDraft) -> String {
        var w = GPXWaypoint(point: GPXPoint(lat: d.lat, lon: d.lon), name: d.name, desc: d.desc, sym: d.keptSym.isEmpty ? "Waypoint" : d.keptSym)
        w.markerIcon = d.iconID; w.markerColor = d.colorHex; w.markerSize = MarkerDraft.sizes[d.sizeIndex]
        var s = "<wpt lat=\"\(String(format: "%.7f", d.lat))\" lon=\"\(String(format: "%.7f", d.lon))\">"
        s += WptText.keptChildren(of: d.keptElement)
        if !d.name.isEmpty { s += "<name>\(esc(d.name))</name>" }
        if !d.desc.isEmpty { s += "<desc>\(esc(d.desc))</desc>" }
        s += "<sym>\(esc(w.sym))</sym>" + w.extensionsXML() + "</wpt>"
        return s
    }

    private func fail(_ msg: String) {
        let a = NSAlert(); a.messageText = L("The marker could not be saved"); a.informativeText = msg; a.runModal()
    }

    /// Writes the sheet's marker: a new file, added to a file, or the changed marker of a file.
    func saveMarker(_ d: MarkerDraft) {
        let fm = FileManager.default
        if let e = d.editing {
            let url = URL(fileURLWithPath: e.file)
            guard let text = try? String(contentsOf: url, encoding: .utf8), let out = WptText.replace(e.index, with: wptXML(d), in: text) else {
                fail(L("The file could not be changed.")); return
            }
            guard trashCopyOfOriginal(url) else { fail(L("The original could not be moved to the Trash; nothing was changed.")); return }
            do { try out.write(to: url, atomically: true, encoding: .utf8) } catch { fail(error.localizedDescription); return }
            markerDraft = nil
            reloadFile(e.file)
            return
        }
        switch d.target {
        case .add:
            guard let path = d.addFile else { return }
            let url = URL(fileURLWithPath: path)
            guard let text = try? String(contentsOf: url, encoding: .utf8), let out = WptText.insert(wptXML(d), into: text) else {
                fail(L("The marker could not be added to this file.")); return
            }
            guard trashCopyOfOriginal(url) else { fail(L("The original could not be moved to the Trash; nothing was changed.")); return }
            do { try out.write(to: url, atomically: true, encoding: .utf8) } catch { fail(error.localizedDescription); return }
            markerDraft = nil
            reloadFile(path)
        case .newFile:
            var base = d.fileName.trimmingCharacters(in: .whitespaces)
            if base.isEmpty { base = d.name.trimmingCharacters(in: .whitespaces) }
            if base.isEmpty { base = "Marker" }
            base = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            if base.lowercased().hasSuffix(".gpx") { base = String(base.dropLast(4)) }
            var url = markerFolder.appendingPathComponent(base + ".gpx")
            var n = 2
            while fm.fileExists(atPath: url.path) { url = markerFolder.appendingPathComponent("\(base) \(n).gpx"); n += 1 }
            var doc = GPXDocument(name: d.name.isEmpty ? base : d.name)
            var w = GPXWaypoint(point: GPXPoint(lat: d.lat, lon: d.lon), name: d.name, desc: d.desc, sym: "Waypoint")
            w.markerIcon = d.iconID; w.markerColor = d.colorHex; w.markerSize = MarkerDraft.sizes[d.sizeIndex]
            doc.waypoints = [w]
            do { try doc.xml().write(to: url, atomically: true, encoding: .utf8) } catch { fail(error.localizedDescription); return }
            markerDraft = nil
            pendingSelect = url.path
            reloadTree()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in          // a marker file has no elevation profile
                if self?.foregroundPath == url.path { self?.showProfile = false }
            }
        }
    }

    /// Reads one file again after it was changed and refreshes the map.
    private func reloadFile(_ path: String) {
        cache.removeValue(forKey: path); failed.remove(path)
        reloadTree()
    }

    /// Dragged to a new place: the file is patched as text and the loaded copy is updated right away.
    func moveMarker(file: String, index: Int, lat: Double, lon: Double) {
        defer { MarkerDrag.hidden = nil; viewRevision += 1 }
        let url = URL(fileURLWithPath: file)
        guard let text = try? String(contentsOf: url, encoding: .utf8), let out = WptText.move(index, lat: lat, lon: lon, in: text),
              trashCopyOfOriginal(url) else { fail(L("The file could not be changed.")); return }
        do { try out.write(to: url, atomically: true, encoding: .utf8) } catch { fail(error.localizedDescription); return }
        if let f = cache[file], let i = f.waypoints.firstIndex(where: { $0.index == index }) {
            let o = f.waypoints[i]
            var w = Waypoint(x: Merc.x(lon: lon), y: Merc.y(lat: lat), name: o.name, sym: o.sym)
            w.desc = o.desc; w.iconID = o.iconID; w.colorHex = o.colorHex; w.size = o.size; w.index = o.index
            f.waypoints[i] = w
            f.boundsFromWaypointsIfNeeded()
        }
    }

    func deleteMarker(file: String, index: Int) {
        let name = cache[file]?.waypoints.first(where: { $0.index == index })?.name ?? ""
        let a = NSAlert()
        a.messageText = L("Delete the marker") + (name.isEmpty ? "?" : " “\(name)”?")
        a.informativeText = L("It is removed from “%@”. The original goes to the Trash first.", "\(URL(fileURLWithPath: file).lastPathComponent)")
        a.addButton(withTitle: L("Delete")); a.addButton(withTitle: L("Cancel"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let url = URL(fileURLWithPath: file)
        guard let text = try? String(contentsOf: url, encoding: .utf8), let out = WptText.remove(index, in: text), trashCopyOfOriginal(url) else {
            fail(L("The file could not be changed.")); return
        }
        do { try out.write(to: url, atomically: true, encoding: .utf8) } catch { fail(error.localizedDescription); return }
        reloadFile(file)
    }
}

final class FlagHolder: ObservableObject { @Published var on = false }

struct MarkerSheet: View {
    static func rgb(of c: Color) -> [Double] {
        guard let n = NSColor(c).usingColorSpace(.sRGB) else { return [0.5, 0.5, 0.5] }
        return [Double(n.redComponent), Double(n.greenComponent), Double(n.blueComponent)]
    }

    @EnvironmentObject var model: AppModel
    @ObservedObject var d: MarkerDraft
    @Environment(\.dismiss) private var dismiss
    @StateObject private var pick = FlagHolder()
    private let cols = Array(repeating: GridItem(.fixed(40), spacing: 5), count: 8)

    private var addName: String { d.addFile.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(d.editing == nil ? L("New Marker") : L("Edit Marker")).font(.headline)
            Form {
                TextField("Heading", text: $d.name)
                TextField("Description", text: $d.desc, axis: .vertical).lineLimit(2...5)
                LabeledContent("Icon") {
                    Button { pick.on = true } label: {
                        HStack(spacing: 6) {
                            IconImage(name: IconCatalog.symbol(for: d.iconID)).foregroundStyle(d.color).frame(width: 22)
                            Text(IconCatalog.entry(d.iconID)?.label ?? d.iconID)
                        }
                    }
                    .popover(isPresented: $pick.on) { iconGrid }
                }
                LabeledContent("Color") {
                    HStack {
                        PaletteButton(rgb: Self.rgb(of: d.color)) { rgb in d.color = Color(red: rgb[0], green: rgb[1], blue: rgb[2]) }       // the same palette as everywhere
                        Button("Icon Default") { d.colorHex = nil }.disabled(d.colorHex == nil).controlSize(.small)
                    }
                }
                Picker("Size", selection: $d.sizeIndex) {
                    ForEach(0..<MarkerDraft.sizeTitles.count, id: \.self) { Text(MarkerDraft.sizeTitles[$0]).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Position") {
                    Text(String(format: "%.5f, %.5f", d.lat, d.lon)).monospacedDigit().textSelection(.enabled)
                }
            }
            .formStyle(.columns)
            if d.editing == nil {
                Divider()
                Text("Where to keep the marker").font(.subheadline).foregroundStyle(.secondary)
                Picker("", selection: $d.target) {
                    if d.addFile != nil { Text(L("Add to the file “%@”", "\(addName)")).tag(MarkerDraft.Target.add) }
                    Text("Save as a new GPX file").tag(MarkerDraft.Target.newFile)
                }
                .pickerStyle(.radioGroup).labelsHidden()
                if d.target == .newFile {
                    HStack {
                        Text("File name")
                        TextField(d.name.isEmpty ? "Marker" : d.name, text: $d.fileName)
                        Text(".gpx").foregroundStyle(.secondary)
                    }
                    Text(L("in the folder “%@”", "\(URL(fileURLWithPath: model.displayedFolder ?? model.rootURL.path).lastPathComponent)"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { model.markerDraft = nil; dismiss() }.keyboardShortcut(.cancelAction)
                Button(d.editing == nil ? L("Save") : L("Save Changes")) { model.saveMarker(d) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 440)
    }

    private var iconGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(IconCatalog.all, id: \.0) { group in
                    Text(group.0).font(.caption).foregroundStyle(.secondary)
                    LazyVGrid(columns: cols, alignment: .leading, spacing: 5) {
                        ForEach(group.1, id: \.id) { entry in
                            Button { d.iconID = entry.id; pick.on = false } label: {
                                IconImage(name: entry.symbol).font(.system(size: 18)).foregroundStyle(entry.color)
                                    .frame(width: 36, height: 36)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(d.iconID == entry.id ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.12)))
                            }
                            .buttonStyle(.plain).help(entry.label)
                        }
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 370, height: 360)
    }
}
