import SwiftUI
import WidgetKit

@main
struct MeshNorwayWidgets: WidgetBundle {
    var body: some Widget {
        WatchedNodesWidget()
        MeshTodayWidget()
    }
}

/// When a widget asks the site again. The site's answers are cached for an
/// hour, and iOS spreads widget updates as it sees fit.
enum WidgetRefresh {
    static func next(after date: Date) -> Date { date.addingTimeInterval(45 * 60) }
}

/// The line every widget carries: whose data it shows.
struct SourceLine: View {
    var body: some View {
        Text("map.868.no")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}
