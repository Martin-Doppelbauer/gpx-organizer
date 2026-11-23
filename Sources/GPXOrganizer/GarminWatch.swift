import SwiftUI
import AppKit
import IOKit
import IOUSBHost
import BCCore

// Reads the activity files (FIT) straight from a Garmin watch connected by USB.
// Newer Garmin watches do not show up as a drive but speak MTP ("Media Transfer Protocol"), which macOS cannot mount.
// This is a small MTP client on top of IOUSBHost. The watch is only READ: nothing on it is changed or deleted.

private func le16(_ d: Data, _ o: Int) -> Int { Int(d[d.startIndex + o]) | Int(d[d.startIndex + o + 1]) << 8 }
private func le32(_ d: Data, _ o: Int) -> Int {
    Int(d[d.startIndex + o]) | Int(d[d.startIndex + o + 1]) << 8 | Int(d[d.startIndex + o + 2]) << 16 | Int(d[d.startIndex + o + 3]) << 24
}
private func put16(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255)] }
private func put32(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255), UInt8(v >> 16 & 255), UInt8(v >> 24 & 255)] }

enum MTPError: LocalizedError {
    case noDevice
    case busy
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .noDevice: return "No Garmin device found. Connect it with a USB data cable (not a charging-only cable); on a bike computer wake the screen and choose the USB mode if it asks.\n\n" + GarminVolume.diagnostics()
        case .busy: return "Another program is using the device (for example “Android File Transfer” or Garmin Express). Quit it and try again."
        case .failed(let m): return m
        }
    }
}

struct WatchFile: Identifiable {
    let id: Int              // MTP object handle
    let name: String
    let size: Int
    let start: Date?         // from the file name (local time)
    var url: URL? = nil      // device that shows up as a drive (Edge …): the file on that drive
}

final class MTPClient {
    private var dev: IOUSBHostDevice?
    private var intf: IOUSBHostInterface?
    private var bin: IOUSBHostPipe?
    private var bout: IOUSBHostPipe?
    private var tid = 0

    /// Is a Garmin device (that is not a drive) connected?
    static func devicePresent() -> Bool {
        let m = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        m["IOPropertyMatch"] = ["idVendor": 0x091E]
        var it: io_iterator_t = 0
        IOServiceGetMatchingServices(kIOMainPortDefault, m as CFDictionary, &it)
        let svc = IOIteratorNext(it)
        IOObjectRelease(it)
        if svc != 0 { IOObjectRelease(svc) }
        return svc != 0
    }

    init() throws {
        let m = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        m["IOPropertyMatch"] = ["idVendor": 0x091E]                 // Garmin
        var it: io_iterator_t = 0
        IOServiceGetMatchingServices(kIOMainPortDefault, m as CFDictionary, &it)
        let svc = IOIteratorNext(it)
        IOObjectRelease(it)
        guard svc != 0 else { throw MTPError.noDevice }
        do {
            let d = try IOUSBHostDevice(__ioService: svc, options: [], queue: nil, interestHandler: nil)
            dev = d
            try d.__configure(withValue: 1, matchInterfaces: true)
        } catch {
            if (error as NSError).code == Int(bitPattern: UInt(kIOReturnExclusiveAccess)) || (error as NSError).code == Int(kIOReturnExclusiveAccess) { throw MTPError.busy }
            throw MTPError.failed("The watch could not be opened: \(error.localizedDescription)")
        }
        // the interface appears a moment after the configuration
        var isvc: io_service_t = 0
        for _ in 0..<20 {
            let im = IOServiceMatching("IOUSBHostInterface") as NSMutableDictionary
            im["IOPropertyMatch"] = ["idVendor": 0x091E]
            var it2: io_iterator_t = 0
            IOServiceGetMatchingServices(kIOMainPortDefault, im as CFDictionary, &it2)
            isvc = IOIteratorNext(it2)
            IOObjectRelease(it2)
            if isvc != 0 { break }
            usleep(150_000)
        }
        guard isvc != 0 else { throw MTPError.failed("The watch does not offer a file transfer interface.") }
        do {
            let i = try IOUSBHostInterface(__ioService: isvc, options: [], queue: nil, interestHandler: nil)
            intf = i
            bin = try i.copyPipe(withAddress: 0x81)
            bout = try i.copyPipe(withAddress: 0x03)
        } catch {
            if (error as NSError).code == Int(bitPattern: UInt(kIOReturnExclusiveAccess)) || (error as NSError).code == Int(kIOReturnExclusiveAccess) { throw MTPError.busy }
            throw MTPError.failed("The transfer interface of the watch could not be opened: \(error.localizedDescription)")
        }
    }

