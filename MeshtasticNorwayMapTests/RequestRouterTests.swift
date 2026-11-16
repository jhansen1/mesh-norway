import XCTest
@testable import MeshtasticNorwayMap

final class RequestRouterTests: XCTestCase {
    private func route(_ path: String, method: String = "GET", headers: [String: String] = [:]) -> Route {
        RequestRouter.route(method: method, url: URL(string: "meshmap://map.868.no" + path)!, headers: headers)
    }

    func testOnlyTheAppOriginIsServed() {
        XCTAssertTrue(RequestRouter.isAppURL(URL(string: "meshmap://map.868.no/")!))
        XCTAssertTrue(RequestRouter.isAppURL(URL(string: "MESHMAP://MAP.868.NO/x")!))
        for other in ["https://map.868.no/", "meshmap://evil.example/", "meshmap://map.868.no:8080/", "meshmap://user@map.868.no/", "meshmap://map.868.no.evil.example/"] {
            XCTAssertFalse(RequestRouter.isAppURL(URL(string: other)!), other)
            XCTAssertEqual(RequestRouter.route(method: "GET", url: URL(string: other)!, headers: [:]), .reject, other)
            XCTAssertNil(RequestRouter.upstreamURL(for: URL(string: other)!), other)
        }
    }

    func testPageLoadsCarryTheAppsMark() {
        func marked(_ text: String) -> String? { RequestRouter.markedPageURL(for: URL(string: text)!)?.absoluteString }
        XCTAssertEqual(marked("meshmap://map.868.no/"), "meshmap://map.868.no/?client=ios-app")
        XCTAssertEqual(marked("meshmap://map.868.no/?node=!997b0449"), "meshmap://map.868.no/?node=!997b0449&client=ios-app")
        XCTAssertEqual(marked("meshmap://map.868.no/?client=other"), "meshmap://map.868.no/?client=ios-app")
        // Marked already, not the page, or not the site: left alone.
        XCTAssertNil(marked("meshmap://map.868.no/?client=ios-app&node=!997b0449"))
        XCTAssertNil(marked("meshmap://map.868.no/privacy.html"))
        XCTAssertNil(marked("https://map.868.no/"))
    }

    func testUpstreamURLKeepsPathAndQuery() {
        let url = URL(string: "meshmap://map.868.no/api/v1/nodes/%21a206ab04/contact?x=1&y=a%20b#frag")!
        XCTAssertEqual(RequestRouter.upstreamURL(for: url)?.absoluteString, "https://map.868.no/api/v1/nodes/%21a206ab04/contact?x=1&y=a%20b")
        XCTAssertEqual(RequestRouter.publicURL(for: URL(string: "meshmap://map.868.no/privacy.html#data")!)?.absoluteString, "https://map.868.no/privacy.html#data")
    }

    func testRoutesFollowTheServiceWorker() {
        XCTAssertEqual(route("/tiles/basemap.pmtiles"), .networkOnly)
        XCTAssertEqual(route("/api/v1/stream?x=1"), .networkOnly)
        XCTAssertEqual(route("/api/v1/observations"), .networkOnly)
        XCTAssertEqual(route("/api/v1/observations/day/2026-11-01"), .networkOnly)
        XCTAssertEqual(route("/health/ready"), .networkOnly)
        XCTAssertEqual(route("/api/v1/capabilities"), .api)
        XCTAssertEqual(route("/api/v1/capabilities", headers: ["Accept": "text/html"]), .api)
        XCTAssertEqual(route("/api/v1/terrain/profile", method: "POST"), .networkOnly)
        XCTAssertEqual(route("/assets/index-abc.js"), .immutable)
        XCTAssertEqual(route("/fonts/Noto%20Sans%20Regular/0-255.pbf"), .immutable)
        XCTAssertEqual(route("/styles/dark.json"), .style)
        XCTAssertEqual(route("/theme-boot.js"), .entry)
        XCTAssertEqual(route("/", headers: ["Accept": "text/html,application/xhtml+xml"]), .document(key: "/index.html"))
        XCTAssertEqual(route("/?node=!a206ab04", headers: ["accept": "text/html"]), .document(key: "/index.html"))
        XCTAssertEqual(route("/privacy.html", headers: ["Accept": "text/html"]), .document(key: "/privacy.html"))
        XCTAssertEqual(route("/assets/index-abc.js", headers: ["Range": "bytes=0-10"]), .networkOnly)
    }

