import XCTest
@testable import MeshtasticNorwayMap

@MainActor
final class OfflineStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("OfflineStoreTests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func response(_ bytes: Int, _ fill: UInt8 = 1) -> SavedResponse {
        SavedResponse(status: 200, headers: ["Content-Type": "application/json"], body: Data(repeating: fill, count: bytes))
    }

    /// Sets when a saved copy was last used, without waiting for the clock.
    private func age(_ key: String, in store: OfflineStore, secondsAgo: TimeInterval) throws {
        let before = Set(try bodyFiles())
        _ = store.read(key) // touches exactly this key's file
        let touched = try bodyFiles().filter { url in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return before.contains(url) && date > Date().addingTimeInterval(-5)
        }
        let newest = try XCTUnwrap(touched.max { modified($0) < modified($1) })
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-secondsAgo)], ofItemAtPath: newest.path)
    }

    private func bodyFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "body" }
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    func testRoundTrip() {
        let store = OfflineStore(directory: directory, budgetBytes: 1000, maxEntryBytes: 500)
        XCTAssertNil(store.read("/a"))
        XCTAssertFalse(store.contains("/a"))
        store.write(response(100), for: "/a")
        XCTAssertTrue(store.contains("/a"))
        XCTAssertEqual(store.read("/a"), response(100))
        XCTAssertNil(store.read("/b"))
        store.write(response(50, 2), for: "/a")
        XCTAssertEqual(store.read("/a"), response(50, 2))
        store.remove("/a")
        XCTAssertNil(store.read("/a"))
    }

    func testSurvivesANewInstance() {
        OfflineStore(directory: directory, budgetBytes: 1000, maxEntryBytes: 500).write(response(10), for: "/a?x=1")
        XCTAssertEqual(OfflineStore(directory: directory, budgetBytes: 1000, maxEntryBytes: 500).read("/a?x=1"), response(10))
    }

    func testTooLargeIsNotKept() {
        let store = OfflineStore(directory: directory, budgetBytes: 1000, maxEntryBytes: 500)
        store.write(response(501), for: "/big")
        XCTAssertNil(store.read("/big"))
    }

    func testDropsTheLeastRecentlyUsedOverBudget() throws {
        let store = OfflineStore(directory: directory, budgetBytes: 1000, maxEntryBytes: 500)
        store.write(response(300), for: "/1")
        try age("/1", in: store, secondsAgo: 100)
        store.write(response(300), for: "/2")
        try age("/2", in: store, secondsAgo: 300) // used longest ago
        store.write(response(300), for: "/3")
        try age("/3", in: store, secondsAgo: 200)

        store.write(response(300), for: "/4")
        XCTAssertNil(store.read("/2"))
        XCTAssertNotNil(store.read("/1"))
        XCTAssertNotNil(store.read("/3"))
        XCTAssertNotNil(store.read("/4"))
        XCTAssertLessThanOrEqual(store.totalBytes(), 1000)
    }

    func testRemoveAll() {
        let store = OfflineStore(directory: directory, budgetBytes: 1000, maxEntryBytes: 500)
        store.write(response(10), for: "/a")
        store.removeAll()
        XCTAssertNil(store.read("/a"))
        XCTAssertEqual(store.totalBytes(), 0)
        store.write(response(10), for: "/a")
        XCTAssertNotNil(store.read("/a"))
    }
}
