import XCTest
import ScoreCore
@testable import jifen

@MainActor
final class LocalScoreboardDisplayStateTests: XCTestCase {
    func testMutationPolicyBlocksEditingFinishedAndFollowerStates() {
        XCTAssertTrue(LocalScoreboardMutationPolicy.allowsMutation(
            isEditing: false,
            finished: false,
            scoringLocked: false
        ))
        XCTAssertFalse(LocalScoreboardMutationPolicy.allowsMutation(
            isEditing: true,
            finished: false,
            scoringLocked: false
        ))
        XCTAssertFalse(LocalScoreboardMutationPolicy.allowsMutation(
            isEditing: false,
            finished: true,
            scoringLocked: false
        ))
        XCTAssertFalse(LocalScoreboardMutationPolicy.allowsMutation(
            isEditing: false,
            finished: false,
            scoringLocked: true
        ))
    }

    @MainActor
    func testLegacySnapshotWithoutKeyPointStillDecodes() throws {
        let json = #"{"gameID":"badminton","title":"羽毛球","leftName":"A","rightName":"B","leftScore":"20","rightScore":"18","themeID":"default","fontID":"default","finished":false,"revision":3}"#
        let state = try JSONDecoder().decode(LocalScoreboardDisplayState.self, from: Data(json.utf8))

        XCTAssertNil(state.keyPoint)
        XCTAssertEqual(state.revision, 3)
    }

    @MainActor
    func testKeyPointRoundTripPreservesSemanticKindAndScreenSide() throws {
        let state = LocalScoreboardDisplayState(
            gameID: "tennis",
            title: "网球",
            leftName: "A",
            rightName: "B",
            leftScore: "40",
            rightScore: "30",
            themeID: "default",
            fontID: "default",
            finished: false,
            keyPoint: LocalScoreboardKeyPoint(
                status: KeyPointStatus(kind: .set, side: .right),
                sidesSwapped: false
            ),
            revision: 4
        )

        let decoded = try JSONDecoder().decode(
            LocalScoreboardDisplayState.self,
            from: JSONEncoder().encode(state)
        )
        XCTAssertEqual(decoded.keyPoint?.kind, .set)
        XCTAssertEqual(decoded.keyPoint?.side, .right)
        XCTAssertTrue(decoded.keyPoint?.isRenderable == true)
    }

    @MainActor
    func testUnknownKeyPointValuesDoNotRejectTheScoreSnapshot() throws {
        let json = #"{"gameID":"badminton","title":"羽毛球","leftName":"A","rightName":"B","leftScore":"20","rightScore":"18","themeID":"default","fontID":"default","finished":false,"keyPoint":{"kind":"future","side":"middle"},"revision":5}"#
        let state = try JSONDecoder().decode(LocalScoreboardDisplayState.self, from: Data(json.utf8))

        XCTAssertEqual(state.keyPoint?.kind, .unknown)
        XCTAssertEqual(state.keyPoint?.side, .unknown)
        XCTAssertFalse(state.keyPoint?.isRenderable ?? true)
    }

    func testSideSwapIsAppliedBeforePublishing() {
        let keyPoint = LocalScoreboardKeyPoint(
            status: KeyPointStatus(kind: .match, side: .left),
            sidesSwapped: true
        )

        XCTAssertEqual(keyPoint?.kind, .match)
        XCTAssertEqual(keyPoint?.side, .right)
    }

    func testEditingAndFinishedSnapshotsOmitKeyPoint() {
        let keyPoint = LocalScoreboardKeyPoint(
            status: KeyPointStatus(kind: .match, side: .left),
            sidesSwapped: false
        )

        XCTAssertEqual(
            LocalScoreboardKeyPoint.syncValue(keyPoint, finished: false, isEditing: false),
            keyPoint
        )
        XCTAssertNil(LocalScoreboardKeyPoint.syncValue(keyPoint, finished: false, isEditing: true))
        XCTAssertNil(LocalScoreboardKeyPoint.syncValue(keyPoint, finished: true, isEditing: false))
    }

    func testTennisTiebreakOnlySevenAndTenOmitGameAndSetDetails() {
        for target in [7, 10] {
            var state = TennisMatchState(
                leftName: "A",
                rightName: "B",
                rules: TennisRuleSet(
                    maxSets: 1,
                    tieBreakPoints: target,
                    setScoringMode: .tiebreakOnly
                )
            )
            state.leftPoints = target - 1
            state.rightPoints = target - 3
            state.leftGames = 1
            state.leftSets = 1

            XCTAssertNil(tennisLocalSyncDetail(state: state, side: .left))
            XCTAssertNil(tennisLocalSyncDetail(state: state, side: .right))
        }
    }

