import XCTest

/// Drives the real app against map.868.no: needs a network connection.
final class AppUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCreditIsShownMapLoadsAndLinksOpen() {
        let app = XCUIApplication()
        app.launch()

        // Under the map, always: whose map it is, and the way to the full credits.
        XCTAssertTrue(app.staticTexts["map.868.no by Jim C K Flaten"].waitForExistence(timeout: 20))
        app.buttons["aboutButton"].tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["The iOS edition of map.868.no"].exists)
        let credit = NSPredicate(format: "label CONTAINS %@", "created by Jim C K Flaten")
        XCTAssertTrue(app.staticTexts.matching(credit).firstMatch.exists)
        app.buttons["Done"].tap() // the app's own button: its interface is English
        XCTAssertTrue(app.navigationBars["About"].waitForNonExistence(timeout: 10))

        // The site's own attribution, inside the web view: the map is up, and the opening screen is gone.
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 30))
        let siteCredit = web.links["© OpenStreetMap contributors"]
        XCTAssertTrue(siteCredit.waitForExistence(timeout: 60), "the map did not load")
        XCTAssertTrue(app.descendants(matching: .any)["openingCredit"].waitForNonExistence(timeout: 10))
        // Nothing of the app's own is left around the map.
        XCTAssertFalse(app.segmentedControls.firstMatch.exists)

        // A link out of the map opens in the browser sheet, and the map is still there afterwards.
        siteCredit.tap()
        let browser = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "BrowserView")).firstMatch
        XCTAssertTrue(browser.waitForExistence(timeout: 20), "the link did not open in the browser sheet")
        XCTAssertTrue(app.buttons["URL"].waitForExistence(timeout: 15))
        // The sheet's close button, whatever the device's language calls it.
        browser.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(browser.waitForNonExistence(timeout: 15))
        XCTAssertTrue(siteCredit.waitForExistence(timeout: 15))
    }
}
