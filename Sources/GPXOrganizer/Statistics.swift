import SwiftUI
import AppKit
import Charts
import BCCore

// Statistics over all track files below the root folder, and a search for duplicate tracks.
// The files are only read (except "Move to Trash", which asks first and can be undone in the Finder).

// MARK: Data

struct TrackRecord: Codable, Identifiable {
    var id: String { path }
    var path: String
    var mtime: Double
    var size: Int64
    var distance: Double      // m
    var ascent: Double        // m
    var seconds: Double       // moving time
    var date: Double          // start time, else the file's date
    var hasTime: Bool
    var pts: Int
    var sx: Double, sy: Double, ex: Double, ey: Double      // start and end (Web-Mercator)

    var folder: String { (path as NSString).deletingLastPathComponent }
    var name: String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }
    var when: Date { Date(timeIntervalSince1970: date) }
}

@MainActor
final class StatsStore: ObservableObject {
    static let shared = StatsStore()
    @Published private(set) var records: [TrackRecord] = []
    @Published var status = ""
    @Published var root: URL?
    var customRoot: URL?          // chosen in the statistics windows; otherwise the main folder is used
    private var running = false
    private var pendingRoot: URL?

    private nonisolated static var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GPXOrganizer/TrackStats2.json")
    }

    /// Reads (or updates) the statistics of all tracks below `root`; unchanged files come from the cache.
    func refresh(root newRoot: URL) {
        guard !running else { if newRoot != root { pendingRoot = newRoot }; return }
        root = newRoot
        running = true
        status = L("Looking for tracks …")
        let rootPath = newRoot.path
        Task.detached(priority: .userInitiated) {
            var known: [String: TrackRecord] = [:]
            if let d = try? Data(contentsOf: Self.cacheURL), let r = try? JSONDecoder().decode([TrackRecord].self, from: d) {
                known = Dictionary(r.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
            }
            var files: [(URL, Double, Int64)] = []
            if let en = FileManager.default.enumerator(at: URL(fileURLWithPath: rootPath), includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                                                       options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let u as URL in en where ForeignTracks.isSupported(u) {
                    guard let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]), v.isRegularFile == true else { continue }
                    files.append((u, v.contentModificationDate?.timeIntervalSince1970 ?? 0, Int64(v.fileSize ?? 0)))
                }
            }
            let slots = Slots(count: files.count)
            var todo: [Int] = []
            for (i, f) in files.enumerated() {
                if let k = known[f.0.path], k.mtime == f.1, k.size == f.2 { slots[i] = k } else { todo.append(i) }
            }
            let total = todo.count
            var from = 0
            while from < total {
                let to = min(from + 400, total)
                DispatchQueue.concurrentPerform(iterations: to - from) { n in
                    let i = todo[from + n]
                    slots[i] = Self.compute(files[i].0, mtime: files[i].1, size: files[i].2)
                }
                from = to
                await MainActor.run { self.status = L("Reading tracks … %@ of %@", "\(from)", "\(total)") }
            }
            let list = (0..<files.count).compactMap { slots[$0] }
            if let d = try? JSONEncoder().encode(list) {
                try? FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? d.write(to: Self.cacheURL, options: .atomic)
            }
            await MainActor.run { self.records = list; self.status = ""; self.running = false
                if let r = self.pendingRoot { self.pendingRoot = nil; self.refresh(root: r) } }
        }
    }

    func remove(paths: Set<String>) {
        records.removeAll { paths.contains($0.path) }
        if let d = try? JSONEncoder().encode(records) { try? d.write(to: Self.cacheURL, options: .atomic) }
    }

    private final class Slots: @unchecked Sendable {
        private let p: UnsafeMutablePointer<TrackRecord?>
        private let n: Int
        init(count: Int) { n = count; p = .allocate(capacity: max(count, 1)); p.initialize(repeating: nil, count: max(count, 1)) }
        deinit { p.deinitialize(count: max(n, 1)); p.deallocate() }
        subscript(i: Int) -> TrackRecord? { get { p[i] } set { p[i] = newValue } }
    }

    nonisolated private static func compute(_ url: URL, mtime: Double, size: Int64) -> TrackRecord? {
        guard let f = GPXFile.load(url), let first = f.segments.first(where: { $0.count >= 4 }), let last = f.segments.last(where: { $0.count >= 4 }) else { return nil }
        var date = mtime
        if url.pathExtension.lowercased() == "gpx", let t = firstTime(url) { date = t }
        return TrackRecord(path: url.path, mtime: mtime, size: size, distance: f.distance, ascent: f.ascent, seconds: f.movingSeconds, date: date,
                           hasTime: f.hasTime, pts: f.pointTotal, sx: first[0], sy: first[1], ex: last[last.count - 2], ey: last[last.count - 1])
    }

    nonisolated private static let timeRe = try! NSRegularExpression(pattern: "<time>\\s*([^<\\s]+)\\s*</time>")
    /// Time of the first track point (not the time in the file header, which is the time of the export).
    nonisolated private static func firstTime(_ url: URL) -> Double? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        let data = (try? h.read(upToCount: 131_072)) ?? Data()
        try? h.close()
        let s = String(decoding: data, as: UTF8.self)
        guard let p = s.range(of: "<trkpt") else { return nil }
        let rest = String(s[p.lowerBound...])
        guard let m = timeRe.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)), let r = Range(m.range(at: 1), in: rest) else { return nil }
        let t = String(rest[r])
        let a = ISO8601DateFormatter(); a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return (a.date(from: t) ?? ISO8601DateFormatter().date(from: t))?.timeIntervalSince1970
    }
}

