import SwiftUI
import WidgetKit

/// The whole mesh today: nodes and gateways heard, new nodes, packets.
struct MeshTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Shared.meshWidgetKind, provider: MeshTodayProvider()) { entry in
            MeshTodayView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "\(Shared.urlScheme)://map"))
        }
        .configurationDisplayName("Mesh today")
        .description("Nodes and gateways heard on the Norwegian mesh today.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct MeshTodayEntry: TimelineEntry {
    var date: Date
    /// The newest day the site has, and the one before it; nil when the site could not be asked.
    var day: MeshAPI.MeshDay?
    var dayBefore: MeshAPI.MeshDay?

    static let sample = MeshTodayEntry(
        date: .now,
        day: MeshAPI.MeshDay(start: "", nodes: 227, gateways: 57, newNodes: 6, packets: 3481),
        dayBefore: MeshAPI.MeshDay(start: "", nodes: 256, gateways: 54, newNodes: 16, packets: 6806))

    /// "Today", or the day's date when the newest day is not today (the site has been down).
    var title: String {
        guard let day, let date = Self.date(day.start) else { return "Mesh today" }
        if Calendar.current.isDateInToday(date) { return "Mesh today" }
        return "Mesh " + date.formatted(.dateTime.day().month(.abbreviated))
    }

    static func date(_ text: String) -> Date? {
        try? Date(text, strategy: .iso8601)
    }
}

struct MeshTodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> MeshTodayEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (MeshTodayEntry) -> Void) {
        if context.isPreview {
            completion(.sample)
        } else {
            Task { completion(await Self.entry()) }
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MeshTodayEntry>) -> Void) {
        Task {
            let entry = await Self.entry()
            completion(Timeline(entries: [entry], policy: .after(WidgetRefresh.next(after: entry.date))))
        }
    }

    static func entry(api: MeshAPI = MeshAPI(client: "widget")) async -> MeshTodayEntry {
        guard let days = try? await api.meshDays(), let day = days.last else { return MeshTodayEntry(date: .now) }
        return MeshTodayEntry(date: .now, day: day, dayBefore: days.dropLast().last)
    }
}

struct MeshTodayView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MeshTodayEntry

    var body: some View {
        if let day = entry.day {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title).font(.caption.weight(.semibold))
                    Text("\(day.nodes ?? 0) nodes · \(day.gateways ?? 0) gateways").font(.caption2)
                    Text("\(day.newNodes ?? 0) new · \(day.packets ?? 0) packets").font(.caption2).foregroundStyle(.secondary)
                }
                .monospacedDigit()
            case .systemMedium:
                VStack(alignment: .leading, spacing: 8) {
                    header
                    HStack(alignment: .top, spacing: 0) {
                        Figure(value: day.nodes, label: "nodes", before: entry.dayBefore?.nodes)
                        Figure(value: day.gateways, label: "gateways", before: entry.dayBefore?.gateways)
                        Figure(value: day.newNodes, label: "new nodes", before: entry.dayBefore?.newNodes)
                        Figure(value: day.packets, label: "packets", before: entry.dayBefore?.packets)
                    }
                    Spacer(minLength: 0)
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    header
                    Figure(value: day.nodes, label: "nodes", before: nil)
                    Text("\(day.gateways ?? 0) gateways")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                }
            }
        } else {
            VStack(spacing: 4) {
                Text("Mesh today").font(family == .accessoryRectangular ? .caption : .subheadline.weight(.semibold))
                Text("map.868.no is not answering.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(entry.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if family != .systemSmall { SourceLine() }
        }
    }
}

/// A number with its label and, in the wide widget, the day before for comparison.
private struct Figure: View {
    let value: Int?
    let label: String
    let before: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value.map { $0.formatted(.number.notation(.compactName)) } ?? "–")
                .font(.title2.weight(.semibold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let before {
                Text("\(before.formatted(.number.notation(.compactName))) prev. day")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel("\(before) the day before")
            }
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
