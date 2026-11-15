import XCTest
@testable import MeshtasticNorwayMap

final class WatchRulesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func day(_ start: String, hours: Int, heard: Int, battery: Double? = nil) -> MeshAPI.NodeDay {
        MeshAPI.NodeDay(start: start, hours: hours, hoursHeard: heard, packets: heard, batteryMin: battery)
    }

    /// A week in which the node was heard `share` of the time, then today.
    private func history(share: Double = 1, today: MeshAPI.NodeDay) -> [MeshAPI.NodeDay] {
        (1...7).map { day("d\($0)", hours: 24, heard: Int(24 * share)) } + [today]
    }

    func testFirstCheckIsTheBaseline() {
        let result = WatchRules.check(previous: nil, days: history(today: day("today", hours: 10, heard: 0, battery: 5)), now: now)
        XCTAssertEqual(result.events, [])
        XCTAssertEqual(result.snapshot.quietHours, 0)
        XCTAssertEqual(result.snapshot.hoursToday, 10)
        XCTAssertEqual(result.snapshot.hoursHeardToday, 0)
        XCTAssertEqual(result.snapshot.battery, 5)
        XCTAssertTrue(result.snapshot.toldBatteryLow) // known from the start: not news later
        XCTAssertEqual(result.snapshot.checkedAt, now)
    }

    func testQuietIsToldOnceAfterSixHoursForARegularNode() {
        var snapshot = WatchRules.check(previous: nil, days: history(today: day("today", hours: 4, heard: 4)), now: now).snapshot
        var told: [WatchRules.Event] = []
        for hours in [6, 9, 11, 14] { // heard stays at 4
            let result = WatchRules.check(previous: snapshot, days: history(today: day("today", hours: hours, heard: 4)), now: now)
            snapshot = result.snapshot
            told += result.events
        }
        XCTAssertEqual(told, [.quiet(hours: 7)]) // 2 + 3 = 5 is not yet 6; 5 + 2 = 7 is
        XCTAssertEqual(snapshot.quietHours, 10)
        XCTAssertTrue(snapshot.toldQuiet)
    }

    func testHeardAgainIsToldOnlyAfterQuietWasTold() {
        let base = WatchRules.check(previous: nil, days: history(today: day("today", hours: 2, heard: 2)), now: now).snapshot
        // Quiet for three hours, then heard: nothing was told, so nothing to take back.
        let short = WatchRules.check(previous: base, days: history(today: day("today", hours: 5, heard: 2)), now: now)
        XCTAssertEqual(short.events, [])
        let back = WatchRules.check(previous: short.snapshot, days: history(today: day("today", hours: 6, heard: 3)), now: now)
        XCTAssertEqual(back.events, [])
        XCTAssertEqual(back.snapshot.quietHours, 0)

        let long = WatchRules.check(previous: back.snapshot, days: history(today: day("today", hours: 13, heard: 3)), now: now)
        XCTAssertEqual(long.events, [.quiet(hours: 7)])
        let again = WatchRules.check(previous: long.snapshot, days: history(today: day("today", hours: 14, heard: 4)), now: now)
        XCTAssertEqual(again.events, [.heardAgain])
        XCTAssertFalse(again.snapshot.toldQuiet)
        XCTAssertEqual(again.snapshot.quietHours, 0)
    }

    func testASporadicNodeGetsADay() {
        let days = { (hours: Int) in self.history(share: 0.25, today: self.day("today", hours: hours, heard: 0)) }
        var snapshot = WatchRules.check(previous: nil, days: days(0), now: now).snapshot
        let afterTwelve = WatchRules.check(previous: snapshot, days: days(12), now: now)
        XCTAssertEqual(afterTwelve.events, [])
        snapshot = afterTwelve.snapshot
        let afterDay = WatchRules.check(previous: snapshot, days: days(24), now: now)
        XCTAssertEqual(afterDay.events, [.quiet(hours: 24)])
        XCTAssertEqual(WatchRules.quietThreshold(days: days(0)), 24)
        XCTAssertEqual(WatchRules.quietThreshold(days: history(today: day("today", hours: 0, heard: 0))), 6)
        XCTAssertEqual(WatchRules.quietThreshold(days: []), 24)
    }

    func testQuietTimeCarriesOverMidnight() {
        let week = (1...7).map { day("d\($0)", hours: 24, heard: 24) }
        let evening = week + [day("mon", hours: 21, heard: 20)]
        var snapshot = WatchRules.check(previous: nil, days: evening, now: now).snapshot
        // Monday ends (3 more hours, none heard) and Tuesday starts (4 hours, none heard).
        let morning = week.dropFirst() + [day("mon", hours: 24, heard: 20), day("tue", hours: 4, heard: 0)]
        let result = WatchRules.check(previous: snapshot, days: Array(morning), now: now)
        XCTAssertEqual(result.events, [.quiet(hours: 7)])
        snapshot = result.snapshot
        XCTAssertEqual(snapshot.hoursToday, 4)
        XCTAssertEqual(Set(snapshot.buckets.keys), ["d7", "mon", "tue"])
    }

    func testNoTimePassedChangesNothing() {
        let days = history(today: day("today", hours: 5, heard: 1))
        let first = WatchRules.check(previous: nil, days: days, now: now).snapshot
        let second = WatchRules.check(previous: first, days: days, now: now)
        XCTAssertEqual(second.events, [])
        XCTAssertEqual(second.snapshot.quietHours, 0)
    }

    func testBatteryLowIsToldOnceAndAgainAfterRecovering() {
        var snapshot = WatchRules.check(previous: nil, days: history(today: day("a", hours: 1, heard: 1, battery: 60)), now: now).snapshot
        var result = WatchRules.check(previous: snapshot, days: history(today: day("a", hours: 2, heard: 2, battery: 19.6)), now: now)
        XCTAssertEqual(result.events, [.batteryLow(percent: 20)])
        snapshot = result.snapshot
        result = WatchRules.check(previous: snapshot, days: history(today: day("a", hours: 3, heard: 3, battery: 12)), now: now)
        XCTAssertEqual(result.events, [])
        // A day without a reading says nothing; a day above the limit clears it.
        result = WatchRules.check(previous: result.snapshot, days: history(today: day("b", hours: 1, heard: 1)), now: now)
        XCTAssertEqual(result.events, [])
        XCTAssertNil(result.snapshot.battery)
        XCTAssertTrue(result.snapshot.toldBatteryLow)
        result = WatchRules.check(previous: result.snapshot, days: history(today: day("c", hours: 1, heard: 1, battery: 80)), now: now)
        XCTAssertFalse(result.snapshot.toldBatteryLow)
        result = WatchRules.check(previous: result.snapshot, days: history(today: day("c", hours: 2, heard: 2, battery: 15)), now: now)
        XCTAssertEqual(result.events, [.batteryLow(percent: 15)])
    }

    func testExternalPowerIsNoBattery() {
        let result = WatchRules.check(previous: NodeSnapshot(), days: history(today: day("a", hours: 1, heard: 1, battery: 101)), now: now)
        XCTAssertNil(result.snapshot.battery)
        XCTAssertEqual(result.events, [])
    }

    func testANodeWithoutHistory() {
        let result = WatchRules.check(previous: NodeSnapshot(), days: [], now: now)
        XCTAssertEqual(result.events, [])
        XCTAssertEqual(result.snapshot.hoursToday, 0)
    }

    func testEventTexts() {
        XCTAssertEqual(WatchRules.Event.quiet(hours: 7).text, "Not heard for about 7 h.")
        XCTAssertEqual(WatchRules.Event.heardAgain.text, "Heard again.")
        XCTAssertEqual(WatchRules.Event.batteryLow(percent: 15).text, "Battery down to 15 %.")
    }
}