    func close() {
        _ = try? transact(0x1003, [1])           // CloseSession
        intf?.destroy(); dev?.destroy()
        intf = nil; dev = nil; bin = nil; bout = nil
    }

    private func write(_ bytes: [UInt8]) throws {
        guard let bout else { throw MTPError.failed("not connected") }
        let d = NSMutableData(bytes: bytes, length: bytes.count)
        var n = 0
        try bout.__sendIORequest(with: d, bytesTransferred: &n, completionTimeout: 15)
    }

    private func read(_ size: Int) throws -> Data {
        guard let bin else { throw MTPError.failed("not connected") }
        let d = NSMutableData(length: size)!
        var n = 0
        try bin.__sendIORequest(with: d, bytesTransferred: &n, completionTimeout: 20)
        return Data(bytes: d.bytes, count: n)
    }

    /// One MTP transaction: (response code, data payload).
    func transact(_ code: Int, _ params: [Int] = []) throws -> (code: Int, data: Data) {
        tid += 1
        var cmd = put32(12 + params.count * 4) + put16(1) + put16(code) + put32(tid)
        for p in params { cmd += put32(p) }
        try write(cmd)
        var payload = Data()
        func next() throws -> Data { var b = Data(); while b.isEmpty { b = try read(256 * 1024) }; return b }     // a zero-length packet may come first
        var buf = try next()
        while true {
            guard buf.count >= 12 else { throw MTPError.failed("Unexpected answer from the watch (\(buf.count) bytes).") }
            let len = le32(buf, 0), type = le16(buf, 4), rc = le16(buf, 6)
            if type == 2 {
                payload.append(buf.subdata(in: (buf.startIndex + 12)..<(buf.startIndex + min(buf.count, len == 0xFFFF_FFFF ? buf.count : len))))
                var total = buf.count
                while len != 0xFFFF_FFFF, total < len {
                    let more = try read(256 * 1024)
                    if more.isEmpty { continue }
                    payload.append(more.prefix(len - total))
                    total += more.count
                }
                buf = try next()
                continue
            }
            guard type == 3 else { throw MTPError.failed("Unexpected message type \(type) from the watch.") }
            return (rc, payload)
        }
    }

    func openSession() throws {
        let r = try transact(0x1002, [1])
        if r.code != 0x2001 && r.code != 0x201E { throw MTPError.failed("The watch refused the session (code \(String(r.code, radix: 16))).") }   // OK or SessionAlreadyOpen
    }

    func storageIDs() throws -> [Int] {
        let d = try transact(0x1004).data
        guard d.count >= 4 else { return [] }
        return (0..<le32(d, 0)).map { le32(d, 4 + $0 * 4) }
    }

    struct Entry { let handle: Int; let name: String; let isFolder: Bool; let size: Int }

    private func ptpString(_ d: Data, _ o: inout Int) -> String {
        guard o < d.count else { return "" }
        let n = Int(d[d.startIndex + o]); o += 1
        var u: [UInt16] = []
        for i in 0..<n where o + i * 2 + 1 < d.count { u.append(UInt16(d[d.startIndex + o + i * 2]) | UInt16(d[d.startIndex + o + i * 2 + 1]) << 8) }
        o += n * 2
        if u.last == 0 { u.removeLast() }
        return String(decoding: u, as: UTF16.self)
    }

    /// Objects directly inside a folder (parent 0xFFFFFFFF = the root of the storage).
    func children(storage: Int, parent: Int, progress: ((Int, Int) -> Void)? = nil) throws -> [Entry] {
        let kids = try transact(0x1007, [storage, 0, parent]).data
        guard kids.count >= 4 else { return [] }
        let c = le32(kids, 0)
        var out: [Entry] = []
        for i in 0..<c {
            let h = le32(kids, 4 + i * 4)
            let r = try transact(0x1008, [h])
            guard r.code == 0x2001, r.data.count > 53 else { continue }
            var off = 52
            let name = ptpString(r.data, &off)
            out.append(Entry(handle: h, name: name, isFolder: le16(r.data, 4) == 0x3001, size: le32(r.data, 8)))
            if i % 20 == 0 { progress?(i, c) }
        }
        return out
    }

    func download(_ handle: Int) throws -> Data {
        let r = try transact(0x1009, [handle])
        guard r.code == 0x2001 else { throw MTPError.failed("The watch could not deliver the file (code \(String(r.code, radix: 16))).") }
        return r.data
    }

