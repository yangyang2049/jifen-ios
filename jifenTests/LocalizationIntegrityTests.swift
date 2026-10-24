import Foundation
import AVFoundation
@testable import jifen
import ScoreCore
import XCTest

final class LocalizationIntegrityTests: XCTestCase {
    func testMembershipMetadataUsesAppLanguageAcrossPromotedLocales() throws {
        for locale in LocalizationTestSupport.promotedLocales {
            let bundle = try XCTUnwrap(Bundle(path: repositoryRoot.appendingPathComponent("jifen/Resources/\(locale).lproj").path))
            let values = try LocalizationTestSupport.valuesByKey(relativePath: LocalizationTestSupport.localizablePaths[locale]!)
            for (cycles, key) in [
                (["month", "monthly"], "membership_monthly_plan_title"),
                (["year", "yearly", "annual"], "membership_yearly_plan_title"),
                (["lifetime", "permanent", "permant"], "membership_lifetime_plan_title"),
                (["quarter", "unknown"], "me_profile_vip_badge")
            ] {
                for cycle in cycles {
                    var membership = AppMembership(memberNo: "000046", displayCode: "V-000046", numberLabel: "会员编号", tier: "vip", billingCycle: " \(cycle.uppercased()) ", purchaseChannel: "apple", purchasedAt: "", status: "active", identitySummary: "VIP年卡")
                    let user = AppUser(id: "member", role: "VIP", plan: "VIP", createdAt: 0, membership: membership)
                    XCTAssertEqual(membership.localizedTitle(bundle: bundle), values[key], "\(locale)/\(cycle)")
                    XCTAssertEqual(user.localizedMembershipTitle(bundle: bundle), values[key], "\(locale)/\(cycle)")
                    membership.status = "expired"
                    let expired = AppUser(id: "member", role: "FREE", plan: "FREE", createdAt: 0, membership: membership)
                    XCTAssertEqual(expired.localizedMembershipTitle(bundle: bundle), values["me_profile_vip_badge"], locale)
                }
            }
            XCTAssertEqual(MembershipDisplayText.title(billingCycle: nil, bundle: bundle), values["me_profile_vip_badge"], locale)
        }
    }

    func testServerMessagesDoNotOverrideLocalizedInterfaceCopy() throws {
        for locale in LocalizationTestSupport.promotedLocales {
            let bundle = try XCTUnwrap(Bundle(path: repositoryRoot.appendingPathComponent("jifen/Resources/\(locale).lproj").path))
            let values = try LocalizationTestSupport.valuesByKey(relativePath: LocalizationTestSupport.localizablePaths[locale]!)
            for (code, key) in [("NAME_COOLDOWN", "me_profile_nickname_cooldown_generic"), ("NAME_BLOCKED", "group_error_content_blocked"), ("ACCOUNT_DELETION_FAILED", "account_deletion_failed")] {
                XCTAssertEqual(APIClientError.serverMessage(status: 400, code: code, message: "服务端中文", bundle: bundle), values[key], "\(locale)/\(code)")
            }
            if locale != "zh-Hans" {
                XCTAssertEqual(APIClientError.serverMessage(status: 500, code: "UNKNOWN_CODE", message: "服务端中文", bundle: bundle), values["network_request_failed"], locale)
                XCTAssertEqual(APIClientError.serverMessage(status: 429, code: nil, message: "服务端中文", bundle: bundle), values["group_rate_limited"], locale)
            }
            for (success, status, key) in [(true, "deleted", "account_deletion_success"), (true, "pending", "account_deletion_submitted"), (false, "failed", "account_deletion_failed")] {
                XCTAssertEqual(AccountDeletionOutcome(success: success, status: status, message: "服务端中文").localizedMessage(bundle: bundle), values[key], locale)
            }
        }
    }

