import BackgroundTasks
import Foundation
import WidgetKit

/// Looks after the watched nodes while the map is closed: asks the site how
/// each has been heard, tells the viewer what changed (when they ticked
/// "Notify me" on the map), and leaves the result for the widget.
@MainActor
final class WatchMonitor {
    static let shared = WatchMonitor()

    private let store: SharedStore
    private let api: MeshAPI
    private var isChecking = false
    private var lastCheck = Date.distantPast

    /// The site's answers are cached for an hour: asking more often learns nothing.
    private static let minimumInterval: TimeInterval = 15 * 60
    private static let refreshInterval: TimeInterval = 60 * 60
    private static let namesInterval: TimeInterval = 24 * 60 * 60

    init(store: SharedStore = SharedStore(), api: MeshAPI = MeshAPI(client: "background")) {
        self.store = store
        self.api = api
    }

    /// Takes the watchlist the map has now. Returns whether it changed.
    @discardableResult
    func update(watchList: WatchList) -> Bool {
        guard store.watchList != watchList else { return false }
        store.watchList = watchList
        // Nothing is kept about nodes that are no longer watched.
        let watched = Set(watchList.ids)
        store.snapshots = store.snapshots.filter { watched.contains($0.key) }
        store.namesFetchedAt = .distantPast // a new node may need its name
        WidgetCenter.shared.reloadTimelines(ofKind: Shared.watchedWidgetKind)
        return true
    }

    /// Asks iOS for time in the background; iOS decides when, and how often.
    func scheduleBackgroundRefresh() {
        guard !store.watchList.ids.isEmpty else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Shared.refreshTaskIdentifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: Shared.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.refreshInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// One round over the watched nodes.
    /// - Parameter force: also when the last round was moments ago (the watchlist just changed).
    func check(force: Bool = false) async {
        let watch = store.watchList
        guard !watch.ids.isEmpty, !isChecking else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastCheck) >= Self.minimumInterval else { return }
        isChecking = true
        lastCheck = now
        defer { isChecking = false }

        await refreshNames(for: watch.ids, now: now)

        var snapshots = store.snapshots
        var told: [(id: String, events: [WatchRules.Event])] = []
        for id in watch.ids {
            if Task.isCancelled { break }
            // A node that cannot be asked about now keeps what was known.
            guard let days = try? await api.nodeDays(id: id) else { continue }
            let result = WatchRules.check(previous: snapshots[id], days: days, now: now)
            snapshots[id] = result.snapshot
            if !result.events.isEmpty { told.append((id, result.events)) }
        }
        store.snapshots = snapshots
        WidgetCenter.shared.reloadTimelines(ofKind: Shared.watchedWidgetKind)

        guard watch.notify, await Notifier.shared.isAllowed() else { return }
        for (id, events) in told {
            await Notifier.shared.post(title: "\(store.name(of: id)) (868.no Map)",
                                       body: events.map(\.text).joined(separator: "\n"),
                                       tag: Notifier.tag(forNode: id))
        }
    }

    /// Names for the widget and for notifications: once a day, and when the watchlist changes.
    private func refreshNames(for ids: [String], now: Date) async {
        guard now.timeIntervalSince(store.namesFetchedAt) >= Self.namesInterval else { return }
        var names = store.names
        if let listed = try? await api.positionedNodeNames() {
            for id in ids { if let name = listed[id] { names[id] = name } }
        }
        // Nodes that report no position are not in that list: their contact link has the name.
        for id in ids where names[id] == nil {
            if Task.isCancelled { break }
            if let name = try? await api.contactName(id: id) { names[id] = name }
        }
        store.names = names.filter { ids.contains($0.key) }
        store.namesFetchedAt = now
    }
}
