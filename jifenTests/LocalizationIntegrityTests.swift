import Foundation
@testable import jifen
import ScoreCore
import XCTest

final class LocalizationIntegrityTests: XCTestCase {
    private typealias Entry = LocalizationTestSupport.Entry

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testLocalizedResourcePairsStayInSync() throws {
        let tables = [
            ("phone", LocalizationTestSupport.localizablePaths),
            ("phone Info.plist", LocalizationTestSupport.infoPlistPaths)
        ]

        for (label, paths) in tables {
            let english = try LocalizationTestSupport.entries(relativePath: paths["en"]!)
            XCTAssertEqual(duplicateKeys(in: english), [], "\(label) English contains duplicate keys")

            for locale in ["zh-Hans", "zh-Hant"] {
                let chinese = try LocalizationTestSupport.entries(relativePath: paths[locale]!)
                XCTAssertEqual(duplicateKeys(in: chinese), [], "\(label) \(locale) contains duplicate keys")
                XCTAssertEqual(
                    Set(english.map(\.key)), Set(chinese.map(\.key)),
                    "\(label) key sets differ between en and \(locale)"
                )

                let chineseByKey = Dictionary(uniqueKeysWithValues: chinese.map { ($0.key, $0.value) })
                for entry in english {
                    let chineseValue = try XCTUnwrap(
                        chineseByKey[entry.key],
                        "\(label) is missing \(entry.key) in \(locale)"
                    )
                    XCTAssertEqual(
                        LocalizationTestSupport.formatTokens(in: entry.value),
                        LocalizationTestSupport.formatTokens(in: chineseValue),
                        "\(label) format placeholders differ for \(entry.key) in \(locale)"
                    )
                }
            }
        }
    }