    func testOptionalPingpongServerCallsKeepNamesAndOtherSportsUnchanged() throws {
        for code in LocalizationTestSupport.promotedLocales {
            guard let language = SportsVoiceLanguage.resolve(localization: code, iosMajorVersion: 27) else { continue }
            for game in [ScoreCore.GameType.pingpong, .pingpongDoubles] {
                var payload = VoiceAnnouncementPayload(gameType: game, phase: .scoreChange,
                    leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 2, rightScore: 1,
                    serverSide: .right, serverName: game == .pingpongDoubles ? "Carol %2$@" : nil)
                let standard = try XCTUnwrap(SportsVoiceSupport.message(payload, language: language))
                let name = payload.serverName ?? "Bob"
                let expected = VoiceAnnouncementMessage.phrase("%1$@. %2$@ to serve", [.verbatim(standard), .verbatim(name)])
                    .render(locale: Locale(identifier: language.speechLocale), template: { SportsVoiceSupport.template($0, language: language) })
                XCTAssertEqual(SportsVoiceSupport.message(payload, language: language, announceServer: true), expected, code)
                payload.phase = .matchEnd
                XCTAssertEqual(SportsVoiceSupport.message(payload, language: language, announceServer: true),
                               SportsVoiceSupport.message(payload, language: language), code)
                payload.gameType = .badminton
                payload.phase = .scoreChange
                XCTAssertEqual(SportsVoiceSupport.message(payload, language: language, announceServer: true),
                               SportsVoiceSupport.message(payload, language: language), code)
            }
        }
    }

    func testSportsVoiceResourcesAndLanguageMatrix() throws {
        let englishPath = repositoryRoot.appendingPathComponent("jifen/Resources/en.lproj/ScoreVoice.strings")
        let english = try PropertyListSerialization.propertyList(from: Data(contentsOf: englishPath), format: nil) as! [String: String]
        XCTAssertEqual(SportsVoiceLanguage.all.count, 46)
        for code in LocalizationTestSupport.promotedLocales {
            let language = SportsVoiceLanguage.resolve(localization: code, iosMajorVersion: 27)
            XCTAssertEqual(language != nil, code != "ur", code)
            XCTAssertEqual(SportsVoiceLanguage.resolve(localization: code, iosMajorVersion: 26) != nil, !["ur", "gu", "ml", "or", "pa"].contains(code), code)
            guard let language else { continue }
            let url = repositoryRoot.appendingPathComponent("jifen/Resources/\(code).lproj/ScoreVoice.strings")
            let values = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as! [String: String]
            if code.hasPrefix("zh-") { XCTAssertTrue(Set(values.keys).isSuperset(of: Set(english.keys))) }
            else { XCTAssertEqual(Set(values.keys), Set(english.keys), code) }
            XCTAssertTrue(values.values.allSatisfy { !$0.isEmpty }, code)
            for (key, value) in values {
                XCTAssertEqual(SportsVoiceSupport.template(key, language: language), value, "compiled bundle differs from reviewed \(code)/\(key)")
            }
            for (key, source) in english {
                XCTAssertEqual(Set(LocalizationTestSupport.formatTokens(in: source)), Set(LocalizationTestSupport.formatTokens(in: values[key]!)), "\(code) \(key)")
                XCTAssertNotNil(SportsVoiceSupport.template(key, language: language), "compiled bundle lacks \(code)/\(key)")
            }
            for sport in ScoreCore.GameType.allCases.filter({ VoiceAnnouncementSupport.isSupported($0) }) {
                for phase in [VoiceAnnouncementPhase.opening, .scoreChange, .setEnd, .matchEnd, .breakWarning, .breakResume] {
                    let payload = VoiceAnnouncementPayload(gameType: sport, phase: phase, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 3, rightScore: 3, winnerSide: .left, leftPlayerNames: ["Alice", "Carol"], breakCue: .twentySeconds)
                    let rendered = SportsVoiceSupport.message(payload, language: language)
                    XCTAssertNotNil(rendered, "\(code) \(sport) \(phase)")
                    XCTAssertFalse(rendered?.contains("%1$@") ?? true, code)
                }
            }
        }
    }

    func testSportsVoiceUsesReviewedCallsAndNumericFallbacks() {
        for language in SportsVoiceLanguage.all {
            let separator = ["zh-Hans", "zh-Hant"].contains(language.localization) ? "比" : (language.localization == "ja" ? "、" : ", ")
            for sport in [ScoreCore.GameType.volleyball, .beachVolleyball, .airVolleyball, .shuttlecock] {
                let payload = VoiceAnnouncementPayload(gameType: sport, phase: .scoreChange, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 3, rightScore: 2, serverSide: .right, serviceOver: true, criticalPoint: .matchPoint, isInterval: true)
                XCTAssertEqual(SportsVoiceSupport.message(payload, language: language), "3\(separator)2", "\(language.localization) \(sport)")
            }
        }
        let english = SportsVoiceLanguage.resolve(localization: "en", iosMajorVersion: 27)!
        var payload = VoiceAnnouncementPayload(gameType: .softTennis, phase: .scoreChange, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 4, rightScore: 3, serverSide: .right)
        XCTAssertEqual(SportsVoiceSupport.message(payload, language: english), "Advantage, receiver")
        payload.gameType = .pingpong; payload.phase = .breakResume; payload.leftScore = 8; payload.rightScore = 7
        XCTAssertEqual(SportsVoiceSupport.message(payload, language: english), "Time. 7, 8")
    }

