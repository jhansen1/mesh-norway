import Foundation

/// How the proxy answers a request from the page. The rules follow the web
/// app's own service worker (frontend/sw/sw.js in the 868.no Map source),
/// which cannot run under a private URL scheme, so the app does its job.
enum Route: Equatable, Sendable {
    /// Not a request the app serves.
    case reject
    /// The viewer reset the map: the app's saved copies go as well.
    case clearSavedCopies
    /// The page shows a notification.
    case notify
    /// The page asks whether it may notify (`ask`: and has the viewer asked, if not yet).
    case notifyPermission(ask: Bool)
    /// A tile of the satellite layer, fetched from the imagery provider.
    case satellite(z: Int, x: Int, y: Int)
    /// Straight to the site, no saved copy: tiles, the live stream, raw
    /// observations, health, and everything that is not a GET.
    case networkOnly
    /// API: the site's answer when it comes; the last good one, marked
    /// offline, when the site cannot be reached.
    case api
    /// A page. Every page that is not a file of its own is the app shell.
    case document(key: String)
    /// Files that keep their name across deploys: fresh when possible.
    case entry
    /// A map style: as `entry`, and rewritten when the satellite layer is on.
    case style
    /// Files named by their content, and fonts: a saved copy is never stale.
    case immutable

    /// How long the site may take before a saved copy is served instead.
    var fallbackTimeout: TimeInterval? {
        switch self {
        case .api: 8
        case .document, .entry, .style: 5
        case .reject, .clearSavedCopies, .notify, .notifyPermission, .satellite, .networkOnly, .immutable: nil
        }
    }

    /// Whether answers are saved for later.
    var keepsCopy: Bool {
        switch self {
        case .api, .document, .entry, .style, .immutable: true
        case .reject, .clearSavedCopies, .notify, .notifyPermission, .satellite, .networkOnly: false
        }
    }
}

