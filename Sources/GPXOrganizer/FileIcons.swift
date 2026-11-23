import SwiftUI
import AppKit
import BCCore

extension AppModel {
    /// Sets (or with nil clears) the icon of the given files by writing its *name* into the GPX file
    /// (`gpxorg:icon` in the metadata). The files are the only place icons are kept; other formats cannot store one.
    func setIcon(_ idsIn: [String], _ name: String?) {
        guard let ids = convertToGPXIfNeeded(idsIn) else { return }
        var failed: [String] = []
        for id in ids {
            let url = URL(fileURLWithPath: id)
            guard url.pathExtension.lowercased() == "gpx", writeMeta(url, ["icon": name]) else { failed.append(url.lastPathComponent); continue }
            fileIcons[id] = name
            cache[id]?.iconOverride = name
            cache[id]?.embeddedIcon = name
        }
        refreshWaypointKinds()
        applySort()                                   // the file moves to its new place in the list …
        viewRevision += 1
        if let first = ids.first(where: { !failed.contains(URL(fileURLWithPath: $0).lastPathComponent) }) {
            for delay in [0.15, 0.5] {                // … and the list scrolls so that it can be found there
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    scrollFileListToTop(first, rows: self.fileRows, offsetFraction: 0.3)
                }
            }
        }
        if !failed.isEmpty {
            let a = NSAlert()
            a.messageText = "The icon could not be stored in \(failed.count == 1 ? "this file" : "\(failed.count) files")"
            a.informativeText = "Icons are stored inside GPX files only. Not changed: " + failed.prefix(5).joined(separator: ", ") + (failed.count > 5 ? " …" : "")
            a.runModal()
        }
    }

    /// Patches values (icon, color, width) into the GPX text and keeps the modification date. Returns false if the file
    /// cannot take them (not UTF-8, unusual metadata, result would not be well-formed XML); the file is then left unchanged.
    func writeMeta(_ url: URL, _ values: [String: String?]) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        guard let patched = GPXIconTag.apply(to: text, values: values) else { return false }
        if patched == text { return true }
        let fm = FileManager.default
        let old = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard trashCopyOfOriginal(url) else { return false }
        do { try patched.write(to: url, atomically: true, encoding: .utf8) } catch { return false }
        if let old { try? fm.setAttributes([.modificationDate: old], ofItemAtPath: url.path) }
        return true
    }

    /// Speed limits changed: classify all loaded tracks again.
    func reclassify() {
        trackKinds = [:]
        refreshWaypointKinds()
        fileRevision += 1
    }

    func showIconPicker(for ids: [String]) { iconPickerIDs = ids; iconPickerOpen = true }

    /// What the file list shows for a file: symbol, tint, and whether it sits in a colored disc (waypoint files).
    func rowIcon(_ id: String) -> (name: String, color: Color, disc: Bool) {
        if let c = waypointColors[id] {
            return (waypointIcons[id] ?? "mappin", Color(red: c[0], green: c[1], blue: c[2]), true)
        }
        let kind = trackKinds[id] ?? .other
        let custom = fileIconColors[id].map { Color(red: $0[0], green: $0[1], blue: $0[2]) }
        if let o = fileIcons[id] { return (IconCatalog.symbol(for: o), custom ?? IconCatalog.color(o), false) }
        let tint: Color
        switch kind { case .planned: tint = .gray; case .hike: tint = .green; case .bike: tint = .orange; case .car: tint = .indigo; case .other: tint = .teal }
        return (kind.iconName, custom ?? tint, false)
    }
}

/// Which symbol and color a waypoint marker gets. A chosen icon (or icon color) in the file wins; otherwise the Garmin symbol
/// is turned into the matching icon of the icon menu with that menu's default color (symbols that name a color keep it).
enum IconStyle {
    static func catalogID(forSymbol sym: String) -> String {
        let s = sym.lowercased()
        let table: [(String, String)] = [("city (large)", "city"), ("city (medium)", "town"), ("city", "village"), ("summit", "mountains"),
            ("parking", "parking"), ("lodge", "lodging"), ("residence", "home"), ("trail head", "hike"), ("campground", "camp"),
            ("restaurant", "restaurant"), ("shower", "spring"), ("boat ramp", "sailing"), ("park", "tree"), ("scenic", "viewpoint"),
            ("bank", "cash"), ("navaid", "radio-tower"), ("triangle", "triangle"), ("circle", "circle"), ("flag", "flag"), ("pin", "pin")]
        for (k, v) in table where s.contains(k) { return v }
        return "waypoint"
    }

