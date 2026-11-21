import Foundation
import BCCore
import ImageIO
import UniformTypeIdentifiers

// usage: bcprobe list | bcprobe render <gmap name> <lat> <lon> <worldSize> <out.png> [w h]
let root = URL(fileURLWithPath: "/Library/Application Support/Garmin/Maps")
let args = CommandLine.arguments
if args.count < 2 { print("usage"); exit(1) }
if args[1] == "list" {
    for m in GarminMap.discover(in: root) {
        print(m.name, m.isSupported ? "tiles=\(m.tiles.count)" : "UNSUPPORTED: \(m.unsupportedReason ?? "")")
    }
} else if args[1] == "render" {
    let m = GarminMap(url: root.appendingPathComponent(args[2] + ".gmap"))
    let lat = Double(args[3])!, lon = Double(args[4])!, ws = Double(args[5])!
    let w = args.count > 7 ? Int(args[7])! : 1000, h = args.count > 8 ? Int(args[8])! : 700
    let v = ViewState(mx: Merc.x(lon: lon), my: Merc.y(lat: lat), worldSize: ws, width: w, height: h)
    let t0 = Date()
    let img = MapRenderer.render(map: m, view: v)!
    print("render \(Date().timeIntervalSince(t0))s tiles=\(m.tiles.count)")
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[6]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, img, nil); CGImageDestinationFinalize(dst)
} else if args[1] == "tile" {
    let m = GarminMap(url: root.appendingPathComponent(args[2] + ".gmap"))
    let t = m.tiles[Int(args[3])!]
    t.ensureLoaded()
    print("tile", t.number, t.bounds, "levels:", t.levels.map { "\($0.index):\($0.bits)b×\($0.count)" })
    print("subs", t.subs.count)
}
if args[1] == "hist" {
    let m = GarminMap(url: root.appendingPathComponent(args[2] + ".gmap"))
    let lat = Double(args[3])!, lon = Double(args[4])!, ws = Double(args[5])!
    let v = ViewState(mx: Merc.x(lon: lon), my: Merc.y(lat: lat), worldSize: ws, width: 1000, height: 700)
    var h: [String: Int] = [:]
    for t in m.tiles where t.bounds.intersects(v.mapBounds) {
        guard let li = t.levelIndex(unitsPerPixel: unitsPerCircle / ws) else { continue }
        for si in t.subdivisions(level: li, in: v.mapBounds) {
            for f in t.features(sub: si) { h["\(f.kind) 0x" + String(f.type, radix: 16), default: 0] += 1 }
        }
    }
    for (k, c) in h.sorted(by: { $0.key < $1.key }) { print(k, c) }
}
if args[1] == "gpx" {
    let url = URL(fileURLWithPath: args[2])
    guard var doc = GPXDocument.parse(url) else { print("parse failed"); exit(1) }
    let p = doc.profile()
    print("tracks", doc.tracks.count, "points", doc.pointCount, "wpts", doc.waypoints.count,
          String(format: "dist %.1f km up %.0f down %.0f ele %.0f..%.0f profilePts %d", p.totalDistance / 1000, p.ascent, p.descent, p.minEle, p.maxEle, p.dist.count))
    // edit simulation: move, insert, delete, then write + re-read
    doc.tracks[0].segments[0][1].lat += 0.0001
    doc.tracks[0].segments[0].insert(GPXPoint(lat: doc.tracks[0].segments[0][0].lat, lon: doc.tracks[0].segments[0][0].lon, ele: 100), at: 1)
    doc.tracks[0].segments[0].remove(at: 2)
    let out = URL(fileURLWithPath: args[3])
    try! doc.xml().write(to: out, atomically: true, encoding: .utf8)
    let d2 = GPXDocument.parse(out)!
    print("roundtrip points", d2.pointCount, "same count:", d2.pointCount == doc.pointCount, "ele kept:", d2.tracks[0].segments[0][1].ele as Any)
}

