import Observation
import UIKit
import WebKit

/// The viewer's choices that the app itself keeps.
@MainActor
@Observable
final class AppSettings {
    private static let satelliteKey = "showsSatellite"
    @ObservationIgnored private let defaults: UserDefaults

    var showsSatellite: Bool {
        didSet { defaults.set(showsSatellite, forKey: Self.satelliteKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsSatellite = defaults.bool(forKey: Self.satelliteKey)
    }
}

struct BrowserPage: Identifiable, Equatable {
    let url: URL
    var id: URL { url }
}

/// The map: one web view showing map.868.no through `UpstreamProxy`, and what
/// the native interface around it needs to know.
@MainActor
@Observable
final class MapModel: NSObject {
    let settings: AppSettings
    let webView: WKWebView
    @ObservationIgnored let proxy: UpstreamProxy

    private(set) var isLoading = false
    private(set) var progress = 0.0
    /// Why the map could not be loaded, when it could not.
    private(set) var failure: String?
    /// The map has been shown at least once since the app started.
    private(set) var hasLoaded = false
    /// The page's own theme colour (light or dark), for the edges around it.
    private(set) var themeColor: UIColor?
    /// A page shown in the browser sheet.
    var browserPage: BrowserPage?
    /// A short message for the viewer.
    var notice: String?

    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var lastCrash: Date?

    /// Links the page copies or shares carry its public address, never the app's private scheme.
    private static let publicLinksScript = """
    (function () {
      var APP = '\(AppConfig.appOrigin)', WEB = '\(AppConfig.webOrigin)';
      function pub(s) { return typeof s === 'string' ? s.split(APP).join(WEB) : s; }
      try {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          var write = navigator.clipboard.writeText.bind(navigator.clipboard);
          navigator.clipboard.writeText = function (text) { return write(pub(text)); };
        }
      } catch (e) {}
      try {
        if (navigator.share) {
          var share = navigator.share.bind(navigator);
          navigator.share = function (data) {
            if (data && typeof data === 'object') {
              data = Object.assign({}, data);
              data.url = pub(data.url);
              data.text = pub(data.text);
            }
            return share(data);
          };
        }
      } catch (e) {}
    })();
    """

    /// The map's own "Reset and reload" promises to delete everything it has
    /// stored. Inside the app that includes the copies the app keeps in the
    /// service worker's place, so the page's reset (which starts by clearing
    /// local storage) also asks the app to forget them.
    private static let resetScript = """
    (function () {
      try {
        var clear = Storage.prototype.clear;
        Storage.prototype.clear = function () {
          if (this === window.localStorage) {
            try { fetch('\(AppConfig.clearSavedCopiesPath)', { method: 'POST', keepalive: true }).catch(function () {}); } catch (e) {}
          }
          return clear.apply(this, arguments);
        };
      } catch (e) {}
    })();
    """

    /// WKWebView has no Notification API, so the map would not offer "Notify
    /// me" for watched nodes. This stands in for it: the page's notifications
    /// go to the app, which shows them as iOS notifications.
    private static let notificationScript = """
    (function () {
      if ('Notification' in window) return;
      var permission = 'default';
      function sync(method) {
        return fetch('\(AppConfig.notifyPermissionPath)', { method: method })
          .then(function (r) { return r.json(); })
          .then(function (j) { if (j && typeof j.permission === 'string') permission = j.permission; return permission; })
          .catch(function () { return permission; });
      }
      function Notification(title, options) {
        if (!(this instanceof Notification)) throw new TypeError("Failed to construct 'Notification'");
        options = options || {};
        this.title = String(title);
        this.body = options.body === undefined ? '' : String(options.body);
        this.tag = options.tag === undefined ? '' : String(options.tag);
        this.onclick = this.onclose = this.onerror = this.onshow = null;
        try {
          fetch('\(AppConfig.notifyPath)', { method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ title: this.title, body: this.body, tag: this.tag }) }).catch(function () {});
        } catch (e) {}
      }
      Notification.prototype.close = function () {};
      Notification.prototype.addEventListener = function () {};
      Notification.prototype.removeEventListener = function () {};
      Object.defineProperty(Notification, 'permission', { get: function () { return permission; } });
      Notification.requestPermission = function (callback) {
        var asked = sync('POST');
        if (typeof callback === 'function') asked.then(callback);
        return asked;
      };
      window.Notification = Notification;
      sync('GET');
    })();
    """

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        proxy = UpstreamProxy(isSatelliteOn: { AppConfig.satelliteLayerAvailable && settings.showsSatellite })

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(proxy, forURLScheme: AppConfig.scheme)
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.publicLinksScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.notificationScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.resetScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.addUserScript(
            WKUserScript(source: MapZoom.fixedPageScaleScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.backgroundColor = .systemBackground
        webView.underPageBackgroundColor = .systemBackground
        #if DEBUG
        webView.isInspectable = true
        #endif

        // A pinch on a trackpad is not a touch: the page never sees it, and the
        // web view would magnify the whole page. The page keeps its size, and
        // the pinch is passed to the map as the zoom gesture it understands.
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(trackpadPinched(_:)))
        pinch.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        pinch.delegate = self
        webView.addGestureRecognizer(pinch)

        #if DEBUG
        Diagnostics.syncWatchList = { [weak self] in await self?.syncWatchList() }
        #endif

        observations = [
            webView.observe(\.estimatedProgress) { [weak self] _, _ in
                Task { @MainActor in self?.syncLoadingState() }
            },
            webView.observe(\.isLoading) { [weak self] _, _ in
                Task { @MainActor in self?.syncLoadingState() }
            },
            webView.observe(\.themeColor) { [weak self] _, _ in
                Task { @MainActor in self?.syncLoadingState() }
            },
        ]
    }

    private func syncLoadingState() {
        progress = webView.estimatedProgress
        isLoading = webView.isLoading
        themeColor = webView.themeColor
    }

    @ObservationIgnored private var lastPinchScale: CGFloat = 1

    @objc private func trackpadPinched(_ pinch: UIPinchGestureRecognizer) {
        switch pinch.state {
        case .began:
            lastPinchScale = 1
        case .changed:
            let ratio = pinch.scale / lastPinchScale
            lastPinchScale = pinch.scale
            guard let script = MapZoom.script(ratio: ratio, at: pinch.location(in: webView)) else { return }
            webView.evaluateJavaScript(script, completionHandler: nil)
        default:
            break
        }
    }

    // MARK: Actions

    func loadHome() {
        failure = nil
        webView.load(URLRequest(url: AppConfig.homeURL))
    }

    /// Load the page again where it is; the page restores its own view of the map.
    func reload() {
        failure = nil
        if let url = webView.url, RequestRouter.isAppURL(url) {
            webView.load(URLRequest(url: url))
        } else {
            loadHome()
        }
    }

    /// The satellite layer is part of the map style the page loads at start,
    /// so switching it on or off loads the page again.
    func setSatellite(_ on: Bool) {
        guard settings.showsSatellite != on else { return }
        settings.showsSatellite = on
        reload()
    }

    /// Show a node on the map, as its permanent link does.
    func showNode(_ id: String) {
        guard Shared.isNodeID(id), let url = URL(string: "\(AppConfig.appOrigin)/?node=\(id)") else { return }
        failure = nil
        browserPage = nil
        webView.load(URLRequest(url: url))
    }

    /// Reads the map's watchlist from the page, for the background check and the widget.
    func syncWatchList() async {
        guard hasLoaded, let url = webView.url, RequestRouter.isAppURL(url) else { return }
        let script = "try { return localStorage.getItem('meshmap.watch'); } catch (e) { return undefined; }"
        guard let result = try? await webView.callAsyncJavaScript(script, contentWorld: .page) else { return }
        // No answer at all (storage unavailable) leaves the list as it was.
        let json = result as? String
        guard json != nil || result is NSNull else { return }
        if WatchMonitor.shared.update(watchList: WatchList.parse(json: json)) {
            await WatchMonitor.shared.check(force: true)
        }
    }

    func clearSavedCopies() {
        proxy.clearSavedCopies()
        notice = "The saved offline copy was cleared."
    }

    func open(_ url: URL) {
        switch ExternalLinks.action(for: url, pageURL: webView.url) {
        case .inAppBrowser(let page):
            browserPage = BrowserPage(url: page)
        case .system(let target):
            UIApplication.shared.open(target, options: [:]) { [weak self] opened in
                guard !opened else { return }
                Task { @MainActor in
                    self?.notice = target.scheme?.lowercased() == "meshtastic"
                        ? "The Meshtastic app is not installed on this device."
                        : "This link could not be opened."
                }
            }
        case .ignore:
            break
        }
    }

    private func presenter() -> UIViewController? {
        var controller = webView.window?.rootViewController
        while let presented = controller?.presentedViewController, !presented.isBeingDismissed {
            controller = presented
        }
        return controller
    }
}

// MARK: - Navigation

extension MapModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        let opensWindow = navigationAction.targetFrame == nil
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false

        // Every load of the page says that it is this app asking, also the page's own reloads.
        if isMainFrame, let marked = RequestRouter.markedPageURL(for: url) {
            webView.load(URLRequest(url: marked))
            return .cancel
        }
        if !opensWindow, RequestRouter.isAppURL(url) { return .allow }
        if !opensWindow, !isMainFrame {
            // The site has no frames; an empty one is harmless, anything else is not its own.
            return url.scheme?.lowercased() == "about" ? .allow : .cancel
        }
        // A link out of the map: never loaded in its place.
        if opensWindow || navigationAction.navigationType == .linkActivated {
            open(url)
        }
        return .cancel
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        failure = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasLoaded = true
        Task { await syncWatchList() }
        // The web view sets its zoom gesture up again for every page.
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        #if DEBUG
        Diagnostics.runIfRequested(on: webView)
        #endif
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        report(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // The system ended the page's process (usually for memory): start it
        // again, unless it keeps happening.
        let now = Date()
        if let lastCrash, now.timeIntervalSince(lastCrash) < 15 {
            failure = "The map stopped unexpectedly."
        } else {
            reload()
        }
        lastCrash = now
    }

    private func report(_ error: any Error) {
        let nsError = error as NSError
        // A navigation the app or a newer navigation cancelled is no failure.
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 { return }
        failure = nsError.localizedDescription
    }
}

extension MapModel: UIGestureRecognizerDelegate {
    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                       shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// Zooming the map from outside the page.
enum MapZoom {
    /// Keeps the page at its own size: only the map zooms.
    static let fixedPageScaleScript = """
    (function () {
      var meta = document.querySelector('meta[name="viewport"]');
      if (!meta) { meta = document.createElement('meta'); meta.name = 'viewport'; document.head.appendChild(meta); }
      meta.setAttribute('content', 'width=device-width, initial-scale=1.0, minimum-scale=1.0, maximum-scale=1.0, user-scalable=no');
    })();
    """