    func testRegularTennisKeepsGameAndSetDetails() {
        var state = TennisMatchState(leftName: "A", rightName: "B")
        state.leftGames = 5
        state.leftSets = 1

        XCTAssertNotNil(tennisLocalSyncDetail(state: state, side: .left))
    }

    func testBadgeCenterUsesCompactAndLargeViewportSpacing() {
        XCTAssertEqual(
            ScoreboardServeGeometry.keyPointBadgeCenterY(
                height: 360,
                doublesTopRow: nil,
                largeWindow: false,
                triangleSize: 36
            ),
            138
        )
        XCTAssertEqual(
            ScoreboardServeGeometry.keyPointBadgeCenterY(
                height: 640,
                doublesTopRow: nil,
                largeWindow: true,
                triangleSize: 36
            ),
            274
        )
    }

    func testDoublesBadgeFollowsTheActiveServingRow() {
        let topAnchor = ScoreboardServeGeometry.doublesAnchorY(height: 600, topRow: true)
        let bottomAnchor = ScoreboardServeGeometry.doublesAnchorY(height: 600, topRow: false)

        XCTAssertEqual(topAnchor, 100)
        XCTAssertEqual(bottomAnchor, 500)
        XCTAssertEqual(
            ScoreboardServeGeometry.keyPointBadgeCenterY(
                height: 600,
                doublesTopRow: true,
                largeWindow: true,
                triangleSize: 64
            ),
            100
        )
        XCTAssertEqual(
            ScoreboardServeGeometry.keyPointBadgeCenterY(
                height: 600,
                doublesTopRow: false,
                largeWindow: true,
                triangleSize: 64
            ),
            500
        )
    }

    func testBadgeSpacingUsesTheRenderedServeIndicatorSize() {
        XCTAssertEqual(
            ScoreboardServeGeometry.keyPointBadgeCenterY(
                height: 640,
                doublesTopRow: nil,
                largeWindow: true,
                triangleSize: 64
            ),
            260
        )
        XCTAssertEqual(
            ScoreboardServeGeometry.keyPointBadgeHorizontalOffset(
                doublesTopRow: nil,
                triangleSize: 64
            ),
            40
        )
        XCTAssertEqual(
            ScoreboardServeGeometry.keyPointBadgeHorizontalOffset(
                doublesTopRow: true,
                triangleSize: 64
            ),
            104
        )
    }

    func testResponsiveInlineGapAndServeIndicatorStayWithinBounds() {
        XCTAssertEqual(ScoreboardLayoutMetrics.inlineMainToSecondarySpacing(halfViewportWidth: 320), 32)
        XCTAssertEqual(ScoreboardLayoutMetrics.inlineMainToSecondarySpacing(halfViewportWidth: 600), 60)
        XCTAssertEqual(ScoreboardLayoutMetrics.inlineMainToSecondarySpacing(halfViewportWidth: 1_000), 72)

        XCTAssertEqual(
            ScoreboardLayoutMetrics.serveIndicatorSize(
                halfViewportSize: CGSize(width: 320, height: 360)
            ),
            36
        )
        XCTAssertEqual(
            ScoreboardLayoutMetrics.serveIndicatorSize(
                halfViewportSize: CGSize(width: 500, height: 700)
            ),
            52
        )
        XCTAssertEqual(
            ScoreboardLayoutMetrics.serveIndicatorSize(
                halfViewportSize: CGSize(width: 900, height: 700)
            ),
            64
        )

        for shortEdge in stride(from: CGFloat(320), through: 720, by: 20) {
            let size = ScoreboardLayoutMetrics.serveIndicatorSize(
                halfViewportSize: CGSize(width: shortEdge, height: shortEdge + 100)
            )
            XCTAssertEqual(size.truncatingRemainder(dividingBy: 4), 0)
        }
    }

    func testDoublesScoreRegionScalesFromPhoneToTabletGeometry() {
        XCTAssertEqual(
            ScoreboardLayoutMetrics.doublesScoreRegionHeight(panelHeight: 360),
            201.6,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ScoreboardLayoutMetrics.doublesScoreRegionHeight(panelHeight: 1_000),
            600,
            accuracy: 0.001
        )
    }