    /// Sends a new file into a folder of the device (never replaces or deletes anything).
    func upload(name: String, data: Data, storage: Int, parent: Int) throws {
        // 1. SendObjectInfo: the description of the new object
        var info: [UInt8] = []
        info += put32(storage) + put16(0x3000) + put16(0) + put32(data.count)       // storage, format (undefined), protection, size
        info += put16(0) + put32(0) + put32(0) + put32(0)                            // thumbnail: none
        info += put32(0) + put32(0) + put32(0)                                       // image size / depth: none
        info += put32(parent) + put16(0) + put32(0) + put32(0)                       // parent, association, sequence
        let u = Array(name.utf16) + [0]
        info.append(UInt8(u.count))
        for c in u { info += put16(Int(c)) }
        info += [0, 0, 0]                                                            // capture date, modification date, keywords: empty strings
        let r = try transactSend(0x100C, [storage, parent], Data(info))
        guard r == 0x2001 else { throw MTPError.failed("The device did not accept “\(name)” (code \(String(r, radix: 16)))." ) }
        // 2. SendObject: the contents
        let r2 = try transactSend(0x100D, [], data)
        guard r2 == 0x2001 else { throw MTPError.failed("The device did not take the contents of “\(name)” (code \(String(r2, radix: 16)))." ) }
    }

    /// One MTP transaction with a data phase to the device; returns the response code.
    private func transactSend(_ code: Int, _ params: [Int], _ payload: Data) throws -> Int {
        tid += 1
        var cmd = put32(12 + params.count * 4) + put16(1) + put16(code) + put32(tid)
        for p in params { cmd += put32(p) }
        try write(cmd)
        var all = Data(put32(12 + payload.count) + put16(2) + put16(code) + put32(tid))
        all.append(payload)
        var off = 0
        while off < all.count {
            let n = min(64 * 1024, all.count - off)
            try write([UInt8](all.subdata(in: (all.startIndex + off)..<(all.startIndex + off + n))))
            off += n
        }
        if (12 + payload.count) % 512 == 0 { try write([]) }        // a transfer that ends exactly on a packet boundary needs an empty packet
        let b = try readResponse()
        return b
    }

    private func readResponse() throws -> Int {
        var buf = Data()
        while buf.isEmpty { buf = try read(64 * 1024) }
        guard buf.count >= 12 else { throw MTPError.failed("Unexpected answer from the device.") }
        // (a response to a send has no data phase)
        return le16(buf, 6)
    }

    /// Finds the folder GARMIN/Activity on one of the storages: (storage, handle of Activity).
    /// Finds GARMIN/NewFiles (where the device picks up new courses): (storage, handle).
    func findNewFilesFolder() throws -> (Int, Int)? {
        for sid in try storageIDs() {
            guard let g = try children(storage: sid, parent: 0xFFFF_FFFF).first(where: { $0.isFolder && $0.name.uppercased() == "GARMIN" }) else { continue }
            if let a = try children(storage: sid, parent: g.handle).first(where: { $0.isFolder && $0.name.lowercased() == "newfiles" }) { return (sid, a.handle) }
        }
        return nil
    }

    /// What the device shows at its top level (for the message when the expected folders are missing).
    func describeRoot() -> String {
        var out: [String] = []
        for sid in (try? storageIDs()) ?? [] {
            let top = (try? children(storage: sid, parent: 0xFFFF_FFFF)) ?? []
            out.append("Storage \(sid): " + (top.isEmpty ? "(empty)" : top.map { $0.name }.joined(separator: ", ")))
            if let g = top.first(where: { $0.isFolder && $0.name.uppercased() == "GARMIN" }) {
                out.append("GARMIN: " + ((try? children(storage: sid, parent: g.handle)) ?? []).map { $0.name }.joined(separator: ", "))
            }
        }
        return out.joined(separator: "\n")
    }

    func findActivityFolder() throws -> (Int, Int)? {
        for sid in try storageIDs() {
            guard let g = try children(storage: sid, parent: 0xFFFF_FFFF).first(where: { $0.isFolder && $0.name.uppercased() == "GARMIN" }) else { continue }
            if let a = try children(storage: sid, parent: g.handle).first(where: { $0.isFolder && ["activity", "activities"].contains($0.name.lowercased()) }) { return (sid, a.handle) }
        }
        return nil
    }
}

// MARK: Session (all USB work runs on one background queue)

@MainActor
final class WatchSession: ObservableObject {
    enum Phase: Equatable { case idle, working(String), ready, failed(String), busy }
    @Published var phase: Phase = .idle
    @Published var files: [WatchFile] = []
    @Published var volume: GarminVolume?            // device that shows up as a drive (Edge …)
    private let queue = DispatchQueue(label: "garmin.usb", qos: .userInitiated)
    private var client: MTPClient?
    private var storage = 0

