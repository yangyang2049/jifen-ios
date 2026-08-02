import ScoreCore
@testable import jifen
import XCTest

@MainActor
final class ScoreboardUsageHintTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ScoreboardUsageHintTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testCatalogAndDoublesCoverEveryExactScoreboardType() {
        XCTAssertEqual(GameCatalog.scoreboardItems.count, 23)

        let baseTypes = GameCatalog.scoreboardItems.compactMap {
            ScoreboardUsageHintDescriptor.resolve(gameType: $0.gameType, setup: nil)?.gameType
        }
        let doublesTypes = singlesDoublesFamilies.compactMap { family in
            var setup = SportsSetupResult(team1Name: "A", team2Name: "B")
            setup.isSingles = false
            return ScoreboardUsageHintDescriptor.resolve(
                gameType: family.appType,
                setup: setup
            )?.gameType
        }
        let covered = Set(baseTypes + doublesTypes)

        XCTAssertEqual(covered.count, 28)
        XCTAssertEqual(covered, Set(ScoreCore.GameType.allCases))
    }

    func testEveryExactTypeHasUniqueCopyAndPermanentStorageKey() {
        let store = ScoreboardUsageHintStore(defaults: defaults)
        let descriptors = ScoreCore.GameType.allCases.map(ScoreboardUsageHintDescriptor.init)

        XCTAssertEqual(Set(descriptors.map(\.localizationKey)).count, descriptors.count)
        XCTAssertEqual(Set(descriptors.map(store.key)).count, descriptors.count)
        XCTAssertTrue(descriptors.allSatisfy {
            store.key(for: $0).hasPrefix("scoreboard_usage_hint_shown_once_")
        })
        for descriptor in descriptors {
            XCTAssertFalse(descriptor.localizedMessage.isEmpty)
            XCTAssertNotEqual(descriptor.localizedMessage, descriptor.localizationKey)
        }
    }

    func testEverySinglesAndDoublesFamilyUsesIndependentCopyAndShownFlag() throws {
        let store = ScoreboardUsageHintStore(defaults: defaults)

        for family in singlesDoublesFamilies {
            var setup = SportsSetupResult(team1Name: "A", team2Name: "B")
            setup.isSingles = true
            let singles = try XCTUnwrap(ScoreboardUsageHintDescriptor.resolve(
                gameType: family.appType,
                setup: setup
            ))

            setup.isSingles = false
            let doubles = try XCTUnwrap(ScoreboardUsageHintDescriptor.resolve(
                gameType: family.appType,
                setup: setup
            ))

            XCTAssertEqual(singles.gameType, family.singlesType)
            XCTAssertEqual(doubles.gameType, family.doublesType)
            XCTAssertNotEqual(singles.localizationKey, doubles.localizationKey)
            XCTAssertNotEqual(store.key(for: singles), store.key(for: doubles))

            store.markShown(singles)
            XCTAssertTrue(store.hasShown(singles))
            XCTAssertFalse(store.hasShown(doubles))
        }
    }

    func testLegacyExactVariantFlagStillSuppressesThatVariantAfterUpgrade() throws {
        let store = ScoreboardUsageHintStore(defaults: defaults)
        var setup = SportsSetupResult(team1Name: "A", team2Name: "B")
        setup.isSingles = false
        let doubles = try XCTUnwrap(ScoreboardUsageHintDescriptor.resolve(
            gameType: .tennis,
            setup: setup
        ))
        defaults.set(
            true,
            forKey: "scoreboard_usage_hint_shown_v1_\(ScoreCore.GameType.tennisDoubles.rawValue)"
        )

        XCTAssertTrue(store.hasShown(doubles))
    }

    func testExactResumeTypeOverridesCollapsedFamilyAndSetup() throws {
        var setup = SportsSetupResult(team1Name: "A", team2Name: "B")
        setup.isSingles = true

        let descriptor = try XCTUnwrap(ScoreboardUsageHintDescriptor.resolve(
            gameType: .tennis,
            setup: setup,
            exactGameType: .tennisDoubles
        ))

        XCTAssertEqual(descriptor.gameType, .tennisDoubles)
    }

    func testCoordinatorOnlyAutoPresentsUntilEitherDismissActionMarksShown() {
        let descriptor = ScoreboardUsageHintDescriptor(gameType: .basketball)
        let store = ScoreboardUsageHintStore(defaults: defaults)
        let coordinator = ScoreboardUsageHintCoordinator(descriptor: descriptor, store: store)

        coordinator.presentAutomaticallyIfNeeded()
        XCTAssertTrue(coordinator.isPresented)

        coordinator.dismissAndMarkShown()
        XCTAssertFalse(coordinator.isPresented)
        XCTAssertTrue(store.hasShown(descriptor))

        coordinator.presentAutomaticallyIfNeeded()
        XCTAssertFalse(coordinator.isPresented)

        coordinator.presentFromMenu()
        XCTAssertTrue(coordinator.isPresented)
        coordinator.dismissAndMarkShown()
        XCTAssertFalse(coordinator.isPresented)
    }

    func testAutomaticPresentationPolicyExcludesRecordReplayAndWatchLinkedStarts() {
        XCTAssertTrue(ScoreboardUsageHintAutomaticPresentationPolicy.allows(
            requested: true,
            setup: nil
        ))
        XCTAssertFalse(ScoreboardUsageHintAutomaticPresentationPolicy.allows(
            requested: false,
            setup: nil
        ))

        var watchSetup = SportsSetupResult(team1Name: "A", team2Name: "B")
        watchSetup.startOnWatch = true
        XCTAssertFalse(ScoreboardUsageHintAutomaticPresentationPolicy.allows(
            requested: true,
            setup: watchSetup
        ))

        watchSetup.startOnWatch = false
        watchSetup.linkedWatchSessionId = UUID()
        XCTAssertFalse(ScoreboardUsageHintAutomaticPresentationPolicy.allows(
            requested: true,
            setup: watchSetup
        ))
    }

    func testUsageHintMenuActionRemainsAvailableWhileWatchScoringIsLocked() {
        XCTAssertTrue(ScoreboardMenuActionPolicy.isAllowedWhileScoringLocked("usageHint"))
    }

    func testDialogTypographyIsRoomierOnPadWhilePhoneMetricsStayUnchanged() {
        let phone = ScoreboardUsageHintDialogMetrics.resolve(
            isPad: false,
            compactHeight: false
        )
        let pad = ScoreboardUsageHintDialogMetrics.resolve(
            isPad: true,
            compactHeight: false
        )

        XCTAssertEqual(phone.titleFontSize, 20)
        XCTAssertEqual(phone.bodyFontSize, 15)
        XCTAssertEqual(phone.bodyLineSpacing, 0)
        XCTAssertEqual(phone.buttonFontSize, 16)
        XCTAssertEqual(phone.buttonHeight, 44)

        XCTAssertEqual(pad.titleFontSize, 24)
        XCTAssertEqual(pad.bodyFontSize, 19)
        XCTAssertEqual(pad.bodyLineSpacing, 7)
        XCTAssertEqual(pad.buttonFontSize, 18)
        XCTAssertEqual(pad.buttonHeight, 50)
        XCTAssertGreaterThan(pad.horizontalPadding, phone.horizontalPadding)
        XCTAssertGreaterThan(pad.verticalPadding, phone.verticalPadding)
    }

    func testCompactPadDialogRetainsLargerBodyTypeWithoutIncreasingButtonHeight() {
        let compactPhone = ScoreboardUsageHintDialogMetrics.resolve(
            isPad: false,
            compactHeight: true
        )
        let compactPad = ScoreboardUsageHintDialogMetrics.resolve(
            isPad: true,
            compactHeight: true
        )

        XCTAssertGreaterThan(compactPad.bodyFontSize, compactPhone.bodyFontSize)
        XCTAssertGreaterThan(compactPad.bodyLineSpacing, compactPhone.bodyLineSpacing)
        XCTAssertEqual(compactPad.buttonHeight, compactPhone.buttonHeight)
    }

    private var singlesDoublesFamilies: [(
        appType: jifen.GameType,
        singlesType: ScoreCore.GameType,
        doublesType: ScoreCore.GameType
    )] {
        [
            (.pingpong, .pingpong, .pingpongDoubles),
            (.badminton, .badminton, .badmintonDoubles),
            (.tennis, .tennis, .tennisDoubles),
            (.pickleball, .pickleball, .pickleballDoubles),
            (.foosball, .foosball, .foosballDoubles)
        ]
    }
}
