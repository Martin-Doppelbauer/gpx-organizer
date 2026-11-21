import SwiftUI
import AppKit
import BCCore

/// Per-file colour / line width chosen by the user; stored inside the GPX file (gpxorg:color / gpxorg:width).
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

    /// Colour and line width live inside the GPX files (`gpxorg:color`, `gpxorg:width`); the app keeps nothing per file.
    private func applyStyle(_ ids: [String], _ values: [String: String?]) {
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
            a.informativeText = "Colours and line widths are stored inside GPX files only. Not changed: " + failed.prefix(5).joined(separator: ", ") + (failed.count > 5 ? " …" : "")
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
        let icons = NSMenu()
        icons.addItem(ClosureMenuItem("Default (the icon's own colour)") { [weak self] in self?.setIconColor(ids, rgb: nil) })
        icons.addItem(.separator())
        for (name, rgb) in StylePresets.colors { icons.addItem(ClosureMenuItem(name) { [weak self] in self?.setIconColor(ids, rgb: rgb) }) }
        icons.addItem(.separator())
        icons.addItem(ClosureMenuItem("Other Color …") { [weak self] in self?.pickColor(ids, forIcon: true) })
        let ii = NSMenuItem(title: "Icon Color", action: nil, keyEquivalent: ""); ii.submenu = icons; m.addItem(ii)
        let colors = NSMenu()
        for (name, rgb) in StylePresets.colors { colors.addItem(ClosureMenuItem(name) { [weak self] in self?.setColor(ids, rgb: rgb) }) }
        colors.addItem(.separator())
        colors.addItem(ClosureMenuItem("Other Color …") { [weak self] in self?.pickColor(ids) })
        let ci = NSMenuItem(title: "Track Color", action: nil, keyEquivalent: ""); ci.submenu = colors; m.addItem(ci)
        let widths = NSMenu()
        for w in StylePresets.widths { widths.addItem(ClosureMenuItem("\(Int(w)) pt") { [weak self] in self?.setWidth(ids, width: w) }) }
        let wi = NSMenuItem(title: "Track Width", action: nil, keyEquivalent: ""); wi.submenu = widths; m.addItem(wi)
        m.addItem(ClosureMenuItem("Reset Style") { [weak self] in self?.resetStyle(ids) })
        return m
    }
}

/// Context menu content for sidebar rows.
struct StyleMenu: View {
    @EnvironmentObject var model: AppModel
    let ids: [String]
    var body: some View {
        Menu("Icon Color") {
            Button("Default (the icon's own colour)") { model.setIconColor(ids, rgb: nil) }
            Divider()
            ForEach(StylePresets.colors, id: \.0) { c in Button(c.0) { model.setIconColor(ids, rgb: c.1) } }
            Divider()
            Button("Other Color …") { model.pickColor(ids, forIcon: true) }
        }
        Menu("Track Color") {
            ForEach(StylePresets.colors, id: \.0) { c in Button(c.0) { model.setColor(ids, rgb: c.1) } }
            Divider()
            Button("Other Color …") { model.pickColor(ids) }
        }
        Menu("Track Width") {
            ForEach(StylePresets.widths, id: \.self) { w in Button("\(Int(w)) pt") { model.setWidth(ids, width: w) } }
        }
        Button("Reset Style") { model.resetStyle(ids) }
    }
}
