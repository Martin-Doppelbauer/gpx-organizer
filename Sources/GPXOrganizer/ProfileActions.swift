import Foundation
import BCCore

extension AppModel {
    /// Zoom the map so that all given points are visible.
    func fitPoints(_ pts: [(lat: Double, lon: Double)]) {
        guard !pts.isEmpty else { return }
        let xs = pts.map { Merc.x(lon: $0.lon) }, ys = pts.map { Merc.y(lat: $0.lat) }
        let x0 = xs.min()!, x1 = xs.max()!, y0 = ys.min()!, y1 = ys.max()!
        let w = max(x1 - x0, 2e-7), h = max(y1 - y0, 2e-7)
        let ws = min(Double(view.width) * 0.8 / w, Double(view.height) * 0.8 / h)
        view.mx = (x0 + x1) / 2; view.my = (y0 + y1) / 2
        view.worldSize = max(1024.0, min(67108864.0, ws))
        viewRevision += 1
    }

    /// Click in the elevation profile: select that point (when editing) and move the map to it.
    func profileClick(distance d: Double, extend: Bool) {
        if extend, let a = profileAnchor { profileRange(a, d); return }
        profileAnchor = d
        profileHighlight = nil
        if let e = edit, let r = e.nearestRow(distance: d) {
            e.selection = [r.id]
            center(on: r.lat, r.lon)
        } else if let p = profile, let i = nearestIndex(p, d) {
            center(on: p.lat[i], p.lon[i])
        }
    }

    /// Range in the profile (metres): selects the points (when editing), shows the range on the map and in the list.
    func profileRange(_ a: Double, _ b: Double) {
        if let e = edit {
            let rows = e.rows(inDistance: a, b)
            guard !rows.isEmpty else { return }
            e.selection = Set(rows.map { $0.id })
            fitPoints(rows.map { ($0.lat, $0.lon) })
        } else if let p = profile {
            let lo = min(a, b), hi = max(a, b)
            let pts = zip(p.lat, zip(p.lon, p.dist)).filter { $0.1.1 >= lo && $0.1.1 <= hi }.map { (lat: $0.0, lon: $0.1.0) }
            profileHighlight = (lo, hi)
            fitPoints(pts)
        }
    }

    private func nearestIndex(_ p: Profile, _ d: Double) -> Int? {
        guard !p.dist.isEmpty else { return nil }
        var best = 0, bd = Double.infinity
        for (i, v) in p.dist.enumerated() where abs(v - d) < bd { bd = abs(v - d); best = i }
        return best
    }
}
