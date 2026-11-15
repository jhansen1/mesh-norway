import Foundation

/// The public API of map.868.no, as far as the widgets and the background
/// check use it: the endpoints the site documents for other services
/// (`/api-docs.html`). Every field beyond the ones a view cannot do without is
/// optional, so an addition or a missing value on the server never breaks decoding.
struct MeshAPI: Sendable {
    /// One day of the whole mesh.
    struct MeshDay: Decodable, Equatable, Sendable {
        var start: String
        var nodes: Int?
        var gateways: Int?
        var newNodes: Int?
        var packets: Int?

        enum CodingKeys: String, CodingKey {
            case start, nodes, gateways, packets
            case newNodes = "new_nodes"
        }
    }

    /// One day of one node.
    struct NodeDay: Decodable, Equatable, Sendable {
        var start: String
        /// Hours of the day in which anything at all was logged.
        var hours: Int?
        /// Of those, hours in which the node sent anything.
        var hoursHeard: Int?
        var packets: Int?
        /// Lowest battery level (%); 101 means external power only.
        var batteryMin: Double?

        enum CodingKeys: String, CodingKey {
            case start, hours, packets
            case hoursHeard = "hours_heard"
            case batteryMin = "battery_min"
        }
    }

    private struct Buckets<Bucket: Decodable>: Decodable {
        var buckets: [Bucket]
    }

    private struct NodesBody: Decodable {
        struct Node: Decodable {
            struct Identity: Decodable {
                var longName: String?
                var shortName: String?

                enum CodingKeys: String, CodingKey {
                    case longName = "long_name"
                    case shortName = "short_name"
                }
            }

            var id: String
            var identity: Identity?
        }

        var nodes: [Node]
    }

    private struct Contact: Decodable {
        var longName: String?
        var shortName: String?

        enum CodingKeys: String, CodingKey {
            case longName = "long_name"
            case shortName = "short_name"
        }
    }

    enum Failure: Error {
        case badStatus(Int)
        case badRequest
    }

    private let session: URLSession
    private let userAgent: String

    /// - Parameter client: who is asking ("widget", "background"), named in the user agent for the site's operator.
    init(client: String, session: URLSession? = nil) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        userAgent = "MeshNorway/\(version) (\(client))"
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
            config.urlCredentialStorage = nil
            config.waitsForConnectivity = false
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 20
            self.session = URLSession(configuration: config)
        }
    }

    /// The mesh per day, oldest first.
    func meshDays() async throws -> [MeshDay] {
        try await get("trends", query: ["bucket": "day", "tz": TimeZone.current.identifier], as: Buckets<MeshDay>.self).buckets
    }

    /// A node per day, oldest first. Nil for a node the site has never heard.
    func nodeDays(id: String) async throws -> [NodeDay]? {
        guard Shared.isNodeID(id) else { throw Failure.badRequest }
        do {
            return try await get("trends/node/\(id)", query: ["bucket": "day", "tz": TimeZone.current.identifier], as: Buckets<NodeDay>.self).buckets
        } catch Failure.badStatus(404) {
            return nil
        }
    }

    /// Names of the nodes that reported a position in the last 14 days.
    func positionedNodeNames() async throws -> [String: String] {
        let body = try await get("nodes", query: ["duration": "336h"], as: NodesBody.self)
        var names: [String: String] = [:]
        for node in body.nodes where Shared.isNodeID(node.id) {
            if let name = Self.cleaned(node.identity?.longName) ?? Self.cleaned(node.identity?.shortName) { names[node.id] = name }
        }
        return names
    }

    /// The name in a node's contact link; nil when it has none.
    func contactName(id: String) async throws -> String? {
        guard Shared.isNodeID(id) else { throw Failure.badRequest }
        do {
            let contact = try await get("nodes/\(id)/contact", query: [:], as: Contact.self)
            return Self.cleaned(contact.longName) ?? Self.cleaned(contact.shortName)
        } catch Failure.badStatus(404) {
            return nil
        }
    }

    static func cleaned(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(60))
    }

    static func decodeNodeDays(_ data: Data) throws -> [NodeDay] {
        try JSONDecoder().decode(Buckets<NodeDay>.self, from: data).buckets
    }

    static func decodeMeshDays(_ data: Data) throws -> [MeshDay] {
        try JSONDecoder().decode(Buckets<MeshDay>.self, from: data).buckets
    }

    private func get<Body: Decodable>(_ path: String, query: [String: String], as type: Body.Type) async throws -> Body {
        guard var parts = URLComponents(url: Shared.apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw Failure.badRequest }
        if !query.isEmpty { parts.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = parts.url, url.scheme == "https", url.host == Shared.host else { throw Failure.badRequest }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.badStatus(0) }
        guard http.statusCode == 200 else { throw Failure.badStatus(http.statusCode) }
        return try JSONDecoder().decode(Body.self, from: data)
    }
}
