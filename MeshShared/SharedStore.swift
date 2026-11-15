import Foundation

/// Identifiers the app and its widgets share.
enum Shared {
    static let appGroup = "group.no.meshnorway.map"
    static let host = "map.868.no"
    static let apiBase = URL(string: "https://map.868.no/api/v1/")!
    /// Opens the app on a node: `meshnorway://node/!a1b2c3d4`.
    static let urlScheme = "meshnorway"
    static let refreshTaskIdentifier = "no.meshnorway.map.refresh"
    static let watchedWidgetKind = "WatchedNodesWidget"
    static let meshWidgetKind = "MeshTodayWidget"
    /// Battery (%) at which a watched node's battery is called low, as on the map.
    static let batteryLow = 20

    /// A node id as the map writes it: `!` and 8 hex digits.
    static func isNodeID(_ text: String) -> Bool {
        text.count == 9 && text.first == "!" && text.dropFirst().allSatisfy { "0123456789abcdef".contains($0) }
    }

    static func nodeURL(_ id: String) -> URL? {
        isNodeID(id) ? URL(string: "\(urlScheme)://node/\(id)") : nil
    }

    /// The node a `meshnorway://node/…` link names.
    static func nodeID(from url: URL) -> String? {
        guard url.scheme?.lowercased() == urlScheme, url.host?.lowercased() == "node" else { return nil }
        let id = url.lastPathComponent
        return isNodeID(id) ? id : nil
    }
}

/// The map's watchlist, as the page keeps it (`meshmap.watch` in its local storage).
struct WatchList: Codable, Equatable, Sendable {
    static let maxNodes = 30

    var ids: [String] = []
    /// The viewer ticked "Notify me" on the map.
    var notify = false

    /// Reads what the page stored; anything unreadable is an empty list.
    static func parse(json: String?) -> WatchList {
        struct Raw: Decodable {
            var ids: [String]?
            var notify: Bool?
        }
        guard let data = json?.data(using: .utf8), let raw = try? JSONDecoder().decode(Raw.self, from: data) else { return WatchList() }
        var seen = Set<String>()
        let ids = (raw.ids ?? []).filter { Shared.isNodeID($0) && seen.insert($0).inserted }
        return WatchList(ids: Array(ids.prefix(maxNodes)), notify: raw.notify == true)
    }
}

/// What the app last knew about a watched node, for the widget and for telling what changed.
struct NodeSnapshot: Codable, Equatable, Sendable {
    /// Per day bucket (its start, as the API writes it): hours with data, and hours the node was heard in.
    var buckets: [String: BucketCount] = [:]
    /// Hours with data, in a row, in which the node was not heard.
    var quietHours = 0
    /// The viewer has been told that the node went quiet.
    var toldQuiet = false
    /// The viewer has been told that the battery is low.
    var toldBatteryLow = false
    /// Today so far.
    var hoursToday = 0
    var hoursHeardToday = 0
    /// Lowest battery level today (%); nil when it reported none or runs on external power.
    var battery: Int?
    var checkedAt = Date.distantPast

    struct BucketCount: Codable, Equatable, Sendable {
        var hours: Int
        var heard: Int
    }
}

/// State shared between the app and its widgets, in the app group's defaults.
/// Without the app group (an unsigned build), each side falls back to its own
/// defaults: the app works, and the widget shows no watched nodes.
struct SharedStore: @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: Shared.appGroup) ?? .standard
    }

    var watchList: WatchList {
        get { read("watchList") ?? WatchList() }
        nonmutating set { write(newValue, "watchList") }
    }

    /// Node id to name, for the nodes whose name is known.
    var names: [String: String] {
        get { read("names") ?? [:] }
        nonmutating set { write(newValue, "names") }
    }

    var snapshots: [String: NodeSnapshot] {
        get { read("snapshots") ?? [:] }
        nonmutating set { write(newValue, "snapshots") }
    }

    var namesFetchedAt: Date {
        get { defaults.object(forKey: "namesFetchedAt") as? Date ?? .distantPast }
        nonmutating set { defaults.set(newValue, forKey: "namesFetchedAt") }
    }

    func name(of id: String) -> String {
        names[id] ?? id
    }

    private func read<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
