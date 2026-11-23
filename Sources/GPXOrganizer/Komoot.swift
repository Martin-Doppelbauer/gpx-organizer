import SwiftUI
import Security
import BCCore

// Komoot has no public API for private users. This uses the same undocumented v006/v007 interface that other
// community tools use; it may stop working at any time. Only reads (login, tour list, GPX download) and the
// upload of new tours are used: nothing that already exists on Komoot is ever changed or deleted.

// MARK: Keychain (e-mail and password are stored nowhere else)

enum KomootKeychain {
    private static let service = "GPX Organizer – Komoot"

    static func load() -> (email: String, password: String)? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecReturnAttributes as String: true, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? [String: Any],
              let acc = d[kSecAttrAccount as String] as? String, let data = d[kSecValueData as String] as? Data,
              let pw = String(data: data, encoding: .utf8) else { return nil }
        return (acc, pw)
    }

    static func save(email: String, password: String) {
        delete()
        var item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: email, kSecValueData as String: Data(password.utf8)]
        // No trusted-application list: a rebuilt or updated app can read its own entry without asking for the keychain again
        var access: SecAccess?
        if SecAccessCreate(service as CFString, nil, &access) == errSecSuccess, let access { item[kSecAttrAccess as String] = access }
        SecItemAdd(item as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}

// MARK: Client

struct KomootTour: Identifiable {
    let id: String
    let name: String
    let type: String          // tour_planned / tour_recorded
    let sport: String
    let date: Date?
    let distance: Double      // metres
    let status: String
    var planned: Bool { type == "tour_planned" }
}

enum KomootError: LocalizedError {
    case login, http(Int), format
    var errorDescription: String? {
        switch self {
        case .login: return "Sign-in failed. Check e-mail address and password."
        case .http(let c): return "Komoot answered with error \(c). The unofficial interface may have changed."
        case .format: return "Unexpected answer from Komoot."
        }
    }
}

final class KomootClient {
    private var userID = ""
    private var token = ""
    private let base = "https://api.komoot.de"

    private func basic(_ u: String, _ p: String) -> String { "Basic " + Data("\(u):\(p)".utf8).base64EncodedString() }

    private func request(_ url: URL, method: String = "GET", body: Data? = nil, auth: String) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 60)
        r.httpMethod = method; r.httpBody = body
        r.setValue(auth, forHTTPHeaderField: "Authorization")
        r.setValue("GPXOrganizer", forHTTPHeaderField: "User-Agent")
        return r
    }

    private func fetch(_ r: URLRequest) async throws -> (Data, Int) {
        let (d, resp) = try await URLSession.shared.data(for: r)
        return (d, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    func login(email: String, password: String) async throws {
        let enc = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? email
        guard let url = URL(string: "\(base)/v006/account/email/\(enc)/") else { throw KomootError.format }
        let (d, code) = try await fetch(request(url, auth: basic(email, password)))
        if code == 401 || code == 403 { throw KomootError.login }
        guard code == 200 else { throw KomootError.http(code) }
        guard let j = try JSONSerialization.jsonObject(with: d) as? [String: Any],
              let u = j["username"] as? String, let t = j["password"] as? String else { throw KomootError.format }
        userID = u; token = t
    }

    func tours() async throws -> [KomootTour] {
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        var all: [KomootTour] = []
        var page = 0
        while true {
            guard let url = URL(string: "\(base)/v007/users/\(userID)/tours/?page=\(page)&limit=50") else { throw KomootError.format }
            let (d, code) = try await fetch(request(url, auth: basic(userID, token)))
            guard code == 200 else { throw KomootError.http(code) }
            guard let j = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw KomootError.format }
            let items = ((j["_embedded"] as? [String: Any])?["tours"] as? [[String: Any]]) ?? []
            for t in items {
                let id: String
                if let n = t["id"] as? Int { id = String(n) } else if let s = t["id"] as? String { id = s } else { continue }
                let ds = t["date"] as? String ?? ""
                all.append(KomootTour(id: id, name: t["name"] as? String ?? "Tour \(id)", type: t["type"] as? String ?? "",
                                      sport: t["sport"] as? String ?? "", date: iso.date(from: ds) ?? iso2.date(from: ds),
                                      distance: (t["distance"] as? Double) ?? Double(t["distance"] as? Int ?? 0),
                                      status: t["status"] as? String ?? ""))
            }
            page += 1
            let total = ((j["page"] as? [String: Any])?["totalPages"] as? Int) ?? 0
            if page >= total || items.isEmpty { break }
        }
        return all
    }

    func gpx(of id: String) async throws -> Data {
        guard let url = URL(string: "\(base)/v007/tours/\(id).gpx") else { throw KomootError.format }
        let (d, code) = try await fetch(request(url, auth: basic(userID, token)))
        guard code == 200 else { throw KomootError.http(code) }
        return d
    }

    /// Uploads a GPX file as a new tour. Returns true when Komoot created it, false when it already existed there.
    func upload(gpx: Data, sport: String) async throws -> Bool {
        guard let url = URL(string: "\(base)/v007/tours/?data_type=gpx&sport=\(sport)") else { throw KomootError.format }
        var r = request(url, method: "POST", body: gpx, auth: basic(userID, token))
        r.setValue("application/gpx+xml", forHTTPHeaderField: "Content-Type")
        let (_, code) = try await fetch(r)
        if code == 201 { return true }
        if code == 202 { return false }
        throw KomootError.http(code)
    }
}