// MARK: Overview

struct StatRow: Identifiable {
    let id: String
    let name: String
    var count = 0
    var distance = 0.0
    var ascent = 0.0
    var seconds = 0.0
    var longest = 0.0
}

final class StatsUI: ObservableObject {
    @Published var group = 1                      // 0 folder, 1 year, 2 month
    @Published var year = 0                       // 0 = all years
    @Published var recordedOnly = false
    @Published var cumulative = true              // folders: include sub-folders
    @Published var sort = [KeyPathComparator(\StatRow.name, order: .forward)]
    @Published var dupRevision = 0
}

/// The two windows share this frame: a title bar with refresh button and the reading progress.
struct StatsWindow<Content: View>: View {
    @ObservedObject var store = StatsStore.shared
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { chooseFolder() } label: { Label(store.root?.lastPathComponent ?? L("Folder"), systemImage: "folder") }
                    .help("Choose the folder to analyze (including its sub-folders)")
                Spacer()
                if !store.status.isEmpty { ProgressView().controlSize(.small); Text(store.status).font(.caption).foregroundStyle(.secondary) }
                Button("Refresh") { reload() }
            }
            .padding(10)
            Divider()
            content
        }
        .frame(minWidth: 820, minHeight: 520)
        .onAppear { reload() }
    }

    private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.directoryURL = store.root; p.prompt = L("Choose")
        p.message = L("Folder to analyze (including its sub-folders)")
        guard p.runModal() == .OK, let u = p.url else { return }
        store.customRoot = u
        store.refresh(root: u)
    }

    private func reload() {
        if let c = store.customRoot { store.refresh(root: c); return }
        let root = AppModel.keyModel()?.rootURL ?? UserDefaults.standard.string(forKey: "rootPath").map { URL(fileURLWithPath: $0) } ?? AppSettings.defaultRouteFolder
        store.refresh(root: root)
    }
}

struct StatisticsView: View {
    @ObservedObject var store = StatsStore.shared
    @StateObject private var ui = StatsUI()
    var body: some View { StatsWindow { OverviewView(store: store, ui: ui) } }
}

struct DuplicatesWindow: View {
    @ObservedObject var store = StatsStore.shared
    var body: some View { StatsWindow { DuplicatesView(store: store) } }
}

struct OverviewView: View {
    @ObservedObject var store: StatsStore
    @ObservedObject var ui: StatsUI

    private var base: [TrackRecord] {
        store.records.filter { r in
            (!ui.recordedOnly || r.hasTime) && (ui.year == 0 || Calendar.current.component(.year, from: r.when) == ui.year)
        }
    }
    private var years: [Int] { Array(Set(store.records.map { Calendar.current.component(.year, from: $0.when) })).sorted(by: >) }