    /// Default color of a menu icon as RGB.
    static func rgb(ofIcon stored: String) -> [Double]? {
        guard let e = IconCatalog.entry(stored), let c = NSColor(e.color).usingColorSpace(.sRGB) else { return nil }
        return [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)]
    }

    static func marker(file: GPXFile?, sym: String) -> (symbol: String, rgb: [Double]) {
        let override = file?.iconOverride
        let id = override ?? catalogID(forSymbol: sym)
        let symbol = IconCatalog.symbol(for: id)
        if let hex = file?.embeddedIconColor, let c = Waypoint.rgb(fromHex: hex) { return (symbol, c) }
        if override != nil, let c = rgb(ofIcon: id) { return (symbol, c) }
        let s = sym.lowercased()
        if ["blue", "red", "green", "yellow", "orange"].contains(where: s.contains) { return (symbol, Waypoint.rgb(forSymbol: sym)) }
        return (symbol, rgb(ofIcon: id) ?? Waypoint.rgb(forSymbol: sym))
    }
}

/// All icons the user can pick from. Each has a plain, generic name (`id`) that is what gets written into the GPX file;
/// the SF Symbol behind it is only how this app draws it (only symbols that exist on this macOS are offered).
enum IconCatalog {
    struct Entry { let id: String; let symbol: String; let label: String; let color: Color }
    static let groups: [(String, [Entry])] = [
        ("Geography", [
            e("mountains", "mountain.2.fill", "Mountains", .brown), e("city", "building.2.fill", "City", .orange),
            e("river", "water.waves", "River", .blue), e("spring", "drop.fill", "Spring", .cyan),
            e("well", "drop.circle.fill", "Well / water point", .teal), e("village", "building", "Village", .yellow),
            e("lake", "humidity.fill", "Lake", .blue), e("hills", "mountain.2", "Hills", .brown),
            e("pass", "custom.mountain-pass", "Mountain pass", .brown)]),
        ("Tracks", [
            e("planned-route", "pencil.and.ruler.fill", "Planned route (no recorded times)", .gray),
            e("track", "point.topleft.down.to.point.bottomright.curvepath", "Track (kind unknown)", .teal),
            e("hike", "figure.hiking", "Hike", .green), e("walk", "figure.walk", "Walk", .mint), e("run", "figure.run", "Run / trail run", .teal),
            e("mountain-bike", "figure.outdoor.cycle", "Mountain bike ride", .orange), e("road-bike", "bicycle", "Road bike / cycling", .yellow),
            e("car", "car.fill", "Car trip", .indigo), e("motorcycle", "motorcycle.fill", "Motorcycle ride", .red), e("bus", "bus.fill", "Bus", .blue),
            e("train", "tram.fill", "Train / tram", .red), e("flight", "airplane", "Flight", .cyan), e("sailing", "sailboat.fill", "Sailing / boat trip", .blue),
            e("ferry", "ferry.fill", "Ferry", .cyan), e("skiing", "figure.skiing.downhill", "Skiing", .blue), e("climbing", "figure.climbing", "Climbing", .brown),
            e("finish", "flag.checkered", "Race / finish", .primary)]),
        ("Places", [
            e("waypoint", "mappin", "Waypoint", .red), e("pin", "pin.fill", "Pin", .pink), e("flag", "flag.fill", "Flag", .red),
            e("favorite", "star.fill", "Favourite", .yellow), e("heart", "heart.fill", "Heart", .red), e("home", "house.fill", "Home", .brown),
            e("town", "building.2", "Town", .orange), e("official-building", "building.columns.fill", "Bank / museum / official building", .brown),
            e("camp", "tent.fill", "Campground", .green), e("lodging", "bed.double.fill", "Lodging", .purple),
            e("mountain-hut", "custom.mountain-hut", "Mountain hut", .brown),
            e("church", "custom.church", "Church", .indigo), e("cathedral", "custom.cathedral", "Cathedral", .indigo), e("monastery", "custom.monastery", "Monastery", .indigo),
            e("summit-cross", "custom.summit-cross", "Summit cross", .indigo), e("parking", "parkingsign", "Parking", .blue),
            e("fuel", "fuelpump.fill", "Fuel station", .orange), e("cash", "banknote", "Cash point", .green), e("restaurant", "fork.knife", "Restaurant", .orange),
            e("cafe", "cup.and.saucer.fill", "Café", .brown), e("shop", "cart.fill", "Shop", .pink), e("first-aid", "cross.case.fill", "First aid / pharmacy", .red),
            e("phone", "phone.fill", "Telephone", .green),
            e("coal-plant", "custom.coal-plant", "Coal power plant", .gray), e("wind-turbine", "custom.wind-turbine", "Wind turbine", .teal),
            e("solar-plant", "custom.solar-plant", "Solar (PV) plant", .blue), e("nuclear-plant", "custom.nuclear-plant", "Nuclear power plant", .yellow)]),
        ("Nature", [
            e("tree", "tree.fill", "Tree / forest", .green), e("nature", "leaf.fill", "Nature", .green), e("snow", "snowflake", "Snow / winter", .cyan),
            e("sun", "sun.max.fill", "Sun", .yellow), e("rain", "cloud.rain.fill", "Rain", .gray), e("fire", "flame.fill", "Fire place", .orange),
            e("viewpoint", "binoculars.fill", "Viewpoint / scenic area", .brown), e("photo", "camera.fill", "Photo spot", .gray),
            e("waterfall", "custom.waterfall", "Waterfall", .blue), e("lightning", "bolt.fill", "Lightning / power", .yellow)]),
        ("Marks", [
            e("circle", "circle.fill", "Circle", .blue), e("triangle", "triangle.fill", "Triangle", .green), e("square", "square.fill", "Square", .red),
            e("diamond", "diamond.fill", "Diamond", .purple), e("hexagon", "hexagon.fill", "Hexagon", .orange),
            e("warning", "exclamationmark.triangle.fill", "Warning", .yellow), e("question", "questionmark.circle.fill", "Question", .blue),
            e("blocked", "xmark.circle.fill", "Blocked", .red), e("ok", "checkmark.circle.fill", "Done / OK", .green),
            e("radio-tower", "antenna.radiowaves.left.and.right", "Navigation aid / radio signal", .gray),
            e("transmitter-tower", "custom.transmitter-tower", "Transmitter tower", .gray),
            e("lookout-tower", "custom.lookout-tower", "Lookout tower", .brown), e("location", "location.fill", "Location", .blue),
            e("target", "scope", "Target", .red)])
    ]
    private static func e(_ id: String, _ sym: String, _ l: String, _ c: Color) -> Entry { Entry(id: id, symbol: sym, label: l, color: c) }

