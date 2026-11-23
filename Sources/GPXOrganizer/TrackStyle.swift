import SwiftUI
import AppKit
import BCCore

/// Per-file color / line width chosen by the user; stored inside the GPX file (gpxorg:color / gpxorg:width).
struct TrackStyle: Codable, Equatable, Hashable {
    var rgb: [Double]?      // r,g,b 0…1
    var width: Double?      // points
    var cgColor: CGColor? { rgb.map { CGColor(red: $0[0], green: $0[1], blue: $0[2], alpha: 1) } }
}

enum StylePresets {
    static let colors: [(String, [Double])] = [
        ("Red", [0.90, 0.10, 0.10]), ("Orange", [1.0, 0.50, 0.0]), ("Yellow", [0.95, 0.80, 0.0]),
        ("Green", [0.10, 0.65, 0.20]), ("Teal", [0.0, 0.70, 0.75]), ("Blue", [0.10, 0.25, 0.90]),
        ("Purple", [0.55, 0.20, 0.80]), ("Magenta", [0.90, 0.10, 0.70]), ("Brown", [0.50, 0.30, 0.15]),
        ("Black", [0, 0, 0]), ("Gray", [0.5, 0.5, 0.5])]
    static let widths: [Double] = [1, 2, 3, 4, 6, 8, 10]
}

final class ClosureMenuItem: NSMenuItem {
    private var handler: (() -> Void)?
    convenience init(_ title: String, _ handler: @escaping () -> Void) {
        self.init(title: title, action: #selector(run), keyEquivalent: "")
        self.handler = handler; target = self
    }
    @objc private func run() { handler?() }
}

final class ColorPanelHelper: NSObject {
    var onChange: ((NSColor) -> Void)?
    @objc func changed(_ panel: NSColorPanel) { onChange?(panel.color) }
}

extension AppModel {
    func style(_ id: String) -> TrackStyle? { styles[id] }

    static func hex(_ rgb: [Double]) -> String {
        String(format: "%02X%02X%02X", Int((rgb[0] * 255).rounded()), Int((rgb[1] * 255).rounded()), Int((rgb[2] * 255).rounded()))
    }
    static func rgb(fromHex h: String) -> [Double]? {
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return [Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255]
    }