    private var rows: [StatRow] {
        var dict: [String: StatRow] = [:]
        func add(_ key: String, _ name: String, _ r: TrackRecord) {
            var s = dict[key] ?? StatRow(id: key, name: name)
            s.count += 1; s.distance += r.distance; s.ascent += r.ascent; s.seconds += r.seconds; s.longest = max(s.longest, r.distance)
            dict[key] = s
        }
        let cal = Calendar.current
        let rootPath = store.root?.path ?? ""
        for r in base {
            switch ui.group {
            case 0:
                if ui.cumulative {
                    var dir = r.folder
                    while dir.hasPrefix(rootPath) {
                        add(dir, dir == rootPath ? (rootPath as NSString).lastPathComponent : String(dir.dropFirst(rootPath.count + 1)), r)
                        if dir == rootPath { break }
                        dir = (dir as NSString).deletingLastPathComponent
                    }
                } else {
                    add(r.folder, r.folder == rootPath ? (rootPath as NSString).lastPathComponent : String(r.folder.dropFirst(rootPath.count + 1)), r)
                }
            case 1:
                let y = cal.component(.year, from: r.when); add(String(y), String(y), r)
            default:
                let c = cal.dateComponents([.year, .month], from: r.when)
                let k = String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0); add(k, k, r)
            }
        }
        return dict.values.sorted(using: ui.sort)
    }

    var body: some View {
        let list = rows
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Per", selection: $ui.group) { Text("Folder").tag(0); Text("Year").tag(1); Text("Month").tag(2) }.pickerStyle(.segmented).frame(width: 240)
                Picker("Year", selection: $ui.year) { Text("All years").tag(0); ForEach(years, id: \.self) { Text(String($0)).tag($0) } }.frame(width: 150)
                Toggle("Only recorded tracks (with time stamps)", isOn: $ui.recordedOnly)
                if ui.group == 0 { Toggle("Include sub-folders", isOn: $ui.cumulative) }
                Spacer()
            }
            Text(summary(list)).font(.callout).foregroundStyle(.secondary)
            if ui.group != 0 && !list.isEmpty {
                Chart(list.sorted { $0.name < $1.name }) { r in
                    BarMark(x: .value(L("Period"), r.name), y: .value("km", r.distance / 1000)).foregroundStyle(Color.accentColor)
                }
                .chartYAxisLabel("km")
                .chartXAxis {
                    // many months: only every n-th label, so they stay readable
                    let names = list.map(\.name).sorted()
                    let step = max(1, Int((Double(names.count) / 12).rounded(.up)))
                    AxisMarks(values: names.enumerated().filter { $0.offset % step == 0 }.map(\.element)) { _ in
                        AxisTick(); AxisValueLabel()
                    }
                }
                .frame(height: 150)
            }
            Table(list, sortOrder: $ui.sort) {
                TableColumn(L("Name"), value: \.name) { Text($0.name).lineLimit(1) }.width(min: 160, ideal: 260)
                TableColumn(L("Tracks"), value: \.count) { Text("\($0.count)").monospacedDigit() }.width(60)
                TableColumn(L("Distance"), value: \.distance) { Text(String(format: "%.0f km", $0.distance / 1000)).monospacedDigit() }.width(90)
                TableColumn(L("Ascent"), value: \.ascent) { Text(String(format: "%.0f m", $0.ascent)).monospacedDigit() }.width(90)
                TableColumn(L("Moving time"), value: \.seconds) { Text(Self.hours($0.seconds)).monospacedDigit() }.width(100)
                TableColumn(L("Longest"), value: \.longest) { Text(String(format: "%.0f km", $0.longest / 1000)).monospacedDigit() }.width(80)
            }
        }
        .padding(10)
    }

    private func summary(_ list: [StatRow]) -> String {
        let b = base
        return L("%@ tracks · %@ · ascent %@ m · moving time %@", "\(b.count)", "\(Self.km(b.reduce(0) { $0 + $1.distance }))", "\(Self.num(b.reduce(0) { $0 + $1.ascent }))", "\(Self.hours(b.reduce(0) { $0 + $1.seconds }))")
    }
    static func km(_ m: Double) -> String { String(format: "%.0f km", m / 1000) }
    static func num(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0))) }
    static func hours(_ s: Double) -> String { s < 60 ? "–" : String(format: "%d:%02d h", Int(s) / 3600, Int(s) % 3600 / 60) }
}

// MARK: Duplicates

struct DupGroup: Identifiable {
    let id: Int
    let members: [TrackRecord]       // the first one is the suggested one to keep
    let identical: Bool
}

enum DuplicateFinder {
    private static func lat(_ y: Double) -> Double { Merc.lat(y: y) }
    private static func close(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, meters: Double) -> Bool {
        let a = GPXPoint(lat: lat(ay), lon: Merc.lon(x: ax)), b = GPXPoint(lat: lat(by), lon: Merc.lon(x: bx))
        return haversineMeters(a, b) <= meters
    }

