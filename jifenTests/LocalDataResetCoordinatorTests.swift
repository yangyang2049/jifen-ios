import XCTest
import Combine
import Observation
@testable import jifen

@MainActor
final class LocalDataResetCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "LocalDataResetCoordinatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testPreferenceResetPreservesOnlyLegalDecisionAndFreshDefaultMarker() {
        defaults.set(LegalDocuments.currentVersion, forKey: LegalConsent.acceptedVersionKey)
        defaults.set(Data([1, 2, 3]), forKey: "quickStartConfig")
        defaults.set(true, forKey: "scoreboard_usage_hint_shown_once_pingpong")
        defaults.set(Data([4, 5]), forKey: "phone_link_terminal_outbox")
        defaults.set("old", forKey: "arbitrary_future_app_key")

        LocalPreferenceDataResetter.clear(defaults: defaults)

        XCTAssertEqual(
            defaults.string(forKey: LegalConsent.acceptedVersionKey),
            LegalDocuments.currentVersion
        )
        XCTAssertTrue(defaults.bool(forKey: LocalPreferenceDataResetter.postResetInitializationKey))
        XCTAssertNil(defaults.object(forKey: "quickStartConfig"))
        XCTAssertNil(defaults.object(forKey: "scoreboard_usage_hint_shown_once_pingpong"))
        XCTAssertNil(defaults.object(forKey: "phone_link_terminal_outbox"))
        XCTAssertNil(defaults.object(forKey: "arbitrary_future_app_key"))
    }

    func testCoordinatorContinuesAfterFailureAndReportsCategoryForSafeRetry() async {
        var completed: [LocalDataResetCategory] = []
        let coordinator = LocalDataResetCoordinator(steps: [
            LocalDataResetStep(category: .scoreboardRecords) {
                throw StubError.failed
            },
            LocalDataResetStep(category: .timerRecords) {
                completed.append(.timerRecords)
            },
            LocalDataResetStep(category: .resumeSessions) {
                completed.append(.resumeSessions)
            }
        ])

        let result = await coordinator.clearAll()

        XCTAssertEqual(completed, [.timerRecords, .resumeSessions])
        XCTAssertEqual(result.failures.map(\.category), [.scoreboardRecords])
        XCTAssertFalse(result.succeeded)
    }

    func testLiveResetScopeContainsOnlyUserGeneratedDataAndLocalPreferences() {
        let appearance = AppAppearanceStore(defaults: defaults)
        let coordinator = LocalDataResetCoordinator.live(
            appearance: appearance,
            defaults: defaults
        )

        XCTAssertEqual(
            coordinator.steps.map(\.category),
            [
                .activeSyncSession,
                .scoreboardRecords,
                .timerRecords,
                .bookingsAndNotifications,
                .resumeSessions,
                .legacySyncData,
                .localPreferencesAndTools,
            ]
        )
        // Account credentials live in the protected app-container auth file;
        // purchase recovery stays in Keychain. Both are outside this reset.
    }

    func testTimerLoadDiscardsSnapshotInvalidatedByClearBeforePublishing() async {
        let firstStarted = expectation(description: "First timer snapshot read")
        let secondStarted = expectation(description: "Fresh timer snapshot read")
        let loaded = expectation(description: "Only the fresh timer snapshot completes loading")
        let old = GameRecordSummary(id: "deleted-timer", gameType: .chess, timestamp: 1)
        let loader = BlockingRecordSnapshots(first: [old], next: [], firstStarted: firstStarted, nextStarted: secondStarted)
        defer { loader.releaseFirst(); loader.releaseNext() }
        let viewModel = TimerRecordsViewModel(recordsLoader: loader.load)
        var publishedIDs: [[String]] = []
        let recordsSubscription = viewModel.$records.dropFirst().sink { records in
            publishedIDs.append(records.map(\.id))
        }
        let loadedSubscription = viewModel.$hasLoaded.filter { $0 }.prefix(1).sink { _ in loaded.fulfill() }
        defer { recordsSubscription.cancel(); loadedSubscription.cancel() }

        viewModel.ensureLoaded()
        await fulfillment(of: [firstStarted], timeout: 3)
        // Clearing the store requests another load while the old read is blocked.
        viewModel.loadFromStorage()
        loader.releaseFirst()
        await fulfillment(of: [secondStarted], timeout: 3)
        XCTAssertTrue(publishedIDs.isEmpty)
        XCTAssertTrue(viewModel.records.isEmpty)
        XCTAssertFalse(viewModel.hasLoaded)
        XCTAssertTrue(viewModel.isLoading)

        loader.releaseNext()
        await fulfillment(of: [loaded], timeout: 3)
        XCTAssertEqual(publishedIDs, [[]])
        XCTAssertTrue(viewModel.records.isEmpty)
        XCTAssertTrue(viewModel.groupedRecords.isEmpty)
        XCTAssertTrue(viewModel.hasLoaded)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testScoreboardLoadDiscardsSnapshotInvalidatedByClearBeforePublishing() async {
        let firstStarted = expectation(description: "First score snapshot read")
        let secondStarted = expectation(description: "Fresh score snapshot read")
        let loaded = expectation(description: "Only the fresh score snapshot completes loading")
        let old = ScoreboardRecordSummary(from: ScoreboardRecord(id: "deleted-score", gameType: .pingpong,
            startTime: Date(timeIntervalSince1970: 1), team1Name: "甲", team2Name: "乙",
            team1FinalScore: 11, team2FinalScore: 9, totalScoreChanges: 1))
        let loader = BlockingRecordSnapshots(first: [old], next: [], firstStarted: firstStarted, nextStarted: secondStarted)
        defer { loader.releaseFirst(); loader.releaseNext() }
        let viewModel = ScoreboardRecordsViewModel(summaryLoader: loader.load, notificationCenter: NotificationCenter())
        let publications = RecordPublicationCounter()
        withObservationTracking {
            _ = viewModel.records
        } onChange: {
            publications.increment()
        }
        withObservationTracking {
            _ = viewModel.hasLoaded
        } onChange: {
            loaded.fulfill()
        }

        viewModel.ensureLoaded()
        await fulfillment(of: [firstStarted], timeout: 3)
        viewModel.refreshRecordsImmediately()
        loader.releaseFirst()
        await fulfillment(of: [secondStarted], timeout: 3)
        XCTAssertEqual(publications.count, 0)
        XCTAssertTrue(viewModel.records.isEmpty)
        XCTAssertFalse(viewModel.hasLoaded)
        XCTAssertTrue(viewModel.isLoading)

        loader.releaseNext()
        await fulfillment(of: [loaded], timeout: 3)
        // Observation may suppress an empty-to-empty assignment. Any callback
        // must occur only after the fresh read has been released.
        XCTAssertLessThanOrEqual(publications.count, 1)
        XCTAssertTrue(viewModel.records.isEmpty)
        XCTAssertTrue(viewModel.groupedRecords.isEmpty)
        XCTAssertTrue(viewModel.hasLoaded)
        XCTAssertFalse(viewModel.isLoading)
    }
}

