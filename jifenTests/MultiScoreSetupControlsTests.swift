import XCTest
@testable import jifen

final class MultiScoreSetupControlsTests: XCTestCase {
    func testSolidPaletteHasStableIdentifiersAndReadableText() {
        let colors = MultiScoreboardStyle.SolidColor.allCases
        XCTAssertEqual(colors.count, 12)
        XCTAssertEqual(Set(colors.map(\.rawValue)).count, 12)
        for color in colors {
            XCTAssertGreaterThanOrEqual(ScoreboardStyleColorMath.contrastRatio(color.foregroundHex, color.hex), 4.5, color.rawValue)
        }
        XCTAssertEqual(MultiScoreboardStyle.SolidColor.paper.foregroundHex, "191D22")
        XCTAssertEqual(MultiScoreboardStyle.SolidColor.ink.foregroundHex, "F7F8FA")
    }

    @MainActor
    func testStylePreferencesRoundTripStableIDsAndReset() throws {
        let suite = "multi-score-style-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesManager(defaults: defaults)
        XCTAssertEqual(preferences.multiScoreboardStyle, .default)
        preferences.multiScoreboardStyle = .init(mode: .solid, solidColor: .forest)
        XCTAssertEqual(defaults.string(forKey: "multiScoreboardStyleMode"), "solid")
        XCTAssertEqual(defaults.string(forKey: "multiScoreboardSolidColor"), "forest")
        let reloaded = PreferencesManager(defaults: defaults)
        XCTAssertEqual(reloaded.multiScoreboardStyle, .init(mode: .solid, solidColor: .forest))
        reloaded.resetToOfflineReleaseDefaults()
        XCTAssertNil(defaults.object(forKey: "multiScoreboardStyleMode"))
        XCTAssertNil(defaults.object(forKey: "multiScoreboardSolidColor"))
        XCTAssertEqual(reloaded.multiScoreboardStyle, .default)
        defaults.set("future-mode", forKey: "multiScoreboardStyleMode")
        defaults.set("translated-label", forKey: "multiScoreboardSolidColor")
        XCTAssertEqual(reloaded.multiScoreboardStyle, .default)
    }

    @MainActor
    func testDisplayStylePreservesAllPlayersAndUsesMatchingReadableColors() {
        let appearance = ScoreboardDisplayAppearance(snapshot: .current(), fontCode: ScoreboardFont.default.rawValue)
        let players = (0..<50).map { ScoreboardDisplayPlayer(id: "player_\($0)", name: "P\($0)", score: $0, order: $0) }
        let paper = MultiScoreboardStyle(mode: .solid, solidColor: .paper)
        let wire = paper.displayStyle(appearance: appearance, players: players)
        XCTAssertEqual(wire.panels.count, 50)
        for index in players.indices {
            XCTAssertEqual(wire.panelColor(slot: "player_\(index)"), "#F4F3EF")
            XCTAssertEqual(wire.renderColor("mainScore", slot: "player_\(index)"), "#191D22")
            XCTAssertEqual(wire.renderColor("playerName", slot: "player_\(index)"), "#191D22")
            XCTAssertEqual(wire.panels[index].participantId, players[index].id)
        }
        let legacy = MultiScoreboardStyle.default
        XCTAssertEqual(legacy.backgroundHex(index: 12, theme: .defaultTheme), "EF4444")
        XCTAssertEqual(legacy.backgroundHex(index: 1, theme: .electronic), "000000")
        XCTAssertEqual(paper.backgroundHex(index: 49, theme: .electronic), "F4F3EF")
    }

    func testEveryBundledLanguageProvidesAllStyleAndColorNames() throws {
        let keys = ["multi_score_style", "multi_score_style_solid", "multi_score_style_colorful"]
            + MultiScoreboardStyle.SolidColor.allCases.map { "multi_score_color_" + $0.rawValue }
        for locale in Bundle.main.localizations where locale != "Base" {
            let path = try XCTUnwrap(Bundle.main.path(forResource: locale, ofType: "lproj"), locale)
            let bundle = try XCTUnwrap(Bundle(path: path), locale)
            for key in keys {
                let translated = bundle.localizedString(forKey: key, value: "__missing__", table: nil)
                XCTAssertNotEqual(translated, "__missing__", "\(locale): \(key)")
                XCTAssertFalse(translated.isEmpty, "\(locale): \(key)")
            }
        }
    }

    func testCustomCountNormalizesDecimalKeyboardsAndRejectsOtherCharacters() {
        for raw in ["５０", "٥٠", "۵۰", "५०", " 50 ", "050"] {
            XCTAssertEqual(MultiScoreCapacity.parsePlayerCount(raw), 50, raw)
        }
        for raw in ["", "2a5", "2.5", "-5", "5️⃣", "²", "51", "2", "9999999999999999999999"] {
            XCTAssertNil(MultiScoreCapacity.parsePlayerCount(raw), raw)
        }
        XCTAssertEqual(normalizedDecimalDigits("２a５", limit: 3), "25")
    }

    @MainActor
    func testNameDraftKeepsAllFiftySlotsIncludingHiddenPlayers() {
        let names = (1...50).map { "Saved \($0)" }
        let draft = MultiScoreSetupDialogView.normalizePlayerNames(names, capacity: 50)
        XCTAssertEqual(draft, names)
        XCTAssertEqual(MultiScoreSetupDialogView.normalizePlayerNames(["甲", "乙"], capacity: 50).count, 50)
        // 人数只限制显示窗口，既有 50 位草稿可重新显示，不截断源数组。
        XCTAssertEqual(Array(draft.prefix(3)), Array(names.prefix(3)))
        XCTAssertEqual(draft[49], "Saved 50")
    }