if args[1] == "img" {
    let m = GarminMap(imgURL: URL(fileURLWithPath: args[2]))
    print(m.name, m.isSupported ? "tiles=\(m.tiles.count) typ=\(m.typ != nil)" : "UNSUPPORTED: \(m.unsupportedReason ?? "")")
    if args.count > 7 {
        let lat = Double(args[3])!, lon = Double(args[4])!, ws = Double(args[5])!
        let v = ViewState(mx: Merc.x(lon: lon), my: Merc.y(lat: lat), worldSize: ws, width: 1000, height: 700)
        let img = MapRenderer.render(map: m, view: v)!
        let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[6]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dst, img, nil); CGImageDestinationFinalize(dst)
        print("rendered")
    }
}
if args[1] == "bench" {
    let m = GarminMap(url: root.appendingPathComponent(args[2] + ".gmap"))
    let lat = Double(args[3])!, lon = Double(args[4])!
    for ws in [262144.0, 1048576, 2097152, 4194304, 8388608, 16777216] {
        let v = ViewState(mx: Merc.x(lon: lon), my: Merc.y(lat: lat), worldSize: ws, width: 1600, height: 1000)
        let t0 = Date()
        _ = MapRenderer.render(map: m, view: v, scale: 2)
        let t1 = Date().timeIntervalSince(t0)
        let t2 = Date()
        _ = MapRenderer.render(map: m, view: v, scale: 2)
        print(String(format: "ws=%9.0f cold %.2fs warm %.2fs", ws, t1, Date().timeIntervalSince(t2)))
    }
}
if args[1] == "typ" {
    let m = GarminMap(url: root.appendingPathComponent(args[2] + ".gmap"))
    guard let t = m.typ else { print("no typ"); exit(0) }
    for k in 1...0x1f {
        if let l = t.lines[k] {
            let c = l.color.components ?? []
            print(String(format: "line 0x%02x w=%.0f/%.0f dashed=%d rgb=%@", k, l.width, l.borderWidth, l.dashed ? 1 : 0, c.prefix(3).map { String(format: "%.2f", $0) }.joined(separator: ",")))
        }
    }
}
if args[1] == "lines" {
    let m = GarminMap(url: root.appendingPathComponent(args[2] + ".gmap"))
    let lat = Double(args[3])!, lon = Double(args[4])!
    var h: [Int: Int] = [:]
    let area = Bounds(north: Int((lat + 0.05) / degPerUnit), east: Int((lon + 0.07) / degPerUnit), south: Int((lat - 0.05) / degPerUnit), west: Int((lon - 0.07) / degPerUnit))
    for t in m.tiles where t.bounds.intersects(area) {
        t.ensureLoaded()
        guard let li = t.levels.indices.max(by: { t.levels[$0].bits < t.levels[$1].bits }) else { continue }
        for si in t.subdivisions(level: li, in: area) { for f in t.features(sub: si) where f.kind == .line { h[f.type, default: 0] += 1 } }
    }
    print(h.sorted { $0.key < $1.key }.map { String(format: "0x%x:%d", $0.key, $0.value) }.joined(separator: " "))
}
if args[1] == "route" {
    let m = GarminMap(url: root.appendingPathComponent(args[2] + ".gmap"))
    let a = (lat: Double(args[3])!, lon: Double(args[4])!), b = (lat: Double(args[5])!, lon: Double(args[6])!)
    for p in RouteProfile.allCases {
        let t0 = Date()
        do {
            let r = try Router.plan(map: m, vias: [a, b], profile: p)
            print(String(format: "%@: %.2f km, %.0f min, %d pts, %.2fs", p.title, r.distance / 1000, r.duration / 60, r.points.count, Date().timeIntervalSince(t0)))
        } catch { print(p.title, "ERROR:", error.localizedDescription, String(format: "%.2fs", Date().timeIntervalSince(t0))) }
    }
}