// MARK: Local files (what is already on disk?)

struct LocalGPXIndex {
    var times: [TimeInterval] = []     // start times found in the files, sorted
    var ids: Set<String> = []          // Komoot tour numbers found in the files

    func has(_ t: KomootTour) -> Bool {
        if ids.contains(t.id) { return true }
        guard let d = t.date?.timeIntervalSince1970 else { return false }
        var lo = 0, hi = times.count
        while lo < hi { let m = (lo + hi) / 2; if times[m] < d { lo = m + 1 } else { hi = m } }
        for i in [lo - 1, lo] where i >= 0 && i < times.count && abs(times[i] - d) <= 600 { return true }
        return false
    }

    /// Reads the head of every GPX file below `root`: the first time stamps and Komoot tour references.
    static func scan(_ root: URL) -> LocalGPXIndex {
        var idx = LocalGPXIndex()
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        let timeRe = try! NSRegularExpression(pattern: "<time>([^<]+)</time>")
        let idRe = try! NSRegularExpression(pattern: "(?:komoot-tour:|komoot\\.[a-z]+/tour/)(\\d+)")
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return idx }
        for case let u as URL in en where u.pathExtension.lowercased() == "gpx" {
            guard let h = try? FileHandle(forReadingFrom: u) else { continue }
            let data = (try? h.read(upToCount: 160_000)) ?? Data()
            try? h.close()
            let s = String(decoding: data, as: UTF8.self)
            let ns = s as NSString
            let full = NSRange(location: 0, length: ns.length)
            for m in timeRe.matches(in: s, range: full).prefix(3) {
                let t = ns.substring(with: m.range(at: 1))
                if let d = iso.date(from: t) ?? iso2.date(from: t) { idx.times.append(d.timeIntervalSince1970) }
            }
            for m in idRe.matches(in: s, range: full) { idx.ids.insert(ns.substring(with: m.range(at: 1))) }
        }
        idx.times.sort()
        return idx
    }
}

// MARK: Session shared by both sheets

@MainActor
final class KomootSession: ObservableObject {
    enum Phase { case signedOut, working(String), ready }
    @Published var phase: Phase = .signedOut
    @Published var email = ""
    @Published var password = ""
    @Published var remember = true
    @Published var error: String?
    let client = KomootClient()

    init() {
        if let c = KomootKeychain.load() { email = c.email; password = c.password; hasSavedLogin = true }
    }

    /// Remembered here: the view asks often, and every keychain access could bring up the keychain dialog again.
    @Published private(set) var hasSavedLogin = false

    func signIn() async -> Bool {
        error = nil
        phase = .working("Signing in …")
        do {
            try await client.login(email: email.trimmingCharacters(in: .whitespaces), password: password)
            if remember { KomootKeychain.save(email: email.trimmingCharacters(in: .whitespaces), password: password); hasSavedLogin = true }
            phase = .ready
            return true
        } catch {
            self.error = error.localizedDescription
            phase = .signedOut
            return false
        }
    }

    func forgetLogin() { KomootKeychain.delete(); hasSavedLogin = false; password = ""; phase = .signedOut }
}

struct KomootLoginForm: View {
    @ObservedObject var session: KomootSession
    var buttonTitle = "Sign In"
    var onSignIn: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in to Komoot").font(.headline)
            TextField("E-mail address", text: $session.email).textFieldStyle(.roundedBorder)
            SecureField("Password", text: $session.password).textFieldStyle(.roundedBorder)
            Toggle("Store in the macOS keychain", isOn: $session.remember)
            Text("Komoot offers no public interface for private users; this uses the same unofficial interface as other tools and may stop working. Password and e-mail are kept only in the keychain. Nothing that is stored on Komoot is ever changed.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let e = session.error { Text(e).foregroundStyle(.red).font(.callout) }
            HStack {
                if session.hasSavedLogin { Button("Remove Saved Login") { session.forgetLogin() } }
                Spacer()
                Button(buttonTitle, action: onSignIn).keyboardShortcut(.defaultAction)
                    .disabled(session.email.isEmpty || session.password.isEmpty)
            }
        }
    }
}

