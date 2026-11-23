import SwiftUI
import AppKit

/// "About" window: name, version, licence (GNU GPL v3) and credits.
struct AboutView: View {
    @StateObject private var ui = AboutState()

    private var version: String {
        let i = Bundle.main.infoDictionary
        return L("Version %@ (%@)", "\(i?["CFBundleShortVersionString"] as? String ?? "0.1")", "\(i?["CFBundleVersion"] as? String ?? "1")")
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
            Text("GPX Organizer").font(.title).bold()
            Text(version).font(.callout).foregroundStyle(.secondary)
            Text("A native macOS app to browse and edit GPX tracks and waypoints on Garmin and online maps.")
                .multilineTextAlignment(.center).font(.callout).fixedSize(horizontal: false, vertical: true)
            Divider()
            if ui.showLicense {
                ScrollView {
                    Text(Self.licenseText).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
                .frame(height: 300)
                Button("Back") { ui.showLicense = false }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.")
                    Text("This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.")
                    Text("Map data and services").font(.caption).bold().padding(.top, 4)
                    Text("""
                    • © OpenStreetMap contributors (ODbL)
                    • OpenTopoMap (CC-BY-SA), map data © OpenStreetMap contributors, SRTM
                    • TopPlusOpen © Federal Agency for Cartography and Geodesy (BKG)
                    • Knowledge of the Garmin map format thanks to the QMapShack project (GPL v3)
                    """)
                    Text("GPX Organizer is an independent project and is not affiliated with or endorsed by Garmin Ltd. Garmin and BaseCamp are trademarks of Garmin Ltd.")
                        .foregroundStyle(.secondary)
                }
                .font(.caption).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("View Full License") { ui.showLicense = true }
                    Link("gnu.org/licenses/gpl-3.0", destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
                }
            }
            Text("© 2026 Martin Doppelbauer").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 460)
    }

    static var licenseText: String {
        if let u = Bundle.main.url(forResource: "LICENSE", withExtension: nil), let s = try? String(contentsOf: u, encoding: .utf8) { return s }
        return "The full text of the GNU General Public License, version 3, is available at https://www.gnu.org/licenses/gpl-3.0.txt"
    }
}

final class AboutState: ObservableObject { @Published var showLicense = false }
