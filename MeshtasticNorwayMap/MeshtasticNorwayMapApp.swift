import SwiftUI

@main
struct MeshtasticNorwayMapApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        guard !Self.isRunningUnitTests else { return }
        Notifier.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            if Self.isRunningUnitTests {
                // Unit tests are hosted by the app: no map, no network.
                Color.clear
            } else {
                RootView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard !Self.isRunningUnitTests else { return }
            switch phase {
            case .active:
                Task { await WatchMonitor.shared.check() }
            case .background:
                WatchMonitor.shared.scheduleBackgroundRefresh()
            default:
                break
            }
        }
        // iOS runs this now and then while the app is closed: one round over the watched nodes.
        .backgroundTask(.appRefresh(Shared.refreshTaskIdentifier)) {
            await WatchMonitor.shared.scheduleBackgroundRefresh()
            await WatchMonitor.shared.check(force: true)
        }
    }

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
