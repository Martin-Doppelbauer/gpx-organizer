import Foundation

public enum Continent: String, CaseIterable, Identifiable {
    case northAmerica, southAmerica, europe, africa, indianSubcontinent, asia, oceania
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .northAmerica: return "North America"; case .southAmerica: return "South America"; case .europe: return "Europe"
        case .africa: return "Africa"; case .indianSubcontinent: return "Indian Subcontinent"; case .asia: return "Asia"
        case .oceania: return "Australia / Oceania"
        }
    }
}

/// A known free online map (Web-Mercator tiles). `{s}` is replaced by one of the subdomains.
public struct CatalogMap: Identifiable, Hashable {
    public var id: String { template }
    public let name: String
    public let template: String
    public let subdomains: [String]
    public let maxZoom: Int
    public let attribution: String
    public let continents: Set<Continent>
    public let keywords: [String]
    public let note: String
}

public enum MapCatalog {
    private static let all7 = Set(Continent.allCases)
    private static let osmCredit = "© OpenStreetMap contributors"

    private static func m(_ name: String, _ t: String, sub: [String] = [], zoom: Int, credit: String, _ c: Set<Continent> = all7,
                          keys: [String] = [], note: String = "") -> CatalogMap {
        CatalogMap(name: name, template: t, subdomains: sub, maxZoom: zoom, attribution: credit, continents: c, keywords: keys, note: note)
    }

