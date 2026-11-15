import Foundation
import WebKit

/// Serves the page's origin (`meshmap://map.868.no`) from the real site.
///
/// Every request the page makes arrives here. It is passed to
/// https://map.868.no and the answer is streamed back, so the live event
/// stream and the basemap's range requests work as in a browser. Along the way
/// the proxy keeps the copies the web app's service worker would keep (see
/// `Route`), adds the satellite layer to the map styles when it is switched on,
/// and answers the layer's tile requests from the imagery provider.
///
/// Everything runs on the main thread, including the URL sessions' callbacks:
/// a scheme task must never be touched after WebKit stops it, and with one
/// thread there is no window in which that can happen.
@MainActor
final class UpstreamProxy: NSObject, WKURLSchemeHandler {
    private final class Operation {
        let schemeTask: any WKURLSchemeTask
        let route: Route
        let url: URL
        let cacheKey: String?
        var dataTask: URLSessionDataTask?
        var timeout: DispatchWorkItem?
        var response: HTTPURLResponse?
        /// The scheme task has its answer, failed or was stopped: never touch it again.
        var closed = false
        var headSent = false
        /// The body is delivered whole at the end (a style being rewritten).
        var holdsBody = false
        var keepsCopy = false
        var body = Data()

        init(schemeTask: any WKURLSchemeTask, route: Route, url: URL, cacheKey: String?) {
            self.schemeTask = schemeTask
            self.route = route
            self.url = url
            self.cacheKey = cacheKey
        }
    }

    /// The app shell: pages, scripts, styles, fonts.
    let shellStore: OfflineStore
    /// The last API answers, for showing old data when offline.
    let dataStore: OfflineStore

    private let provider: SatelliteProvider
    private let isSatelliteOn: @MainActor () -> Bool
    private let userAgentSuffix: String
    private var upstream: URLSession!
    private var imagery: URLSession!
    private var byDataTask: [URLSessionTask: Operation] = [:]
    private var bySchemeTask: [ObjectIdentifier: Operation] = [:]
    /// Requests the app answers itself after a moment's work; a task WebKit stopped is no longer in here.
    private var ownTasks: Set<ObjectIdentifier> = []

    /// A style being rewritten is held in memory; no style is anywhere near this.
    private static let heldBodyLimit = 8 * 1024 * 1024

    init(provider: SatelliteProvider = .current, isSatelliteOn: @escaping @MainActor () -> Bool) {
        self.provider = provider
        self.isSatelliteOn = isSatelliteOn
        shellStore = OfflineStore(name: "shell", budgetBytes: 150 * 1024 * 1024, maxEntryBytes: 32 * 1024 * 1024)
        dataStore = OfflineStore(name: "data", budgetBytes: 30 * 1024 * 1024, maxEntryBytes: 10 * 1024 * 1024)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        userAgentSuffix = "MeshNorway/\(version)"
        super.init()
        upstream = Self.makeSession(delegate: self, cacheName: "upstream-http", diskCapacity: 256 * 1024 * 1024)
        imagery = Self.makeSession(delegate: self, cacheName: "satellite-http", diskCapacity: 256 * 1024 * 1024)
    }