// MARK: Import

struct KomootImportSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: KomootSession
    @StateObject private var state = ImportState()

    final class ImportState: ObservableObject {
        @Published var tours: [KomootTour] = []
        @Published var onDisk: Set<String> = []
        @Published var chosen: Set<String> = []
        @Published var onlyMissing = false
        @Published var year = 0          // 0 = all years
        @Published var status = ""
        @Published var busy = false
    }

    /// Fixed destination: the folder "Komoot" directly in the root folder (created when needed).
    private var target: URL { model.rootURL.appendingPathComponent("Komoot", isDirectory: true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import from Komoot").font(.title3.bold())
            switch session.phase {
            case .signedOut:
                KomootLoginForm(session: session) { Task { await start() } }
            case .working(let msg):
                HStack { ProgressView().controlSize(.small); Text(msg) }
            case .ready:
                list
            }
        }
        .padding(18)
        .frame(width: 720, height: session.phase.isReady ? 560 : 330)
        .task { if session.hasSavedLogin && !session.password.isEmpty { await start() } }
    }

    private func yearOf(_ t: KomootTour) -> Int? { t.date.map { Calendar.current.component(.year, from: $0) } }
    private var years: [Int] { Array(Set(state.tours.compactMap(yearOf))).sorted(by: >) }
    private var inYear: [KomootTour] { state.year == 0 ? state.tours : state.tours.filter { yearOf($0) == state.year } }
    private var chosenShown: [KomootTour] { shown.filter { state.chosen.contains($0.id) } }
    private var shown: [KomootTour] { state.onlyMissing ? inYear.filter { !state.onDisk.contains($0.id) } : inYear }

    @ViewBuilder private var list: some View {
        HStack {
            Picker("Year", selection: $state.year) {
                Text("All years").tag(0)
                ForEach(years, id: \.self) { Text(String($0)).tag($0) }
            }
            .pickerStyle(.menu).fixedSize()
            Spacer()
            Toggle("Only missing", isOn: $state.onlyMissing).toggleStyle(.checkbox)
        }
        Text("\(inYear.count) tours on Komoot, \(inYear.filter { !state.onDisk.contains($0.id) }.count) not found on disk")
            .font(.callout).foregroundStyle(.secondary)
        List {
            ForEach(shown) { t in
                let here = state.onDisk.contains(t.id)
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(get: { state.chosen.contains(t.id) },
                                             set: { if $0 { state.chosen.insert(t.id) } else { state.chosen.remove(t.id) } }))
                        .labelsHidden().toggleStyle(.checkbox)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.name).lineLimit(1)
                        Text((t.planned ? "Planned" : "Recorded") + " · " + t.sport.replacingOccurrences(of: "_", with: " "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(t.date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "%.1f km", t.distance / 1000)).font(.caption).monospacedDigit().frame(width: 62, alignment: .trailing)
                    Text(here ? "on disk" : "missing").font(.caption.bold())
                        .foregroundStyle(here ? Color.secondary : Color.orange).frame(width: 52, alignment: .trailing)
                }
                .listRowBackground(here ? nil : Color.orange.opacity(0.12))
            }
        }
        .border(Color.secondary.opacity(0.3))
        HStack {
            Button(state.year == 0 ? "Select Missing" : "Select Missing from " + String(state.year)) { state.chosen = Set(inYear.filter { !state.onDisk.contains($0.id) }.map(\.id)) }
            Button(state.year == 0 ? "Select All" : "Select All from " + String(state.year)) { state.chosen = Set(inYear.map(\.id)) }
            Button("Select None") { state.chosen = [] }
            Spacer()
            Text("Into: \(model.rootURL.lastPathComponent)/Komoot").font(.caption).foregroundStyle(.secondary)
        }
        if !state.status.isEmpty { Text(state.status).font(.caption).foregroundStyle(.secondary) }
        HStack {
            Spacer()
            Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Download \(chosenShown.count) Tour\(chosenShown.count == 1 ? "" : "s")") { Task { await download() } }
                .keyboardShortcut(.defaultAction).disabled(chosenShown.isEmpty || state.busy)
        }
    }

    private func start() async {
        guard await session.signIn() else { return }
        state.status = "Reading the tour list and comparing it with the files on disk …"
        let root = model.rootURL
        async let local = Task.detached(priority: .userInitiated) { LocalGPXIndex.scan(root) }.value
        do {
            let tours = try await session.client.tours()
            let idx = await local
            state.tours = tours
            state.onDisk = Set(tours.filter { idx.has($0) }.map(\.id))
            state.chosen = Set(tours.filter { !state.onDisk.contains($0.id) }.map(\.id))
            state.status = ""
        } catch {
            session.error = error.localizedDescription
            session.phase = .signedOut
        }
    }

    private func download() async {
        state.busy = true
        defer { state.busy = false }
        let todo = chosenShown            // only what the list shows right now (year and filter), not marks made under another year
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        var done = 0, failed = 0
        for t in todo {
            state.status = "Downloading \(done + failed + 1) of \(todo.count): \(t.name)"
            do {
                var text = String(decoding: try await session.client.gpx(of: t.id), as: UTF8.self)
                let tag = "<!-- komoot-tour:\(t.id) -->"      // lets the app recognise the file later
                if let r = text.range(of: "?>") { text.insert(contentsOf: "\n" + tag, at: r.upperBound) } else { text = tag + "\n" + text }
                let url = uniqueURL(for: t)
                try text.write(to: url, atomically: true, encoding: .utf8)
                if let d = t.date { try? FileManager.default.setAttributes([.modificationDate: d, .creationDate: d], ofItemAtPath: url.path) }
                state.onDisk.insert(t.id); state.chosen.remove(t.id)
                done += 1
            } catch { failed += 1 }
        }
        state.status = "\(done) downloaded into “\(target.lastPathComponent)”" + (failed > 0 ? ", \(failed) failed." : ".")
        model.reloadTree()
    }

    private func uniqueURL(for t: KomootTour) -> URL {
        var name = t.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = "Komoot \(t.id)" }
        var url = target.appendingPathComponent(name + ".gpx")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) { url = target.appendingPathComponent("\(name) \(n).gpx"); n += 1 }
        return url
    }
}