    public static let entries: [CatalogMap] = [
        // worldwide
        m("OpenStreetMap (Standard)", "https://tile.openstreetmap.org/{z}/{x}/{y}.png", zoom: 19, credit: osmCredit, keys: ["openstreetmap", "osm"], note: "Worldwide street map"),
        m("OpenTopoMap (Topo, worldwide)", "https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png", sub: ["a", "b", "c"], zoom: 17,
          credit: "Map data © OpenStreetMap contributors, SRTM | Rendering © OpenTopoMap (CC-BY-SA)", keys: ["opentopomap", "topo"], note: "Hiking map with contour lines"),
        m("CyclOSM (cycling)", "https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png", sub: ["a", "b", "c"], zoom: 20,
          credit: "© OpenStreetMap contributors, tiles by CyclOSM", keys: ["cyclosm", "cycle", "bike"], note: "Made for cycling"),
        m("OpenStreetMap Humanitarian", "https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png", sub: ["a", "b", "c"], zoom: 19,
          credit: "© OpenStreetMap contributors, tiles by Humanitarian OpenStreetMap Team", keys: ["humanitarian", "hot"], note: "Clear map, good for Africa and Asia"),
        m("Esri World Topographic", "https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}", zoom: 19,
          credit: "Tiles © Esri — Esri, DeLorme, NAVTEQ, USGS, and others", keys: ["esri", "arcgis"], note: "Topographic map"),
        m("Esri World Imagery (satellite)", "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}", zoom: 19,
          credit: "Tiles © Esri — Source: Esri, Maxar, Earthstar Geographics, and the GIS User Community", keys: ["imagery", "satellite", "esri"], note: "Satellite images"),
        m("Esri World Street Map", "https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}", zoom: 19,
          credit: "Tiles © Esri — Esri, DeLorme, NAVTEQ", keys: ["esri", "street"], note: "Street map"),
        m("Esri World Terrain", "https://server.arcgisonline.com/ArcGIS/rest/services/World_Terrain_Base/MapServer/tile/{z}/{y}/{x}", zoom: 13,
          credit: "Tiles © Esri — Source: USGS, Esri, TANA, DeLorme, and NPS", keys: ["terrain", "relief"], note: "Shaded relief, up to zoom 13"),
        m("CARTO Positron (light)", "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png", sub: ["a", "b", "c", "d"], zoom: 20,
          credit: "© OpenStreetMap contributors © CARTO", keys: ["carto", "positron", "light"], note: "Calm light background"),
        m("CARTO Dark Matter", "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png", sub: ["a", "b", "c", "d"], zoom: 20,
          credit: "© OpenStreetMap contributors © CARTO", keys: ["carto", "dark"], note: "Dark background"),
        // Europe
        m("TopPlusOpen (Topo, Germany/Europe)", "https://sgx.geodatenzentrum.de/wmts_topplus_open/tile/1.0.0/web/default/WEBMERCATOR/{z}/{y}/{x}.png", zoom: 18,
          credit: "© Federal Agency for Cartography and Geodesy (TopPlusOpen), data sources: sg.geodatenzentrum.de", [.europe], keys: ["topplus", "bkg", "geodatenzentrum"], note: "Official topographic map of Germany and Europe"),
        m("TopPlusOpen gray", "https://sgx.geodatenzentrum.de/wmts_topplus_open/tile/1.0.0/web_grau/default/WEBMERCATOR/{z}/{y}/{x}.png", zoom: 18,
          credit: "© Federal Agency for Cartography and Geodesy (TopPlusOpen), data sources: sg.geodatenzentrum.de", [.europe], keys: ["topplus", "bkg"], note: "Gray version, good under colored tracks"),
        m("OpenStreetMap Germany", "https://tile.openstreetmap.de/{z}/{x}/{y}.png", zoom: 19, credit: osmCredit, [.europe], keys: ["openstreetmap.de"], note: "German style, names in local language"),
        m("Switzerland: swisstopo (color)", "https://wmts.geo.admin.ch/1.0.0/ch.swisstopo.pixelkarte-farbe/default/current/3857/{z}/{x}/{y}.jpeg", zoom: 18,
          credit: "© swisstopo", [.europe], keys: ["swisstopo", "schweiz", "switzerland"], note: "Official Swiss map"),
        m("Switzerland: swisstopo (gray)", "https://wmts.geo.admin.ch/1.0.0/ch.swisstopo.pixelkarte-grau/default/current/3857/{z}/{x}/{y}.jpeg", zoom: 18,
          credit: "© swisstopo", [.europe], keys: ["swisstopo"], note: "Official Swiss map, gray"),
        m("France: IGN Plan", "https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2&STYLE=normal&FORMAT=image/png&TILEMATRIXSET=PM&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}",
          zoom: 18, credit: "© IGN", [.europe], keys: ["ign", "geoportail", "france"], note: "Official French map"),
        m("Norway: Kartverket Topo", "https://cache.kartverket.no/v1/wmts/1.0.0/topo/default/webmercator/{z}/{y}/{x}.png", zoom: 18,
          credit: "© Kartverket", [.europe], keys: ["kartverket", "norway", "norge"], note: "Official Norwegian topographic map"),
        m("Austria: basemap.at", "https://mapsneu.wien.gv.at/basemap/bmaphidpi/normal/google3857/{z}/{y}/{x}.jpeg", zoom: 19,
          credit: "© basemap.at", [.europe], keys: ["basemap", "austria", "oesterreich"], note: "Official Austrian base map"),
        m("Netherlands: PDOK BRT", "https://service.pdok.nl/brt/achtergrondkaart/wmts/v2_0/standaard/EPSG:3857/{z}/{x}/{y}.png", zoom: 19,
          credit: "© Kadaster", [.europe], keys: ["pdok", "kadaster", "netherlands"], note: "Dutch topographic background map"),
        // North America
        m("USA: USGS Topo", "https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer/tile/{z}/{y}/{x}", zoom: 16,
          credit: "USGS The National Map", [.northAmerica], keys: ["usgs", "nationalmap"], note: "Topographic maps of the USA"),
        m("USA: USGS Imagery", "https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer/tile/{z}/{y}/{x}", zoom: 16,
          credit: "USGS The National Map", [.northAmerica], keys: ["usgs"], note: "Satellite images of the USA"),
        // Asia
        m("Japan: GSI Standard", "https://cyberjapandata.gsi.go.jp/xyz/std/{z}/{x}/{y}.png", zoom: 18,
          credit: "地理院タイル (GSI Japan)", [.asia], keys: ["gsi", "japan"], note: "Official Japanese map"),
        m("Japan: GSI Pale", "https://cyberjapandata.gsi.go.jp/xyz/pale/{z}/{x}/{y}.png", zoom: 18,
          credit: "地理院タイル (GSI Japan)", [.asia], keys: ["gsi", "japan"], note: "Pale Japanese map"),
        // Oceania
        m("Australia: Geoscience Australia Topographic", "https://services.ga.gov.au/gis/rest/services/Topographic_Base_Map/MapServer/tile/{z}/{y}/{x}", zoom: 16,
          credit: "© Commonwealth of Australia (Geoscience Australia)", [.oceania], keys: ["geoscience", "australia", "ga.gov"], note: "Topographic base map of Australia"),
    ]