if args[1] == "kinds" {
    // bcprobe kinds <folder>: kind per top-level subfolder, with average speeds
    let base = URL(fileURLWithPath: args[2])
    var perFolder: [String: [TrackKind: Int]] = [:]
    var speeds: [TrackKind: [Double]] = [:]
    let en = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)!
    for case let u as URL in en where u.pathExtension.lowercased() == "gpx" {
        guard let f = GPXFile.load(u), !f.isWaypointFile else { continue }
        let rel = u.path.replacingOccurrences(of: base.path + "/", with: "")
        let top = rel.split(separator: "/").first.map(String.init) ?? "-"
        perFolder[top, default: [:]][f.kind, default: 0] += 1
        if let v = f.movingSpeedKmh { speeds[f.kind, default: []].append(v) }
    }
    for (k, v) in perFolder.sorted(by: { $0.key < $1.key }) { print(k, v.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: " ")) }
    for (k, v) in speeds { let s = v.sorted(); print(k.rawValue, "n=\(s.count) median=\(String(format: "%.1f", s[s.count/2])) p10=\(String(format: "%.1f", s[s.count/10])) p90=\(String(format: "%.1f", s[s.count*9/10]))") }
} else if args[1] == "gpxbench" {
    let dir = URL(fileURLWithPath: args[2])
    let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
        .filter { $0.pathExtension.lowercased() == "gpx" }.sorted { $0.path < $1.path }
    let n = args.count > 3 ? min(Int(args[3])!, files.count) : files.count
    let sel = Array(files.prefix(n))
    let bytes = sel.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    var t0 = Date()
    var slow = [GPXFile?](repeating: nil, count: n)
    DispatchQueue.concurrentPerform(iterations: n) { i in let f = GPXFile.loadXML(sel[i]); slow[i] = f }
    let tSlow = Date().timeIntervalSince(t0)
    t0 = Date()
    var fast = [GPXFile?](repeating: nil, count: n)
    DispatchQueue.concurrentPerform(iterations: n) { i in let f = GPXFile.load(sel[i]); fast[i] = f }
    let tFast = Date().timeIntervalSince(t0)
    var bad = 0
    for i in 0..<n {
        guard let a = slow[i], let b = fast[i] else { if (slow[i] == nil) != (fast[i] == nil) { bad += 1; print("presence differs:", sel[i].lastPathComponent) }; continue }
        let pa = a.segments.reduce(0) { $0 + $1.count / 2 }, pb = b.segments.reduce(0) { $0 + $1.count / 2 }
        if pa != pb || abs(a.distance - b.distance) > max(5, a.distance * 0.001) || abs(a.ascent - b.ascent) > max(5, a.ascent * 0.02) || a.name != b.name
            || a.waypoints.count != b.waypoints.count {
            bad += 1
            if bad <= 5 { print("DIFF", sel[i].lastPathComponent, pa, pb, String(format: "%.1f/%.1f", a.distance, b.distance), a.name, "|", b.name, a.waypoints.count, b.waypoints.count) }
        }
    }
    print("nil results: xml", slow.filter { $0 == nil }.count, "fast", fast.filter { $0 == nil }.count, "total points xml", slow.compactMap { $0 }.reduce(0) { $0 + $1.segments.reduce(0) { $0 + $1.count / 2 } }, "fast", fast.compactMap { $0 }.reduce(0) { $0 + $1.segments.reduce(0) { $0 + $1.count / 2 } })
    print(String(format: "%d files, %.0f MB: XMLParser %.1fs, fast %.1fs (%.1fx), mismatches: %d", n, Double(bytes) / 1e6, tSlow, tFast, tSlow / max(tFast, 0.001), bad))
}
if args[1] == "overlaybench" {
    let dir = URL(fileURLWithPath: args[2])
    let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension.lowercased() == "gpx" }
    var t0 = Date()
    var tracks = [GPXFile?](repeating: nil, count: files.count)
    let lock = NSLock()
    DispatchQueue.concurrentPerform(iterations: files.count) { i in let f = GPXFile.load(files[i]); lock.lock(); tracks[i] = f; lock.unlock() }
    let all = tracks.compactMap { $0 }
    print(String(format: "loaded %d tracks in %.2fs, points: %d", all.count, Date().timeIntervalSince(t0), all.reduce(0) { $0 + $1.segments.reduce(0) { $0 + $1.count / 2 } }))
    let lat = Double(args[3])!, lon = Double(args[4])!
    for ws in [262144.0, 1048576, 4194304, 16777216] {
        let v = ViewState(mx: Merc.x(lon: lon), my: Merc.y(lat: lat), worldSize: ws, width: 1600, height: 1000)
        for round in 0..<2 {
            t0 = Date()
            let w = 2160, h = 1350
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
            ctx.scaleBy(x: 2, y: -2); ctx.translateBy(x: 0, y: -Double(h) / 2)
            let ev = ViewState(mx: v.mx, my: v.my, worldSize: ws, width: 1080, height: 675)
            let (wx0, wy0) = ev.world(.zero), (wx1, wy1) = ev.world(CGPoint(x: 1080, y: 675))
            var drawn = 0
            for f in all where f.maxX >= wx0 && f.minX <= wx1 && f.maxY >= wy0 && f.minY <= wy1 {
                let p = CGMutablePath()
                for seg in f.lodSegments(step: 0.6 / ws) {
                    var i = 0; var last = CGPoint(x: -1e9, y: -1e9); var started = false
                    while i + 1 < seg.count { let pt = ev.screen(mx: seg[i], my: seg[i + 1]); i += 2
                        if !started { p.move(to: pt); started = true; last = pt; continue }
                        if abs(pt.x - last.x) < 0.8 && abs(pt.y - last.y) < 0.8 { continue }
                        p.addLine(to: pt); last = pt }
                }
                ctx.setStrokeColor(f.color); ctx.setLineWidth(2.2); ctx.addPath(p); ctx.strokePath(); drawn += 1
            }
            print(String(format: "ws=%9.0f round %d: %d tracks drawn in %.2fs", ws, round, drawn, Date().timeIntervalSince(t0)))
        }
    }
}
if args[1] == "foreign" {
    let en = FileManager.default.enumerator(at: URL(fileURLWithPath: args[2]), includingPropertiesForKeys: nil)
    var stats: [String: (files: Int, ok: Int, pts: Int, km: Double, failed: [String])] = [:]
    var shown: [String: Int] = [:]
    while let u = en?.nextObject() as? URL {
        let e = u.pathExtension.lowercased()
        guard ["trc", "ikt", "ptm", "axe", "ovl", "trail"].contains(e) else { continue }
        var s = stats[e] ?? (0, 0, 0, 0, [])
        s.files += 1
        if let f = GPXFile.load(u) {
            s.ok += 1; s.pts += f.segments.reduce(0) { $0 + $1.count / 2 }; s.km += f.distance / 1000
            if shown[e, default: 0] < 3 && (e == "ptm" || e == "axe" || shown[e, default: 0] < 2) {
                shown[e, default: 0] += 1
                print(String(format: "  %@: %@  %.1f km, up %.0f m, %d wpts, bbox lon %.3f..%.3f", e, u.lastPathComponent, f.distance / 1000, f.ascent, f.waypoints.count,
                             Merc.lon(x: f.minX), Merc.lon(x: f.maxX)))
            }
        } else { s.failed.append(u.lastPathComponent) }
        stats[e] = s
    }
    for (e, s) in stats.sorted(by: { $0.key < $1.key }) {
        print("\(e): \(s.ok)/\(s.files) gelesen, \(s.pts) Punkte, \(String(format: "%.0f", s.km)) km gesamt", s.failed.isEmpty ? "" : "FEHLER: \(s.failed)")
    }
}
if args[1] == "trail" {
    let en = FileManager.default.enumerator(at: URL(fileURLWithPath: args[2]), includingPropertiesForKeys: nil)
    while let u = en?.nextObject() as? URL {
        guard u.pathExtension == "trail" else { continue }
        if let d = GPXDocument.parse(u) {
            let p = d.profile()
            print(String(format: "%@: %d Tracks, %d Punkte, %d Wegpunkte, %.1f km, ↑ %.0f m, Namen: %@", u.lastPathComponent, d.tracks.count, d.pointCount, d.waypoints.count,
                         p.totalDistance / 1000, p.ascent, d.tracks.map { String($0.name.prefix(34)) }.joined(separator: " | ")))
        } else { print("FEHLER", u.lastPathComponent) }
    }
}
if args[1] == "traildetail" {
    guard let d = GPXDocument.parse(URL(fileURLWithPath: args[2])) else { print("fail"); exit(1) }
    for (i, t) in d.tracks.enumerated() {
        let pts = t.segments.flatMap { $0 }
        let one = GPXDocument(name: "x")
        var dd = one; dd.tracks = [t]
        let km = dd.profile().totalDistance / 1000
        print(i, t.name.prefix(40), pts.count, String(format: "%.1f km", km),
              String(format: "(%.4f,%.4f) → (%.4f,%.4f)", pts.first!.lat, pts.first!.lon, pts.last!.lat, pts.last!.lon), pts.first?.time ?? "-")
    }
}
if args[1] == "subtree" {
    let t0 = Date()
    let n = FolderNode.build(URL(fileURLWithPath: args[2]))
    let all = n.gpxURLs(), direct = n.directGPXURLs()
    print("direkt:", direct.count, "mit Unterordnern:", all.count, String(format: "(%.2fs)", Date().timeIntervalSince(t0)))
}

