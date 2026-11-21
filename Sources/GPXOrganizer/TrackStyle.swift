import SwiftUI
import AppKit
import BCCore

/// Per-file colour / line width chosen by the user. Stored in UserDefaults (GPX files are not modified).
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

    func setColor(_ ids: [String], rgb: [Double]?) {
        for id in ids { var s = styles[id] ?? TrackStyle(); s.rgb = rgb; styles[id] = (s.rgb == nil && s.width == nil) ? nil : s }
        saveStyles()
    }

    func setWidth(_ ids: [String], width: Double?) {
        for id in ids { var s = styles[id] ?? TrackStyle(); s.width = width; styles[id] = (s.rgb == nil && s.width == nil) ? nil : s }
        saveStyles()
    }

    func resetStyle(_ ids: [String]) { for id in ids { styles[id] = nil }; saveStyles() }

    func saveStyles() {
        if let d = try? JSONEncoder().encode(styles) { UserDefaults.standard.set(d, forKey: "trackStyles") }
    }

    static func loadStyles() -> [String: TrackStyle] {
        guard let d = UserDefaults.standard.data(forKey: "trackStyles"),
              let s = try? JSONDecoder().decode([String: TrackStyle].self, from: d) else { return [:] }
        return s
    }

    func pickColor(_ ids: [String]) {
        let panel = NSColorPanel.shared
        if let c = ids.first.flatMap({ styles[$0]?.rgb }) { panel.color = NSColor(red: c[0], green: c[1], blue: c[2], alpha: 1) }
        colorHelper.onChange = { [weak self] col in
            guard let c = col.usingColorSpace(.sRGB) else { return }
            self?.setColor(ids, rgb: [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)])
        }
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(colorHelper)
        panel.setAction(#selector(ColorPanelHelper.changed(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    /// Right-click menu for the given track files (used on the map).
    func makeStyleMenu(for ids: [String]) -> NSMenu {
        let m = NSMenu()
        let colors = NSMenu()
        for (name, rgb) in StylePresets.colors { colors.addItem(ClosureMenuItem(name) { [weak self] in self?.setColor(ids, rgb: rgb) }) }
        colors.addItem(.separator())
        colors.addItem(ClosureMenuItem("Other Color …") { [weak self] in self?.pickColor(ids) })
        let ci = NSMenuItem(title: "Color", action: nil, keyEquivalent: ""); ci.submenu = colors; m.addItem(ci)
        let widths = NSMenu()
        for w in StylePresets.widths { widths.addItem(ClosureMenuItem("\(Int(w)) pt") { [weak self] in self?.setWidth(ids, width: w) }) }
        let wi = NSMenuItem(title: "Line Width", action: nil, keyEquivalent: ""); wi.submenu = widths; m.addItem(wi)
        m.addItem(.separator())
        m.addItem(ClosureMenuItem("Reset Style") { [weak self] in self?.resetStyle(ids) })
        m.addItem(.separator())
        m.addItem(ClosureMenuItem("Choose Icon …") { [weak self] in self?.showIconPicker(for: ids) })
        return m
    }
}

/// Context menu content for sidebar rows.
struct StyleMenu: View {
    @EnvironmentObject var model: AppModel
    let ids: [String]
    var body: some View {
        Menu("Color") {
            ForEach(StylePresets.colors, id: \.0) { c in Button(c.0) { model.setColor(ids, rgb: c.1) } }
            Divider()
            Button("Other Color …") { model.pickColor(ids) }
        }
        Menu("Line Width") {
            ForEach(StylePresets.widths, id: \.self) { w in Button("\(Int(w)) pt") { model.setWidth(ids, width: w) } }
        }
        Divider()
        Button("Reset Style") { model.resetStyle(ids) }
    }
}