    /// Color and line width live inside the GPX files (`gpxorg:color`, `gpxorg:width`); the app keeps nothing per file.
    private func applyStyle(_ idsIn: [String], _ values: [String: String?]) {
        guard let ids = convertToGPXIfNeeded(idsIn) else { return }
        if ids.count > 20 {
            let a = NSAlert()
            a.messageText = "Change the style of \(ids.count) files?"
            a.informativeText = "The choice is written into each GPX file (only a small metadata entry is added)."
            a.addButton(withTitle: "Change"); a.addButton(withTitle: "Cancel")
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        var failed: [String] = []
        var new = styles
        for id in ids {
            let url = URL(fileURLWithPath: id)
            guard url.pathExtension.lowercased() == "gpx", writeMeta(url, values) else { failed.append(url.lastPathComponent); continue }
            var st = new[id] ?? TrackStyle()
            if let c = values["color"] { st.rgb = c.flatMap(Self.rgb(fromHex:)); cache[id]?.embeddedColor = c }
            if let w = values["width"] { st.width = w.flatMap { Double($0) }; cache[id]?.embeddedWidth = w.flatMap { Double($0) } }
            if let ic = values["iconcolor"] { cache[id]?.embeddedIconColor = ic; fileIconColors[id] = ic.flatMap { Waypoint.rgb(fromHex: $0) } }
            new[id] = (st.rgb == nil && st.width == nil) ? nil : st
        }
        styles = new
        if values["iconcolor"] != nil { refreshWaypointKinds(); fileRevision += 1 }
        viewRevision += 1
        if !failed.isEmpty {
            let a = NSAlert()
            a.messageText = "The style could not be stored in \(failed.count == 1 ? "this file" : "\(failed.count) files")"
            a.informativeText = "Colors and line widths are stored inside GPX files only. Not changed: " + failed.prefix(5).joined(separator: ", ") + (failed.count > 5 ? " …" : "")
            a.runModal()
        }
    }

    func setColor(_ ids: [String], rgb: [Double]?) { applyStyle(ids, ["color": rgb.map(Self.hex)]) }
    func setIconColor(_ ids: [String], rgb: [Double]?) { applyStyle(ids, ["iconcolor": rgb.map(Self.hex)]) }
    func setWidth(_ ids: [String], width: Double?) { applyStyle(ids, ["width": width.map { String(format: "%g", $0) }]) }
    func resetStyle(_ ids: [String]) { applyStyle(ids, ["color": nil, "width": nil]) }

    /// Style of a file as stored inside it.
    static func style(of f: GPXFile) -> TrackStyle? {
        let rgb = f.embeddedColor.flatMap(Self.rgb(fromHex:))
        return rgb == nil && f.embeddedWidth == nil ? nil : TrackStyle(rgb: rgb, width: f.embeddedWidth)
    }

    func pickColor(_ ids: [String], forIcon: Bool = false) {
        let panel = NSColorPanel.shared
        if let c = ids.first.flatMap({ forIcon ? fileIconColors[$0] : styles[$0]?.rgb }) { panel.color = NSColor(red: c[0], green: c[1], blue: c[2], alpha: 1) }
        colorHelper.onChange = { [weak self] col in
            guard let c = col.usingColorSpace(.sRGB) else { return }
            let rgb = [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)]
            if forIcon { self?.setIconColor(ids, rgb: rgb) } else { self?.setColor(ids, rgb: rgb) }
        }
        panel.showsAlpha = false
        panel.isContinuous = false
        panel.setTarget(colorHelper)
        panel.setAction(#selector(ColorPanelHelper.changed(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    /// Right-click menu for the given track files (used on the map).
    func makeStyleMenu(for ids: [String]) -> NSMenu {
        let m = NSMenu()
        m.addItem(ClosureMenuItem("Choose Icon …") { [weak self] in self?.showIconPicker(for: ids) })
        let curIcon = commonColor(ids, icon: true), curTrack = commonColor(ids, icon: false)
        func tick(_ item: NSMenuItem, _ on: Bool) -> NSMenuItem { item.state = on ? .on : .off; return item }
        let icons = NSMenu()
        icons.addItem(tick(ClosureMenuItem("Default (the icon's own color)") { [weak self] in self?.setIconColor(ids, rgb: nil) }, curIcon.same && curIcon.rgb == nil))
        icons.addItem(.separator())
        for (name, rgb) in StylePresets.colors { icons.addItem(tick(ClosureMenuItem(name) { [weak self] in self?.setIconColor(ids, rgb: rgb) }, Self.colorsEqual(curIcon.rgb, rgb) && curIcon.same)) }
        icons.addItem(.separator())
        icons.addItem(tick(ClosureMenuItem("Other Color …") { [weak self] in self?.pickColor(ids, forIcon: true) }, Self.isCustom(curIcon)))
        let ii = NSMenuItem(title: "Icon Color", action: nil, keyEquivalent: ""); ii.submenu = icons; m.addItem(ii)
        let colors = NSMenu()
        for (name, rgb) in StylePresets.colors { colors.addItem(tick(ClosureMenuItem(name) { [weak self] in self?.setColor(ids, rgb: rgb) }, Self.colorsEqual(curTrack.rgb, rgb) && curTrack.same)) }
        colors.addItem(.separator())
        colors.addItem(tick(ClosureMenuItem("Other Color …") { [weak self] in self?.pickColor(ids) }, Self.isCustom(curTrack)))
        let ci = NSMenuItem(title: "Track Color", action: nil, keyEquivalent: ""); ci.submenu = colors; m.addItem(ci)
        let widths = NSMenu()
        let curWidth = commonWidth(ids)
        for w in StylePresets.widths { widths.addItem(tick(ClosureMenuItem("\(Int(w)) pt") { [weak self] in self?.setWidth(ids, width: w) }, curWidth.same && curWidth.width.map { abs($0 - w) < 0.01 } == true)) }
        let wi = NSMenuItem(title: "Track Width", action: nil, keyEquivalent: ""); wi.submenu = widths; m.addItem(wi)
        m.addItem(ClosureMenuItem("Reset Style") { [weak self] in self?.resetStyle(ids) })
        m.addItem(.separator())
        m.addItem(ClosureMenuItem("Replace Elevation Data …") { [weak self] in self?.startElevationFix(ids) })
        return m
    }
}

/// Context menu content for sidebar rows.
struct StyleMenu: View {
    @EnvironmentObject var model: AppModel
    let ids: [String]

    /// Menu entry with a check mark in front when it is the color in use.
    @ViewBuilder private func entry(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { on }, set: { _ in action() }))        // a Toggle shows the check mark in front of the title in a menu
    }

