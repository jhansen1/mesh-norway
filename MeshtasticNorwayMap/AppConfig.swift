import Foundation

/// Where the map comes from, and how the app addresses it.
///
/// The web app at map.868.no is loaded live through `UpstreamProxy`, under a
/// private URL scheme with the site's own host name. Everything the page asks
/// for is fetched from the real site over HTTPS, so the app always runs the
/// version the server is serving.
enum AppConfig {
    /// The private scheme the page is served under inside the app.
    static let scheme = "meshmap"
    /// The site this app is the iOS edition of.
    static let host = "map.868.no"

    /// The page's origin inside the app.
    static let appOrigin = "\(scheme)://\(host)"
    /// The page's public origin, used in every link that leaves the app.
    static let webOrigin = "https://\(host)"

    static let homeURL = URL(string: "\(appOrigin)/")!

    /// The satellite map layer. Switched off for now: the code stays, but the
    /// app shows no control for it and never adds the layer.
    static let satelliteLayerAvailable = false

    /// Paths under this prefix are answered by the app itself, not the site.
    static let satellitePathPrefix = "/__app/sat/"

    /// Asked for by the page when the viewer resets the map: the app forgets its saved copies too.
    static let clearSavedCopiesPath = "/__app/clear-saved"

    /// The page's notifications (the web's Notification API) arrive here and become iOS notifications.
    static let notifyPath = "/__app/notify"
    static let notifyPermissionPath = "/__app/notify/permission"

    // Credits and links shown on the About screen.
    static let upstreamAuthor = "Jim C K Flaten"
    static let upstreamProjectName = "868.no Map"
    static let upstreamSiteURL = URL(string: webOrigin)!
    static let upstreamSourceURL = URL(string: "https://github.com/868-no/map")!
    static let upstreamLicenseURL = URL(string: "https://github.com/868-no/map/blob/main/LICENSE")!
    static let upstreamNoticesURL = URL(string: "https://github.com/868-no/map/blob/main/THIRD_PARTY_NOTICES.md")!
    static let upstreamPrivacyURL = URL(string: "\(webOrigin)/privacy.html")!
    static let linkSimURL = URL(string: "https://linksim.link/")!
}

/// The imagery behind the Satellite map layer.
///
/// Tiles are fetched by the app (never by the page), so a provider that needs
/// an API key can be used by putting the key in `tileURLTemplate`.
struct SatelliteProvider: Equatable, Sendable {
    /// XYZ tile URL with `{z}`, `{x}` and `{y}`.
    var tileURLTemplate: String
    /// Deepest zoom the provider has tiles for; the map upscales beyond it.
    var maxZoom: Int
    /// Shown whenever the layer is on.
    var attribution: String
    var attributionURL: URL
    var licenseName: String
    var licenseURL: URL

    /// Sentinel-2 cloudless 2017 by EOX: 10 m imagery of the whole world,
    /// released under CC BY 4.0 and served without an account or key.
    static let sentinel2Cloudless = SatelliteProvider(
        tileURLTemplate: "https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2017_3857/default/g/{z}/{y}/{x}.jpg",
        maxZoom: 14,
        attribution: "Sentinel-2 cloudless by EOX IT Services GmbH (contains modified Copernicus Sentinel data 2017)",
        attributionURL: URL(string: "https://s2maps.eu")!,
        licenseName: "CC BY 4.0",
        licenseURL: URL(string: "https://creativecommons.org/licenses/by/4.0/")!
    )

    static let current = sentinel2Cloudless

    /// The tile's address at the provider, or nil for a tile that cannot exist.
    func tileURL(z: Int, x: Int, y: Int) -> URL? {
        guard (0...22).contains(z), x >= 0, y >= 0, x < (1 << z), y < (1 << z) else { return nil }
        let text = tileURLTemplate
            .replacingOccurrences(of: "{z}", with: String(z))
            .replacingOccurrences(of: "{x}", with: String(x))
            .replacingOccurrences(of: "{y}", with: String(y))
        guard let url = URL(string: text), url.scheme == "https" else { return nil }
        return url
    }
}
