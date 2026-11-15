import SwiftUI
import WidgetKit

/// The nodes watched on the map: how each has been heard today, and its battery.
struct WatchedNodesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Shared.watchedWidgetKind, provider: WatchedNodesProvider()) { entry in
            WatchedNodesView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Watched nodes")
        .description("The nodes you watch on the map: hours heard today and battery.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct WatchedNode: Identifiable, Equatable {
    var id: String
    var name: String
    /// Hours with data today, and hours the node was heard in; nil when nothing is known yet.
    var hours: Int?
    var heard: Int?
    var battery: Int?
    /// Hours in a row without being heard, once the viewer would be told about it.
    var quietHours: Int?
}

struct WatchedNodesEntry: TimelineEntry {
    var date: Date
    var nodes: [WatchedNode]
    /// More nodes are watched than any size of the widget shows.
    var total: Int

    static let sample = WatchedNodesEntry(date: .now, nodes: [
        WatchedNode(id: "!00000001", name: "Hilltop router", hours: 13, heard: 13, battery: 87),
        WatchedNode(id: "!00000002", name: "Cabin", hours: 13, heard: 9, battery: 18),
        WatchedNode(id: "!00000003", name: "Harbour gateway", hours: 13, heard: 2, quietHours: 8),
    ], total: 3)
}

struct WatchedNodesProvider: TimelineProvider {
    /// The most rows any size shows; nodes beyond are not asked about.
    private static let maxRows = 7

    func placeholder(in context: Context) -> WatchedNodesEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (WatchedNodesEntry) -> Void) {
        if context.isPreview {
            completion(.sample)
        } else {
            Task { completion(await Self.entry()) }
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchedNodesEntry>) -> Void) {
        Task {
            let entry = await Self.entry()
            completion(Timeline(entries: [entry], policy: .after(WidgetRefresh.next(after: entry.date))))
        }
    }

    static func entry(store: SharedStore = SharedStore(), api: MeshAPI = MeshAPI(client: "widget")) async -> WatchedNodesEntry {
        let watch = store.watchList
        let snapshots = store.snapshots
        var nodes: [WatchedNode] = []
        for id in watch.ids.prefix(maxRows) {
            let saved = snapshots[id]
            var node = WatchedNode(id: id, name: store.name(of: id))
            if let saved, saved.checkedAt > .distantPast {
                node.hours = saved.hoursToday
                node.heard = saved.hoursHeardToday
                node.battery = saved.battery
                if saved.toldQuiet { node.quietHours = saved.quietHours }
            }
            // Fresher than what the app last saw, when the site answers.
            if let today = (try? await api.nodeDays(id: id))?.last {
                node.hours = max(today.hours ?? 0, 0)
                node.heard = max(today.hoursHeard ?? 0, 0)
                if let level = today.batteryMin, level.isFinite, level >= 0, level <= 100 { node.battery = Int(level.rounded()) }
            }
            nodes.append(node)
        }
        return WatchedNodesEntry(date: .now, nodes: nodes, total: watch.ids.count)
    }
}

struct WatchedNodesView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchedNodesEntry

    private var rows: Int {
        switch family {
        case .systemLarge: 7
        case .accessoryRectangular: 2
        default: 3
        }
    }

    var body: some View {
        if entry.nodes.isEmpty {
            empty
        } else if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(entry.nodes.prefix(rows)) { NodeRow(node: $0, compact: true) }
            }
            .widgetURL(Shared.nodeURL(entry.nodes[0].id))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Watched nodes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    SourceLine()
                }
                .padding(.bottom, 6)
                ForEach(entry.nodes.prefix(rows)) { node in
                    if let url = Shared.nodeURL(node.id) {
                        Link(destination: url) { NodeRow(node: node, compact: false) }
                    } else {
                        NodeRow(node: node, compact: false)
                    }
                    if node.id != entry.nodes.prefix(rows).last?.id { Divider().padding(.vertical, 3) }
                }
                Spacer(minLength: 0)
                if entry.total > rows {
                    Text("and \(entry.total - rows) more on the map")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Text("No watched nodes")
                .font(family == .accessoryRectangular ? .caption : .subheadline.weight(.semibold))
            Text("Watch a node on the map to see it here.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct NodeRow: View {
    let node: WatchedNode
    let compact: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(node.name)
                .font(compact ? .caption : .subheadline)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let battery = node.battery, !compact || node.quietHours == nil {
                Text("\(battery) %")
                    .foregroundStyle(battery <= Shared.batteryLow ? Color.red : Color.secondary)
            }
            status
        }
        .font(compact ? .caption2 : .caption)
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var status: some View {
        if let quiet = node.quietHours {
            Text("quiet \(quiet) h")
                .foregroundStyle(.orange)
        } else if let hours = node.hours, let heard = node.heard {
            Text("\(heard)/\(hours) h")
                .foregroundStyle(heard == 0 && hours > 0 ? Color.orange : Color.secondary)
                .accessibilityLabel("heard in \(heard) of \(hours) hours today")
        } else {
            Text("no data")
                .foregroundStyle(.tertiary)
        }
    }
}
