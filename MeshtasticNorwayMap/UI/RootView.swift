import SafariServices
import SwiftUI
import WebKit

/// The map, edge to edge inside the safe area, with nothing of the app's own
/// around it. The app's own screens (the opening credit, About, a failure
/// message) appear over the map only when they are needed.
struct RootView: View {
    @State private var model = MapModel()
    @State private var showsAbout = false
    @State private var creditHasBeenRead = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ZStack {
                    WebViewContainer(webView: model.webView)
                    if let failure = model.failure {
                        FailureView(message: failure, retry: { model.reload() }, about: { showsAbout = true })
                    } else if !(model.hasLoaded && creditHasBeenRead) {
                        OpeningView()
                            .transition(.opacity)
                    }
                }
                // The strip around the home indicator, otherwise empty, carries the credit.
                CreditLine(about: { showsAbout = true })
                    .frame(height: max(geometry.safeAreaInsets.bottom, 20), alignment: .top)
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .animation(.easeOut(duration: 0.35), value: model.hasLoaded && creditHasBeenRead)
        .background(edgeColor.ignoresSafeArea())
        // The web view moves its own content clear of the keyboard.
        .ignoresSafeArea(.keyboard)
        .task {
            model.loadHome()
            // Long enough to read who made the map, even on a fast connection.
            try? await Task.sleep(for: .seconds(1.5))
            creditHasBeenRead = true
        }
        // A tapped notification or widget names a node: show it.
        .onChange(of: Notifier.shared.requestedNode, initial: true) { _, node in
            guard let node else { return }
            Notifier.shared.requestedNode = nil
            showsAbout = false
            model.showNode(node)
        }
        .onOpenURL { url in
            if let node = Shared.nodeID(from: url) { Notifier.shared.requestedNode = node }
        }
        // Leaving the map: take its watchlist along for the widget and the background check.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await model.syncWatchList() } }
        }
        .sheet(isPresented: $showsAbout) {
            AboutView(model: model)
        }
        .sheet(item: $model.browserPage) { page in
            SafariView(url: page.url).ignoresSafeArea()
        }
        .alert("Mesh Norway", isPresented: noticeIsShown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.notice ?? "")
        }
    }

    /// The colour around the map (behind the status bar and the home
    /// indicator): the page's own theme colour, so the map and its edges are
    /// one surface. When the viewer has picked a theme in the map that differs
    /// from the system's, the system's background is used instead, so the
    /// status bar stays readable.
    private var edgeColor: Color {
        guard model.hasLoaded, model.failure == nil, let theme = model.themeColor else { return Color(.systemBackground) }
        var white: CGFloat = 0
        var alpha: CGFloat = 0
        guard theme.getWhite(&white, alpha: &alpha), (white < 0.5) == (colorScheme == .dark) else { return Color(.systemBackground) }
        return Color(theme)
    }

    private var noticeIsShown: Binding<Bool> {
        Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })
    }
}

/// Shown while the map loads: what the app is and who made the map.
private struct OpeningView: View {
    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("Mesh Norway")
                .font(.title2.bold())
            Text("An unofficial app for map.868.no")
                .foregroundStyle(.secondary)
            ProgressView()
                .padding(.top, 16)
                .accessibilityLabel("Loading the map")
            Spacer()
            Text("The map is the work of the \(AppConfig.upstreamProjectName) project,\ncreated by \(AppConfig.upstreamAuthor) and contributors.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("openingCredit")
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

/// One quiet line under the map: whose map it is, and the way to the full credits.
private struct CreditLine: View {
    let about: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Unofficial app · map.868.no by \(AppConfig.upstreamAuthor)")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier("creditLine")
            Spacer(minLength: 12)
            Button("About", action: about)
                .accessibilityIdentifier("aboutButton")
        }
        .font(.caption2)
        // Clear of the screen's rounded corners.
        .padding(.horizontal, 30)
        .padding(.top, 2)
    }
}

private struct FailureView: View {
    let message: String
    let retry: () -> Void
    let about: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("The map could not be loaded", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
            Button("About and credits", action: about)
                .font(.footnote)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

/// Hosts the model's one web view.
private struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