    /// Free aerial and satellite imagery (no access key needed). Terms of use differ; the note says what to keep in mind.
    public static let imageryEntries: [CatalogMap] = [
        m("Esri World Imagery", "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}", zoom: 19,
          credit: "Tiles © Esri — Source: Esri, Maxar, Earthstar Geographics, and the GIS User Community", keys: ["esri", "world imagery"], note: "Sharp aerial images, worldwide; Esri's terms of use apply"),
        m("Sentinel-2 cloudless (EOX)", "https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2024_3857/default/g/{z}/{y}/{x}.jpg", zoom: 13,
          credit: "Sentinel-2 cloudless 2024 by EOX IT Services GmbH (contains modified Copernicus Sentinel data 2024), CC BY-NC-SA 4.0", keys: ["sentinel", "eox"], note: "Satellite mosaic, 10 m resolution, free for non-commercial use"),
        m("Switzerland: SWISSIMAGE", "https://wmts.geo.admin.ch/1.0.0/ch.swisstopo.swissimage/default/current/3857/{z}/{x}/{y}.jpeg", zoom: 19,
          credit: "© swisstopo", [.europe], keys: ["swissimage", "swisstopo"], note: "Official Swiss aerial images"),
        m("France: IGN Orthophotos", "https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=ORTHOIMAGERY.ORTHOPHOTOS&STYLE=normal&FORMAT=image/jpeg&TILEMATRIXSET=PM&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}",
          zoom: 19, credit: "© IGN", [.europe], keys: ["ign", "orthophoto"], note: "Official French aerial images"),
        m("Austria: basemap.at Orthofoto", "https://mapsneu.wien.gv.at/basemap/bmaporthofoto30cm/normal/google3857/{z}/{y}/{x}.jpeg", zoom: 19,
          credit: "© basemap.at", [.europe], keys: ["basemap", "orthofoto"], note: "Austrian aerial images"),
        m("Netherlands: PDOK Luchtfoto", "https://service.pdok.nl/hwh/luchtfotorgb/wmts/v1_0/Actueel_orthoHR/EPSG:3857/{z}/{x}/{y}.jpeg", zoom: 19,
          credit: "© Beeldmateriaal Nederland", [.europe], keys: ["pdok", "luchtfoto"], note: "Dutch aerial images"),
        m("Bavaria: Digitale Orthophotos", "https://wmtsod1.bayernwolke.de/wmts/by_dop/smerc/{z}/{x}/{y}", zoom: 20,
          credit: "© Bayerische Vermessungsverwaltung (CC BY 4.0)", [.europe], keys: ["bayern", "bavaria", "orthophoto"], note: "Open aerial images of Bavaria"),
        m("Spain: PNOA Orthophotos", "https://www.ign.es/wmts/pnoa-ma?request=getTile&service=WMTS&version=1.0.0&layer=OI.OrthoimageCoverage&style=default&format=image/jpeg&tilematrixset=GoogleMapsCompatible&tilematrix={z}&tilerow={y}&tilecol={x}",
          zoom: 19, credit: "PNOA © Instituto Geográfico Nacional de España (CC BY 4.0)", [.europe], keys: ["pnoa", "spain", "espana"], note: "Spanish aerial images"),
        m("USA: USGS Imagery", "https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer/tile/{z}/{y}/{x}", zoom: 16,
          credit: "USGS The National Map", [.northAmerica], keys: ["usgs"], note: "Aerial images of the USA"),
        m("Japan: GSI Seamless Photo", "https://cyberjapandata.gsi.go.jp/xyz/seamlessphoto/{z}/{x}/{y}.jpg", zoom: 18,
          credit: "地理院タイル (GSI Japan)", [.asia], keys: ["gsi", "japan"], note: "Japanese aerial images"),
    ]

    public static func imagerySuggestions(for c: Continent) -> [CatalogMap] {
        let own = imageryEntries.filter { $0.continents.contains(c) && $0.continents.count < Continent.allCases.count }
        let global = imageryEntries.filter { $0.continents.count == Continent.allCases.count }
        return own + global
    }

    /// Suggestions for a continent: its own maps first, then the worldwide ones.
    public static func suggestions(for c: Continent) -> [CatalogMap] {
        let own = entries.filter { $0.continents.contains(c) && $0.continents.count < Continent.allCases.count }
        let global = entries.filter { $0.continents.count == Continent.allCases.count }
        return own + global
    }

    /// Maps whose keywords or host resemble a typed word (tolerates small typing errors).
    public static func fuzzyMatches(_ text: String) -> [CatalogMap] {
        let stop: Set<String> = ["map", "maps", "topo", "topographic", "street", "world", "tile", "tiles", "online", "org", "com", "www", "http", "https", "official",
                                 "base", "standard", "worldwide", "gray", "grey", "the", "and", "satellite", "imagery", "light", "dark", "hiking", "cycling", "net", "gov", "wmts", "arcgis"]
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 && !stop.contains($0) }
        guard !words.isEmpty else { return [] }
        func dist(_ a: String, _ b: String) -> Int {
            let a = Array(a), b = Array(b)
            var prev = Array(0...b.count)
            for i in 1...max(1, a.count) where !a.isEmpty {
                var cur = [i]
                for j in 1...max(1, b.count) where !b.isEmpty {
                    cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)))
                }
                prev = cur
            }
            return prev.last ?? 0
        }
        var hits: [(CatalogMap, Int)] = []
        for e in entries {
            var best = 99
            let hay = ([e.name.lowercased()] + e.keywords).joined(separator: " ")
            for w in words {
                if w.count >= 4, hay.contains(w) { best = min(best, 0) }
                for k in e.keywords + e.name.lowercased().split(separator: " ").map(String.init) where k.count >= 3 && !stop.contains(k) {
                    let d = dist(w, k)
                    if d <= (k.count > 6 ? 2 : 1) { best = min(best, d + 1) }
                }
            }
            if best < 99 { hits.append((e, best)) }
        }
        return hits.sorted { $0.1 < $1.1 }.map { $0.0 }
    }
}