    /// A pinch step as the wheel events browsers send for a trackpad pinch
    /// (ctrl + wheel), which the map zooms on around the pointer. The map
    /// tells a trackpad from a mouse wheel by its small steps (under 4
    /// units), so a larger step is sent as several small ones. Measured on
    /// the map, about 139 units zoom it by one level, so a step that scales
    /// by `ratio` is 139 · log2(ratio) units.
    static func script(ratio: CGFloat, at point: CGPoint) -> String? {
        guard ratio.isFinite, ratio > 0, point.x.isFinite, point.y.isFinite else { return nil }
        let delta = -139 * log2(Double(min(max(ratio, 0.25), 4)))
        guard delta != 0 else { return nil }
        return """
        (function () {
          var x = \(Double(point.x)), y = \(Double(point.y));
          var target = document.elementFromPoint(x, y);
          if (!target) return;
          var total = \(delta), parts = Math.max(1, Math.ceil(Math.abs(total) / 3.5));
          for (var i = 0; i < parts; i++) {
            target.dispatchEvent(new WheelEvent('wheel', { deltaY: total / parts, deltaMode: 0, ctrlKey: true,
              clientX: x, clientY: y, bubbles: true, cancelable: true, view: window }));
          }
        })();
        """
    }
}

// MARK: - Windows and dialogs

extension MapModel: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { open(url) }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            guard let presenter = presenter() else { return continuation.resume() }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in continuation.resume() })
            presenter.present(alert, animated: true)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await withCheckedContinuation { continuation in
            guard let presenter = presenter() else { return continuation.resume(returning: false) }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in continuation.resume(returning: false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in continuation.resume(returning: true) })
            presenter.present(alert, animated: true)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo) async -> String? {
        await withCheckedContinuation { continuation in
            guard let presenter = presenter() else { return continuation.resume(returning: nil) }
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in continuation.resume(returning: nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
                continuation.resume(returning: alert?.textFields?.first?.text ?? "")
            })
            presenter.present(alert, animated: true)
        }
    }

    /// The map uses neither camera nor microphone.
    func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
                 initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
        .deny
    }
}