    func testSportsVoiceFeatureFilteringAndOldDraftProtection() {
        for code in LocalizationTestSupport.promotedLocales {
            for version in [26, 27] {
                let supported = SportsVoiceLanguage.resolve(localization: code, iosMajorVersion: version) != nil
                for sport in [jifen.GameType.pingpong, .badminton, .tennis, .pickleball, .volleyball, .beachVolleyball, .airVolleyball, .shuttlecock, .squash, .softTennis, .padel] {
                    for singles in [true, false] {
                        let features = SportsSetupMatchFeature.features(for: sport, isSingles: singles, voiceSupported: supported)
                        XCTAssertEqual(features.contains(.voiceAnnouncement), supported, "\(code) iOS \(version) \(sport)")
                        var draft = SportsSetupDraft()
                        draft.voiceAnnouncement = true // Includes restored drafts and booking configurations.
                        draft.isSingles = singles
                        XCTAssertEqual(draft.makeResult(gameType: sport, usesDoublesPlayerInputs: !singles, voiceSupported: supported).voiceAnnouncement, supported)
                    }
                }
            }
        }
        for code in ["fr", "fr-CA", "es-ES", "es-MX", "pt-PT", "pt-BR"] {
            let target = SportsVoiceLanguage.resolve(localization: code, iosMajorVersion: 27)!
            XCTAssertEqual(target.matchedVoiceLanguage(in: [target.speechLocale]), target.speechLocale)
            XCTAssertNil(target.matchedVoiceLanguage(in: []))
        }
    }

