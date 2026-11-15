import XCTest
@testable import MeshtasticNorwayMap

final class SharedTests: XCTestCase {
    func testWatchListFromThePage() {
        XCTAssertEqual(WatchList.parse(json: #"{"ids":["!a206ab04","!0400a3ac"],"notify":true}"#),
                       WatchList(ids: ["!a206ab04", "!0400a3ac"], notify: true))
        XCTAssertEqual(WatchList.parse(json: #"{"ids":["!a206ab04","bad","!A206AB04","!a206ab04"]}"#), WatchList(ids: ["!a206ab04"], notify: false))
        XCTAssertEqual(WatchList.parse(json: #"{"ids":["!a206ab04"],"notify":"yes"}"#).notify, false)
        for bad in [nil, "", "null", "[]", "{", #"{"ids":"x"}"#, #"{"ids":[1,2]}"#] {
            XCTAssertEqual(WatchList.parse(json: bad).ids, [], bad ?? "nil")
        }
        let many = (0..<40).map { String(format: "\"!%08x\"", $0) }.joined(separator: ",")
        XCTAssertEqual(WatchList.parse(json: "{\"ids\":[\(many)]}").ids.count, WatchList.maxNodes)
    }

    func testNodeLinks() {
        XCTAssertEqual(Shared.nodeURL("!a206ab04")?.absoluteString, "meshnorway://node/!a206ab04")
        XCTAssertNil(Shared.nodeURL("a206ab04"))
        XCTAssertEqual(Shared.nodeID(from: URL(string: "meshnorway://node/!a206ab04")!), "!a206ab04")
        XCTAssertEqual(Shared.nodeID(from: URL(string: "MESHNORWAY://NODE/!a206ab04")!), "!a206ab04")
        for bad in ["meshnorway://map", "meshnorway://node/", "meshnorway://node/!A206AB04", "meshnorway://other/!a206ab04", "https://node/!a206ab04", "meshnorway://node/x/../!a206ab0"] {
            XCTAssertNil(Shared.nodeID(from: URL(string: bad)!), bad)
        }
    }

    func testStoreRoundTrip() throws {
        let suite = "SharedTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SharedStore(defaults: defaults)
        XCTAssertEqual(store.watchList, WatchList())
        XCTAssertEqual(store.name(of: "!a206ab04"), "!a206ab04")
        store.watchList = WatchList(ids: ["!a206ab04"], notify: true)
        store.names = ["!a206ab04": "Heltec"]
        var snapshot = NodeSnapshot()
        snapshot.quietHours = 3
        snapshot.buckets = ["d": .init(hours: 5, heard: 2)]
        store.snapshots = ["!a206ab04": snapshot]
        let again = SharedStore(defaults: defaults)
        XCTAssertEqual(again.watchList, WatchList(ids: ["!a206ab04"], notify: true))
        XCTAssertEqual(again.name(of: "!a206ab04"), "Heltec")
        XCTAssertEqual(again.snapshots["!a206ab04"], snapshot)
    }

    func testDecodingTheSitesAnswers() throws {
        // As map.868.no answered on 15 November 2026, shortened.
        let node = #"{"$schema":"x","node":"!a206ab04","bucket":"day","since":"2026-10-03T22:41:30Z","buckets":[{"start":"2026-11-14T00:00:00+01:00","hours":24,"hours_heard":24,"hours_gateway":24,"packets":36,"receptions":0,"receptions_per_packet":0,"battery_min":101},{"start":"2026-11-15T00:00:00+01:00","hours":13,"hours_heard":12,"packets":18,"battery_min":87.5,"new_field":{"a":1}},{"start":"2026-11-16T00:00:00+01:00"}]}"#
        let days = try MeshAPI.decodeNodeDays(Data(node.utf8))
        XCTAssertEqual(days.count, 3)
        XCTAssertEqual(days[1], MeshAPI.NodeDay(start: "2026-11-15T00:00:00+01:00", hours: 13, hoursHeard: 12, packets: 18, batteryMin: 87.5))
        XCTAssertEqual(days[2], MeshAPI.NodeDay(start: "2026-11-16T00:00:00+01:00"))

        let mesh = #"{"bucket":"day","since":"x","buckets":[{"start":"2026-11-15T00:00:00+01:00","nodes":227,"gateways":57,"new_nodes":6,"packets":3481,"receptions":8461,"by_type":{"text":10}}]}"#
        XCTAssertEqual(try MeshAPI.decodeMeshDays(Data(mesh.utf8)), [MeshAPI.MeshDay(start: "2026-11-15T00:00:00+01:00", nodes: 227, gateways: 57, newNodes: 6, packets: 3481)])
        XCTAssertThrowsError(try MeshAPI.decodeMeshDays(Data("{}".utf8)))
        XCTAssertThrowsError(try MeshAPI.decodeNodeDays(Data("<html>".utf8)))
    }

    func testNames() {
        XCTAssertEqual(MeshAPI.cleaned("  Heltec v3 \n"), "Heltec v3")
        XCTAssertNil(MeshAPI.cleaned("   "))
        XCTAssertNil(MeshAPI.cleaned(nil))
        XCTAssertEqual(MeshAPI.cleaned(String(repeating: "x", count: 100))?.count, 60)
    }

    @MainActor
    func testNotificationRoutesAndBodies() {
        let route = { (path: String, method: String) in
            RequestRouter.route(method: method, url: URL(string: "meshmap://map.868.no" + path)!, headers: [:])
        }
        XCTAssertEqual(route("/__app/notify", "POST"), .notify)
        XCTAssertEqual(route("/__app/notify", "GET"), .reject)
        XCTAssertEqual(route("/__app/notify/permission", "GET"), .notifyPermission(ask: false))
        XCTAssertEqual(route("/__app/notify/permission", "POST"), .notifyPermission(ask: true))
        XCTAssertEqual(route("/__app/notify/permission", "DELETE"), .reject)

        let message = UpstreamProxy.notification(from: Data(#"{"title":" Node (868.no Map) ","body":"Heard again.","tag":"meshmap-!a206ab04"}"#.utf8))
        XCTAssertEqual(message?.title, "Node (868.no Map)")
        XCTAssertEqual(message?.body, "Heard again.")
        XCTAssertEqual(message?.tag, "meshmap-!a206ab04")
        XCTAssertEqual(UpstreamProxy.notification(from: Data(#"{"title":"T"}"#.utf8))?.body, "")
        for bad in [nil, Data(), Data("[]".utf8), Data(#"{"title":""}"#.utf8), Data(#"{"title":5}"#.utf8), Data(#"{"body":"x"}"#.utf8), Data(repeating: 0x20, count: 20_000)] {
            XCTAssertNil(UpstreamProxy.notification(from: bad))
        }
        XCTAssertEqual(Notifier.node(fromTag: "meshmap-!a206ab04"), "!a206ab04")
        XCTAssertNil(Notifier.node(fromTag: "meshmap-!zzzzzzzz"))
        XCTAssertNil(Notifier.node(fromTag: "other"))
        XCTAssertEqual(Notifier.tag(forNode: "!a206ab04"), "meshmap-!a206ab04")
        XCTAssertEqual(Notifier.webName(.authorized), "granted")
        XCTAssertEqual(Notifier.webName(.denied), "denied")
        XCTAssertEqual(Notifier.webName(.notDetermined), "default")
    }
}