// bcprobe roads [name]: line types at the finest level (sample of up to 60 tiles per map)
if args[1] == "roads" {
    let maps = GarminMap.discover(in: root).filter { args.count < 3 || $0.name == args[2] }
    for m in maps {
        guard m.isSupported else { print("== \(m.name): UNSUPPORTED \(m.unsupportedReason ?? "")"); continue }
        var h: [Int: (n: Int, one: Int, lab: Int)] = [:]
        let step = max(1, m.tiles.count / 60)
        var used = 0
        for (i, t) in m.tiles.enumerated() where i % step == 0 {
            t.ensureLoaded()
            guard let li = t.levels.indices.max(by: { t.levels[$0].bits < t.levels[$1].bits }) else { continue }
            used += 1
            for si in t.subdivisions(level: li, in: t.bounds) {
                for f in t.features(sub: si) where f.kind == .line {
                    var e = h[f.type] ?? (0, 0, 0)
                    e.n += 1; if f.oneway { e.one += 1 }; if f.label != 0 { e.lab += 1 }
                    h[f.type] = e
                }
            }
        }
        print("== \(m.name) tiles=\(m.tiles.count) sampled=\(used)")
        for (t, e) in h.sorted(by: { $0.key < $1.key }) {
            print("  0x" + String(t, radix: 16), "n=\(e.n) oneway=\(e.one) named=\(e.lab)")
        }
    }
}

