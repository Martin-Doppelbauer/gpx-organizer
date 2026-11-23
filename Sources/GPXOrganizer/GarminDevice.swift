import SwiftUI
import AppKit
import BCCore

// Garmin devices that show up as a drive (Edge bike computers and many older devices): activities are read from the
// folder Garmin/Activities, new courses are copied to Garmin/NewFiles (the device takes them over when it is unplugged).
// Devices that speak MTP (newer watches) are handled in GarminWatch.swift.

struct GarminVolume: Identifiable, Hashable {
    let url: URL                 // the drive, e.g. /Volumes/GARMIN
    let model: String            // from GarminDevice.xml
    var id: String { url.path }
    var title: String { model.isEmpty ? url.lastPathComponent : "\(model) (\(url.lastPathComponent))" }

    private var garmin: URL? { child(url, "Garmin") }

    private func child(_ dir: URL, _ name: String) -> URL? {
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return items.first { $0.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    /// Folder with the recorded activities (FIT), if the device has one.
    var activityFolder: URL? {
        guard let g = garmin else { return nil }
        return child(g, "Activities") ?? child(g, "Activity")
    }

    /// Where new courses go: the NewFiles folder (created when missing), as announced in GarminDevice.xml for GPX otherwise.
    var newFilesFolder: URL? {
        guard let g = garmin else { return nil }
        if let n = child(g, "NewFiles") { return n }
        if let p = xmlPath(forExtension: "gpx"), let d = child(g, (p as NSString).lastPathComponent) { return d }
        let n = g.appendingPathComponent("NewFiles", isDirectory: true)
        return (try? FileManager.default.createDirectory(at: n, withIntermediateDirectories: true)) != nil ? n : nil
    }

    /// Folder for files of the given extension that the device declares as writable in GarminDevice.xml.
    private func xmlPath(forExtension ext: String) -> String? {
        guard let g = garmin, let doc = try? XMLDocument(contentsOf: g.appendingPathComponent("GarminDevice.xml"), options: []) else { return nil }
        for t in (try? doc.nodes(forXPath: "//*[local-name()='DataType']")) ?? [] {
            func v(_ n: String) -> String { ((try? t.nodes(forXPath: ".//*[local-name()='\(n)']"))?.first?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            if v("FileExtension").lowercased() == ext, v("TransferDirection").lowercased().contains("input") || v("TransferDirection").isEmpty, !v("Path").isEmpty { return v("Path") }
        }
        return nil
    }

    static func model(of url: URL) -> String {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        guard let g = items.first(where: { $0.lastPathComponent.caseInsensitiveCompare("Garmin") == .orderedSame }),
              let doc = try? XMLDocument(contentsOf: g.appendingPathComponent("GarminDevice.xml"), options: []),
              let d = (try? doc.nodes(forXPath: "//*[local-name()='Model']/*[local-name()='Description']"))?.first?.stringValue else { return "" }
        return d.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// All drives that look like a Garmin device.
    static func find() -> [GarminVolume] {
        let fm = FileManager.default
        let vols = (try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        var out: [GarminVolume] = []
        for v in vols {
            let items = (try? fm.contentsOfDirectory(at: v, includingPropertiesForKeys: nil)) ?? []
            guard let g = items.first(where: { $0.lastPathComponent.caseInsensitiveCompare("Garmin") == .orderedSame }) else { continue }
            let inside = ((try? fm.contentsOfDirectory(at: g, includingPropertiesForKeys: nil)) ?? []).map { $0.lastPathComponent.lowercased() }
            guard inside.contains("garmindevice.xml") || inside.contains("activities") || inside.contains("activity") || inside.contains("newfiles") else { continue }
            out.append(GarminVolume(url: v, model: model(of: v)))
        }
        return out
    }

    /// FIT files in the activity folder.
    func activities() -> [WatchFile] {
        guard let a = activityFolder else { return [] }
        let items = (try? FileManager.default.contentsOfDirectory(at: a, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        var out: [WatchFile] = []
        for (i, u) in items.enumerated() where u.pathExtension.lowercased() == "fit" {
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            out.append(WatchFile(id: i + 1, name: u.lastPathComponent, size: v?.fileSize ?? 0, start: WatchSession.startDate(u.lastPathComponent) ?? v?.contentModificationDate, url: u))
        }
        return out.sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }
    }

    /// What the Mac sees: for the message when no device is found.
    static func diagnostics() -> String {
        let vols = ((try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? []).filter { !$0.hasPrefix(".") }
        return "Drives the Mac shows: " + (vols.isEmpty ? "none" : vols.joined(separator: ", ")) + " – none of them has a Garmin folder.\nUSB: no Garmin device (vendor 091E) reported by macOS."
    }

    func eject() { try? NSWorkspace.shared.unmountAndEjectDevice(at: url) }
}

// MARK: Send to the device

@MainActor
final class SendJob: ObservableObject {
    enum Target: Equatable { case none, drive(String), mtp }
    @Published var volumes: [GarminVolume] = []
    @Published var volumeID: String?
    @Published var mtpPresent = false
    @Published var status = ""
    @Published var busy = false
    @Published var finished = false
    @Published var failed = false
    @Published var asRoute = false
    @Published var eject = true
    private let queue = DispatchQueue(label: "garmin.send", qos: .userInitiated)

    var volume: GarminVolume? { volumes.first { $0.id == volumeID } }
    var hasTarget: Bool { volume != nil || mtpPresent }

    func look() {
        volumes = GarminVolume.find()
        if volumeID == nil || volume == nil { volumeID = volumes.first?.id }
        mtpPresent = volumes.isEmpty && MTPClient.devicePresent()
    }

    /// Name used on the device: the file name without folders, letters / digits / space - _ only.
    static func deviceName(_ id: String, ext: String) -> String {
        let base = URL(fileURLWithPath: id).deletingPathExtension().lastPathComponent
        let ok = base.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || " -_().".unicodeScalars.contains($0) ? Character($0) : "_" }
        return String(ok) + "." + ext
    }

    /// GPX text of a file (any supported format).
    static func gpx(of id: String, asRoute: Bool) -> String? {
        let url = URL(fileURLWithPath: id)
        guard let doc = (url.pathExtension.lowercased() == "gpx" ? GPXDocument.parse(url) : ForeignTracks.parse(url)), !doc.tracks.isEmpty else { return nil }
        var d = doc
        if d.name.isEmpty { d.name = url.deletingPathExtension().lastPathComponent }
        d.tracks = d.tracks.enumerated().map { i, t in
            var t = t
            if t.name.isEmpty || doc.tracks.count == 1 { t.name = url.deletingPathExtension().lastPathComponent + (doc.tracks.count > 1 ? " \(i + 1)" : "") }
            return t
        }
        return asRoute ? d.gpxAsRoute() : d.gpxAsTrack()
    }

    func send(_ ids: [String]) {
        guard !busy else { return }
        busy = true; finished = false; failed = false
        status = "Preparing …"
        let route = asRoute
        var files: [(String, Data)] = []
        var skipped: [String] = []
        for id in ids {
            if let t = Self.gpx(of: id, asRoute: route), let d = t.data(using: .utf8) { files.append((Self.deviceName(id, ext: "gpx"), d)) }
            else { skipped.append(URL(fileURLWithPath: id).lastPathComponent) }
        }
        guard !files.isEmpty else { busy = false; failed = true; status = "None of the files contains a track or route."; return }
        if let v = volume {
            guard let dir = v.newFilesFolder else { busy = false; failed = true; status = "The folder Garmin/NewFiles could not be found or created on the device."; return }
            var done = 0
            for (name, data) in files {
                status = "Copying \(done + 1) of \(files.count): \(name)"
                do {
                    try data.write(to: dir.appendingPathComponent(name), options: .atomic); done += 1
                    try? FileManager.default.removeItem(at: dir.appendingPathComponent("._" + name))        // macOS leaves such a helper file on FAT drives; the device does not need it
                }
                catch { busy = false; failed = true; status = "“\(name)” could not be written: \(error.localizedDescription)"; return }
            }
            var msg = "\(done) file\(done == 1 ? "" : "s") copied to \(v.url.lastPathComponent)/Garmin/\(dir.lastPathComponent)."
            if !skipped.isEmpty { msg += " Skipped (no track): \(skipped.joined(separator: ", "))." }
            if eject { v.eject(); msg += " The device was ejected: unplug it now; it takes over the new courses when it starts." }
            else { msg += " Eject the device before unplugging it; it takes over the new courses then." }
            status = msg; busy = false; finished = true
            return
        }
        // MTP device
        let total = files.count, skippedList = skipped
        queue.async { [weak self] in
            var result = ""
            var bad = false
            do {
                let c = try MTPClient()
                defer { c.close() }
                try c.openSession()
                guard let (sid, folder) = try c.findNewFilesFolder() else { throw MTPError.failed("The folder GARMIN/NewFiles was not found on the device.") }
                for (i, f) in files.enumerated() {
                    DispatchQueue.main.async { self?.status = "Sending \(i + 1) of \(total): \(f.0)" }
                    try c.upload(name: f.0, data: f.1, storage: sid, parent: folder)
                }
                result = "\(total) file\(total == 1 ? "" : "s") sent to GARMIN/NewFiles."
                if !skippedList.isEmpty { result += " Skipped (no track): \(skippedList.joined(separator: ", "))." }
                result += " Disconnect the device; it takes over the new courses then."
            } catch MTPError.busy {
                bad = true; result = "Another program is using the device (for example “Android File Transfer” or Garmin Express). Quit it and try again."
            } catch { bad = true; result = error.localizedDescription }
            DispatchQueue.main.async { self?.status = result; self?.busy = false; self?.failed = bad; self?.finished = !bad }
        }
    }
}

struct GarminSendSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var job = SendJob()
    let ids: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send to Garmin Device").font(.title3.bold())
            Group {
                if job.volumes.count > 1 {
                    Picker("Device", selection: Binding(get: { job.volumeID ?? "" }, set: { job.volumeID = $0 })) {
                        ForEach(job.volumes) { Text($0.title).tag($0.id) }
                    }
                } else if let v = job.volume {
                    Label(v.title, systemImage: "externaldrive.connected.to.line.below").font(.headline)
                } else if job.mtpPresent {
                    Label("Garmin device (USB, MTP)", systemImage: "applewatch").font(.headline)
                } else {
                    Text("No Garmin device found.").font(.headline).foregroundStyle(.orange)
                    Text("Connect the device with a USB data cable. Bike computers (Edge) appear as a drive named GARMIN; on the device itself choose “Mass Storage” / “Garmin” mode if it asks. Programs such as Garmin Express may keep the device for themselves.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Look Again") { job.look() }
                }
            }
            if job.hasTarget {
                Text(ids.isEmpty ? "Nothing selected: close this dialog, select one or more tracks in the file list and open it again." : "\(ids.count) file\(ids.count == 1 ? "" : "s") to send")
                    .font(.callout).foregroundStyle(ids.isEmpty ? Color.orange : Color.secondary)
                List(ids, id: \.self) { id in
                    Text(URL(fileURLWithPath: id).lastPathComponent).lineLimit(1)
                }
                .frame(height: 120).border(Color.secondary.opacity(0.3))
                Picker("Send as", selection: $job.asRoute) {
                    Text("Track – the device shows it as a course to follow").tag(false)
                    Text("Route – for navigation with the device's own turn instructions").tag(true)
                }
                .pickerStyle(.radioGroup)
                if job.volume != nil { Toggle("Eject the device afterwards", isOn: $job.eject).toggleStyle(.checkbox) }
                Text("The files are converted to GPX and copied to the folder Garmin/NewFiles of the device. Nothing on the device is changed or deleted; your files stay as they are.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !job.status.isEmpty {
                HStack(alignment: .top) {
                    if job.busy { ProgressView().controlSize(.small) }
                    Text(job.status).font(.callout).foregroundStyle(job.failed ? Color.red : (job.finished ? Color.green : Color.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(job.finished ? "Done" : "Close") { dismiss() }.keyboardShortcut(.cancelAction)
                if job.hasTarget && !job.finished {
                    Button("Send") { job.send(ids) }.keyboardShortcut(.defaultAction).disabled(job.busy || ids.isEmpty)
                }
            }
        }
        .padding(18)
        .frame(width: 520, height: 470)
        .onAppear { job.look() }
    }
}

extension AppModel {
    /// Files for "Send to Garmin Device": the marked files, otherwise the track shown.
    func defaultSendIDs() -> [String] {
        (multiSelected.count > 1 ? Array(multiSelected) : foregroundPath.map { [$0] } ?? []).sorted()
    }

    /// Opens the Garmin dialog on "Send" (with the given files, otherwise the marked ones).
    func sendToGarmin(_ ids: [String]? = nil) {
        garminSendIDs = (ids ?? defaultSendIDs()).sorted()
        garminSendMode = true
        showGarminImport = true
    }
}

/// One dialog for Garmin devices: Import / Send are switched inside it.
struct GarminDialog: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: Binding(get: { model.garminSendMode }, set: { on in
                if on { model.garminSendIDs = model.defaultSendIDs() }
                model.garminSendMode = on
            })) { Text("Import from Device").tag(false); Text("Send to Device").tag(true) }
                .pickerStyle(.segmented).labelsHidden().frame(width: 320).padding(.top, 14)
            if model.garminSendMode { GarminSendSheet(ids: model.garminSendIDs) } else { GarminImportSheet() }
        }
    }
}

extension Notification.Name { static let garminSend = Notification.Name("garminSend") }