    @MainActor
    func testBulkFeedbackFormatsEveryPlaceholder() {
        let names = MultiScoreNameBatchParser.parse("甲\n乙\n丙\n丁\n戊")
        XCTAssertEqual(MultiScoreBulkNamesDialog.feedback(for: names, playerCount: 3),
                       String.localizedStringWithFormat(NSLocalizedString("multi_score_bulk_expand", comment: ""), 5, 5))
        XCTAssertEqual(MultiScoreBulkNamesDialog.feedback(for: names, playerCount: 50),
                       String.localizedStringWithFormat(NSLocalizedString("multi_score_bulk_apply", comment: ""), 5, 5))
    }

    @MainActor
    func testPreferenceResetClearsBasketballTiming() throws {
        let suite = "basketball-reset-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesManager(defaults: defaults)
        preferences.basketballRuleSet = "custom"
        preferences.basketballPeriodSeconds = 1200
        preferences.basketballOvertimeSeconds = 180
        preferences.resetToOfflineReleaseDefaults()
        for key in ["basketballRuleSet", "basketballPeriodSeconds", "basketballOvertimeSeconds"] {
            XCTAssertNil(defaults.object(forKey: key))
        }
        XCTAssertEqual(preferences.basketballRuleSet, "fiba")
        XCTAssertEqual(preferences.basketballPeriodSeconds, 600)
        XCTAssertEqual(preferences.basketballOvertimeSeconds, 300)
    }

    func testCapacityKeepsAndroidBounds() {
        XCTAssertEqual(MultiScoreCapacity.minPlayers, 3)
        XCTAssertEqual(MultiScoreCapacity.maxPlayers, 50)
        XCTAssertTrue(MultiScoreCapacity.isValid(3))
        XCTAssertTrue(MultiScoreCapacity.isValid(50))
        XCTAssertFalse(MultiScoreCapacity.isValid(2))
        XCTAssertFalse(MultiScoreCapacity.isValid(51))
        XCTAssertEqual(MultiScoreCapacity.normalized(0), 3)
        XCTAssertEqual(MultiScoreCapacity.normalized(51), 50)
        XCTAssertEqual(MultiScoreCapacity.normalized(30), 30)
    }

    func testBatchParserKeepsOrderAndDuplicates() {
        let batch = MultiScoreNameBatchParser.parse("红A\n蓝B、红A, 绿C；黄D;青E")
        XCTAssertEqual(batch.names, ["红A", "蓝B", "红A", "绿C", "黄D", "青E"])
        XCTAssertNil(batch.error)
        XCTAssertEqual(batch.invalidNameIndex, -1)
    }

    func testBatchParserTrimsAndIgnoresBlankEntries() {
        let batch = MultiScoreNameBatchParser.parse("  甲  \n\n\t 乙\t\r\n")
        XCTAssertEqual(batch.names, ["甲", "乙"])
        XCTAssertNil(batch.error)
    }

    func testBatchParserKeepsEmbeddedSpaces() {
        let batch = MultiScoreNameBatchParser.parse("Red  Team\nBlue Team")
        XCTAssertEqual(batch.names, ["Red  Team", "Blue Team"])
    }

    func testBatchParserReportsEmpty() {
        let batch = MultiScoreNameBatchParser.parse(" , 、 \n ")
        XCTAssertTrue(batch.names.isEmpty)
        XCTAssertEqual(batch.error, .empty)
    }

    func testBatchParserRejectsMoreThanFiftyNames() {
        let raw = (1 ... 51).map { "P\($0)" }.joined(separator: "\n")
        let batch = MultiScoreNameBatchParser.parse(raw)
        XCTAssertEqual(batch.names.count, 51)
        XCTAssertEqual(batch.error, .tooMany)
    }

    func testBatchParserRejectsOverlongNameWithIndex() {
        let longName = String(repeating: "长", count: 25)
        let batch = MultiScoreNameBatchParser.parse("甲\n\(longName)")
        XCTAssertEqual(batch.error, .nameTooLong)
        XCTAssertEqual(batch.invalidNameIndex, 1)
    }

    func testBatchParserAcceptsTwentyFourCharacterName() {
        let name = String(repeating: "长", count: 24)
        let batch = MultiScoreNameBatchParser.parse(name)
        XCTAssertNil(batch.error)
    }

    @MainActor
    func testPreferencesClampKeepsFiftyAndMigratesLegacy() throws {
        let suite = "multi-score-capacity-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = PreferencesManager(defaults: defaults)
        preferences.multiScoreboardPlayerCount = 50
        XCTAssertEqual(preferences.multiScoreboardPlayerCount, 50)
        preferences.multiScoreboardPlayerCount = 60
        XCTAssertEqual(preferences.multiScoreboardPlayerCount, 50)
        preferences.multiScoreboardPlayerCount = 1
        XCTAssertEqual(preferences.multiScoreboardPlayerCount, 3)

        // 旧版本写入的 3～9 值继续可读。
        defaults.set(7, forKey: "multiScoreboardPlayerCount")
        XCTAssertEqual(preferences.multiScoreboardPlayerCount, 7)
        // 越界历史值回退到默认 4，而不是被夹取成 50。
        defaults.set(88, forKey: "multiScoreboardPlayerCount")
        XCTAssertEqual(preferences.multiScoreboardPlayerCount, 4)
    }
}
