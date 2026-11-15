import XCTest
@testable import MeshtasticNorwayMap

final class ExternalLinksTests: XCTestCase {
    private func action(_ link: String, page: String? = "meshmap://map.868.no/") -> ExternalAction {
        ExternalLinks.action(for: URL(string: link)!, pageURL: page.flatMap(URL.init(string:)))
    }

    func testPagesOfTheSiteOpenAsPublicLinks() {
        XCTAssertEqual(action("meshmap://map.868.no/privacy.html"), .inAppBrowser(URL(string: "https://map.868.no/privacy.html")!))
    }

    func testWebLinksOpenInTheBrowserSheet() {
        XCTAssertEqual(action("https://github.com/868-no/map"), .inAppBrowser(URL(string: "https://github.com/868-no/map")!))
        XCTAssertEqual(action("https://www.openstreetmap.org/copyright"), .inAppBrowser(URL(string: "https://www.openstreetmap.org/copyright")!))
    }

    func testMeshtasticLinksGoToTheSystem() {
        XCTAssertEqual(action("meshtastic:///v#abc"), .system(URL(string: "meshtastic:///v#abc")!))
        XCTAssertEqual(action("https://meshtastic.org/v/#abc"), .system(URL(string: "https://meshtastic.org/v/#abc")!))
        XCTAssertEqual(action("mailto:someone@example.org"), .system(URL(string: "mailto:someone@example.org")!))
    }

    func testEverythingElseIsIgnored() {
        for link in ["javascript:alert(1)", "file:///etc/passwd", "data:text/html,x", "about:blank", "itms-services://x", "https:///nohost"] {
            XCTAssertEqual(action(link), .ignore, link)
        }
    }

    func testLinkSimGetsTheNodesPublicLink() {
        let link = "https://linksim.link/?site=1&lat=63.43000&lon=10.40000&name=Test&source=map.868.no"
        guard case .inAppBrowser(let url) = action(link, page: "meshmap://map.868.no/?node=!a206ab04&w=3d") else { return XCTFail("not opened in the browser sheet") }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "sourceUrl" }?.value, "https://map.868.no/?node=!a206ab04")
        XCTAssertEqual(items.first { $0.name == "lat" }?.value, "63.43000")
        XCTAssertEqual(items.count, 6)
    }

    func testLinkSimIsLeftAloneWithoutAKnownNode() {
        let link = URL(string: "https://linksim.link/?site=1&lat=1&lon=2")!
        XCTAssertEqual(ExternalLinks.withLinkBack(link, pageURL: URL(string: "meshmap://map.868.no/")!), link)
        XCTAssertEqual(ExternalLinks.withLinkBack(link, pageURL: URL(string: "meshmap://map.868.no/?node=%3Cscript%3E")!), link)
        XCTAssertEqual(ExternalLinks.withLinkBack(link, pageURL: URL(string: "https://evil.example/?node=!a206ab04")!), link)
        XCTAssertEqual(ExternalLinks.withLinkBack(link, pageURL: nil), link)
        let has = URL(string: "https://linksim.link/?site=1&sourceUrl=https%3A%2F%2Fmap.868.no%2F")!
        XCTAssertEqual(ExternalLinks.withLinkBack(has, pageURL: URL(string: "meshmap://map.868.no/?node=!a206ab04")!), has)
        let other = URL(string: "https://example.org/?site=1")!
        XCTAssertEqual(ExternalLinks.withLinkBack(other, pageURL: URL(string: "meshmap://map.868.no/?node=!a206ab04")!), other)
    }

    func testNodeIDs() {
        XCTAssertTrue(ExternalLinks.isNodeID("!a206ab04"))
        for bad in ["a206ab04", "!A206AB04", "!a206ab0", "!a206ab045", "!a206ab0g", ""] {
            XCTAssertFalse(ExternalLinks.isNodeID(bad), bad)
        }
    }
}