    var body: some View {
        let curIcon = model.commonColor(ids, icon: true), curTrack = model.commonColor(ids, icon: false)
        Menu("Icon Color") {
            entry("Default (the icon's own color)", on: curIcon.same && curIcon.rgb == nil) { model.setIconColor(ids, rgb: nil) }
            Divider()
            ForEach(StylePresets.colors, id: \.0) { c in entry(c.0, on: curIcon.same && AppModel.colorsEqual(curIcon.rgb, c.1)) { model.setIconColor(ids, rgb: c.1) } }
            Divider()
            entry("Other Color …", on: AppModel.isCustom(curIcon)) { model.pickColor(ids, forIcon: true) }
        }
        Menu("Track Color") {
            ForEach(StylePresets.colors, id: \.0) { c in entry(c.0, on: curTrack.same && AppModel.colorsEqual(curTrack.rgb, c.1)) { model.setColor(ids, rgb: c.1) } }
            Divider()
            entry("Other Color …", on: AppModel.isCustom(curTrack)) { model.pickColor(ids) }
        }
        let curWidth = model.commonWidth(ids)
        Menu("Track Width") {
            ForEach(StylePresets.widths, id: \.self) { w in entry("\(Int(w)) pt", on: curWidth.same && curWidth.width.map { abs($0 - w) < 0.01 } == true) { model.setWidth(ids, width: w) } }
        }
        Button("Reset Style") { model.resetStyle(ids) }
    }
}


extension AppModel {
    /// Icons and colors are stored inside GPX files. Other track formats (FIT, TRC …) cannot take them, so they are
    /// converted to GPX first (heart rate, cadence and power are kept). Returns the paths to work on, or nil when cancelled.
    func convertToGPXIfNeeded(_ ids: [String]) -> [String]? {
        let foreign = ids.filter { URL(fileURLWithPath: $0).pathExtension.lowercased() != "gpx" && ForeignTracks.isSupported(URL(fileURLWithPath: $0)) }
        guard !foreign.isEmpty else { return ids }
        let a = NSAlert()
        a.messageText = foreign.count == 1 ? "“\(URL(fileURLWithPath: foreign[0]).lastPathComponent)” is not a GPX file." : "\(foreign.count) of the files are not GPX files."
        a.informativeText = "Icons and colors are stored inside GPX files. The files can be converted to GPX first (position, elevation, time, heart rate, cadence and power are kept; laps and other device data of the original are not)."
        a.addButton(withTitle: "Convert; Originals to the Trash")
        a.addButton(withTitle: "Convert; Keep Originals")
        a.addButton(withTitle: "Cancel")
        let r = a.runModal()
        guard r != .alertThirdButtonReturn else { return nil }
        let trash = r == .alertFirstButtonReturn
        let fm = FileManager.default
        var mapping: [String: String] = [:]
        var failed: [String] = []
        for id in foreign {
            let src = URL(fileURLWithPath: id)
            guard let doc = GPXDocument.parse(src), !doc.tracks.isEmpty else { failed.append(src.lastPathComponent); continue }
            var dst = src.deletingPathExtension().appendingPathExtension("gpx")
            var n = 2
            while fm.fileExists(atPath: dst.path) { dst = src.deletingPathExtension().deletingLastPathComponent().appendingPathComponent(src.deletingPathExtension().lastPathComponent + " \(n).gpx"); n += 1 }
            do {
                try doc.xml().write(to: dst, atomically: true, encoding: .utf8)
                if let d = (try? fm.attributesOfItem(atPath: src.path))?[.modificationDate] as? Date { try? fm.setAttributes([.modificationDate: d], ofItemAtPath: dst.path) }
                if trash { try? fm.trashItem(at: src, resultingItemURL: nil) }
                mapping[id] = dst.path
            } catch { failed.append(src.lastPathComponent) }
        }
        if !failed.isEmpty {
            let f = NSAlert(); f.messageText = "\(failed.count) file\(failed.count == 1 ? "" : "s") could not be converted"
            f.informativeText = failed.prefix(5).joined(separator: ", ") + (failed.count > 5 ? " …" : ""); f.runModal()
        }
        for (old, _) in mapping { cache.removeValue(forKey: old) }
        if !mapping.isEmpty { reloadTree() }
        return ids.compactMap { mapping[$0] ?? ($0.lowercased().hasSuffix(".gpx") ? $0 : nil) }
    }
}


extension AppModel {
    /// The color all the given files share (`same` is false when they differ; `rgb` is nil when none is set).
    func commonColor(_ ids: [String], icon: Bool) -> (rgb: [Double]?, same: Bool) {
        let list: [[Double]?] = ids.map { icon ? fileIconColors[$0] : embeddedStyle($0).rgb }
        guard let first = list.first else { return (nil, false) }
        for c in list.dropFirst() where !(c == nil && first == nil) && !(c != nil && first != nil && Self.colorsEqual(c, first!)) { return (nil, false) }
        return (first, true)
    }