enum RequestRouter {
    /// Whether the URL belongs to the page's origin inside the app.
    static func isAppURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == AppConfig.scheme
            && url.host?.lowercased() == AppConfig.host
            && url.port == nil
            && url.user == nil
    }

    /// The address at the real site for a URL of the page's origin.
    static func upstreamURL(for url: URL) -> URL? {
        guard isAppURL(url), var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = "https"
        parts.fragment = nil
        return parts.url
    }

    /// The page's address with the app's mark on it (`AppConfig.clientParameter`), or nil when the
    /// URL is not the page or carries the mark already.
    static func markedPageURL(for url: URL) -> URL? {
        guard isAppURL(url), url.path.isEmpty || url.path == "/",
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let mark = AppConfig.clientParameter
        var items = parts.queryItems ?? []
        if items.contains(where: { $0.name == mark.name && $0.value == mark.value }) { return nil }
        items.removeAll { $0.name == mark.name }
        items.append(URLQueryItem(name: mark.name, value: mark.value))
        parts.queryItems = items
        return parts.url
    }

    /// The public (https) form of a URL of the page's origin.
    static func publicURL(for url: URL) -> URL? {
        guard isAppURL(url), var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = "https"
        return parts.url
    }

    static func route(method: String, url: URL, headers: [String: String]) -> Route {
        guard isAppURL(url) else { return .reject }
        let path = url.path.isEmpty ? "/" : url.path
        let isGet = method.uppercased() == "GET"

        if path.hasPrefix(AppConfig.satellitePathPrefix) {
            guard isGet, let tile = satelliteTile(path: path) else { return .reject }
            return .satellite(z: tile.z, x: tile.x, y: tile.y)
        }
        if path == AppConfig.clearSavedCopiesPath { return method.uppercased() == "POST" ? .clearSavedCopies : .reject }
        if path == AppConfig.notifyPath { return method.uppercased() == "POST" ? .notify : .reject }
        if path == AppConfig.notifyPermissionPath {
            switch method.uppercased() {
            case "GET": return .notifyPermission(ask: false)
            case "POST": return .notifyPermission(ask: true)
            default: return .reject
            }
        }
        // The rest of the app's own namespace is never passed on to the site.
        if path.hasPrefix("/__app/") { return .reject }
        guard isGet else { return .networkOnly }
        // A partial answer is never a copy worth keeping.
        if header("Range", in: headers) != nil { return .networkOnly }

        if path.hasPrefix("/tiles/") || path == "/api/v1/stream" || path == "/api/v1/observations"
            || path.hasPrefix("/api/v1/observations/") || path.hasPrefix("/health/") || path == "/metrics" {
            return .networkOnly
        }
        if path.hasPrefix("/api/") { return .api }
        if header("Accept", in: headers)?.lowercased().contains("text/html") == true {
            return .document(key: path.lowercased().hasSuffix(".html") ? path : "/index.html")
        }
        if path.hasPrefix("/fonts/") || path.hasPrefix("/assets/") { return .immutable }
        if path.hasPrefix("/styles/") { return .style }
        return .entry
    }

    /// The name a saved copy is kept under.
    static func cacheKey(route: Route, url: URL) -> String? {
        switch route {
        case .document(let key):
            return "document:" + key
        case .api, .entry, .style, .immutable:
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let path = parts?.percentEncodedPath ?? url.path
            if let query = parts?.percentEncodedQuery, !query.isEmpty { return path + "?" + query }
            return path
        case .reject, .clearSavedCopies, .notify, .notifyPermission, .satellite, .networkOnly:
            return nil
        }
    }

    /// Whether an answer may be kept as the saved copy for its route.
    static func shouldKeep(route: Route, status: Int, contentType: String?) -> Bool {
        guard route.keepsCopy, status == 200 else { return false }
        let isHTML = contentType?.lowercased().contains("text/html") == true
        switch route {
        case .document: return isHTML
        // Never a page standing in for a script, a style or data.
        default: return !isHTML
        }
    }

    /// A proxy's answer while the backend behind it is down. The backend's own
    /// errors are problem+json: its 503 means it is up and the page should retry.
    static func isGatewayDown(status: Int, contentType: String?) -> Bool {
        [502, 503, 504].contains(status) && contentType?.lowercased().contains("application/problem+json") != true
    }

    // MARK: Headers

    private static let forwardedRequestHeaders: Set<String> = [
        "accept", "accept-language", "cache-control", "content-type", "if-match", "if-modified-since",
        "if-none-match", "if-range", "last-event-id", "pragma", "range",
    ]

    /// The page's request headers that are passed on to the site.
    static func upstreamHeaders(from headers: [String: String], method: String) -> [String: String] {
        var out: [String: String] = [:]
        for (name, value) in headers where forwardedRequestHeaders.contains(name.lowercased()) {
            out[name] = value
        }
        // The site sees its own origin, as it does from a browser.
        if method.uppercased() != "GET" && method.uppercased() != "HEAD" {
            out["Origin"] = AppConfig.webOrigin
        }
        out["Referer"] = AppConfig.webOrigin + "/"
        return out
    }

    private static let droppedResponseHeaders: Set<String> = [
        "alt-svc", "connection", "content-encoding", "keep-alive", "nel", "proxy-authenticate",
        "report-to", "set-cookie", "speculation-rules", "strict-transport-security", "transfer-encoding",
    ]

    /// The site's response headers as the page gets them. The body arrives
    /// already decoded, so its encoding and encoded length are dropped.
    static func clientHeaders(from headers: [AnyHashable: Any]) -> [String: String] {
        var out: [String: String] = [:]
        var encoded = false
        for (rawName, rawValue) in headers {
            guard let name = rawName as? String, let value = rawValue as? String else { continue }
            let lower = name.lowercased()
            if lower == "content-encoding", value.lowercased() != "identity" { encoded = true }
            if droppedResponseHeaders.contains(lower) { continue }
            out[name] = value
        }
        if encoded, let key = out.keys.first(where: { $0.lowercased() == "content-length" }) {
            out[key] = nil
        }
        return out
    }

    static func header(_ name: String, in headers: [String: String]) -> String? {
        let lower = name.lowercased()
        return headers.first { $0.key.lowercased() == lower }?.value
    }

    private static func satelliteTile(path: String) -> (z: Int, x: Int, y: Int)? {
        let parts = path.dropFirst(AppConfig.satellitePathPrefix.count).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.count <= 8 && $0.allSatisfy(\.isASCIIDigit) }),
              let z = Int(parts[0]), let x = Int(parts[1]), let y = Int(parts[2]),
              (0...22).contains(z), x < (1 << z), y < (1 << z) else { return nil }
        return (z, x, y)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
