import SwiftUI
import AppKit
import BCCore

enum ExportFormat: String, CaseIterable {
    case gpxTrack = "GPX – as Track (recording, for archiving and sharing)", gpxRoute = "GPX – as Route (for navigation with turn instructions)", kml = "KML (Google Earth)", csv = "CSV (point list)"
    var title: String { L(rawValue) }
    var ext: String { switch self { case .gpxTrack, .gpxRoute: return "gpx"; case .kml: return "kml"; case .csv: return "csv" } }
}

extension AppModel {
    /// The document to export: the edited version if editing, otherwise the selected file.
    private func exportSource() -> (GPXDocument, String)? {
        if let e = edit { return (e.document, e.url.deletingPathExtension().lastPathComponent) }
        guard let id = foregroundPath, let d = GPXDocument.parse(URL(fileURLWithPath: id)) else { return nil }
        return (d, URL(fileURLWithPath: id).deletingPathExtension().lastPathComponent)
    }

    func exportTrack(_ format: ExportFormat) {
        guard let (doc, base) = exportSource() else { return }
        let p = NSSavePanel()
        p.nameFieldStringValue = "\(base).\(format.ext)"
        p.prompt = L("Export")
        guard p.runModal() == .OK, let url = p.url else { return }
        let text: String
        switch format {
        case .gpxTrack: text = doc.gpxAsTrack()
        case .gpxRoute: text = doc.gpxAsRoute()
        case .kml: text = doc.kml()
        case .csv: text = doc.csv()
        }
        do { try text.write(to: url, atomically: true, encoding: .utf8) }
        catch { let a = NSAlert(); a.messageText = L("Export failed"); a.informativeText = error.localizedDescription; a.runModal() }
    }

    func center(on lat: Double, _ lon: Double) {
        view.mx = Merc.x(lon: lon); view.my = Merc.y(lat: lat)
        viewRevision += 1
    }
}
