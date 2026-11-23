import SwiftUI
import AppKit

/// One color choice for the whole program: the named palette with a short stroke of the color behind each name,
/// the system color panel as the last entry ("Other Color …"). Used by the context menus and by Settings.
@MainActor
enum ColorPalette {
    private final class Item: NSMenuItem {
        private var handler: (() -> Void)?
        convenience init(title: String, attributed: NSAttributedString? = nil, checked: Bool, _ handler: @escaping () -> Void) {
            self.init(title: title, action: #selector(run), keyEquivalent: "")
            self.handler = handler; target = self
            if let a = attributed { attributedTitle = a }
            state = checked ? .on : .off
        }
        @objc private func run() { handler?() }
    }

    /// A short colored stroke (light colors get a thin edge so they show on white).
    static func swatch(_ rgb: [Double]) -> NSImage {
        let size = NSSize(width: 28, height: 6)
        return NSImage(size: size, flipped: false) { r in
            let col = NSColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
            let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
            col.setFill(); path.fill()
            NSColor(white: 0, alpha: 0.25).setStroke(); path.lineWidth = 0.6; path.stroke()
            return true
        }
    }

    /// "Name ▬" – the name with the stroke of the color behind it.
    static func title(_ name: String, rgb: [Double]) -> NSAttributedString {
        // a tab stop puts every stroke at the same horizontal position, whatever the length of the name
        let para = NSMutableParagraphStyle()
        para.tabStops = [NSTextTab(textAlignment: .left, location: 84)]
        para.defaultTabInterval = 84
        let out = NSMutableAttributedString(string: L(name) + "\t", attributes: [.font: NSFont.menuFont(ofSize: 0), .paragraphStyle: para])
        let att = NSTextAttachment()
        att.image = swatch(rgb)
        att.bounds = CGRect(x: 0, y: 1, width: 28, height: 6)
        out.append(NSAttributedString(attachment: att))
        return out
    }

    /// Name of a color that is in the palette, otherwise "Other".
    static func name(of rgb: [Double]?) -> String {
        guard let rgb else { return "–" }
        return L(StylePresets.colors.first { AppModel.colorsEqual(rgb, $0.1) }?.0 ?? "Other")
    }

    /// The entries of the color menu: an optional "default" entry, the palette, then "Other Color …".
    static func items(defaultEntry: (title: String, selected: Bool, action: () -> Void)? = nil, current: [Double]?, same: Bool = true,
                      pick: @escaping ([Double]) -> Void, other: @escaping () -> Void) -> [NSMenuItem] {
        var out: [NSMenuItem] = []
        if let d = defaultEntry { out += [Item(title: d.title, checked: d.selected, d.action), .separator()] }
        for (name, rgb) in StylePresets.colors {
            out.append(Item(title: L(name), attributed: title(name, rgb: rgb), checked: same && AppModel.colorsEqual(current, rgb)) { pick(rgb) })
        }
        let custom = same && current != nil && !StylePresets.colors.contains { AppModel.colorsEqual(current, $0.1) }
        out += [.separator(), Item(title: L("Other Color …"), checked: custom, other)]
        return out
    }
}

/// Settings: shows the chosen color as a stroke with its name; a click opens the same color menu as the context menus.
@MainActor
struct PaletteButton: View {
    let rgb: [Double]
    var width: CGFloat? = nil
    let pick: ([Double]) -> Void

    var body: some View {
        Button { open() } label: {
            HStack(spacing: 6) {
                Image(nsImage: ColorPalette.swatch(rgb))
                Text(ColorPalette.name(of: rgb)).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .frame(width: width)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private func open() {
        let m = NSMenu()
        ColorPalette.items(current: rgb, pick: pick, other: { PaletteButton.openPanel(rgb, pick) }).forEach { m.addItem($0) }
        m.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private static let helper = ColorPanelHelper()
    static func openPanel(_ rgb: [Double], _ pick: @escaping ([Double]) -> Void) {
        let panel = NSColorPanel.shared
        panel.color = NSColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
        helper.onChange = { col in
            guard let c = col.usingColorSpace(.sRGB) else { return }
            pick([Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)])
        }
        panel.showsAlpha = false
        panel.isContinuous = false
        panel.setTarget(helper)
        panel.setAction(#selector(ColorPanelHelper.changed(_:)))
        panel.makeKeyAndOrderFront(nil)
    }
}
