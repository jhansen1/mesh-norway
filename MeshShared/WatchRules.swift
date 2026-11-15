import Foundation

/// What changed for a watched node between two checks, and what to tell the viewer.
///
/// The map itself works this out from every packet while it is open. Away from
/// the map the app has the site's daily history of a node: for each day, the
/// hours in which the site logged anything and the hours in which the node was
/// heard. Between two checks, hours that passed without the node being heard
/// add to its quiet time; an hour in which it was heard ends it.
enum WatchRules {
    /// What a check found worth telling.
    enum Event: Equatable, Sendable {
        case quiet(hours: Int)
        case heardAgain
        case batteryLow(percent: Int)

        /// The text, worded as the map words its own notifications.
        var text: String {
            switch self {
            case .quiet(let hours): "Not heard for about \(hours) h."
            case .heardAgain: "Heard again."
            case .batteryLow(let percent): "Battery down to \(percent) %."
            }
        }
    }

    /// How many days back the hours are compared: today, and yesterday for a check that spans midnight.
    static let comparedDays = 3
    /// A node heard in at least half of the hours counts as heard regularly.
    static let regularShare = 0.5
    /// Quiet hours before the viewer is told: for a node heard regularly, and for one that is not.
    static let quietHoursRegular = 6
    static let quietHoursSporadic = 24

    /// - Parameters:
    ///   - previous: what the last check left; nil for a node checked for the first time (its baseline: nothing is told).
    ///   - days: the node's daily history, oldest first.
    static func check(previous: NodeSnapshot?, days: [MeshAPI.NodeDay], now: Date) -> (snapshot: NodeSnapshot, events: [Event]) {
        var next = previous ?? NodeSnapshot()
        var events: [Event] = []
        let recent = days.suffix(comparedDays)

        // Hours that passed, and hours the node was heard in, since the last check.
        var passed = 0
        var heard = 0
        var counts: [String: NodeSnapshot.BucketCount] = [:]
        for day in recent {
            let count = NodeSnapshot.BucketCount(hours: max(day.hours ?? 0, 0), heard: max(day.hoursHeard ?? 0, 0))
            counts[day.start] = count
            let before = previous?.buckets[day.start] ?? NodeSnapshot.BucketCount(hours: 0, heard: 0)
            passed += max(count.hours - before.hours, 0)
            heard += max(count.heard - before.heard, 0)
        }
        next.buckets = counts

        if previous != nil {
            if heard > 0 {
                if next.toldQuiet { events.append(.heardAgain) }
                next.quietHours = 0
                next.toldQuiet = false
            } else if passed > 0 {
                next.quietHours += passed
                if !next.toldQuiet, next.quietHours >= quietThreshold(days: days) {
                    events.append(.quiet(hours: next.quietHours))
                    next.toldQuiet = true
                }
            }
        }

        let today = days.last
        next.hoursToday = max(today?.hours ?? 0, 0)
        next.hoursHeardToday = max(today?.hoursHeard ?? 0, 0)
        // 101 means external power only: no battery to speak of.
        if let level = today?.batteryMin, level.isFinite, level >= 0, level <= 100 {
            let percent = Int(level.rounded())
            next.battery = percent
            let low = percent <= Shared.batteryLow
            if low, !next.toldBatteryLow, previous != nil { events.append(.batteryLow(percent: percent)) }
            next.toldBatteryLow = low
        } else {
            next.battery = nil
            // No reading today says nothing about the battery: what was told stands.
        }
        next.checkedAt = now
        return (next, events)
    }

    /// Quiet hours after which the viewer is told, from how regularly the node
    /// was heard over the last full week (today left out).
    static func quietThreshold(days: [MeshAPI.NodeDay]) -> Int {
        let week = days.dropLast().suffix(7)
        let hours = week.reduce(0) { $0 + max($1.hours ?? 0, 0) }
        let heard = week.reduce(0) { $0 + max($1.hoursHeard ?? 0, 0) }
        guard hours > 0 else { return quietHoursSporadic }
        return Double(heard) / Double(hours) >= regularShare ? quietHoursRegular : quietHoursSporadic
    }
}