    func testLegalLinksFollowTheAppLanguage() throws {
        XCTAssertEqual(LegalDocuments.languageCode(for: "en"), "en")
        XCTAssertEqual(LegalDocuments.languageCode(for: "zh-Hans"), "zh")
        XCTAssertEqual(LegalDocuments.languageCode(for: "zh-Hant"), "zh-tw")

        for url in [
            LegalDocuments.termsURL,
            LegalDocuments.privacyURL,
            LegalDocuments.membershipAgreementURL,
            LegalDocuments.autoRenewalTermsURL
        ] {
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.host, "jifenqi.com")
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "lang" })?.value,
                           LegalDocuments.languageCode(for: Bundle.main.preferredLocalizations.first ?? Locale.current.identifier))
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "source" })?.value, "mobile_app")
        }
    }

    func testEveryStaticLocalizationKeyExistsInItsTarget() throws {
        for locale in ["en", "zh-Hans", "zh-Hant"] {
            try assertStaticKeysExist(
                sourceDirectory: "jifen",
                stringsPath: LocalizationTestSupport.localizablePaths[locale]!
            )
        }
    }

    func testEnglishResourcesDoNotContainUnexpectedChineseOrBlankValues() throws {
        let tables = [
            "jifen/Resources/en.lproj/Localizable.strings",
            "jifen/Resources/en.lproj/InfoPlist.strings"
        ]
        // Xiangqi piece faces are Chinese glyphs in every app language.
        let allowedChineseKeys: Set<String> = ["about_company_zh", "timer_role_red", "timer_role_black"]
        let allowedBlankKeys: Set<String> = ["points_table_team_suffix"]

        for path in tables {
            for entry in try entries(at: path) {
                if !allowedChineseKeys.contains(entry.key) {
                    XCTAssertNil(
                        entry.value.range(of: #"[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]"#, options: .regularExpression),
                        "\(path) contains Chinese in English value for \(entry.key): \(entry.value)"
                    )
                }
                if !allowedBlankKeys.contains(entry.key) {
                    XCTAssertFalse(entry.value.isEmpty, "\(path) contains a blank value for \(entry.key)")
                }
            }
        }
    }

    func testXiangqiPieceFacesStayChineseInEnglish() throws {
        let english = try entries(at: "jifen/Resources/en.lproj/Localizable.strings")
        let values = Dictionary(uniqueKeysWithValues: english.map { ($0.key, $0.value) })
        XCTAssertEqual(values["timer_role_red"], "帅")
        XCTAssertEqual(values["timer_role_black"], "将")
    }

    func testDynamicLocalizationKeyFamiliesAreComplete() throws {
        let expected = [
            "appearance_system", "appearance_light", "appearance_dark",
            "faq_question_1", "faq_answer_1",
            "faq_question_2", "faq_answer_2",
            "faq_question_3", "faq_answer_3",
            "faq_question_4", "faq_answer_4",
            "faq_question_5", "faq_answer_5",
            "faq_question_6", "faq_answer_6",
            "faq_question_7", "faq_answer_7",
            "faq_question_8", "faq_answer_8",
            "faq_question_10", "faq_answer_10",
            "faq_question_11", "faq_answer_11"
        ]
        for (locale, path) in LocalizationTestSupport.localizablePaths {
            let keys = Set(try LocalizationTestSupport.entries(relativePath: path).map(\.key))
            XCTAssertEqual(expected.filter { !keys.contains($0) }, [], "\(locale) is missing dynamic keys")
        }
    }

    /// zh-Hant gate 1: no simplified-only glyph may survive in the table.
    func testZhHantContainsNoSimplifiedOnlyCharacters() throws {
        for path in [
            LocalizationTestSupport.localizablePaths["zh-Hant"]!,
            LocalizationTestSupport.infoPlistPaths["zh-Hant"]!
        ] {
            for entry in try LocalizationTestSupport.entries(relativePath: path) {
                let hits = Set(entry.value).intersection(LocalizationTestSupport.simplifiedOnlyCharacters)
                XCTAssertTrue(
                    hits.isEmpty,
                    "zh-Hant value for \(entry.key) contains simplified characters: \(hits.sorted()) — \(entry.value.prefix(40))"
                )
            }
        }
    }

    /// zh-Hant gate 2: any key whose zh-Hans copy uses a simplified-only glyph
    /// must have been converted (catches whole-table copies and half-done rows).
    func testZhHantConvertsEveryKeyWithSimplifiedOnlySource() throws {
        let hans = try LocalizationTestSupport.valuesByKey(
            relativePath: LocalizationTestSupport.localizablePaths["zh-Hans"]!
        )
        let hant = try LocalizationTestSupport.valuesByKey(
            relativePath: LocalizationTestSupport.localizablePaths["zh-Hant"]!
        )
        var failures: [String] = []
        for (key, hansValue) in hans {
            guard !Set(hansValue).isDisjoint(with: LocalizationTestSupport.simplifiedOnlyCharacters) else { continue }
            if hant[key] == hansValue {
                failures.append(key)
            }
        }
        XCTAssertEqual(failures.sorted(), [], "zh-Hant values copied unchanged from zh-Hans where conversion is required")
    }

    func testScoreboardKeyPointLabelsKeepLocalizedFullChineseAndCompactEnglishCopy() throws {
        let english = Dictionary(uniqueKeysWithValues: try entries(
            at: LocalizationTestSupport.localizablePaths["en"]!
        ).map { ($0.key, $0.value) })
        let simplified = try LocalizationTestSupport.valuesByKey(
            relativePath: LocalizationTestSupport.localizablePaths["zh-Hans"]!
        )
        let traditional = try LocalizationTestSupport.valuesByKey(
            relativePath: LocalizationTestSupport.localizablePaths["zh-Hant"]!
        )

        XCTAssertEqual(english["scoreboard_key_point_game"], "GP")
        XCTAssertEqual(english["scoreboard_key_point_match"], "MP")
        XCTAssertEqual(english["scoreboard_key_point_set"], "SP")
        XCTAssertEqual(simplified["scoreboard_key_point_game"], "局点")
        XCTAssertEqual(simplified["scoreboard_key_point_match"], "赛点")
        XCTAssertEqual(simplified["scoreboard_key_point_set"], "盘点")
        XCTAssertEqual(traditional["scoreboard_key_point_game"], "局點")
        XCTAssertEqual(traditional["scoreboard_key_point_match"], "賽點")
        XCTAssertEqual(traditional["scoreboard_key_point_set"], "盤點")
    }

    func testDefaultParticipantNamesUseCanonicalEnglishAndChineseCopy() throws {
        let expected: [String: (english: String, simplified: String, traditional: String)] = [
            "red_team": ("Red", "红方", "紅方"),
            "blue_team": ("Blue", "蓝方", "藍方"),
            "team_a": ("Team A", "A队", "A隊"),
            "team_b": ("Team B", "B队", "B隊"),
            "player_a": ("Player A", "选手A", "選手A"),
            "player_b": ("Player B", "选手B", "選手B"),
            "archer_a": ("Archer A", "射手A", "射手A"),
            "archer_b": ("Archer B", "射手B", "射手B"),
            "doubles_red_a": ("Red A", "红A", "紅A"),
            "doubles_red_b": ("Red B", "红B", "紅B"),
            "doubles_blue_a": ("Blue A", "蓝A", "藍A"),
            "doubles_blue_b": ("Blue B", "蓝B", "藍B")
        ]
        let english = try LocalizationTestSupport.valuesByKey(
            relativePath: LocalizationTestSupport.localizablePaths["en"]!
        )
        let simplified = try LocalizationTestSupport.valuesByKey(
            relativePath: LocalizationTestSupport.localizablePaths["zh-Hans"]!
        )
        let traditional = try LocalizationTestSupport.valuesByKey(
            relativePath: LocalizationTestSupport.localizablePaths["zh-Hant"]!
        )
        for (key, values) in expected {
            XCTAssertEqual(english[key], values.english, "Unexpected English value for \(key)")
            XCTAssertEqual(simplified[key], values.simplified, "Unexpected zh-Hans value for \(key)")
            XCTAssertEqual(traditional[key], values.traditional, "Unexpected zh-Hant value for \(key)")
        }
    }

    func testTennisSetupUsesNaturalMatchAndTiebreakTerminology() throws {
        let english = try LocalizationTestSupport.valuesByKey(
            relativePath: LocalizationTestSupport.localizablePaths["en"]!
        )
        let simplified = try LocalizationTestSupport.valuesByKey(
            relativePath: LocalizationTestSupport.localizablePaths["zh-Hans"]!
        )
        let traditional = try LocalizationTestSupport.valuesByKey(
            relativePath: LocalizationTestSupport.localizablePaths["zh-Hant"]!
        )

        XCTAssertEqual(simplified["tennis_scoring_mode_regular"], "标准赛制")
        XCTAssertEqual(simplified["tennis_scoring_mode_tiebreak_7"], "抢七赛")
        XCTAssertEqual(simplified["tennis_scoring_mode_tiebreak_10"], "抢十赛")
        XCTAssertEqual(simplified["tennis_deuce_option_no_ad"], "无占先")
        XCTAssertEqual(traditional["tennis_scoring_mode_regular"], "標準賽制")
        XCTAssertEqual(traditional["tennis_scoring_mode_tiebreak_7"], "搶七賽")
        XCTAssertEqual(traditional["tennis_scoring_mode_tiebreak_10"], "搶十賽")
        XCTAssertEqual(traditional["tennis_deuce_option_no_ad"], "無佔先")
        XCTAssertEqual(english["tennis_scoring_mode_regular"], "Standard")
        XCTAssertEqual(english["tennis_scoring_mode_tiebreak_7"], "7-Point Tiebreak")
        XCTAssertEqual(english["tennis_scoring_mode_tiebreak_10"], "10-Point Tiebreak")
    }

    /// Voice and UI must speak one vocabulary: the zh-TW announcer's
    /// post-converted terms have to equal the zh-Hant table copy.
    func testVoiceTraditionalTermsMatchZhHantUIVocabulary() throws {
        let values = try LocalizationTestSupport.valuesByKey(
            relativePath: LocalizationTestSupport.localizablePaths["zh-Hant"]!
        )
        let voiceCases: [(simplified: String, key: String)] = [
            ("局点", "scoreboard_key_point_game"),
            ("赛点", "scoreboard_key_point_match"),
            ("盘点", "scoreboard_key_point_set"),
            ("占先", "tennis_deuce_option_advantage"),
            ("抢七赛", "tennis_scoring_mode_tiebreak_7"),
            ("抢十赛", "tennis_scoring_mode_tiebreak_10")
        ]
        for item in voiceCases {
            XCTAssertEqual(
                VoiceChinesePhrases.toTraditional(item.simplified),
                values[item.key],
                "Voice term \(item.simplified) diverges from UI key \(item.key)"
            )
        }
        // Interval wording: the announcer says 间歇, the UI vocabulary is 休息.
        XCTAssertEqual(VoiceChinesePhrases.toTraditional("11比9，间歇"), "11比9，休息")
    }

    func testSwiftUIHasNoDirectChineseStringLiterals() throws {
        let pattern = #"(?:Text|Button|Label|navigationTitle|alert|confirmationDialog|Section|Picker|TextField|SecureField|accessibilityLabel|accessibilityHint)\s*\(\s*\"([^\"]*[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF][^\"]*)\""#
        var failures: [String] = []

        for directory in ["jifen"] {
            for file in try swiftFiles(in: directory) {
                let source = try String(contentsOf: file, encoding: .utf8)
                for match in captures(pattern: pattern, in: source) {
                    let line = source[..<match.range].reduce(into: 1) { count, character in
                        if character == "\n" { count += 1 }
                    }
                    failures.append("\(file.path):\(line): \(match.value)")
                }
            }
        }

        XCTAssertEqual(failures, [], "Direct Chinese SwiftUI literals must use localization keys:\n\(failures.joined(separator: "\n"))")
    }

    func testPrimaryPageCardsUseTheUnifiedStableSurface() throws {
        let unifiedSurfacePaths = [
            "jifen/Features/Scoreboard/ScoreboardTab.swift",
            "jifen/Features/Timer/TimerTab.swift",
            "jifen/Features/Home/Components/ProToolsSectionView.swift",
            "jifen/Features/Activity/RecentActivityPage.swift",
            "jifen/Features/Activity/TimerRecordDetailPage.swift",
            "jifen/Features/Me/SettingsView.swift",
            "jifen/Features/Schedule/SchedulePage.swift",
            "jifen/Features/Home/Components/CommonDataManagementShared.swift",
            "jifen/Features/Tools/ToolsTab.swift",
            "jifen/Features/Tools/PointsTable/PointsTableView.swift",
            "jifen/Features/Tools/AACalculatorView.swift",
            "jifen/Features/Tools/RandomTeamView.swift",
            "jifen/Features/Tools/FlipCoinView.swift",
            "jifen/Features/Tools/StopwatchView.swift",
            "jifen/Features/Tools/WhistleToolView.swift"
        ]

        for relativePath in unifiedSurfacePaths {
            let source = try String(
                contentsOf: repositoryRoot.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            XCTAssertTrue(
                source.contains("Theme.appCardBackground"),
                "\(relativePath) must use the shared page-card surface"
            )
        }

        let materialRegressionPaths = [
            "jifen/Features/Scoreboard/ScoreboardTab.swift",
            "jifen/Features/Timer/TimerTab.swift",
            "jifen/Features/Home/Components/ProToolsSectionView.swift",
            "jifen/Features/Activity/RecentActivityPage.swift"
        ]
        for relativePath in materialRegressionPaths {
            let source = try String(
                contentsOf: repositoryRoot.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            XCTAssertFalse(
                source.contains(".ultraThinMaterial"),
                "\(relativePath) must not use window-dependent material for page cards"
            )
        }
    }

    func testLegacyStandingsDefaultsFollowCurrentLocaleWithoutChangingCustomNames() {
        let legacy = PointsTableRecord(
            name: "新积分表",
            teams: ["甲", "乙", "丙"].map { PointsTableTeam(name: $0) }
        )
        let localized = legacy.localizingLegacyDefaults()

        XCTAssertEqual(localized.name, NSLocalizedString("points_table_new_name", comment: ""))
        XCTAssertEqual(
            localized.teams.map(\.name),
            ["points_table_team_a", "points_table_team_b", "points_table_team_c"].map {
                NSLocalizedString($0, comment: "")
            }
        )

        let custom = PointsTableRecord(name: "公司联赛", teams: legacy.teams)
        XCTAssertEqual(custom.localizingLegacyDefaults(), custom)

        let customTeamsWithLegacyTitle = PointsTableRecord(
            name: "New Standings",
            teams: ["Alpha", "Beta", "Gamma"].map { PointsTableTeam(name: $0) }
        )
        XCTAssertEqual(
            customTeamsWithLegacyTitle.localizingLegacyDefaults(),
            customTeamsWithLegacyTitle
        )

        let additionalTeamWithLegacyDefaults = PointsTableRecord(
            name: "新积分榜",
            teams: ["甲", "乙", "丙", "丁"].map { PointsTableTeam(name: $0) }
        )
        XCTAssertEqual(
            additionalTeamWithLegacyDefaults.localizingLegacyDefaults(),
            additionalTeamWithLegacyDefaults
        )
    }

    private func assertStaticKeysExist(sourceDirectory: String, stringsPath: String) throws {
        let available = Set(try entries(at: stringsPath).map(\.key))
        let patterns = [
            #"NSLocalizedString\s*\(\s*\"([^\"]+)\""#,
            #"\blocalized\s*\(\s*\"([^\"]+)\"\s*,"#
        ]
        var missing: [String] = []

        for file in try swiftFiles(in: sourceDirectory) {
            let source = try String(contentsOf: file, encoding: .utf8)
            for pattern in patterns {
                for match in captures(pattern: pattern, in: source) {
                    guard !match.value.contains(#"\("#), !available.contains(match.value) else { continue }
                    let line = source[..<match.range].reduce(into: 1) { count, character in
                        if character == "\n" { count += 1 }
                    }
                    missing.append("\(match.value) at \(file.lastPathComponent):\(line)")
                }
            }
        }

        XCTAssertEqual(missing.sorted(), [], "Missing localization keys in \(stringsPath):\n\(missing.sorted().joined(separator: "\n"))")
    }

    private func entries(at relativePath: String) throws -> [Entry] {
        try LocalizationTestSupport.entries(relativePath: relativePath)
    }

    private func duplicateKeys(in entries: [Entry]) -> [String] {
        Dictionary(grouping: entries, by: \.key)
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
    }

    private func swiftFiles(in relativeDirectory: String) throws -> [URL] {
        let directory = repositoryRoot.appendingPathComponent(relativeDirectory)
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
            return url
        }
    }

    private func captures(pattern: String, in source: String, captureGroup: Int = 1) -> [(value: String, range: String.Index)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard
                match.numberOfRanges > captureGroup,
                let valueRange = Range(match.range(at: captureGroup), in: source),
                let matchRange = Range(match.range(at: 0), in: source)
            else { return nil }
            return (String(source[valueRange]), matchRange.lowerBound)
        }
    }
}
