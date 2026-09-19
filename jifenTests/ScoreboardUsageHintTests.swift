import CoreGraphics
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
        XCTAssertEqual(GameCatalog.scoreboardItems.count, 29)

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

        XCTAssertEqual(covered.count, 34)
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

    func testAutomaticPresentationPolicyExcludesRecordReplay() {
        XCTAssertTrue(ScoreboardUsageHintAutomaticPresentationPolicy.allows(
            requested: true,
            setup: nil
        ))
        XCTAssertFalse(ScoreboardUsageHintAutomaticPresentationPolicy.allows(
            requested: false,
            setup: nil
        ))


    }

    func testUsageHintMenuActionRemainsAvailableWhileWatchScoringIsLocked() {
        XCTAssertTrue(ScoreboardMenuActionPolicy.isAllowedWhileScoringLocked("usageHint"))
    }

    func testDialogTypographyKeepsReadablePhoneBodyAndRoomierPadLayout() {
        let phone = ScoreboardUsageHintDialogMetrics.resolve(
            isPad: false,
            compactHeight: false
        )
        let pad = ScoreboardUsageHintDialogMetrics.resolve(
            isPad: true,
            compactHeight: false
        )

        XCTAssertEqual(phone.titleFontSize, 20)
        XCTAssertEqual(phone.bodyFontSize, 17)
        XCTAssertEqual(phone.bodyLineSpacing, 4)
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

    func testCompactPhoneMatchesReadablePadBodyWithoutIncreasingButtonHeight() {
        let compactPhone = ScoreboardUsageHintDialogMetrics.resolve(
            isPad: false,
            compactHeight: true
        )
        let compactPad = ScoreboardUsageHintDialogMetrics.resolve(
            isPad: true,
            compactHeight: true
        )

        XCTAssertEqual(compactPhone.bodyFontSize, 17)
        XCTAssertEqual(compactPhone.bodyLineSpacing, 4)
        XCTAssertEqual(compactPad.bodyFontSize, compactPhone.bodyFontSize)
        XCTAssertEqual(compactPad.bodyLineSpacing, compactPhone.bodyLineSpacing)
        XCTAssertEqual(compactPad.buttonHeight, compactPhone.buttonHeight)
    }

    func testDoubleTapSubtractWhitelistMatchesAndroidTrueSource() {
        // 对齐安卓 supportsScoreboardDoubleTapSubtract：白名单逐项核对。
        let supported: Set<ScoreCore.GameType> = [
            .pingpong, .pingpongDoubles,
            .badminton, .badmintonDoubles, .shuttlecock, .squash,
            .volleyball, .beachVolleyball, .airVolleyball,
            .pickleball, .pickleballDoubles,
            .tennis, .tennisDoubles, .softTennis, .padel,
            .football, .football5v5,
            .foosball, .foosballDoubles,
            .billiards, .eightBall,
            .simpleScore, .multiScoreboard
        ]
        for type in ScoreCore.GameType.allCases {
            XCTAssertEqual(
                ScoreboardUsageHintHelper.supportsDoubleTapSubtract(type),
                supported.contains(type),
                "白名单不一致：\(type.rawValue)"
            )
        }
    }

    func testTouchGuardBlacklistMatchesAndroidTrueSource() {
        // 对齐安卓：斗地主/掼蛋/升级/UNO/多分数板固定不启用防误触。
        let disabled: Set<ScoreCore.GameType> = [.doudizhu, .guandan, .shengji, .uno, .multiScoreboard]
        for type in ScoreCore.GameType.allCases {
            XCTAssertEqual(
                ScoreboardUsageHintHelper.disablesTouchGuard(type),
                disabled.contains(type),
                "防误触豁免不一致：\(type.rawValue)"
            )
        }
    }

    func testTouchGuardOffAllowsAnyLocation() {
        let size = CGSize(width: 400, height: 800)
        XCTAssertTrue(ScoreboardTouchGuard.isAllowed(
            location: CGPoint(x: 4, y: 4),
            panelSize: size,
            gameType: .pingpong,
            enabled: false
        ))
        XCTAssertTrue(ScoreboardTouchGuard.isAllowed(
            location: CGPoint(x: 399, y: 799),
            panelSize: size,
            gameType: .pingpong,
            enabled: false
        ))
    }

    func testTouchGuardCenterRegionGeometry() {
        // 400×800 → 可点区域应为居中 60%：x∈[80,320)、y∈[160,640)。
        let size = CGSize(width: 400, height: 800)
        let enabled = true
        XCTAssertTrue(ScoreboardTouchGuard.isAllowed(
            location: CGPoint(x: 200, y: 400),
            panelSize: size,
            gameType: .pingpong,
            enabled: enabled
        ))
        XCTAssertTrue(ScoreboardTouchGuard.isAllowed(
            location: CGPoint(x: 80, y: 160),
            panelSize: size,
            gameType: .pingpong,
            enabled: enabled
        ))
        XCTAssertFalse(ScoreboardTouchGuard.isAllowed(
            location: CGPoint(x: 79, y: 160),
            panelSize: size,
            gameType: .pingpong,
            enabled: enabled
        ))
        XCTAssertFalse(ScoreboardTouchGuard.isAllowed(
            location: CGPoint(x: 200, y: 159),
            panelSize: size,
            gameType: .pingpong,
            enabled: enabled
        ))
        XCTAssertFalse(ScoreboardTouchGuard.isAllowed(
            location: CGPoint(x: 5, y: 700),
            panelSize: size,
            gameType: .pingpong,
            enabled: enabled
        ))
    }

    func testTouchGuardBlacklistIgnoresLocationEvenWhenEnabled() {
        let size = CGSize(width: 400, height: 800)
        for type in [ScoreCore.GameType.guandan, .shengji, .doudizhu, .uno, .multiScoreboard] {
            XCTAssertTrue(ScoreboardTouchGuard.isAllowed(
                location: CGPoint(x: 5, y: 700),
                panelSize: size,
                gameType: type,
                enabled: true
            ), "黑名单项目仍被防误触拦截：\(type.rawValue)")
        }
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