    static func colorsEqual(_ a: [Double]?, _ b: [Double]) -> Bool {
        guard let a, a.count == 3, b.count == 3 else { return false }
        return zip(a, b).allSatisfy { abs($0 - $1) < 0.01 }
    }

    /// A color is set but is none of the presets.
    static func isCustom(_ c: (rgb: [Double]?, same: Bool)) -> Bool {
        guard c.same, let rgb = c.rgb else { return false }
        return !StylePresets.colors.contains { colorsEqual(rgb, $0.1) }
    }
}


extension AppModel {
    /// Color and width of a file as stored in it; read from the file's head when the track is not loaded.
    func embeddedStyle(_ id: String) -> (rgb: [Double]?, width: Double?) {
        if let st = styles[id] { return (st.rgb, st.width) }
        if let f = cache[id] { return (f.embeddedColor.flatMap(Self.rgb(fromHex:)), f.embeddedWidth) }
        guard id.lowercased().hasSuffix(".gpx"), let h = try? FileHandle(forReadingFrom: URL(fileURLWithPath: id)) else { return (nil, nil) }
        defer { try? h.close() }
        let head = String(decoding: (try? h.read(upToCount: 8192)) ?? Data(), as: UTF8.self)
        func value(_ tag: String) -> String? {
            guard let a = head.range(of: "<gpxorg:\(tag)>"), let b = head.range(of: "</gpxorg:\(tag)>", range: a.upperBound..<head.endIndex) else { return nil }
            return String(head[a.upperBound..<b.lowerBound])
        }
        return (value("color").flatMap(Self.rgb(fromHex:)), value("width").flatMap { Double($0) })
    }

    func commonWidth(_ ids: [String]) -> (width: Double?, same: Bool) {
        let list = ids.map { embeddedStyle($0).width }
        guard let first = list.first else { return (nil, false) }
        return list.allSatisfy { $0 == first } ? (first, true) : (nil, false)
    }
}