    private func run<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async { do { cont.resume(returning: try work()) } catch { cont.resume(throwing: error) } }
        }
    }

    nonisolated static func startDate(_ name: String) -> Date? {
        // "2026-11-13-07-01-09.fit": local time of the watch
        let n = name.split(whereSeparator: { "-.".contains($0) }).compactMap { Int($0) }
        guard n.count >= 6 else { return nil }
        var c = DateComponents(); c.year = n[0]; c.month = n[1]; c.day = n[2]; c.hour = n[3]; c.minute = n[4]; c.second = n[5]
        return Calendar.current.date(from: c)
    }

    func connect() async {
        phase = .working("Looking for the device …")
        // a device that shows up as a drive (Edge bike computers): read the files straight from it
        if let v = GarminVolume.find().first(where: { $0.activityFolder != nil }) {
            volume = v
            files = v.activities()
            phase = .ready
            return
        }
        volume = nil
        do {
            let (list, sid): ([WatchFile], Int) = try await run { [self] in
                client?.close(); client = nil
                let c = try MTPClient()
                client = c
                try c.openSession()
                guard let (sid, act) = try c.findActivityFolder() else { throw MTPError.failed("The folder GARMIN/Activity (or Activities) was not found on the device.\n\n" + c.describeRoot()) }
                let entries = try c.children(storage: sid, parent: act)
                let files = entries.filter { !$0.isFolder && $0.name.lowercased().hasSuffix(".fit") }
                    .map { WatchFile(id: $0.handle, name: $0.name, size: $0.size, start: Self.startDate($0.name)) }
                    .sorted { $0.name > $1.name }
                return (files, sid)
            }
            storage = sid
            files = list
            phase = .ready
        } catch MTPError.busy {
            phase = .busy
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func fetch(_ f: WatchFile) async throws -> Data {
        if let u = f.url { return try Data(contentsOf: u) }
        return try await run { [self] in
            guard let c = client else { throw MTPError.failed("The watch is not connected.") }
            return try c.download(f.id)
        }
    }

    func close() {
        let c = client
        client = nil
        queue.async { c?.close() }
    }
}

// MARK: Sheet

struct GarminImportSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = WatchSession()
    @StateObject private var state = ImportState()

    final class ImportState: ObservableObject {
        @Published var onDisk: Set<String> = []
        @Published var chosen: Set<Int> = []
        @Published var year = 0
        @Published var onlyMissing = false
        @Published var status = ""
        @Published var busy = false
    }

    private var target: URL { model.rootURL.appendingPathComponent("Garmin", isDirectory: true) }
    private func yearOf(_ f: WatchFile) -> Int? { f.start.map { Calendar.current.component(.year, from: $0) } }
    private var years: [Int] { Array(Set(session.files.compactMap(yearOf))).sorted(by: >) }
    private var inYear: [WatchFile] { state.year == 0 ? session.files : session.files.filter { yearOf($0) == state.year } }
    private var chosenShown: [WatchFile] { shown.filter { state.chosen.contains($0.id) } }
    private var shown: [WatchFile] { state.onlyMissing ? inYear.filter { !state.onDisk.contains($0.name.lowercased()) } : inYear }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.volume.map { "Import from \($0.title)" } ?? "Import from Garmin Device").font(.title3.bold())
            switch session.phase {
            case .idle, .working:
                HStack { ProgressView().controlSize(.small); Text(workingText) }
                Text("The device is only read; nothing on it is changed or deleted.").font(.caption).foregroundStyle(.secondary)
            case .busy:
                Text("Another program is using the watch.").font(.headline)
                Text("Programs such as “Android File Transfer” or Garmin Express keep the watch for themselves. Quit them and try again.").foregroundStyle(.secondary)
                if let app = otherApp { Button("Quit “\(app.localizedName ?? "that program")” and Try Again") { app.terminate(); retry(after: 1.5) } }
                Button("Try Again") { retry(after: 0) }
            case .failed(let msg):
                Text(msg).foregroundStyle(.red)
                Button("Try Again") { retry(after: 0) }
            case .ready:
                list
            }
            if session.phase != .ready { HStack { Spacer(); Button("Close") { close() }.keyboardShortcut(.cancelAction) } }
        }
        .padding(18)
        .frame(width: 640, height: session.phase == .ready ? 560 : 240)
        .task { await start() }
    }

    private var workingText: String { if case .working(let t) = session.phase { return t }; return "Looking for the device …" }

    private var otherApp: NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { ($0.localizedName ?? "").localizedCaseInsensitiveContains("Android File Transfer") }
    }

    private func close() { session.close(); dismiss() }

    private func retry(after: Double) {
        Task { try? await Task.sleep(nanoseconds: UInt64(after * 1e9)); await start() }
    }

    @ViewBuilder private var list: some View {
        HStack {
            Picker("Year", selection: $state.year) {
                Text("All years").tag(0)
                ForEach(years, id: \.self) { Text(String($0)).tag($0) }
            }.pickerStyle(.menu).fixedSize()
            Spacer()
            Toggle("Only missing", isOn: $state.onlyMissing).toggleStyle(.checkbox)
        }
        Text("\(inYear.count) activities on the device, \(inYear.filter { !state.onDisk.contains($0.name.lowercased()) }.count) not yet in your folders")
            .font(.callout).foregroundStyle(.secondary)
        List {
            ForEach(shown) { f in
                let here = state.onDisk.contains(f.name.lowercased())
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(get: { state.chosen.contains(f.id) }, set: { if $0 { state.chosen.insert(f.id) } else { state.chosen.remove(f.id) } }))
                        .labelsHidden().toggleStyle(.checkbox)
                    Text(f.start.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? f.name)
                    Text(f.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(f.size), countStyle: .file)).font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
                    Text(here ? "on disk" : "missing").font(.caption.bold()).foregroundStyle(here ? Color.secondary : Color.orange).frame(width: 52, alignment: .trailing)
                }
                .listRowBackground(here ? nil : Color.orange.opacity(0.12))
            }
        }
        .border(Color.secondary.opacity(0.3))
        HStack {
            Button(state.year == 0 ? "Select Missing" : "Select Missing from " + String(state.year)) { state.chosen = Set(inYear.filter { !state.onDisk.contains($0.name.lowercased()) }.map(\.id)) }
            Button("Select None") { state.chosen = [] }
            Spacer()
            Text("Into: \(model.rootURL.lastPathComponent)/Garmin").font(.caption).foregroundStyle(.secondary)
        }
        if !state.status.isEmpty { Text(state.status).font(.caption).foregroundStyle(.secondary) }
        HStack {
            Spacer()
            Button("Close") { close() }.keyboardShortcut(.cancelAction)
            Button("Download \(chosenShown.count) Activit\(chosenShown.count == 1 ? "y" : "ies")") { Task { await download() } }
                .keyboardShortcut(.defaultAction).disabled(chosenShown.isEmpty || state.busy)
        }
    }

    private func start() async {
        let root = model.rootURL
        async let names = Task.detached(priority: .userInitiated) { Self.localFITNames(root) }.value
        await session.connect()
        state.onDisk = await names
        state.chosen = Set(session.files.filter { !state.onDisk.contains($0.name.lowercased()) }.map(\.id))
    }

    /// File names of all FIT files below the root folder (lower case).
    private static func localFITNames(_ root: URL) -> Set<String> {
        var out = Set<String>()
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return out }
        for case let u as URL in en where u.pathExtension.lowercased() == "fit" { out.insert(u.lastPathComponent.lowercased()) }
        return out
    }

    private func download() async {
        state.busy = true
        defer { state.busy = false }
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let todo = chosenShown            // only what the list shows right now (year and filter)
        var done = 0, failed = 0
        for f in todo {
            state.status = "Downloading \(done + failed + 1) of \(todo.count): \(f.name)"
            do {
                let data = try await session.fetch(f)
                var url = target.appendingPathComponent(f.name)
                var n = 2
                while FileManager.default.fileExists(atPath: url.path) { url = target.appendingPathComponent((f.name as NSString).deletingPathExtension + " \(n).fit"); n += 1 }
                try data.write(to: url, options: .atomic)
                if let d = f.start { try? FileManager.default.setAttributes([.modificationDate: d, .creationDate: d], ofItemAtPath: url.path) }
                state.onDisk.insert(f.name.lowercased()); state.chosen.remove(f.id)
                done += 1
            } catch { failed += 1; if failed >= 3 && done == 0 { break } }
        }
        state.status = "\(done) downloaded into “\(target.lastPathComponent)”" + (failed > 0 ? ", \(failed) failed." : ".")
        model.reloadTree()
    }
}

/// Sheet and menu notification for the Garmin watch import.
struct GarminHook: ViewModifier {
    @EnvironmentObject var model: AppModel
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $model.showGarminImport) { GarminDialog().environmentObject(model) }
            .onReceive(model.menuEvents(.garminImport)) { _ in model.garminSendMode = false; model.showGarminImport = true }
            .onReceive(model.menuEvents(.garminSend)) { _ in model.sendToGarmin() }
    }
}

extension Notification.Name { static let garminImport = Notification.Name("garminImport") }
