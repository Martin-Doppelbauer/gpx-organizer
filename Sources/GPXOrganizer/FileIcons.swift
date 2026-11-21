import SwiftUI
import AppKit
import BCCore

extension AppModel {
    static func loadFileIcons() -> [String: String] {
        guard let d = UserDefaults.standard.data(forKey: "fileIcons"),
              let s = try? JSONDecoder().decode([String: String].self, from: d) else { return [:] }
        return s
    }

    func saveFileIcons() {
        if let d = try? JSONEncoder().encode(fileIcons) { UserDefaults.standard.set(d, forKey: "fileIcons") }
    }

    /// Sets (or with nil clears) the icon of the given files.
    func setIcon(_ ids: [String], _ name: String?) {
        for id in ids {
            fileIcons[id] = name
            cache[id]?.iconOverride = name
        }
        saveFileIcons()
        fileRevision += 1
        viewRevision += 1
    }

    func showIconPicker(for ids: [String]) { iconPickerIDs = ids; iconPickerOpen = true }

    /// What the file list shows for a file: symbol, tint, and whether it sits in a coloured disc (waypoint files).
    func rowIcon(_ id: String) -> (name: String, color: Color, disc: Bool) {
        if let c = waypointColors[id] {
            return (fileIcons[id] ?? waypointIcons[id] ?? "mappin", Color(red: c[0], green: c[1], blue: c[2]), true)
        }
        let kind = trackKinds[id] ?? .other
        if let o = fileIcons[id] { return (o, IconCatalog.color(o), false) }
        let tint: Color
        switch kind { case .planned: tint = .gray; case .hike: tint = .green; case .bike: tint = .orange; case .car: tint = .indigo; case .other: tint = .teal }
        return (kind.iconName, tint, false)
    }
}

/// All icons the user can pick from (only symbols that exist on this macOS), with readable names and colours.
enum IconCatalog {
    struct Entry { let name: String; let label: String; let color: Color }
    static let groups: [(String, [Entry])] = [
        ("Geography", [
            e("mountain.2.fill", "Mountains / summit", .brown), e("building.2.fill", "Cities", .orange),
            e("water.waves", "Rivers", .blue), e("drop.fill", "Springs", .cyan),
            e("drop.circle.fill", "Spring (alternative)", .teal), e("building", "Village / small town", .yellow),
            e("humidity.fill", "Lake / pond", .blue), e("mountain.2", "Hill / ridge", .brown),
            e("flag.2.crossed.fill", "Summit cross / pass", .orange)]),
        ("Tracks", [
            e("pencil.and.ruler.fill", "Planned track (no recorded times)", .gray),
            e("point.topleft.down.to.point.bottomright.curvepath", "Track (kind unknown)", .teal),
            e("figure.hiking", "Hike", .green), e("figure.walk", "Walk", .mint), e("figure.run", "Run / trail run", .teal),
            e("figure.outdoor.cycle", "Mountain bike ride", .orange), e("bicycle", "Road bike / cycling", .yellow),
            e("car.fill", "Car trip", .indigo), e("motorcycle.fill", "Motorcycle ride", .red), e("bus.fill", "Bus", .blue),
            e("tram.fill", "Tram / train", .red), e("airplane", "Flight", .cyan), e("sailboat.fill", "Sailing / boat trip", .blue),
            e("ferry.fill", "Ferry", .cyan), e("figure.skiing.downhill", "Skiing", .blue), e("figure.climbing", "Climbing", .brown),
            e("flag.checkered", "Race / finish", .primary)]),
        ("Places", [
            e("mappin", "Waypoint", .red), e("pin.fill", "Pin", .pink), e("flag.fill", "Flag", .red), e("star.fill", "Favourite", .yellow),
            e("heart.fill", "Heart", .red), e("house.fill", "Home / residence", .brown), e("building", "Town (small)", .yellow),
            e("building.2", "Town (medium)", .orange), e("building.2.fill", "City (large)", .red),
            e("building.columns.fill", "Bank / museum / official building", .brown), e("tent.fill", "Campground", .green),
            e("bed.double.fill", "Lodging / lodge", .purple), e("parkingsign", "Parking", .blue), e("fuelpump.fill", "Fuel station", .orange),
            e("banknote", "Bank / cash point", .green), e("fork.knife", "Restaurant", .orange), e("cup.and.saucer.fill", "Café", .brown),
            e("cart.fill", "Shop", .pink), e("cross.case.fill", "First aid / pharmacy", .red), e("phone.fill", "Telephone", .green)]),
        ("Nature", [
            e("mountain.2.fill", "Summit / mountain", .brown), e("tree.fill", "Tree / park", .green), e("leaf.fill", "Nature", .green),
            e("drop.fill", "Spring / water", .blue), e("water.waves", "River / lake / sea", .cyan), e("snowflake", "Snow / winter", .cyan),
            e("sun.max.fill", "Sun / viewpoint", .yellow), e("cloud.rain.fill", "Rain", .gray), e("flame.fill", "Fire place", .orange),
            e("binoculars.fill", "Scenic area / viewpoint", .brown), e("camera.fill", "Photo spot", .gray), e("shower.fill", "Shower", .blue),
            e("bolt.fill", "Lightning / power", .yellow)]),
        ("Marks", [
            e("circle.fill", "Circle", .blue), e("triangle.fill", "Triangle", .green), e("square.fill", "Square", .red),
            e("diamond.fill", "Diamond", .purple), e("hexagon.fill", "Hexagon", .orange),
            e("exclamationmark.triangle.fill", "Warning", .yellow), e("questionmark.circle.fill", "Question", .blue),
            e("xmark.circle.fill", "Cross / blocked", .red), e("checkmark.circle.fill", "Done / OK", .green),
            e("antenna.radiowaves.left.and.right", "Navigation aid / radio tower", .gray), e("location.fill", "Location", .blue),
            e("scope", "Target", .red)])
    ]
    private static func e(_ n: String, _ l: String, _ c: Color) -> Entry { Entry(name: n, label: l, color: c) }

    static var all: [(String, [Entry])] {
        groups.map { ($0.0, $0.1.filter { NSImage(systemSymbolName: $0.name, accessibilityDescription: nil) != nil }) }
    }
    static func entry(_ name: String) -> Entry? { groups.flatMap { $0.1 }.first { $0.name == name } }
    static func color(_ name: String) -> Color { entry(name)?.color ?? .teal }
}

final class HoverLabel: ObservableObject { @Published var entry: IconCatalog.Entry? }

/// Sheet with a matrix of coloured icons; hovering shows the name at once, clicking assigns the icon to all chosen files.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(IconCatalog.all, id: \.0) { group in
                        Text(group.0).font(.caption).foregroundStyle(.secondary)
                        LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
                            ForEach(group.1, id: \.name) { entry in
                                Button {
                                    model.setIcon(model.iconPickerIDs, entry.name); dismiss()
                                } label: {
                                    Image(systemName: entry.name).font(.system(size: 20)).foregroundStyle(entry.color)
                                        .frame(width: 42, height: 42)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(hover.entry?.name == entry.name
                                                                                           ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12)))
                                }
                                .buttonStyle(.plain)
                                .onHover { inside in
                                    if inside { hover.entry = entry } else if hover.entry?.name == entry.name { hover.entry = nil }
                                }
                            }
                        }
                    }
                }
                .padding(.trailing, 6)
            }
            // instant "tooltip": no waiting time
            HStack(spacing: 8) {
                if let e = hover.entry {
                    Image(systemName: e.name).foregroundStyle(e.color).frame(width: 22)
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