    static var all: [(String, [Entry])] {
        groups.map { ($0.0, $0.1.filter { CustomIcons.isCustom($0.symbol) || NSImage(systemSymbolName: $0.symbol, accessibilityDescription: nil) != nil }) }
    }
    /// Looks a stored name up; older files may still hold an SF Symbol name, which is accepted too.
    static func entry(_ stored: String) -> Entry? {
        let id = stored == "shower" || stored == "shower.fill" ? "waterfall" : stored      // files written earlier used "shower"
        return groups.flatMap { $0.1 }.first { $0.id == id || $0.symbol == id }
    }
    static func symbol(for stored: String) -> String { entry(stored)?.symbol ?? stored }
    static func color(_ stored: String) -> Color { entry(stored)?.color ?? .teal }
}

final class HoverLabel: ObservableObject { @Published var entry: IconCatalog.Entry? }

/// Sheet with a matrix of colored icons; hovering shows the name at once, clicking assigns the icon to all chosen files.
struct IconPickerSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var hover = HoverLabel()
    private let cols = Array(repeating: GridItem(.fixed(46), spacing: 6), count: 8)

    private var title: String {
        model.iconPickerIDs.count == 1
            ? "Icon for “\(URL(fileURLWithPath: model.iconPickerIDs[0]).deletingPathExtension().lastPathComponent)”"
            : "Icon for all \(model.iconPickerIDs.count) selected files"
    }

    /// The icon that all chosen files have at the moment (nil when they differ or none is set).
    private var currentID: String? {
        let names = model.iconPickerIDs.map { model.fileIcons[$0].flatMap { IconCatalog.entry($0)?.id } }
        guard let first = names.first, let id = first, names.allSatisfy({ $0 == id }) else { return nil }
        return id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ScrollViewReader { sv in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(IconCatalog.all, id: \.0) { group in
                        Text(group.0).font(.caption).foregroundStyle(.secondary)
                        LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
                            ForEach(group.1, id: \.id) { entry in
                                Button {
                                    model.setIcon(model.iconPickerIDs, entry.id); dismiss()
                                } label: {
                                    IconImage(name: entry.symbol).font(.system(size: 20)).foregroundStyle(entry.color)
                                        .frame(width: 42, height: 42)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(entry.id == currentID ? Color.accentColor.opacity(0.35)
                                                                                           : (hover.entry?.id == entry.id ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12))))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: entry.id == currentID ? 2.5 : 0))
                                }
                                .buttonStyle(.plain)
                                .id(entry.id)
                                .onHover { inside in
                                    if inside { hover.entry = entry } else if hover.entry?.id == entry.id { hover.entry = nil }
                                }
                            }
                        }
                    }
                }
                .padding(.trailing, 6)
            }
            .onAppear { if let c = currentID { DispatchQueue.main.async { sv.scrollTo(c, anchor: .center) } } }
            }
            // instant "tooltip": no waiting time
            HStack(spacing: 8) {
                if let e = hover.entry {
                    IconImage(name: e.symbol).foregroundStyle(e.color).frame(width: 22)
                    Text(e.label).fontWeight(.medium)
                } else {
                    Text("Move the pointer over an icon to see what it means").foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(height: 26)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
            HStack {
                Button("Automatic") { model.setIcon(model.iconPickerIDs, nil); dismiss() }
                    .help("Remove the chosen icon; the app picks one from the file's contents again")
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 440, height: 520)
    }
}