if args[1] == "typ" {
    let m = GarminMap.discover(in: root).first { $0.name == args[2] }!
    guard let t = m.typ else { print("no TYP"); exit(0) }
    func hex(_ c: CGColor?) -> String { guard let c = c?.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil), let k = c.components, k.count >= 3 else { return "-" }
        return String(format: "%02x%02x%02x", Int(k[0]*255), Int(k[1]*255), Int(k[2]*255)) }
    for (k, l) in t.lines.sorted(by: { $0.key < $1.key }) where k < 0x30 {
        print("0x" + String(k, radix: 16), "w=\(l.width) bw=\(l.borderWidth) dash=\(l.dashed) col=\(hex(l.color)) border=\(hex(l.border))")
    }
}

if args[1] == "rules" {
    for m in GarminMap.discover(in: root) where args.count < 3 || m.name == args[2] {
        guard m.isSupported else { print("== \(m.name): unsupported"); continue }
        let t0 = Date()
        let r = m.analyzeRouting()
        print("== \(m.name) routable=\(r.isRoutable) hike=\(r.supports(.hiking)) road=\(r.supports(.roadBike)) mtb=\(r.supports(.mountainBike)) car=\(r.supports(.car)) (\(String(format: "%.1f", Date().timeIntervalSince(t0))) s)")
        if args.count >= 3 { print(r.summary) }
    }
}
