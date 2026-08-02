import Foundation
@testable import jifen
import XCTest

final class LocalizationIntegrityTests: XCTestCase {
    private struct Entry: Equatable {
        let key: String
        let value: String
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testLocalizedResourcePairsStayInSync() throws {
        let pairs = [
            ("phone", "jifen/Resources/en.lproj/Localizable.strings", "jifen/Resources/zh-Hans.lproj/Localizable.strings"),
            ("watch", "jifenWatch Watch App/Resources/en.lproj/Localizable.strings", "jifenWatch Watch App/Resources/zh-Hans.lproj/Localizable.strings"),
            ("phone Info.plist", "jifen/Resources/en.lproj/InfoPlist.strings", "jifen/Resources/zh-Hans.lproj/InfoPlist.strings")
        ]

        for (label, englishPath, chinesePath) in pairs {
            let english = try entries(at: englishPath)
            let chinese = try entries(at: chinesePath)

            XCTAssertEqual(duplicateKeys(in: english), [], "\(label) English contains duplicate keys")
            XCTAssertEqual(duplicateKeys(in: chinese), [], "\(label) Chinese contains duplicate keys")
            XCTAssertEqual(Set(english.map(\.key)), Set(chinese.map(\.key)), "\(label) key sets differ between locales")

            let chineseByKey = Dictionary(uniqueKeysWithValues: chinese.map { ($0.key, $0.value) })
            for entry in english {
                let chineseValue = try XCTUnwrap(chineseByKey[entry.key], "\(label) is missing \(entry.key)")
                XCTAssertEqual(
                    formatTokens(in: entry.value),
                    formatTokens(in: chineseValue),
                    "\(label) format placeholders differ for \(entry.key)"
                )
            }
        }
    }

    func testEveryStaticLocalizationKeyExistsInItsTarget() throws {
        try assertStaticKeysExist(
            sourceDirectory: "jifen",
            stringsPath: "jifen/Resources/en.lproj/Localizable.strings"
        )
        try assertStaticKeysExist(
            sourceDirectory: "jifenWatch Watch App",
            stringsPath: "jifenWatch Watch App/Resources/en.lproj/Localizable.strings"
        )
    }

    func testEnglishResourcesDoNotContainUnexpectedChineseOrBlankValues() throws {
        let tables = [
            "jifen/Resources/en.lproj/Localizable.strings",
            "jifenWatch Watch App/Resources/en.lproj/Localizable.strings",
            "jifen/Resources/en.lproj/InfoPlist.strings"
        ]
        let allowedChineseKeys: Set<String> = ["about_company_zh"]
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

    func testDynamicLocalizationKeyFamiliesAreComplete() throws {
        let phoneKeys = Set(try entries(at: "jifen/Resources/en.lproj/Localizable.strings").map(\.key))
        let expected = [
            "appearance_system", "appearance_light", "appearance_dark",
            "faq_question_1", "faq_answer_1",
            "faq_question_2", "faq_answer_2",
            "faq_question_3", "faq_answer_3",
            "faq_question_5", "faq_answer_5",
            "faq_question_6", "faq_answer_6",
            "faq_question_7", "faq_answer_7",
            "faq_question_8", "faq_answer_8"
        ]
        XCTAssertEqual(expected.filter { !phoneKeys.contains($0) }, [])
    }

    func testScoreboardKeyPointLabelsKeepLocalizedFullChineseAndCompactEnglishCopy() throws {
        let english = Dictionary(uniqueKeysWithValues: try entries(
            at: "jifen/Resources/en.lproj/Localizable.strings"
        ).map { ($0.key, $0.value) })
        let chinese = Dictionary(uniqueKeysWithValues: try entries(
            at: "jifen/Resources/zh-Hans.lproj/Localizable.strings"
        ).map { ($0.key, $0.value) })

        XCTAssertEqual(english["scoreboard_key_point_game"], "GP")
        XCTAssertEqual(english["scoreboard_key_point_match"], "MP")
        XCTAssertEqual(english["scoreboard_key_point_set"], "SP")
        XCTAssertEqual(chinese["scoreboard_key_point_game"], "局点")
        XCTAssertEqual(chinese["scoreboard_key_point_match"], "赛点")
        XCTAssertEqual(chinese["scoreboard_key_point_set"], "盘点")
    }

    func testTennisSetupUsesNaturalMatchAndTiebreakTerminology() throws {
        let english = Dictionary(uniqueKeysWithValues: try entries(
            at: "jifen/Resources/en.lproj/Localizable.strings"
        ).map { ($0.key, $0.value) })
        let chinese = Dictionary(uniqueKeysWithValues: try entries(
            at: "jifen/Resources/zh-Hans.lproj/Localizable.strings"
        ).map { ($0.key, $0.value) })

        XCTAssertEqual(chinese["tennis_scoring_mode_regular"], "标准赛制")
        XCTAssertEqual(chinese["tennis_scoring_mode_tiebreak_7"], "抢七赛")
        XCTAssertEqual(chinese["tennis_scoring_mode_tiebreak_10"], "抢十赛")
        XCTAssertEqual(chinese["tennis_deuce_option_no_ad"], "无占先")
        XCTAssertEqual(english["tennis_scoring_mode_regular"], "Standard")
        XCTAssertEqual(english["tennis_scoring_mode_tiebreak_7"], "7-Point Tiebreak")
        XCTAssertEqual(english["tennis_scoring_mode_tiebreak_10"], "10-Point Tiebreak")
    }

    func testSwiftUIHasNoDirectChineseStringLiterals() throws {
        let pattern = #"(?:Text|Button|Label|navigationTitle|alert|confirmationDialog|Section|Picker|TextField|SecureField|accessibilityLabel|accessibilityHint)\s*\(\s*\"([^\"]*[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF][^\"]*)\""#
        var failures: [String] = []

        for directory in ["jifen", "jifenWatch Watch App"] {
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
            "jifen/Features/Me/WatchLinkSettingsView.swift",
            "jifen/Features/Legal/FirstLaunchLegalScreen.swift",
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
        let content = try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
        let pattern = #"(?m)^\s*\"((?:\\.|[^\"])*)\"\s*=\s*\"((?:\\.|[^\"])*)\"\s*;"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(content.startIndex..., in: content)
        return regex.matches(in: content, range: range).compactMap { match in
            guard
                let keyRange = Range(match.range(at: 1), in: content),
                let valueRange = Range(match.range(at: 2), in: content)
            else { return nil }
            return Entry(key: String(content[keyRange]), value: String(content[valueRange]))
        }
    }

    private func duplicateKeys(in entries: [Entry]) -> [String] {
        Dictionary(grouping: entries, by: \.key)
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
    }

    private func formatTokens(in value: String) -> [String] {
        let pattern = #"%(?:%|(?:\d+\$)?[-+0 #']*(?:\d+|\*)?(?:\.\d+)?(?:hh|h|ll|l|L|z|t|j)?[@dDuUxXoOfFeEgGcCsSpaAi])"#
        return captures(pattern: pattern, in: value, captureGroup: 0)
            .map { $0.value.replacingOccurrences(of: #"%\d+\$"#, with: "%", options: .regularExpression) }
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