    func testNativeVoiceInventoryMatchesSelectedRegions() throws {
        let inventory = AVSpeechSynthesisVoice.speechVoices().map(\.language)
        var report: [String: String] = [:]
        for language in SportsVoiceLanguage.all {
            let expected = language.matchedVoiceLanguage(in: inventory)
            let voice = SportsVoiceSupport.voice(for: language)
            XCTAssertEqual(voice?.language, expected, language.localization)
            report[language.localization] = voice?.language ?? "missing on simulator"
        }
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "sports-voice-inventory"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testRecordDurationUsesLocalizedUnitsAcrossDurationBranches() {
        let chinese = Locale(identifier: "zh-Hans")
        XCTAssertEqual(formatScoreboardDuration(0, locale: chinese), "0秒")
        XCTAssertEqual(formatScoreboardDuration(59.9, locale: chinese), "59秒")
        XCTAssertEqual(formatScoreboardDuration(60, locale: chinese), "1分钟")
        XCTAssertEqual(formatScoreboardDuration(3661, locale: chinese), "1小时1分钟1秒")

        let japanese = formatScoreboardDuration(3661, locale: Locale(identifier: "ja"))
        XCTAssertTrue(japanese.contains("時間"))
        XCTAssertTrue(japanese.contains("分"))
        XCTAssertTrue(japanese.contains("秒"))
        let ukrainian = formatScoreboardDuration(1287, locale: Locale(identifier: "uk"))
        XCTAssertTrue(ukrainian.contains("хв"))
        XCTAssertTrue(ukrainian.contains("с"))
        XCTAssertFalse(ukrainian.contains("m"))
        XCTAssertFalse(ukrainian.contains("s"))
    }

    func testInvalidRecordDurationsDisplayZeroWithoutCrashing() {
        for duration: TimeInterval in [-1, .nan, .infinity, -.infinity] {
            XCTAssertEqual(formatScoreboardDuration(duration, locale: Locale(identifier: "zh-Hans")), "0秒")
        }
    }

    func testExtremeFiniteRecordDurationDoesNotOverflowStorage() {
        let locale = Locale(identifier: "en_US")
        let maximum = Double(Int64.max).nextDown
        XCTAssertEqual(formatScoreboardDuration(.greatestFiniteMagnitude, locale: locale),
                       formatScoreboardDuration(maximum, locale: locale))
        XCTAssertEqual(formatScoreboardDuration(-.greatestFiniteMagnitude, locale: locale), "0 sec")
    }

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

            for locale in LocalizationTestSupport.promotedLocales where locale != "en" {
                let localized = try LocalizationTestSupport.entries(relativePath: paths[locale]!)
                XCTAssertEqual(duplicateKeys(in: localized), [], "\(label) \(locale) contains duplicate keys")
                XCTAssertEqual(
                    Set(english.map(\.key)), Set(localized.map(\.key)),
                    "\(label) key sets differ between en and \(locale)"
                )

                let localizedByKey = Dictionary(uniqueKeysWithValues: localized.map { ($0.key, $0.value) })
                for entry in english {
                    let localizedValue = try XCTUnwrap(
                        localizedByKey[entry.key],
                        "\(label) is missing \(entry.key) in \(locale)"
                    )
                    XCTAssertEqual(
                        LocalizationTestSupport.formatTokens(in: entry.value),
                        LocalizationTestSupport.formatTokens(in: localizedValue),
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
        let references = try swiftFiles(in: "jifen").map { file in
            let source = try String(contentsOf: file, encoding: .utf8)
            return (file: file, references: try LocalizationTestSupport.staticReferences(in: source))
        }
        for locale in LocalizationTestSupport.promotedLocales {
            try assertStaticKeysExist(
                references: references,
                stringsPath: LocalizationTestSupport.localizablePaths[locale]!
            )
        }
    }

    func testStaticLocalizationReferencesKeepExplicitTables() throws {
        let source = #"""
        NSLocalizedString("default_key", comment: "")
        NSLocalizedString("scan_key", tableName: "QRScan", value: "Fallback (example)", comment: "")
        NSLocalizedString("binding_key",
                          tableName: "WechatBinding", comment: "")
        NSLocalizedString("nil_table_key", tableName: nil, comment: "")
        localized("helper_key", bundle: bundle)
        NSLocalizedString("dynamic_\(key)", comment: "")
        """#
        XCTAssertEqual(try LocalizationTestSupport.staticReferences(in: source), [
            .init(key: "default_key", tableName: "Localizable", line: 1),
            .init(key: "scan_key", tableName: "QRScan", line: 2),
            .init(key: "binding_key", tableName: "WechatBinding", line: 3),
            .init(key: "nil_table_key", tableName: "Localizable", line: 5),
            .init(key: "helper_key", tableName: "Localizable", line: 6)
        ])
    }

    func testExplicitLocalizationTablesHaveEnglishFallbackAndMatchingTranslations() throws {
        var tables = Set<String>()
        for file in try swiftFiles(in: "jifen") {
            let source = try String(contentsOf: file, encoding: .utf8)
            tables.formUnion(try LocalizationTestSupport.staticReferences(in: source).map(\.tableName))
        }
        for table in tables.sorted() where table != "Localizable" {
            let englishPath = "jifen/Resources/en.lproj/\(table).strings"
            let englishEntries = try entries(at: englishPath)
            XCTAssertEqual(duplicateKeys(in: englishEntries), [], englishPath)
            let english = Dictionary(uniqueKeysWithValues: englishEntries.map { ($0.key, $0.value) })
            XCTAssertFalse(english.isEmpty, "\(table) must provide the app's English fallback")
            for locale in LocalizationTestSupport.promotedLocales {
                let path = "jifen/Resources/\(locale).lproj/\(table).strings"
                // Dedicated tables may intentionally ship only selected languages.
                // A missing table uses the English development localization.
                guard FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(path).path) else { continue }
                let localizedEntries = try entries(at: path)
                XCTAssertEqual(duplicateKeys(in: localizedEntries), [], path)
                let localized = Dictionary(uniqueKeysWithValues: localizedEntries.map { ($0.key, $0.value) })
                XCTAssertEqual(Set(localized.keys), Set(english.keys), path)
                for (key, value) in english {
                    let translated = try XCTUnwrap(localized[key], "\(path): \(key)")
                    XCTAssertFalse(translated.isEmpty, "\(path): \(key)")
                    XCTAssertEqual(LocalizationTestSupport.formatTokens(in: translated),
                                   LocalizationTestSupport.formatTokens(in: value), "\(path): \(key)")
                }
            }
        }
    }

    func testPromotedNonChineseLocalesKeepTheIScoreboardName() throws {
        for locale in LocalizationTestSupport.promotedLocales where !locale.hasPrefix("zh") {
            let localizable = try LocalizationTestSupport.valuesByKey(
                relativePath: LocalizationTestSupport.localizablePaths[locale]!
            )
            let infoPlist = try LocalizationTestSupport.valuesByKey(
                relativePath: LocalizationTestSupport.infoPlistPaths[locale]!
            )
            XCTAssertEqual(localizable["app_name"], "iScoreboard", "\(locale) app_name")
            XCTAssertEqual(infoPlist["CFBundleDisplayName"], "iScoreboard", "\(locale) CFBundleDisplayName")
        }
    }

    func testMembershipAgreementFragmentsKeepWordBoundaries() throws {
        // These links are concatenated directly in MembershipView. Chinese,
        // Japanese and Thai do not require spaces between the linked phrases;
        // Arabic and Hebrew attach their conjunction to the following word.
        let unspacedLanguages: Set<String> = ["zh-Hans", "zh-Hant", "ja", "th"]
        let attachedConjunctions: Set<String> = ["ar", "he"]
        for locale in LocalizationTestSupport.promotedLocales where !unspacedLanguages.contains(locale) {
            let strings = try LocalizationTestSupport.valuesByKey(
                relativePath: LocalizationTestSupport.localizablePaths[locale]!
            )
            let prefix = try XCTUnwrap(strings["vip_agreement_plain_prefix"])
            let separator = try XCTUnwrap(strings["vip_agreement_link_separator"])
            let middleSeparator = try XCTUnwrap(strings["vip_agreement_link_middle_separator"])
            XCTAssertTrue(prefix.hasSuffix(" "), "\(locale): prefix must separate the first link")
            XCTAssertTrue(separator.hasPrefix(" "), "\(locale): conjunction must separate the previous link")
            if !attachedConjunctions.contains(locale) {
                XCTAssertTrue(separator.hasSuffix(" "), "\(locale): conjunction must separate the next link")
            }
            XCTAssertTrue(middleSeparator.hasSuffix(" "), "\(locale): punctuation must separate the next link")
            let setupSuffix = try XCTUnwrap(strings["setup_suffix"])
            let winnerSeparator = try XCTUnwrap(strings["doudizhu_winner_separator"])
            XCTAssertTrue(setupSuffix.hasPrefix(" ") || setupSuffix.hasPrefix(":"),
                          "\(locale): setup title must separate the sport name")
            XCTAssertTrue(winnerSeparator.hasSuffix(" "),
                          "\(locale): winner names must remain separated")
        }
    }

    func testTimerGoKeepsTheBoardGameMeaningInEveryPromotedLanguage() throws {
        let expected: [String: String] = [
            "en": "Go", "zh-Hans": "围棋", "zh-Hant": "圍棋",
            "ja": "囲碁", "ko": "바둑", "de": "Go",
            "fr": "Go", "fr-CA": "Go", "es-MX": "Go", "es-ES": "Go",
            "pt-BR": "Go", "pt-PT": "Go", "ar": "غو", "he": "גו",
            "ur": "گو", "ru": "Го", "uk": "Ґо",
            "it": "Go", "nl": "Go", "sv": "Go",
            "ca": "Go", "pl": "Go", "ro": "Go", "cs": "Go", "sk": "Go", "sl": "Go", "hr": "Go",
            "da": "Go", "nb": "Go", "fi": "Go", "hu": "Go", "el": "Γκο",
            "hi": "गो", "bn": "গো", "mr": "गो", "gu": "ગો", "pa": "ਗੋ",
            "ta": "கோ", "te": "గో", "kn": "ಗೋ", "ml": "ഗോ", "or": "ଗୋ",
            "tr": "Go", "vi": "Cờ vây", "th": "โกะ", "id": "Go", "ms": "Go"
        ]

        XCTAssertEqual(Set(expected.keys), Set(LocalizationTestSupport.promotedLocales))
        for (locale, value) in expected {
            let strings = try LocalizationTestSupport.valuesByKey(
                relativePath: LocalizationTestSupport.localizablePaths[locale]!
            )
            XCTAssertEqual(strings["timer_go"], value, "\(locale) must name the board game Go, not the start action")
        }
    }

    /// Swift 的 String(format:) 把 `%s` 当 C 字符串读取，传入 Swift String 会段错误（exit 139）。
    /// 安卓资源里的 `%1$s` 一旦整段搬进来就是必崩，这里钉死在资源层。
    func testLocalizableValuesNeverUseCStringPlaceholders() throws {
        for locale in LocalizationTestSupport.promotedLocales + ["en", "zh-Hans", "zh-Hant"] {
            let url = repositoryRoot.appendingPathComponent("jifen/Resources/\(locale).lproj/Localizable.strings")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            let offenders = text.split(separator: "\n").filter { line in
                line.contains("%s") && !line.contains("%@") && !line.contains("%d")
            }
            XCTAssertTrue(offenders.isEmpty, "\(locale) uses a C-string placeholder: \(offenders.prefix(3))")
        }
    }

    func testLocalizationManifestDefinesTheFullAppMatrix() throws {
        let url = repositoryRoot.appendingPathComponent("scripts/localization/locales.json")
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let locales = try XCTUnwrap(root["locales"] as? [[String: Any]])
        let identifiers = locales.compactMap { $0["ios"] as? String }
        let newLocales = locales.filter { ($0["existing"] as? Bool) == false }
        XCTAssertEqual(locales.count, 47)
        XCTAssertEqual(Set(identifiers).count, 47)
        XCTAssertEqual(newLocales.count, 44)
        XCTAssertEqual(Set(identifiers).intersection(["en", "zh-Hans", "zh-Hant"]).count, 3)
    }

    func testPromotedLocalesHaveCompletePluralResources() throws {
        let manifestURL = repositoryRoot.appendingPathComponent("scripts/localization/locales.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        let locales = try XCTUnwrap(manifest["locales"] as? [[String: Any]])
        let categoriesByLocale = Dictionary(uniqueKeysWithValues: locales.compactMap { locale -> (String, Set<String>)? in
            guard let identifier = locale["ios"] as? String,
                  let categories = locale["plural_categories"] as? [String]
            else { return nil }
            return (identifier, Set(categories))
        })

        let pluralURL = repositoryRoot.appendingPathComponent("scripts/localization/plural-keys.json")
        let pluralData = try Data(contentsOf: pluralURL)
        let pluralManifest = try XCTUnwrap(JSONSerialization.jsonObject(with: pluralData) as? [String: Any])
        let pluralRows = try XCTUnwrap(pluralManifest["keys"] as? [[String: String]])
        let expectedKeys = Set(pluralRows.compactMap { $0["key"] })

        for locale in LocalizationTestSupport.promotedLocales {
            let expectedCategories = try XCTUnwrap(categoriesByLocale[locale])
            let path = try XCTUnwrap(LocalizationTestSupport.stringsdictPaths[locale])
            let dictionary = try LocalizationTestSupport.propertyList(relativePath: path)
            XCTAssertEqual(Set(dictionary.keys), expectedKeys, "Plural key set differs for \(locale)")

            for key in expectedKeys {
                let definition = try XCTUnwrap(dictionary[key] as? [String: Any])
                XCTAssertEqual(definition["NSStringLocalizedFormatKey"] as? String, "%#@count@")
                let count = try XCTUnwrap(definition["count"] as? [String: Any])
                let metadata: Set<String> = ["NSStringFormatSpecTypeKey", "NSStringFormatValueTypeKey"]
                XCTAssertEqual(Set(count.keys).subtracting(metadata), expectedCategories, "Plural categories differ for \(locale)/\(key)")
                for category in expectedCategories {
                    let value = try XCTUnwrap(count[category] as? String)
                    XCTAssertEqual(LocalizationTestSupport.formatTokens(in: value), ["%d"], "Plural placeholder differs for \(locale)/\(key).\(category)")
                }
            }
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

    /// Padel 中文名口径：简体「板式网球」、繁体「板式網球」、英文「Padel」。
    /// 依据国家体育总局 / 中国网球协会官方译名；「板网球」是 2016 年早期译名，禁止回流。
    func testPadelNameFollowsTheOfficialChineseGlossary() throws {
        let expectedNames = ["zh-Hans": "板式网球", "zh-Hant": "板式網球", "en": "Padel"]
        for (locale, name) in expectedNames {
            let values = try LocalizationTestSupport.valuesByKey(
                relativePath: "jifen/Resources/\(locale).lproj/Localizable.strings"
            )
            let actualName = try XCTUnwrap(values["game_padel"], "\(locale) game_padel missing")
            XCTAssertEqual(actualName, name, "\(locale) game_padel")
        }

        for locale in ["zh-Hans", "zh-Hant"] {
            let values = try LocalizationTestSupport.valuesByKey(
                relativePath: "jifen/Resources/\(locale).lproj/Localizable.strings"
            )
            let help = try XCTUnwrap(values["scoreboard_official_break_help_message"], locale)
            let localizedName = try XCTUnwrap(expectedNames[locale])
            XCTAssertFalse(help.contains("Padel"), "\(locale) break help must not embed latin Padel")
            XCTAssertTrue(help.contains(localizedName), "\(locale) break help must use \(localizedName)")
        }

        // 「板式网球 / 板式網球」不含早期译名子串，因此这两条断言只在旧写法回流时才触发。
        for locale in ["zh-Hans", "zh-Hant"] {
            let content = try String(
                contentsOf: LocalizationTestSupport.repositoryRoot
                    .appendingPathComponent("jifen/Resources/\(locale).lproj/Localizable.strings"),
                encoding: .utf8
            )
            XCTAssertFalse(content.contains("板网球"), "\(locale) still uses the legacy name 板网球")
            XCTAssertFalse(content.contains("板網球"), "\(locale) still uses the legacy name 板網球")
        }
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

    func testDefaultParticipantNameResourcesCoverEveryLanguage() throws {
        let keys = [
            "team_a", "team_b", "team_home", "team_away", "player_a", "player_b",
            "archer_a", "archer_b", "scoreboard_team_red", "scoreboard_team_blue",
            "player1_name", "player2_name", "timer_red_player", "timer_black_player", "timer_white_player",
            "dual_timer_player", "shot_training_miss", "shot_training_made",
            "doubles_red_a", "doubles_red_b", "doubles_blue_a", "doubles_blue_b",
            "shuttlecock_red_1", "shuttlecock_red_2", "shuttlecock_red_3",
            "shuttlecock_blue_1", "shuttlecock_blue_2", "shuttlecock_blue_3",
            "doudizhu_player_adam", "doudizhu_player_bob", "doudizhu_player_chris", "doudizhu_player_david",
            "multi_score_player_default_format", "schedule_red_top", "schedule_red_bottom",
            "schedule_blue_top", "schedule_blue_bottom"
        ]
        for locale in LocalizationTestSupport.promotedLocales {
            let values = try LocalizationTestSupport.valuesByKey(
                relativePath: LocalizationTestSupport.localizablePaths[locale]!
            )
            for key in keys {
                let value = try XCTUnwrap(values[key], "\(locale) \(key)")
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(locale) \(key)")
                XCTAssertNotEqual(value, key, "\(locale) \(key)")
                if !locale.hasPrefix("zh"), locale != "ja" {
                    XCTAssertNil(value.range(of: "[\\u4E00-\\u9FFF]", options: .regularExpression), "\(locale) \(key): \(value)")
                }
            }
            XCTAssertEqual(LocalizationTestSupport.formatTokens(in: values["multi_score_player_default_format"]!), ["%d"], locale)
        }
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
        XCTAssertEqual(english["tennis_scoring_mode_tiebreak_7"], "Tiebreak to 7")
        XCTAssertEqual(english["tennis_scoring_mode_tiebreak_10"], "Tiebreak to 10")
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
                // 语言门控的纯中文活动页可用「i18n-exempt: <原因>」注记整文件豁免。
                if source.contains("i18n-exempt:") { continue }
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

    private func assertStaticKeysExist(
        references: [(file: URL, references: [LocalizationTestSupport.StaticReference])],
        stringsPath: String
    ) throws {
        let localeDirectory = (stringsPath as NSString).deletingLastPathComponent
        var availableByTable = ["Localizable": Set(try entries(at: stringsPath).map(\.key))]
        var missing: [String] = []

        for (file, fileReferences) in references {
            for reference in fileReferences {
                if availableByTable[reference.tableName] == nil {
                    let localizedPath = "\(localeDirectory)/\(reference.tableName).strings"
                    let tablePath = FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(localizedPath).path)
                        ? localizedPath : "jifen/Resources/en.lproj/\(reference.tableName).strings"
                    availableByTable[reference.tableName] = Set(try entries(at: tablePath).map(\.key))
                }
                guard availableByTable[reference.tableName]?.contains(reference.key) != true else { continue }
                missing.append("\(reference.tableName)/\(reference.key) at \(file.lastPathComponent):\(reference.line)")
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