/// Both reads are gated independently so the test can inspect the state between
/// discarding the invalidated snapshot and publishing the replacement.
private final class BlockingRecordSnapshots<Record>: @unchecked Sendable {
    private let first: [Record]
    private let next: [Record]
    private let firstStarted: XCTestExpectation
    private let nextStarted: XCTestExpectation
    private let firstGate = DispatchSemaphore(value: 0)
    private let nextGate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var reads = 0

    init(first: [Record], next: [Record], firstStarted: XCTestExpectation, nextStarted: XCTestExpectation) {
        self.first = first; self.next = next
        self.firstStarted = firstStarted; self.nextStarted = nextStarted
    }

    func load() -> [Record] {
        lock.lock()
        reads += 1
        let read = reads
        lock.unlock()
        if read == 1 {
            firstStarted.fulfill()
            _ = firstGate.wait(timeout: .now() + 10)
            return first
        }
        nextStarted.fulfill()
        _ = nextGate.wait(timeout: .now() + 10)
        return next
    }

    func releaseFirst() { firstGate.signal() }
    func releaseNext() { nextGate.signal() }
}

private final class RecordPublicationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func increment() { lock.lock(); defer { lock.unlock() }; value += 1 }
}

@MainActor
final class OfflinePreferenceMigrationTests: XCTestCase {
    func testFreshInstallKeepsDoubleTapSubtractDisabled() {
        withDefaults { defaults in
            let manager = PreferencesManager(defaults: defaults)
            manager.migrateLegacyDoubleTapSubtractIfNeeded(hasLegalConsent: false)
            XCTAssertFalse(manager.scoreboardDoubleTapSubtractEnabled)
        }
    }

    func testExistingConsentedInstallMigratesDoubleTapSubtractToEnabledOnce() {
        withDefaults { defaults in
            let manager = PreferencesManager(defaults: defaults)
            manager.migrateLegacyDoubleTapSubtractIfNeeded(hasLegalConsent: true)
            XCTAssertTrue(manager.scoreboardDoubleTapSubtractEnabled)

            manager.scoreboardDoubleTapSubtractEnabled = false
            manager.migrateLegacyDoubleTapSubtractIfNeeded(hasLegalConsent: true)
            XCTAssertFalse(manager.scoreboardDoubleTapSubtractEnabled)
        }
    }

    func testMatchTimePreferenceIsProjectScopedAndDefaultsOff() {
        withDefaults { defaults in
            let manager = PreferencesManager(defaults: defaults)
            XCTAssertFalse(manager.scoreboardMatchTimeVisible(for: .pingpong))
            XCTAssertFalse(manager.scoreboardMatchTimeVisible(for: .volleyball))

            manager.setScoreboardMatchTimeVisible(true, for: .pingpong)
            manager.setScoreboardMatchTimeVisible(true, for: .airVolleyball)

            XCTAssertTrue(manager.scoreboardMatchTimeVisible(for: .pingpong))
            XCTAssertTrue(manager.scoreboardMatchTimeVisible(for: .airVolleyball))
            XCTAssertFalse(manager.scoreboardMatchTimeVisible(for: .volleyball))
            XCTAssertFalse(manager.scoreboardMatchTimeVisible(for: .beachVolleyball))
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "OfflinePreferenceMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        body(defaults)
        defaults.removePersistentDomain(forName: suite)
    }
}

private enum StubError: Error {
    case failed
}