extension KomootSession.Phase {
    var isReady: Bool { if case .ready = self { return true } else { return false } }
}

// MARK: Export

struct KomootExportSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: KomootSession
    @StateObject private var opts = ExportOpts()
    final class ExportOpts: ObservableObject { @Published var sport = "hike"; @Published var result = "" }

    private static let sports: [(String, String)] = [
        ("Hiking", "hike"), ("Road cycling", "racebike"), ("Mountain biking", "mtb"), ("Gravel biking", "mtb_easy"),
        ("Bike touring", "touringbicycle"), ("Biking", "citybike"), ("Running", "jogging"), ("Other", "other")]

    private var fileURL: URL? { model.foregroundPath.map { URL(fileURLWithPath: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export to Komoot").font(.title3.bold())
            if let u = fileURL {
                Text("File: \(u.deletingPathExtension().lastPathComponent)")
                Picker("Sport", selection: $opts.sport) { ForEach(Self.sports, id: \.1) { Text($0.0).tag($0.1) } }.frame(width: 260)
                Text("The file is uploaded as a new tour (Komoot treats uploads as recorded tours). Existing tours on Komoot are not changed. If Komoot already has the same tour, nothing new is created.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                switch session.phase {
                case .signedOut:
                    KomootLoginForm(session: session, buttonTitle: "Sign In and Upload") { Task { await upload(u, signIn: true) } }
                    HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
                case .working(let m):
                    HStack { ProgressView().controlSize(.small); Text(m) }
                case .ready:
                    if opts.result.isEmpty {
                        Text("You are signed in to Komoot.").font(.callout)
                        HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                                 Button("Upload") { Task { await upload(u, signIn: false) } }.keyboardShortcut(.defaultAction) }
                    } else {
                        Text(opts.result).font(.callout)
                        HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.defaultAction) }
                    }
                }
            } else {
                Text("Select a track in the list first.")
                HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
            }
        }
        .padding(18).frame(width: 480)
    }

    private func upload(_ u: URL, signIn: Bool) async {
        if signIn { guard await session.signIn() else { return } }
        session.phase = .working("Uploading …")
        do {
            let data: Data
            if let d = GPXDocument.parse(u) { data = Data(d.gpxAsTrack().utf8) } else { data = try Data(contentsOf: u) }
            let created = try await session.client.upload(gpx: data, sport: opts.sport)
            opts.result = created ? "Uploaded: a new tour was created on Komoot." : "Komoot already has this tour; nothing new was created."
        } catch { opts.result = "Upload failed: " + error.localizedDescription }
        session.phase = .ready
    }
}