    private static func ext(_ r: TrackRecord) -> String { (r.path as NSString).pathExtension.lowercased() }

    /// The first (up to) 100 track points of a file, read from the file itself (all segments in a row).
    private static func firstPoints(_ r: TrackRecord) -> [GPXPoint] {
        let url = URL(fileURLWithPath: r.path)
        guard let doc = (ext(r) == "gpx" ? GPXDocument.parse(url) : ForeignTracks.parse(url)) else { return [] }
        var out: [GPXPoint] = []
        for t in doc.tracks { for seg in t.segments { for p in seg { out.append(p); if out.count >= 100 { return out } } } }
        return out
    }

    /// Candidates are found cheaply from the statistics (same start place, same start time or length); a pair only counts
    /// as duplicate when the first 100 track points of both files agree.
    /// `sameFormatOnly`: a GPX and a FIT file are never duplicates of each other.
    static func find(_ all: [TrackRecord], sameFormatOnly: Bool, progress: @escaping (Double) -> Void) -> [DupGroup] {
        let list = all.filter { $0.distance >= 100 && $0.pts >= 2 }.sorted { $0.distance < $1.distance }
        var pairs: [(Int, Int)] = []
        for i in list.indices {
            let a = list[i]
            var j = i + 1
            while j < list.count, list[j].distance <= a.distance * 1.5 + 200 {
                let b = list[j]
                j += 1
                if sameFormatOnly && ext(a) != ext(b) { continue }
                if a.hasTime && b.hasTime { if abs(a.date - b.date) > 300 { continue } }
                if !close(a.sx, a.sy, b.sx, b.sy, meters: 50) { continue }
                pairs.append((i, j - 1))
            }
        }
        var parent = Array(0..<list.count)
        func root(_ i: Int) -> Int { var x = i; while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }; return x }
        var cache: [Int: [GPXPoint]] = [:]
        func pts(_ i: Int) -> [GPXPoint] {
            if let c = cache[i] { return c }
            if cache.count > 400 { cache.removeAll() }
            let p = firstPoints(list[i]); cache[i] = p; return p
        }
        for (n, pr) in pairs.enumerated() {
            if n % 20 == 0 { progress(Double(n) / Double(max(pairs.count, 1))) }
            if root(pr.0) == root(pr.1) { continue }
            let p = pts(pr.0), q = pts(pr.1)
            let k = min(p.count, q.count)
            guard k >= 2 else { continue }
            var same = true
            for m in 0..<k where haversineMeters(p[m], q[m]) > 3 { same = false; break }
            if same { parent[root(pr.0)] = root(pr.1) }
        }
        progress(1)
        var groups: [Int: [TrackRecord]] = [:]
        for i in list.indices { groups[root(i), default: []].append(list[i]) }
        var out: [DupGroup] = []
        for (_, m) in groups where m.count >= 2 {
            // keep the one with the most points (then the biggest file)
            let sorted = m.sorted { ($0.pts, $0.size) > ($1.pts, $1.size) }
            let identical = Set(m.map { $0.size }).count == 1 && Set(m.map { Int($0.distance) }).count == 1
            out.append(DupGroup(id: out.count, members: sorted, identical: identical))
        }
        return out.sorted { $0.members[0].date > $1.members[0].date }.enumerated().map { DupGroup(id: $0.offset, members: $0.element.members, identical: $0.element.identical) }
    }
}

