import XCTest
@testable import jifen

final class TimerAndToolOfflineTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "TimerAndToolOfflineTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testStopwatchPersistsRunningStateAcrossBackgroundAndCapsLapsAt99() {
        let now = Date(timeIntervalSince1970: 10_000)
        let state = StopwatchPersistedState(
            phase: .running,
            baseMilliseconds: 1_250,
            runStartedAt: now.timeIntervalSince1970 * 1_000 - 2_000,
            lapCumulativeMilliseconds: Array(repeating: 1, count: StopwatchPolicy.maximumLapCount)
        )

        TimerToolStateStore.saveStopwatch(state, defaults: defaults)
        let restored = TimerToolStateStore.loadStopwatch(defaults: defaults)

        XCTAssertEqual(StopwatchPolicy.maximumLapCount, 99)
        XCTAssertEqual(restored.phase, .running)
        XCTAssertEqual(restored.lapCumulativeMilliseconds.count, 99)
        XCTAssertEqual(restored.elapsedMilliseconds(at: now), 3_250, accuracy: 0.001)
    }

    func testCountdownPersistsAndResetClearsBothTimerTools() {
        let state = CountdownPersistedState(
            phase: .paused,
            durationSeconds: 180,
            lastDurationSeconds: 180,
            endAt: 0,
            remainingMilliseconds: 42_500
        )
        TimerToolStateStore.saveCountdown(state, defaults: defaults)
        XCTAssertEqual(
            TimerToolStateStore.loadCountdown(defaults: defaults).remainingMilliseconds,
            42_500
        )

        TimerToolStateStore.clear(defaults: defaults)

        XCTAssertEqual(TimerToolStateStore.loadStopwatch(defaults: defaults).phase, .idle)
        XCTAssertEqual(TimerToolStateStore.loadCountdown(defaults: defaults).phase, .idle)
    }

    func testPointsTablePersistsAndCanBeCompletelyCleared() {
        let record = PointsTableRecord(
            id: "league",
            name: "周末联赛",
            teams: [PointsTableTeam(name: "A", win: 2, draw: 1)]
        )
        PointsTableStorage.save([record], defaults: defaults)
        XCTAssertEqual(PointsTableStorage.load(defaults: defaults), [record])

        PointsTableStorage.clear(defaults: defaults)
        XCTAssertTrue(PointsTableStorage.load(defaults: defaults).isEmpty)
    }

    func testAACalculationRejectsInvalidBoundaryValues() {
        XCTAssertNil(AACalculationPolicy.amountPerPerson(totalText: "", participants: 2))
        XCTAssertNil(AACalculationPolicy.amountPerPerson(totalText: "0", participants: 2))
        XCTAssertNil(AACalculationPolicy.amountPerPerson(totalText: "-1", participants: 2))
        XCTAssertNil(AACalculationPolicy.amountPerPerson(totalText: "nan", participants: 2))
        XCTAssertNil(AACalculationPolicy.amountPerPerson(totalText: "100", participants: 1))
        XCTAssertNil(AACalculationPolicy.amountPerPerson(totalText: "100", participants: 21))
        XCTAssertEqual(
            AACalculationPolicy.amountPerPerson(totalText: "100", participants: 3)!,
            100.0 / 3.0,
            accuracy: 0.000_001
        )
    }

    func testTenSecondChallengeDifferencePolicy() {
        XCTAssertEqual(TenSecondChallengePolicy.absoluteDifference(milliseconds: 10_000), 0)
        XCTAssertEqual(TenSecondChallengePolicy.absoluteDifference(milliseconds: 9_950), 50)
        XCTAssertEqual(TenSecondChallengePolicy.absoluteDifference(milliseconds: 10_125), 125)
        XCTAssertEqual(TenSecondChallengePolicy.absoluteDifference(milliseconds: -10), 10_000)
        XCTAssertEqual(TenSecondChallengePolicy.automaticStopMilliseconds, 59_990)
    }

    func testCubeRequiresHalfSecondHoldAndDoesNotCreateHistory() {
        XCTAssertEqual(CubeTimerPolicy.readinessHoldDuration, 0.5)
        XCTAssertFalse(CubeTimerPolicy.createsHistoryRecord)
    }
}