    func testDoublesTypographyUsesFullPanelBaselineAndMeasuredOverlayLimits() {
        let preference = ScoreboardTypographyPreference.default(font: .default)
        let cellSize = CGSize(width: 500, height: 380)
        let rowBased = ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .rally,
                containerSize: cellSize,
                nameText: "",
                scoreText: "15",
                preference: preference
            )
        )
        let panelBased = ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .rally,
                containerSize: cellSize,
                nameText: "",
                scoreText: "15",
                preference: preference,
                referenceHeight: 700
            )
        )

        XCTAssertGreaterThan(panelBased.scoreFontSize, rowBased.scoreFontSize)
        XCTAssertLessThanOrEqual(panelBased.scoreFontSize, cellSize.height * 0.88)
    }

    func testInlineSecondaryUsesWidthBudgetWithoutStealingScoreHeight() {
        let preference = ScoreboardTypographyPreference.default(font: .default)
        let stacked = ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .rally,
                containerSize: CGSize(width: 500, height: 220),
                nameText: "",
                scoreText: "15",
                secondaryText: "2",
                preference: preference,
                referenceHeight: 680
            )
        )
        let inline = ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .rally,
                containerSize: CGSize(width: 500, height: 220),
                nameText: "",
                scoreText: "15",
                secondaryText: "2",
                preference: preference,
                secondaryIsInline: true,
                referenceHeight: 680
            )
        )

        XCTAssertGreaterThan(inline.scoreFontSize, stacked.scoreFontSize)
        XCTAssertEqual(inline.mainToSecondarySpacing, 50)
    }

    func testCenterLineServeIndicatorTouchesLineAndPointsTowardServer() {
        XCTAssertEqual(ScoreboardServeGeometry.centerLineDirection(isLeftServing: true), .left)
        XCTAssertEqual(ScoreboardServeGeometry.centerLineDirection(isLeftServing: false), .right)
        XCTAssertEqual(
            ScoreboardServeGeometry.centerLineOffsetX(isLeftServing: true, triangleSize: 52),
            -26
        )
        XCTAssertEqual(
            ScoreboardServeGeometry.centerLineOffsetX(isLeftServing: false, triangleSize: 52),
            26
        )
    }

    func testResponsiveTeamNameSizeUsesTheSharedHeightCurve() {
        XCTAssertEqual(ScoreboardLayoutMetrics.teamNameFontSize(halfViewportHeight: 360), 36)
        XCTAssertEqual(ScoreboardLayoutMetrics.teamNameFontSize(halfViewportHeight: 600), 48)
        XCTAssertEqual(ScoreboardLayoutMetrics.teamNameFontSize(halfViewportHeight: 1_200), 72)
    }

    func testAdditionalDialogRolesUseSharedWidthPolicy() {
        XCTAssertEqual(
            Theme.dialogWidth(availableWidth: 300, role: .scoreAdjustment),
            268
        )
        XCTAssertEqual(
            Theme.dialogPreferredWidth(role: .scoreAdjustment),
            600
        )
        XCTAssertEqual(
            Theme.dialogPreferredWidth(role: .scoreboardDisplaySettings),
            Theme.usesPadLayout ? 500 : 360
        )
    }

    func testTypographyRegistryCoversAllScoreboardEntriesAndVariants() {
        let entryStyles = Set(
            ScoreboardStyleID.registeredEntryGameTypes.map(ScoreboardStyleID.init(gameType:))
        )
        XCTAssertEqual(ScoreboardStyleID.registeredEntryGameTypes.count, 23)
        XCTAssertEqual(entryStyles.count, 23)
        XCTAssertTrue(entryStyles.isSubset(of: ScoreboardStyleID.registeredScoreboardStyles))
        for gameType in ScoreCore.GameType.allCases {
            XCTAssertTrue(
                ScoreboardStyleID.registeredScoreboardStyles.contains(
                    ScoreboardStyleID(scoreCoreGameType: gameType)
                ),
                "Missing typography style for \(gameType.rawValue)"
            )
        }
        XCTAssertNotEqual(
            ScoreboardStyleID(scoreCoreGameType: .tennis),
            ScoreboardStyleID(scoreCoreGameType: .tennisDoubles)
        )
        XCTAssertNotEqual(
            ScoreboardStyleID(scoreCoreGameType: .foosball),
            ScoreboardStyleID(scoreCoreGameType: .foosballDoubles)
        )
    }

    func testTypographyResolverLimitsLongNamesAndMultiDigitScores() {
        let preference = ScoreboardTypographyPreference.default(font: .default)
        let short = ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .standard,
                containerSize: CGSize(width: 260, height: 520),
                nameText: "A",
                scoreText: "9",
                preference: preference
            )
        )
        let constrained = ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .standard,
                containerSize: CGSize(width: 260, height: 520),
                nameText: "这是一个很长很长的队伍名称",
                scoreText: "-123456789",
                preference: preference
            )
        )

        XCTAssertLessThan(constrained.nameFontSize, short.nameFontSize)
        XCTAssertLessThan(constrained.scoreFontSize, short.scoreFontSize)
        XCTAssertLessThanOrEqual(constrained.nameToScoreSpacing, short.nameToScoreSpacing)
    }

    func testTypographyResolverReservesExtraUnoAndNineBallRegions() {
        let preference = ScoreboardTypographyPreference.default(font: .default)
        func result(_ profile: ScoreboardTypographyProfile) -> ScoreboardTypographyResult {
            ScoreboardTypographyResolver.resolve(
                ScoreboardTypographyLayoutContext(
                    profile: profile,
                    containerSize: CGSize(width: 600, height: 150),
                    nameText: "Player",
                    scoreText: "128",
                    secondaryText: "500 372 UNO",
                    preference: preference
                )
            )
        }

        XCTAssertLessThan(result(.uno).scoreFontSize, result(.multi).scoreFontSize)
        XCTAssertLessThanOrEqual(result(.nineBall).scoreFontSize, result(.multi).scoreFontSize)
    }

    func testNineBallRowsAdaptForTwoThreeAndFourPlayers() {
        let wide = CGSize(width: 1_000, height: 500)
        let narrow = CGSize(width: 500, height: 800)

        XCTAssertEqual(ScoreboardPlayerGridLayout.nineBallRows(playerCount: 2, containerSize: narrow), [[0, 1]])
        XCTAssertEqual(ScoreboardPlayerGridLayout.nineBallRows(playerCount: 3, containerSize: wide), [[0, 1, 2]])
        XCTAssertEqual(ScoreboardPlayerGridLayout.nineBallRows(playerCount: 4, containerSize: wide), [[0, 1, 2, 3]])
        XCTAssertEqual(ScoreboardPlayerGridLayout.nineBallRows(playerCount: 3, containerSize: narrow), [[0], [1], [2]])
        XCTAssertEqual(ScoreboardPlayerGridLayout.nineBallRows(playerCount: 4, containerSize: narrow), [[0, 1], [2, 3]])
    }

    func testMultiRowsCoverTwoThroughTenPlayersAndCountPlaceholdersInWidth() {
        for count in 2...10 {
            for usesWideLayout in [false, true] {
                let rows = ScoreboardPlayerGridLayout.multiRows(
                    playerCount: count,
                    usesWideLayout: usesWideLayout
                )
                let playerIndices = rows.flatMap { $0 }.compactMap { $0 }
                XCTAssertEqual(playerIndices.sorted(), Array(0..<count))
            }
        }
        XCTAssertEqual(
            ScoreboardPlayerGridLayout.multiRows(playerCount: 5, usesWideLayout: true).map(\.count),
            [3, 3]
        )
        XCTAssertEqual(
            ScoreboardPlayerGridLayout.multiRows(playerCount: 8, usesWideLayout: false)[1],
            [3, nil, 4]
        )
    }

    func testTypographyMultiplierScalesWithoutChangingTheStoredRequest() {
        let normalPreference = ScoreboardTypographyPreference.default(font: .default)
        let enlargedPreference = ScoreboardTypographyPreference(
            font: .default,
            scoreMultiplier: 1.5,
            nameMultiplier: 1.5,
            secondaryMultiplier: 1.5
        )
        let size = CGSize(width: 900, height: 700)
        let normal = ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .standard,
                containerSize: size,
                nameText: "A",
                scoreText: "8",
                secondaryText: "1",
                preference: normalPreference
            )
        )
        let enlarged = ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .standard,
                containerSize: size,
                nameText: "A",
                scoreText: "8",
                secondaryText: "1",
                preference: enlargedPreference
            )
        )

        XCTAssertGreaterThan(enlarged.nameFontSize, normal.nameFontSize)
        XCTAssertGreaterThan(enlarged.scoreFontSize, normal.scoreFontSize)
        XCTAssertGreaterThan(enlarged.secondaryFontSize, normal.secondaryFontSize)
        XCTAssertEqual(enlargedPreference.scoreMultiplier, 1.5)
    }

    func testTypographyMultiplierRangesDifferOnlyAtTheLowerBound() {
        XCTAssertEqual(ScoreboardFontSizePolicy.range(isLargeScreen: false), 0.8 ... 1.5)
        XCTAssertEqual(ScoreboardFontSizePolicy.range(isLargeScreen: true), 0.7 ... 1.5)
        XCTAssertEqual(ScoreboardFontSizePolicy.normalized(0.71, isLargeScreen: true), 0.7, accuracy: 0.0001)
        XCTAssertEqual(ScoreboardFontSizePolicy.normalized(0.71, isLargeScreen: false), 0.8, accuracy: 0.0001)
        XCTAssertEqual(ScoreboardFontSizePolicy.normalized(1.53, isLargeScreen: false), 1.5, accuracy: 0.0001)
    }

    func testProjectTypographyStorageIsIsolatedAndUnversioned() throws {
        let preferences = PreferencesManager.shared
        let first = ScoreboardStyleID(rawValue: "test_\(UUID().uuidString)")
        let second = ScoreboardStyleID(rawValue: "test_\(UUID().uuidString)")
        defer {
            preferences.resetScoreboardTypography(for: first)
            preferences.resetScoreboardTypography(for: second)
        }
        let defaultFontBefore = preferences.defaultScoreboardFont
        let revisionBefore = preferences.scoreboardRevision
        let stored = ScoreboardTypographyPreference(
            font: .sports,
            scoreMultiplier: 1.25,
            nameMultiplier: 0.9,
            secondaryMultiplier: 1.1
        )

        preferences.setScoreboardTypography(stored, for: first)

        XCTAssertEqual(preferences.scoreboardTypography(for: first), stored)
        XCTAssertNotEqual(preferences.scoreboardTypography(for: second), stored)
        XCTAssertEqual(preferences.defaultScoreboardFont, defaultFontBefore)
        XCTAssertEqual(preferences.scoreboardRevision, revisionBefore)
        let key = "scoreboard_typography_\(first.rawValue)"
        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: key))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(
            Set(object.keys),
            Set(["font", "scoreMultiplier", "nameMultiplier", "secondaryMultiplier"])
        )
    }

    func testRequiredScoreboardStylePairsRemainIndependent() {
        let preferences = PreferencesManager.shared
        let pairs: [(ScoreboardStyleID, ScoreboardStyleID)] = [
            (
                ScoreboardStyleID(scoreCoreGameType: .tennis),
                ScoreboardStyleID(scoreCoreGameType: .tennisDoubles)
            ),
            (
                ScoreboardStyleID(gameType: .multiScoreboard),
                ScoreboardStyleID(gameType: .uno)
            ),
            (
                ScoreboardStyleID(gameType: .doudizhu),
                ScoreboardStyleID(gameType: .nineBall)
            )
        ]
        let stored = ScoreboardTypographyPreference(
            font: .sports,
            scoreMultiplier: 1.25,
            nameMultiplier: 1.15,
            secondaryMultiplier: 0.9
        )
        let originalData = Dictionary(uniqueKeysWithValues: pairs
            .flatMap { [$0.0, $0.1] }
            .map { styleID in
                let key = "scoreboard_typography_\(styleID.rawValue)"
                return (key, UserDefaults.standard.data(forKey: key))
            })
        defer {
            for (key, data) in originalData {
                if let data {
                    UserDefaults.standard.set(data, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }

        for pair in pairs {
            preferences.resetScoreboardTypography(for: pair.0)
            preferences.resetScoreboardTypography(for: pair.1)
            preferences.setScoreboardTypography(stored, for: pair.0)
            let actual = preferences.scoreboardTypography(for: pair.0)
            XCTAssertEqual(actual.font, stored.font)
            XCTAssertEqual(actual.scoreMultiplier, stored.scoreMultiplier, accuracy: 0.0001)
            XCTAssertEqual(actual.nameMultiplier, stored.nameMultiplier, accuracy: 0.0001)
            XCTAssertEqual(actual.secondaryMultiplier, stored.secondaryMultiplier, accuracy: 0.0001)
            XCTAssertNotEqual(preferences.scoreboardTypography(for: pair.1), stored)
        }
    }

    func testDefaultFontOnlyAffectsUnconfiguredScoreboardsAndResetRemovesOverride() {
        let preferences = PreferencesManager.shared
        let configured = ScoreboardStyleID(rawValue: "test_\(UUID().uuidString)")
        let unconfigured = ScoreboardStyleID(rawValue: "test_\(UUID().uuidString)")
        let originalDefault = preferences.defaultScoreboardFont
        defer {
            preferences.resetScoreboardTypography(for: configured)
            preferences.resetScoreboardTypography(for: unconfigured)
            preferences.defaultScoreboardFont = originalDefault
        }
        preferences.setScoreboardTypography(
            ScoreboardTypographyPreference(
                font: .sports,
                scoreMultiplier: 1.2,
                nameMultiplier: 1.1,
                secondaryMultiplier: 0.9
            ),
            for: configured
        )

        preferences.defaultScoreboardFont = ScoreboardFont.monospaced.rawValue

        XCTAssertEqual(preferences.scoreboardTypography(for: configured).font, .sports)
        XCTAssertEqual(preferences.scoreboardTypography(for: unconfigured).font, .monospaced)
        preferences.resetScoreboardTypography(for: configured)
        XCTAssertFalse(preferences.hasScoreboardTypography(for: configured))
        XCTAssertEqual(preferences.scoreboardTypography(for: configured).font, .monospaced)
    }

    func testTypographySessionPreviewsCancelsAppliesAndResetsAtomically() {
        let preferences = PreferencesManager.shared
        let style = ScoreboardStyleID(rawValue: "test_\(UUID().uuidString)")
        defer { preferences.resetScoreboardTypography(for: style) }
        let session = ScoreboardTypographySession(styleID: style, preferences: preferences)

        session.updateFont(.sports)
        session.updateMultiplier(1.25, for: .score, isLargeScreen: false)
        XCTAssertEqual(session.effectivePreference.font, .sports)
        XCTAssertFalse(preferences.hasScoreboardTypography(for: style))

        session.cancelPreview()
        XCTAssertEqual(session.effectivePreference.font, preferences.resolvedDefaultScoreboardFont)
        XCTAssertFalse(preferences.hasScoreboardTypography(for: style))

        session.updateFont(.sports)
        session.updateMultiplier(1.25, for: .score, isLargeScreen: false)
        session.applyPreview(preferences: preferences)
        XCTAssertTrue(preferences.hasScoreboardTypography(for: style))
        XCTAssertEqual(preferences.scoreboardTypography(for: style).scoreMultiplier, 1.25)

        session.resetPreview(preferences: preferences)
        XCTAssertTrue(preferences.hasScoreboardTypography(for: style))
        session.applyPreview(preferences: preferences)
        XCTAssertFalse(preferences.hasScoreboardTypography(for: style))
    }

    func testLocalDisplaySnapshotCarriesTypographyMultipliers() throws {
        let state = LocalScoreboardDisplayState(
            gameID: "uno",
            title: "UNO",
            leftName: "A",
            rightName: "B",
            leftScore: "25",
            rightScore: "40",
            leftDetail: nil,
            rightDetail: nil,
            themeID: "default",
            fontID: "sports",
            scoreMultiplier: 1.25,
            nameMultiplier: 0.9,
            secondaryMultiplier: 1.1,
            finished: false,
            revision: 1
        )
        let decoded = try JSONDecoder().decode(
            LocalScoreboardDisplayState.self,
            from: JSONEncoder().encode(state)
        )

        XCTAssertEqual(decoded.scoreMultiplier, 1.25)
        XCTAssertEqual(decoded.nameMultiplier, 0.9)
        XCTAssertEqual(decoded.secondaryMultiplier, 1.1)
    }

    func testDialogGridControlsFitNarrowAndRegularWidths() {
        XCTAssertEqual(
            ScoreboardLayoutMetrics.fittedGridItemSize(
                containerWidth: 288,
                columns: 4,
                spacing: 10,
                horizontalPadding: 16,
                preferredSize: 60,
                minimumSize: 36
            ),
            56
        )
        XCTAssertEqual(
            ScoreboardLayoutMetrics.fittedGridItemSize(
                containerWidth: 144,
                columns: 3,
                spacing: 6,
                horizontalPadding: 4,
                preferredSize: 56,
                minimumSize: 28
            ),
            41
        )
        XCTAssertEqual(
            ScoreboardLayoutMetrics.fittedGridItemSize(
                containerWidth: 250,
                columns: 4,
                spacing: 10,
                horizontalPadding: 16,
                preferredSize: 60,
                minimumSize: 36
            ),
            47
        )
    }
}
