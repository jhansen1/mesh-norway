import XCTest

/// Takes the App Store screenshots. Skipped unless a folder to write them to is given:
/// `TEST_RUNNER_SCREENSHOT_DIR=/path xcodebuild test -only-testing:MeshtasticNorwayMapUITests/ScreenshotTests …`
/// (see Tools/screenshots.sh). Runs in the simulator, which shares the Mac's file system.
final class ScreenshotTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        continueAfterFailure = true
        guard let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !path.isEmpty else {
            throw XCTSkip("SCREENSHOT_DIR is not set")
        }
        folder = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// The map, a node, the watched nodes and the trends.
    @MainActor
    func testAppScreens() throws {
        let app = XCUIApplication()
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.links["© OpenStreetMap contributors"].waitForExistence(timeout: 60), "the map did not load")
        sleep(6)
        shot("01-map")

        // Watch a few hilltop routers; the last one stays open for the picture.
        let watch = web.switches.matching(NSPredicate(format: "label CONTAINS[c] %@", "Watch")).firstMatch
        for node in ["!997b0449", "!f66adc9c", "!d38dd2ca", "!672f1873"] {
            XCUIDevice.shared.system.open(URL(string: "meshnorway://node/\(node)")!)
            sleep(6)
            XCTAssertTrue(watch.waitForExistence(timeout: 20), "no details for \(node)")
            if (watch.value as? String) == "0" { watch.tap() }
            sleep(1)
        }
        sleep(3)
        shot("02-node")

        web.switches["Nodes"].tap()
        sleep(3)
        let notify = web.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "Notify me")).firstMatch
        if notify.waitForExistence(timeout: 5), (notify.value as? String) != "1" {
            notify.tap()
            // The system's question, whatever the device's language calls the buttons: the second one allows.
            let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
            if alert.waitForExistence(timeout: 5) { alert.buttons.element(boundBy: 1).tap() }
        }
        sleep(3)
        shot("03-watched")

        web.switches["Trends"].tap()
        sleep(6)
        shot("04-trends")

        // Leaving the app hands the watchlist to the widgets.
        XCUIDevice.shared.press(.home)
        sleep(5)
    }

    @MainActor
    func testWidgets() throws {
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)
        sleep(2)
        XCUIDevice.shared.press(.home) // to the first page
        sleep(2)
        home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).press(forDuration: 2.0)
        sleep(2)
        // Clear the widgets the simulator starts with.
        let widgets = home.icons.matching(NSPredicate(format: "value BEGINSWITH %@", "Widget"))
        for _ in 0..<6 {
            // Only those on this page: the Today view to the left has its own.
            guard let widget = widgets.allElementsBoundByIndex.first(where: { $0.frame.width > 0 && $0.frame.minX >= 0 && $0.frame.maxX <= home.frame.width }) else { break }
            widget.buttons["DeleteButton"].tap()
            let alert = home.alerts.firstMatch
            if alert.waitForExistence(timeout: 3) { alert.buttons.element(boundBy: 1).tap() }
            sleep(1)
        }
        addWidget(home, swipes: 0, name: "a") // Watched nodes, medium
        addWidget(home, swipes: 3, name: "b") // Mesh today, medium
        XCUIDevice.shared.press(.home) // leaves edit mode
        sleep(20) // the widgets fetch their data
        shot("05-widgets")
    }

    /// With the Home Screen in edit mode: Edit > Add widget > Mesh Norway > the page `swipes` to the right > Add.
    @MainActor
    private func addWidget(_ home: XCUIApplication, swipes: Int, name: String) {
        home.buttons.element(boundBy: 0).tap()
        sleep(2)
        home.cells.element(boundBy: 0).tap() // "Add widget", first in the menu
        let search = home.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8), "no widget gallery")
        search.tap()
        search.typeText("Mesh Norway")
        sleep(2)
        home.cells["Mesh Norway"].firstMatch.tap()
        sleep(3)
        for _ in 0..<swipes {
            home.swipeLeft()
            sleep(1)
        }
        // The one wide button at the bottom of the sheet, whatever the language calls it.
        let add = home.buttons.allElementsBoundByIndex.last(where: { $0.frame.width > 200 && $0.frame.minY > home.frame.height * 0.7 })
        XCTAssertNotNil(add, "no button to add the widget")
        add?.tap()
        sleep(3)
    }

    private func shot(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: folder.appendingPathComponent(name + ".png"))
    }
}
