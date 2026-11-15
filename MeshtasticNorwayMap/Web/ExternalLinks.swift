import Foundation

/// What the app does with a link that leaves the map.
enum ExternalAction: Equatable, Sendable {
    /// Shown in a browser sheet over the map (LinkSim, the source code, the privacy policy).
    case inAppBrowser(URL)
    /// Handed to the system: another app, such as Meshtastic or Mail.
    case system(URL)
    case ignore
}

enum ExternalLinks {
    /// Hosts whose https links belong to an app: opened by the system, so the app can claim them.
    private static let appLinkHosts: Set<String> = ["meshtastic.org", "www.meshtastic.org"]
    private static let systemSchemes: Set<String> = ["meshtastic", "mailto", "tel"]

    /// - Parameter pageURL: the map's current address, which names the selected node.
    static func action(for url: URL, pageURL: URL?) -> ExternalAction {
        if let publicURL = RequestRouter.publicURL(for: url) {
            // A page of the site opened in a window of its own (privacy policy, API docs).
            return .inAppBrowser(publicURL)
        }
        guard let scheme = url.scheme?.lowercased() else { return .ignore }
        switch scheme {
        case "https", "http":
            guard let host = url.host?.lowercased(), !host.isEmpty else { return .ignore }
            if appLinkHosts.contains(host) { return .system(url) }
            return .inAppBrowser(withLinkBack(url, pageURL: pageURL))
        case _ where systemSchemes.contains(scheme):
            return .system(url)
        default:
            return .ignore
        }
    }

    /// LinkSim shows a link back to where a site came from, and takes only
    /// https links. Inside the app the page builds its own links from the
    /// private scheme and so leaves it out: add the node's public link, as the
    /// site does in a browser.
    static func withLinkBack(_ url: URL, pageURL: URL?) -> URL {
        guard url.host?.lowercased() == AppConfig.linkSimURL.host,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              var items = parts.queryItems,
              items.contains(where: { $0.name == "site" && $0.value == "1" }),
              !items.contains(where: { $0.name == "sourceUrl" }),
              let pageURL, RequestRouter.isAppURL(pageURL),
              let node = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "node" })?.value,
              isNodeID(node) else { return url }
        items.append(URLQueryItem(name: "sourceUrl", value: "\(AppConfig.webOrigin)/?node=\(node)"))
        parts.queryItems = items
        return parts.url ?? url
    }

    /// A node id as the site's links carry it: `!` and 8 hex digits.
    static func isNodeID(_ text: String) -> Bool {
        text.count == 9 && text.first == "!" && text.dropFirst().allSatisfy { "0123456789abcdef".contains($0) }
    }
}