#if DEBUG
/// Development aid: launched with `-diagnostics`, the app logs what the page
/// can do under the private scheme. Not compiled into release builds.
@MainActor
enum Diagnostics {
    private static var ran = false
    static var syncWatchList: (@MainActor () async -> Void)?

    static func runIfRequested(on webView: WKWebView) {
        guard !ran, ProcessInfo.processInfo.arguments.contains("-diagnostics") else { return }
        ran = true
        let script = """
        return JSON.stringify({
          origin: location.origin, href: location.href, secure: window.isSecureContext,
          share: typeof navigator.share, clipboard: !!(navigator.clipboard && navigator.clipboard.writeText),
          sw: 'serviceWorker' in navigator, idb: typeof indexedDB, notification: 'Notification' in window,
          storage: (function(){ try { return Object.keys(localStorage); } catch (e) { return String(e); } })(),
          canvas: document.querySelectorAll('canvas').length,
          text: document.body.innerText.slice(0, 400),
          banners: Array.from(document.querySelectorAll('.banner')).map(function (b) { return b.textContent; }),
          attribution: (document.querySelector('.attribution') || {}).textContent || null,
          resources: performance.getEntriesByType('resource').length,
          satTiles: performance.getEntriesByType('resource').filter(function (r) { return r.name.indexOf('/__app/sat/') >= 0; }).length
        });
        """
        Task {
            try? await Task.sleep(for: .seconds(5))
            let view = "return localStorage.getItem('meshmap.view')"
            let before = try? await webView.callAsyncJavaScript(view, contentWorld: .page)
            let center = CGPoint(x: webView.bounds.midX, y: webView.bounds.midY)
            for _ in 0..<35 { // 1.02^35 = 2: one zoom level, in the small steps of a real pinch
                if let step = MapZoom.script(ratio: 1.02, at: center) { _ = try? await webView.evaluateJavaScript(step) }
                try? await Task.sleep(for: .milliseconds(16))
            }
            try? await Task.sleep(for: .seconds(2))
            let after = try? await webView.callAsyncJavaScript(view, contentWorld: .page)
            let scale = try? await webView.callAsyncJavaScript("return String(window.visualViewport ? visualViewport.scale : 1) + ' ' + document.querySelector('meta[name=viewport]').content", contentWorld: .page)
            NSLog("DIAGZOOM before=%@ after=%@ pageScale=%@ pinchEnabled=%@", String(describing: before ?? "nil"), String(describing: after ?? "nil"),
                  String(describing: scale ?? "nil"), String(describing: webView.scrollView.pinchGestureRecognizer?.isEnabled))
            if ProcessInfo.processInfo.arguments.contains("-diagnoseNotify") {
                // The page's own path to a notification, and the watchlist's way to the widget.
                let result = try? await webView.callAsyncJavaScript("""
                    localStorage.setItem('meshmap.watch', JSON.stringify({ ids: ['!a206ab04', '!0400a3ac'], notify: true }));
                    var before = Notification.permission;
                    var asked = await Notification.requestPermission();
                    new Notification('Test node (868.no Map)', { body: 'Heard again.', tag: 'meshmap-!a206ab04' });
                    return before + ' -> ' + asked + ' / ' + Notification.permission;
                    """, contentWorld: .page)
                NSLog("DIAGNOTIFY permission %@", String(describing: result ?? "nil"))
                await syncWatchList?()
                try? await Task.sleep(for: .seconds(6))
                let store = SharedStore()
                NSLog("DIAGNOTIFY watch=%@ names=%@ snapshots=%@", String(describing: store.watchList), String(describing: store.names),
                      String(describing: store.snapshots.mapValues { "\($0.hoursHeardToday)/\($0.hoursToday) h battery \(String(describing: $0.battery))" }))
            }
            if ProcessInfo.processInfo.arguments.contains("-diagnoseReset") {
                _ = try? await webView.callAsyncJavaScript("localStorage.clear(); return 1", contentWorld: .page)
            }
            for delay in [1, 8] {
                try? await Task.sleep(for: .seconds(delay))
                let result = try? await webView.callAsyncJavaScript(script, contentWorld: .page)
                NSLog("DIAG %@", String(describing: result ?? "nil"))
            }
        }
    }
}
#endif