    func testSatelliteTiles() {
        XCTAssertEqual(route("/__app/sat/9/270/137"), .satellite(z: 9, x: 270, y: 137))
        XCTAssertEqual(route("/__app/sat/0/0/0"), .satellite(z: 0, x: 0, y: 0))
        for bad in ["/__app/sat/9/270", "/__app/sat/9/270/137/1", "/__app/sat/9/512/0", "/__app/sat/23/0/0", "/__app/sat/a/b/c",
                    "/__app/sat/9/-1/0", "/__app/sat/9//0", "/__app/sat/9/270/137.jpg", "/__app/sat/999999999999999999999/0/0", "/__app/other"] {
            XCTAssertEqual(route(bad), .reject, bad)
        }
        XCTAssertEqual(route("/__app/sat/9/270/137", method: "POST"), .reject)
        XCTAssertEqual(route("/__app/clear-saved", method: "POST"), .clearSavedCopies)
        XCTAssertEqual(route("/__app/clear-saved"), .reject)
    }

    func testCacheKeys() {
        let url = URL(string: "meshmap://map.868.no/api/v1/trends?a=1&b=2")!
        XCTAssertEqual(RequestRouter.cacheKey(route: .api, url: url), "/api/v1/trends?a=1&b=2")
        XCTAssertEqual(RequestRouter.cacheKey(route: .document(key: "/index.html"), url: url), "document:/index.html")
        XCTAssertNil(RequestRouter.cacheKey(route: .networkOnly, url: url))
        XCTAssertNil(RequestRouter.cacheKey(route: .satellite(z: 1, x: 0, y: 0), url: url))
    }

    func testWhatIsKept() {
        XCTAssertTrue(RequestRouter.shouldKeep(route: .api, status: 200, contentType: "application/json"))
        XCTAssertFalse(RequestRouter.shouldKeep(route: .api, status: 503, contentType: "application/problem+json"))
        XCTAssertFalse(RequestRouter.shouldKeep(route: .api, status: 206, contentType: "application/json"))
        XCTAssertFalse(RequestRouter.shouldKeep(route: .immutable, status: 200, contentType: "text/html; charset=utf-8"))
        XCTAssertTrue(RequestRouter.shouldKeep(route: .document(key: "/index.html"), status: 200, contentType: "text/html; charset=utf-8"))
        XCTAssertFalse(RequestRouter.shouldKeep(route: .document(key: "/index.html"), status: 200, contentType: "application/json"))
        XCTAssertFalse(RequestRouter.shouldKeep(route: .networkOnly, status: 200, contentType: "application/json"))
    }

    func testGatewayDown() {
        XCTAssertTrue(RequestRouter.isGatewayDown(status: 502, contentType: "text/html"))
        XCTAssertTrue(RequestRouter.isGatewayDown(status: 503, contentType: nil))
        XCTAssertFalse(RequestRouter.isGatewayDown(status: 503, contentType: "application/problem+json"))
        XCTAssertFalse(RequestRouter.isGatewayDown(status: 500, contentType: "text/html"))
    }

    func testRequestHeaders() {
        let get = RequestRouter.upstreamHeaders(
            from: ["Accept": "application/json", "range": "bytes=0-1", "Cookie": "a=b", "Origin": "meshmap://map.868.no", "Authorization": "x", "User-Agent": "ua"],
            method: "GET")
        XCTAssertEqual(get, ["Accept": "application/json", "range": "bytes=0-1", "Referer": "https://map.868.no/"])
        let post = RequestRouter.upstreamHeaders(from: ["Content-Type": "application/json"], method: "POST")
        XCTAssertEqual(post["Origin"], "https://map.868.no")
        XCTAssertEqual(post["Content-Type"], "application/json")
    }

    func testResponseHeaders() {
        let encoded = RequestRouter.clientHeaders(from: [
            "Content-Type": "text/html", "Content-Encoding": "gzip", "Content-Length": "123", "Set-Cookie": "a=b",
            "Content-Security-Policy": "default-src 'self'", "Alt-Svc": "h3", "Strict-Transport-Security": "x",
        ])
        XCTAssertEqual(encoded, ["Content-Type": "text/html", "Content-Security-Policy": "default-src 'self'"])
        let plain = RequestRouter.clientHeaders(from: ["content-length": "10", "Content-Range": "bytes 0-9/100", "ETag": "\"e\""])
        XCTAssertEqual(plain, ["content-length": "10", "Content-Range": "bytes 0-9/100", "ETag": "\"e\""])
    }
}
