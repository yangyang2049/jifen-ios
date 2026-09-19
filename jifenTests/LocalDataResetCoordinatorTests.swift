import XCTest
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
        // Account credentials and purchase recovery data live in AuthTokenStore's
        // Keychain service and are intentionally outside this reset composition.
    }
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
