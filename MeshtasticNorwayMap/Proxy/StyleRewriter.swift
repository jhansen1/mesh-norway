import Foundation

/// Adds the satellite layer to the site's MapLibre style.
///
/// The imagery goes above the basemap's area fills (land cover, water,
/// buildings) and below its lines and labels, so borders, roads and names
/// stay readable on top of it. A style it does not understand is left alone:
/// the caller then serves the original.
enum StyleRewriter {
    static let sourceID = "app-satellite"
    static let layerID = "app-satellite"

    /// Tile URLs of the satellite layer as the page requests them.
    static var tileURLTemplate: String {
        AppConfig.appOrigin + AppConfig.satellitePathPrefix + "{z}/{x}/{y}"
    }

    static func addingSatellite(to style: Data, provider: SatelliteProvider) -> Data? {
        guard var root = (try? JSONSerialization.jsonObject(with: style)) as? [String: Any],
              var sources = root["sources"] as? [String: Any],
              var layers = root["layers"] as? [[String: Any]],
              sources[sourceID] == nil,
              !layers.contains(where: { $0["id"] as? String == layerID }) else { return nil }

        // Labels start at the style's marker layer, or at its first symbol layer.
        let labelsStart = layers.firstIndex { layer in
            layer["id"] as? String == "labels-start" || layer["type"] as? String == "symbol"
        } ?? layers.count
        guard let lastArea = layers[..<labelsStart].lastIndex(where: { layer in
            let type = layer["type"] as? String
            return type == "fill" || type == "background"
        }) else { return nil }

        sources[sourceID] = [
            "type": "raster",
            "tiles": [tileURLTemplate],
            "tileSize": 256,
            "minzoom": 0,
            "maxzoom": provider.maxZoom,
            "attribution": provider.attribution,
        ] as [String: Any]
        layers.insert([
            "id": layerID,
            "type": "raster",
            "source": sourceID,
            "paint": ["raster-opacity": 1] as [String: Any],
        ], at: lastArea + 1)

        root["sources"] = sources
        root["layers"] = layers
        return try? JSONSerialization.data(withJSONObject: root)
    }
}