    private static func makeSession(delegate: URLSessionDataDelegate, cacheName: String, diskCapacity: Int) -> URLSession {
        let config = URLSessionConfiguration.default
        // No accounts, no cookies: the site uses none and the app keeps none.
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCredentialStorage = nil
        // The HTTP cache a browser would have: tiles and whole days of
        // observations are kept and revalidated by the site's own headers.
        config.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: diskCapacity, directory: cacheDirectory(cacheName))
        config.requestCachePolicy = .useProtocolCachePolicy
        // Offline must fail at once, so a saved copy can answer.
        config.waitsForConnectivity = false
        // Longest silence on a connection; the live stream sends heartbeats.
        config.timeoutIntervalForRequest = 60
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: config, delegate: delegate, delegateQueue: .main)
    }

    private static func cacheDirectory(_ name: String) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(name, isDirectory: true)
    }

    /// Forget every saved copy and cached answer.
    func clearSavedCopies() {
        shellStore.removeAll()
        dataStore.removeAll()
        upstream.configuration.urlCache?.removeAllCachedResponses()
        imagery.configuration.urlCache?.removeAllCachedResponses()
    }

    // MARK: WKURLSchemeHandler

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let request = urlSchemeTask.request
        guard let url = request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let method = request.httpMethod ?? "GET"
        let headers = request.allHTTPHeaderFields ?? [:]
        let route = RequestRouter.route(method: method, url: url, headers: headers)
        let cacheKey = RequestRouter.cacheKey(route: route, url: url)

        if route == .clearSavedCopies {
            clearSavedCopies()
            #if DEBUG
            NSLog("DIAG saved copies cleared at the page's request")
            #endif
            if let response = HTTPURLResponse(url: url, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "0"]) {
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didFinish()
            } else {
                urlSchemeTask.didFailWithError(URLError(.cannotParseResponse))
            }
            return
        }

        switch route {
        case .notifyPermission(let ask):
            answerLater(urlSchemeTask, url: url) {
                let permission = ask ? await Notifier.shared.requestPermission() : await Notifier.shared.permission()
                return Data(#"{"permission":"\#(permission)"}"#.utf8)
            }
            return
        case .notify:
            let message = Self.notification(from: Self.body(of: request))
            answerLater(urlSchemeTask, url: url) {
                if let message { await Notifier.shared.post(title: message.title, body: message.body, tag: message.tag) }
                return Data("{}".utf8)
            }
            return
        default:
            break
        }

        let target: URL?
        switch route {
        case .reject:
            target = nil
        case .satellite(let z, let x, let y):
            target = provider.tileURL(z: z, x: x, y: y)
        default:
            target = RequestRouter.upstreamURL(for: url)
        }
        guard var target else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
            return
        }
        #if DEBUG
        // Development aid: launched with `-simulateOffline`, no request reaches a server.
        if ProcessInfo.processInfo.arguments.contains("-simulateOffline") {
            target = URL(string: "https://offline.invalid" + target.path)!
        }
        #endif

        // Files named by their content: the saved copy is the answer.
        if route == .immutable, let cacheKey, let saved = shellStore.read(cacheKey) {
            deliver(saved, to: urlSchemeTask, url: url, route: route, offline: false)
            return
        }

        var upstreamRequest = URLRequest(url: target)
        upstreamRequest.httpMethod = method
        let isSatellite: Bool
        if case .satellite = route { isSatellite = true } else { isSatellite = false }
        if isSatellite {
            upstreamRequest.setValue("image/*", forHTTPHeaderField: "Accept")
        } else {
            for (name, value) in RequestRouter.upstreamHeaders(from: headers, method: method) {
                upstreamRequest.setValue(value, forHTTPHeaderField: name)
            }
            upstreamRequest.httpBody = Self.body(of: request)
        }
        upstreamRequest.setValue(userAgent(from: headers), forHTTPHeaderField: "User-Agent")

        let operation = Operation(schemeTask: urlSchemeTask, route: route, url: url, cacheKey: cacheKey)
        let dataTask = (isSatellite ? imagery : upstream).dataTask(with: upstreamRequest)
        operation.dataTask = dataTask
        byDataTask[dataTask] = operation
        bySchemeTask[ObjectIdentifier(urlSchemeTask)] = operation

        if let seconds = route.fallbackTimeout, let cacheKey, store(for: route).contains(cacheKey) {
            let work = DispatchWorkItem { [weak self, weak operation] in
                guard let self, let operation else { return }
                self.serveSavedCopyIfStillWaiting(operation)
            }
            operation.timeout = work
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
        dataTask.resume()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        ownTasks.remove(ObjectIdentifier(urlSchemeTask))
        guard let operation = bySchemeTask[ObjectIdentifier(urlSchemeTask)] else { return }
        close(operation)
        operation.dataTask?.cancel()
    }

    // MARK: Answers of the app's own

    /// Answers with JSON once `work` is done, unless WebKit stopped the task meanwhile.
    private func answerLater(_ schemeTask: any WKURLSchemeTask, url: URL, work: @escaping @MainActor () async -> Data) {
        let key = ObjectIdentifier(schemeTask)
        ownTasks.insert(key)
        Task { @MainActor in
            let body = await work()
            guard self.ownTasks.remove(key) != nil else { return }
            let headers = ["Content-Type": "application/json", "Content-Length": String(body.count), "Cache-Control": "no-store"]
            guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) else {
                schemeTask.didFailWithError(URLError(.cannotParseResponse))
                return
            }
            schemeTask.didReceive(response)
            schemeTask.didReceive(body)
            schemeTask.didFinish()
        }
    }

    /// What the page asked to be notified about; nil for anything that is not that.
    static func notification(from body: Data?) -> (title: String, body: String, tag: String)? {
        guard let body, body.count <= 16 * 1024,
              let fields = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let title = (fields["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        return (title, fields["body"] as? String ?? "", fields["tag"] as? String ?? "")
    }

    // MARK: Answers from the network

    private func received(_ response: URLResponse, for dataTask: URLSessionDataTask) -> URLSession.ResponseDisposition {
        guard let operation = byDataTask[dataTask] else { return .cancel }
        guard let http = response as? HTTPURLResponse else {
            // Not HTTP: nothing the page could use.
            if !operation.closed {
                close(operation)
                operation.schemeTask.didFailWithError(URLError(.badServerResponse))
            }
            return .cancel
        }
        operation.response = http
        let contentType = http.value(forHTTPHeaderField: "Content-Type")
        operation.keepsCopy = operation.cacheKey != nil
            && RequestRouter.shouldKeep(route: operation.route, status: http.statusCode, contentType: contentType)

        if operation.closed {
            // A saved copy was served while this was on its way: go on only to refresh it.
            return operation.keepsCopy ? .allow : .cancel
        }
        operation.timeout?.cancel()

        if operation.route == .api,
           RequestRouter.isGatewayDown(status: http.statusCode, contentType: contentType),
           let saved = savedCopy(for: operation) {
            close(operation)
            deliver(saved, to: operation.schemeTask, url: operation.url, route: operation.route, offline: true)
            return .cancel
        }

        if operation.route == .style, http.statusCode == 200, isSatelliteOn() {
            operation.holdsBody = true
        } else {
            operation.schemeTask.didReceive(clientResponse(for: http, url: operation.url, bodyLength: nil))
            operation.headSent = true
        }
        return .allow
    }

    private func received(_ data: Data, for dataTask: URLSessionDataTask) {
        guard let operation = byDataTask[dataTask] else { return }
        if operation.keepsCopy || operation.holdsBody {
            operation.body.append(data)
            let limit = operation.holdsBody ? Self.heldBodyLimit : store(for: operation.route).entryLimit
            if operation.body.count > limit {
                if operation.holdsBody {
                    // Absurdly large for a style: give up on it.
                    if !operation.closed {
                        close(operation)
                        operation.schemeTask.didFailWithError(URLError(.dataLengthExceedsMaximum))
                    }
                    dataTask.cancel()
                    return
                }
                operation.keepsCopy = false
                operation.body = Data()
            }
        }
        if !operation.closed, operation.headSent {
            operation.schemeTask.didReceive(data)
        }
    }

    private func completed(_ task: URLSessionTask, error: Error?) {
        guard let operation = byDataTask.removeValue(forKey: task) else { return }
        operation.timeout?.cancel()
        let wasClosed = operation.closed
        close(operation)

        if let error {
            guard !wasClosed else { return }
            if !operation.headSent {
                if let saved = savedCopy(for: operation) {
                    deliver(saved, to: operation.schemeTask, url: operation.url, route: operation.route, offline: operation.route == .api)
                    return
                }
                if operation.route == .api {
                    // What the web app's service worker answers when there is neither network nor copy.
                    let body = Data(#"{"title":"Offline","status":503,"detail":"offline and no saved copy of this view"}"#.utf8)
                    let saved = SavedResponse(status: 503, headers: ["Content-Type": "application/problem+json"], body: body)
                    deliver(saved, to: operation.schemeTask, url: operation.url, route: .networkOnly, offline: true)
                    return
                }
            }
            operation.schemeTask.didFailWithError(error)
            return
        }

        guard let http = operation.response else {
            if !wasClosed { operation.schemeTask.didFailWithError(URLError(.badServerResponse)) }
            return
        }
        if operation.keepsCopy, let cacheKey = operation.cacheKey {
            var headers = RequestRouter.clientHeaders(from: http.allHeaderFields)
            Self.removeHeader("Content-Length", from: &headers)
            store(for: operation.route).write(SavedResponse(status: http.statusCode, headers: headers, body: operation.body), for: cacheKey)
        }
        guard !wasClosed else { return }
        if operation.holdsBody {
            let body = transformed(operation.body, route: operation.route)
            operation.schemeTask.didReceive(clientResponse(for: http, url: operation.url, bodyLength: body.count))
            operation.schemeTask.didReceive(body)
        }
        operation.schemeTask.didFinish()
    }

    // MARK: Saved copies

    private func serveSavedCopyIfStillWaiting(_ operation: Operation) {
        guard !operation.closed, !operation.headSent, !operation.holdsBody, let saved = savedCopy(for: operation) else { return }
        close(operation)
        deliver(saved, to: operation.schemeTask, url: operation.url, route: operation.route, offline: operation.route == .api)
        // The request stays alive: a late answer still refreshes the copy.
    }

    private func savedCopy(for operation: Operation) -> SavedResponse? {
        guard operation.route.keepsCopy, let cacheKey = operation.cacheKey else { return nil }
        return store(for: operation.route).read(cacheKey)
    }

    private func store(for route: Route) -> OfflineStore {
        route == .api ? dataStore : shellStore
    }

    /// Marks the scheme task as answered or abandoned. After this, nothing may be sent to it.
    private func close(_ operation: Operation) {
        operation.closed = true
        operation.timeout?.cancel()
        bySchemeTask[ObjectIdentifier(operation.schemeTask)] = nil
    }

    private func deliver(_ saved: SavedResponse, to schemeTask: any WKURLSchemeTask, url: URL, route: Route, offline: Bool) {
        var headers = saved.headers
        if offline { headers["x-meshmap-offline"] = "1" }
        let body = transformed(saved.body, route: route)
        Self.removeHeader("Content-Length", from: &headers)
        headers["Content-Length"] = String(body.count)
        guard let response = HTTPURLResponse(url: url, statusCode: saved.status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            schemeTask.didFailWithError(URLError(.cannotParseResponse))
            return
        }
        schemeTask.didReceive(response)
        schemeTask.didReceive(body)
        schemeTask.didFinish()
    }

    /// A map style with the satellite layer added while the layer is on;
    /// every other body unchanged.
    private func transformed(_ body: Data, route: Route) -> Data {
        guard route == .style, isSatelliteOn() else { return body }
        return StyleRewriter.addingSatellite(to: body, provider: provider) ?? body
    }

    // MARK: Helpers

    private func clientResponse(for http: HTTPURLResponse, url: URL, bodyLength: Int?) -> URLResponse {
        var headers = RequestRouter.clientHeaders(from: http.allHeaderFields)
        if let bodyLength {
            Self.removeHeader("Content-Length", from: &headers)
            headers["Content-Length"] = String(bodyLength)
        }
        return HTTPURLResponse(url: url, statusCode: http.statusCode, httpVersion: "HTTP/1.1", headerFields: headers)
            ?? URLResponse(url: url, mimeType: http.mimeType, expectedContentLength: -1, textEncodingName: http.textEncodingName)
    }

    private static func removeHeader(_ name: String, from headers: inout [String: String]) {
        let lower = name.lowercased()
        for key in headers.keys where key.lowercased() == lower { headers[key] = nil }
    }

    /// The web view's own user agent, with the app named after it so the
    /// site's operator can tell the app's requests from a browser's.
    private func userAgent(from headers: [String: String]) -> String {
        if let own = RequestRouter.header("User-Agent", in: headers), !own.isEmpty {
            return own + " " + userAgentSuffix
        }
        return userAgentSuffix
    }

    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
            if data.count > 4 * 1024 * 1024 { break } // far beyond anything the page posts
        }
        return data
    }
}

// The sessions deliver on the main queue, so these run on the main thread.
extension UpstreamProxy: URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                                completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        let disposition = MainActor.assumeIsolated { received(response, for: dataTask) }
        completionHandler(disposition)
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        MainActor.assumeIsolated { received(data, for: dataTask) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        MainActor.assumeIsolated { completed(task, error: error) }
    }

    /// Redirects are followed only on the same host over HTTPS: the page's
    /// origin must never quietly become another site.
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                                newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let from = task.originalRequest?.url
        let to = request.url
        let sameSite = to?.scheme?.lowercased() == "https" && to?.host?.lowercased() == from?.host?.lowercased()
        completionHandler(sameSite ? request : nil)
    }
}