struct DuplicatesView: View {
    @ObservedObject var store: StatsStore
    @StateObject private var holder = Holder()
    final class Holder: ObservableObject { @Published var groups: [DupGroup] = []; @Published var busy = false; @Published var progress = 0.0; var generation = 0; var expected = -1 }
    @AppStorage("dupSameFormatOnly") private var sameFormatOnly = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tracks whose first 100 points are the same (and that start at the same time, if they have time stamps). The suggested one to keep (★) has the most points. Click a track name to show it in the main window. Nothing is changed unless you move files to the Trash.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Tracks in different file formats (GPX, FIT) are not duplicates", isOn: $sameFormatOnly)
                .onChange(of: sameFormatOnly) { _ in compute() }
            if store.records.isEmpty || holder.busy || !store.status.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    if holder.busy {
                        Text("Comparing tracks …").font(.headline)
                        ProgressView(value: holder.progress).frame(width: 320)
                        Text(L("%@ %%", "\(Int(holder.progress * 100))")).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Reading tracks …").font(.headline)
                        ProgressView().controlSize(.large)
                        if !store.status.isEmpty { Text(store.status).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else if holder.groups.isEmpty {
                Text("No duplicate tracks found.").foregroundStyle(.secondary).padding(.top, 20)
                Spacer()
            } else {
                Text(L("%@ groups, %@ possible duplicates", "\(holder.groups.count)", "\(holder.groups.reduce(0) { $0 + $1.members.count - 1 })")).font(.callout)
                List {
                    ForEach(holder.groups) { g in
                        Section {
                            ForEach(Array(g.members.enumerated()), id: \.element.id) { i, r in
                                HStack(spacing: 8) {
                                    Text(i == 0 ? "★" : " ").frame(width: 14)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(r.name).lineLimit(1)
                                        Text(r.folder).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture { AppModel.lastActive?.revealFile(r.path) }      // shown in the main window; this window stays in front
                                    Spacer()
                                    Text(r.when.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                    Text(String(format: "%.1f km", r.distance / 1000)).monospacedDigit().frame(width: 70, alignment: .trailing)
                                    Text(L("%@ pts", "\(r.pts)")).font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
                                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: r.path)]) }
                                    Button("Trash …") { trash([r]) }
                                }
                            }
                        } header: {
                            HStack {
                                Text(g.identical ? L("Identical copies") : L("Probably the same track")).font(.caption.bold())
                                Spacer()
                                Button("Trash All Except ★ …") { trash(Array(g.members.dropFirst())) }
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .onAppear(perform: compute)
        .onChange(of: store.records.count) { n in if n != holder.expected { compute() } }
        .onChange(of: store.status.isEmpty) { _ in compute() }
    }

    private func compute() {
        let recs = store.records
        guard !recs.isEmpty, store.status.isEmpty else { return }
        holder.generation += 1; holder.expected = -1
        let gen = holder.generation, h = holder, only = sameFormatOnly
        h.busy = true; h.progress = 0
        DispatchQueue.global(qos: .userInitiated).async {
            var last = 0.0
            let g = DuplicateFinder.find(recs, sameFormatOnly: only) { v in
                if v - last >= 0.01 || v >= 1 { last = v; DispatchQueue.main.async { if h.generation == gen { h.progress = v } } }
            }
            DispatchQueue.main.async { if h.generation == gen { h.groups = g; h.busy = false } }
        }
    }

    private func trash(_ list: [TrackRecord]) {
        guard !list.isEmpty else { return }
        let a = NSAlert()
        a.messageText = list.count == 1 ? L("Move “%@” to the Trash?", "\(list[0].name)") : L("Move %@ files to the Trash?", "\(list.count)")
        a.informativeText = L("The files go to the Trash and can be put back from there.\n\n") + list.prefix(6).map { "• " + ($0.path as NSString).lastPathComponent }.joined(separator: "\n")
            + (list.count > 6 ? L("\n… and %@ more", "\(list.count - 6)") : "")
        a.addButton(withTitle: L("Move to Trash")); a.addButton(withTitle: L("Cancel"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        var done = Set<String>()
        for r in list { if (try? FileManager.default.trashItem(at: URL(fileURLWithPath: r.path), resultingItemURL: nil)) != nil { done.insert(r.path) } }
        // update the list in place; the comparison is not started again
        holder.generation += 1
        holder.expected = store.records.count - store.records.filter { done.contains($0.path) }.count
        holder.groups = holder.groups.compactMap { g in
            let m = g.members.filter { !done.contains($0.path) }
            return m.count >= 2 ? DupGroup(id: g.id, members: m, identical: g.identical) : nil
        }
        store.remove(paths: done)
        AppModel.all.allObjects.forEach { $0.reloadTree() }
    }
}


extension AppModel {
    /// Opens the folder of the file in the left column and shows the file selected on the map (the window is not brought to the front).
    func revealFile(_ path: String) {
        if tree?.find(path) != nil {
            select(path)
        } else {
            pendingSelect = path       // the folder tree is read again, then the file is selected
            reloadTree()
        }
        for delay in [0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.foregroundPath == path else { return }
                scrollFileListToTop(path, rows: self.fileRows, offsetFraction: 0.3, window: self.window)
            }
        }
    }
}
