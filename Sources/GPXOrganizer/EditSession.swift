import Foundation
import BCCore

/// Editing state for one GPX file: vertex edits with undo/redo. The file is only touched when saving.
@MainActor
final class EditSession: ObservableObject {
    struct Vertex: Equatable, Hashable { var t: Int; var s: Int; var i: Int }
    struct Seg { var t: Int; var s: Int; var xs: [Double]; var ys: [Double] }
    struct Row: Identifiable, Hashable {
        let id: Vertex
        let n: Int
        let lat: Double, lon: Double
        let ele: Double?
        let dist: Double      // metres from start
    }

    let url: URL
    @Published private(set) var version = 0
    @Published var selection: Set<Vertex> = []
    /// Click on empty map adds a point after the selected one (or at the end).
    @Published var addMode = true
    private(set) var doc: GPXDocument { didSet { rebuild(); version += 1; rowsDirty = true } }
    private(set) var segs: [Seg] = []
    private(set) var dirty = false
    private var undoStack: [GPXDocument] = []
    private var redoStack: [GPXDocument] = []
    private var rowCache: [Row] = []
    private var rowByVertex: [Vertex: Row] = [:]
    private var rowsDirty = true

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var document: GPXDocument { doc }
    var pointCount: Int { doc.pointCount }
    var primary: Vertex? { selection.sorted { ($0.t, $0.s, $0.i) < ($1.t, $1.s, $1.i) }.last }

    init(url: URL, doc: GPXDocument) {
        self.url = url; self.doc = doc
        rebuild()
    }

    /// Flat list of all points for the side panel (cached; not rebuilt while a point is being dragged).
    var rows: [Row] {
        if rowsDirty {
            var out: [Row] = []
            var dist = 0.0
            var n = 0
            var prev: GPXPoint?
            for (ti, t) in doc.tracks.enumerated() {
                for (si, s) in t.segments.enumerated() {
                    for (pi, p) in s.enumerated() {
                        if let q = prev { dist += haversineMeters(q, p) }
                        prev = p; n += 1
                        out.append(Row(id: Vertex(t: ti, s: si, i: pi), n: n, lat: p.lat, lon: p.lon, ele: p.ele, dist: dist))
                    }
                }
            }
            rowCache = out; rowsDirty = false
            rowByVertex = Dictionary(uniqueKeysWithValues: out.map { ($0.id, $0) })
        }
        return rowCache
    }

    func row(for v: Vertex) -> Row? { _ = rows; return rowByVertex[v] }

    /// Row closest to a distance (metres from start) along the route.
    func nearestRow(distance d: Double) -> Row? {
        let r = rows
        guard !r.isEmpty else { return nil }
        var lo = 0, hi = r.count - 1
        while lo < hi { let m = (lo + hi) / 2; if r[m].dist < d { lo = m + 1 } else { hi = m } }
        if lo > 0, abs(r[lo - 1].dist - d) <= abs(r[lo].dist - d) { lo -= 1 }
        return r[lo]
    }

    func rows(inDistance a: Double, _ b: Double) -> [Row] {
        let lo = min(a, b), hi = max(a, b)
        return rows.filter { $0.dist >= lo && $0.dist <= hi }
    }

    /// Selected rows (for highlighting in the elevation profile).
    var selectedRows: [Row] {
        selection.compactMap { row(for: $0) }.sorted { $0.dist < $1.dist }
    }

    func commitMove() { rowsDirty = true; version += 1 }

    private func rebuild() {
        var out: [Seg] = []
        for (ti, t) in doc.tracks.enumerated() {
            for (si, s) in t.segments.enumerated() {
                out.append(Seg(t: ti, s: si, xs: s.map { Merc.x(lon: $0.lon) }, ys: s.map { Merc.y(lat: $0.lat) }))
            }
        }
        segs = out
    }

    /// Call once before a gesture/edit that changes the document.
    func pushUndo() {
        undoStack.append(doc); redoStack.removeAll(); dirty = true
        if undoStack.count > 200 { undoStack.removeFirst() }
    }

