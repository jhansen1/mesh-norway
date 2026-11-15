import XCTest
@testable import MeshtasticNorwayMap

final class StyleRewriterTests: XCTestCase {
    private let style = """
    {"version":8,"name":"t","sources":{"openmaptiles":{"type":"vector","url":"pmtiles:///tiles/basemap.pmtiles"}},
     "glyphs":"/fonts/{fontstack}/{range}.pbf",
     "layers":[
      {"id":"background","type":"background","paint":{"background-color":"#0e1116"}},
      {"id":"water","type":"fill","source":"openmaptiles","source-layer":"water"},
      {"id":"waterway","type":"line","source":"openmaptiles","source-layer":"waterway"},
      {"id":"building","type":"fill","source":"openmaptiles","source-layer":"building","minzoom":13.5},
      {"id":"boundary-country","type":"line","source":"openmaptiles","source-layer":"boundary"},
      {"id":"labels-start","type":"background","layout":{"visibility":"none"}},
      {"id":"place-city","type":"symbol","source":"openmaptiles","source-layer":"place"}
     ]}
    """

    private func layers(_ data: Data) throws -> [[String: Any]] {
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(root["layers"] as? [[String: Any]])
    }

    func testSatelliteGoesAboveAreasAndBelowLinesAndLabels() throws {
        let out = try XCTUnwrap(StyleRewriter.addingSatellite(to: Data(style.utf8), provider: .current))
        let ids = try layers(out).compactMap { $0["id"] as? String }
        XCTAssertEqual(ids, ["background", "water", "waterway", "building", "app-satellite", "boundary-country", "labels-start", "place-city"])

        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: out) as? [String: Any])
        let sources = try XCTUnwrap(root["sources"] as? [String: Any])
        XCTAssertNotNil(sources["openmaptiles"])
        let source = try XCTUnwrap(sources["app-satellite"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "raster")
        XCTAssertEqual(source["tiles"] as? [String], ["meshmap://map.868.no/__app/sat/{z}/{x}/{y}"])
        XCTAssertEqual(source["maxzoom"] as? Int, SatelliteProvider.current.maxZoom)
        XCTAssertEqual(root["glyphs"] as? String, "/fonts/{fontstack}/{range}.pbf")
        XCTAssertEqual(root["version"] as? Int, 8)
        // Untouched layers keep their content.
        let building = try XCTUnwrap(try layers(out).first { $0["id"] as? String == "building" })
        XCTAssertEqual(building["minzoom"] as? Double, 13.5)
    }

    func testIsNotAddedTwice() throws {
        let once = try XCTUnwrap(StyleRewriter.addingSatellite(to: Data(style.utf8), provider: .current))
        XCTAssertNil(StyleRewriter.addingSatellite(to: once, provider: .current))
    }

    func testUnknownStylesAreLeftAlone() {
        for bad in ["", "not json", "[]", "{}", #"{"sources":{},"layers":"x"}"#, #"{"sources":{},"layers":[]}"#,
                    #"{"sources":{},"layers":[{"id":"a","type":"symbol"}]}"#, #"{"sources":[],"layers":[{"id":"a","type":"fill"}]}"#] {
            XCTAssertNil(StyleRewriter.addingSatellite(to: Data(bad.utf8), provider: .current), bad)
        }
    }

    func testProviderTileURLs() {
        let provider = SatelliteProvider.current
        XCTAssertEqual(provider.tileURL(z: 9, x: 270, y: 137)?.absoluteString,
                       "https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2017_3857/default/g/9/137/270.jpg")
        XCTAssertNil(provider.tileURL(z: 2, x: 4, y: 0))
        XCTAssertNil(provider.tileURL(z: -1, x: 0, y: 0))
        var insecure = provider
        insecure.tileURLTemplate = "http://example.org/{z}/{x}/{y}.jpg"
        XCTAssertNil(insecure.tileURL(z: 1, x: 0, y: 0))
    }
}