    func undo() {
        guard let d = undoStack.popLast() else { return }
        redoStack.append(doc); doc = d; selection = []; dirty = true
    }

    func redo() {
        guard let d = redoStack.popLast() else { return }
        undoStack.append(doc); doc = d; selection = []; dirty = true
    }

    func move(_ v: Vertex, mx: Double, my: Double) {
        guard doc.tracks.indices.contains(v.t), doc.tracks[v.t].segments.indices.contains(v.s),
              doc.tracks[v.t].segments[v.s].indices.contains(v.i) else { return }
        let was = rowsDirty
        doc.tracks[v.t].segments[v.s][v.i].lat = Merc.lat(y: my)
        doc.tracks[v.t].segments[v.s][v.i].lon = Merc.lon(x: mx)
        rowsDirty = was
    }

    /// Inserts a new point after vertex `a` at the given fraction (0…1) between `a` and its successor.
    func insert(after a: Vertex, fraction: Double, mx: Double, my: Double) -> Vertex {
        var seg = doc.tracks[a.t].segments[a.s]
        let p0 = seg[a.i], p1 = seg[a.i + 1]
        var ele: Double?
        if let e0 = p0.ele, let e1 = p1.ele { ele = e0 + (e1 - e0) * fraction } else { ele = p0.ele ?? p1.ele }
        seg.insert(GPXPoint(lat: Merc.lat(y: my), lon: Merc.lon(x: mx), ele: ele, time: nil), at: a.i + 1)
        doc.tracks[a.t].segments[a.s] = seg
        let v = Vertex(t: a.t, s: a.s, i: a.i + 1)
        selection = [v]
        return v
    }

    /// Adds a point after the primary selected point, or at the end of the last segment. Returns the new vertex.
    @discardableResult
    func addPoint(mx: Double, my: Double) -> Vertex? {
        guard !doc.tracks.isEmpty else { return nil }
        pushUndo()
        let target = primary ?? {
            let t = doc.tracks.count - 1
            let s = doc.tracks[t].segments.count - 1
            return Vertex(t: t, s: s, i: doc.tracks[t].segments[s].count - 1)
        }()
        guard doc.tracks.indices.contains(target.t), doc.tracks[target.t].segments.indices.contains(target.s) else { return nil }
        var seg = doc.tracks[target.t].segments[target.s]
        let at = min(target.i + 1, seg.count)
        let neighbour = seg[min(target.i, seg.count - 1)]
        seg.insert(GPXPoint(lat: Merc.lat(y: my), lon: Merc.lon(x: mx), ele: neighbour.ele, time: nil), at: at)
        doc.tracks[target.t].segments[target.s] = seg
        let v = Vertex(t: target.t, s: target.s, i: at)
        selection = [v]
        return v
    }

    func deleteSelected() {
        guard !selection.isEmpty else { return }
        pushUndo()
        // remove from the back of each segment so indices stay valid; keep at least two points per segment
        let groups = Dictionary(grouping: selection) { [$0.t, $0.s] }
        for (key, vs) in groups {
            let t = key[0], s = key[1]
            guard doc.tracks.indices.contains(t), doc.tracks[t].segments.indices.contains(s) else { continue }
            for v in vs.sorted(by: { $0.i > $1.i }) where doc.tracks[t].segments[s].count > 2 && doc.tracks[t].segments[s].indices.contains(v.i) {
                doc.tracks[t].segments[s].remove(at: v.i)
            }
        }
        selection = []
    }

    func reverse() {
        pushUndo()
        for ti in doc.tracks.indices {
            doc.tracks[ti].segments = doc.tracks[ti].segments.reversed().map { seg in
                seg.reversed().map { var p = $0; p.time = nil; return p }
            }
        }
        selection = []
    }
}

func haversineMeters(_ a: GPXPoint, _ b: GPXPoint) -> Double {
    let r = 6371000.0, p = Double.pi / 180
    let dLat = (b.lat - a.lat) * p, dLon = (b.lon - a.lon) * p
    let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.lat * p) * cos(b.lat * p) * sin(dLon / 2) * sin(dLon / 2)
    return 2 * r * asin(min(1, sqrt(h)))
}
