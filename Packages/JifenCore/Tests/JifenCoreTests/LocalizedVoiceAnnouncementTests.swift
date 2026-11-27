import Foundation
import Testing
@testable import ScoreCore

@Suite struct LocalizedVoiceAnnouncementTests {
    @Test func supportMatrixAndRegionalVoices() {
        #expect(SportsVoiceLanguage.all.count == 46)
        #expect(SportsVoiceLanguage.all.filter { $0.minimumIOSMajorVersion == 26 }.count == 42)
        for language in SportsVoiceLanguage.all {
            #expect(SportsVoiceLanguage.resolve(localization: language.localization, iosMajorVersion: 27) == language)
            #expect((SportsVoiceLanguage.resolve(localization: language.localization, iosMajorVersion: 26) != nil) == (language.minimumIOSMajorVersion == 26))
            #expect(language.matchedVoiceLanguage(in: [language.speechLocale]) == language.speechLocale)
            #expect(language.matchedVoiceLanguage(in: []) == nil)
        }
        #expect(SportsVoiceLanguage.resolve(localization: "ur", iosMajorVersion: 27) == nil)
        for pair in [("fr", "fr-CA"), ("fr-CA", "fr-FR"), ("es-ES", "es-MX"), ("es-MX", "es-ES"), ("pt-BR", "pt-PT"), ("pt-PT", "pt-BR")] {
            #expect(SportsVoiceLanguage.resolve(localization: pair.0, iosMajorVersion: 27)?.matchedVoiceLanguage(in: [pair.1]) == nil)
        }
        #expect(SportsVoiceLanguage.resolve(localization: "zh-Hant-HK", iosMajorVersion: 26)?.speechLocale == "zh-TW")
    }

    static let sports: [GameType] = [.badminton, .badmintonDoubles, .pingpong, .pingpongDoubles, .tennis, .pickleball, .squash, .shuttlecock, .softTennis, .padel, .volleyball]
    static let phases: [VoiceAnnouncementPhase] = [.opening, .scoreChange, .gameEnd, .setEnd, .matchEnd, .sideChange, .breakStart, .breakWarning, .breakResume]
    static func samples() -> [VoiceAnnouncementPayload] {
        var result: [VoiceAnnouncementPayload] = []
        for sport in sports {
            for phase in phases {
                for index in 0..<32 {
                    result.append(.init(
                        gameType: sport, phase: phase,
                        leftTeamName: "Alice %1$@", rightTeamName: "王明",
                        leftScore: index % 16, rightScore: index % 4 == 0 ? index % 16 : (index + 1) % 16,
                        leftSets: index % 3, rightSets: index % 5 == 0 ? index % 3 : (index + 1) % 3,
                        currentSet: index % 7 + 1, serverSide: index % 2 == 0 ? .left : .right,
                        winnerSide: index % 5 == 0 ? nil : .right,
                        receiverName: index % 2 == 0 ? "Carol" : nil,
                        leftPlayerNames: index % 3 == 0 ? ["Alice", "Carol"] : [],
                        serviceOver: index % 2 == 0,
                        criticalPoint: [nil, .gamePoint, .matchPoint, .gameBall, .matchBall][index % 5],
                        isInterval: index % 3 == 0, isManualEnd: index % 4 == 0,
                        isTieBreak: index % 2 == 0, tieBreakTarget: index % 3 == 0 ? 10 : 7,
                        tennisDeuceMode: index % 2 == 0 ? "no_ad" : "golden_point",
                        setScores: [.init(leftGames: 6, rightGames: 4), .init(leftGames: 3, rightGames: 6)],
                        serverNumber: index % 3 == 0 ? nil : index % 2 + 1,
                        sideChange: index % 2 == 0,
                        breakCue: [.twentySeconds, .halfTime, .fifteenSeconds, .time, nil][index % 5],
                        breakDurationSeconds: index % 3 == 0 ? 120 : 60,
                        secondServer: index % 2 == 1, starPointReturnedAdvantages: index % 3,
                        maxSets: index % 2 == 0 ? 9 : 7
                    ))
                }
            }
        }
        for mode in ["advantage", "no_ad", PadelDeuceMode.goldenPoint.rawValue, PadelDeuceMode.starPoint.rawValue] {
            for sport in [GameType.tennis, .padel, .softTennis, .squash] {
                for phase in Self.phases {
                    for score in [3, 6, 10] {
                        for returns in 0...2 {
                            result.append(.init(gameType: sport, phase: phase, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: score, rightScore: score, leftSets: 1, rightSets: 0, currentSet: 2, serverSide: .right, winnerSide: .left, tennisDeuceMode: mode, starPointReturnedAdvantages: returns))
                        }
                    }
                }
            }
        }
        return result
    }

    @Test func reviewedDoublesAdvantageLocalizesNameJoinWithoutReinterpretingNames() throws {
        for code in ["en", "zh-Hans", "zh-Hant", "ja", "ko"] {
            let templates = try VoiceProductionCalls.templates(code)
            let connector = try #require(templates[" and "])
            let advantage = try #require(templates["tennis.advantage.name"])
            for side in [MatchSide.left, .right] {
                let names = side == .left ? ["Alice %1$@", "Carol"] : ["王明", "李华 %2$@"]
                let payload = VoiceAnnouncementPayload(
                    gameType: .tennisDoubles, phase: .scoreChange,
                    leftTeamName: "Red", rightTeamName: "Blue",
                    leftScore: side == .left ? 4 : 3, rightScore: side == .right ? 4 : 3,
                    leftPlayerNames: ["Alice %1$@", "Carol"], rightPlayerNames: ["王明", "李华 %2$@"]
                )
                let rendered = LocalizedVoiceAnnouncementBuilder.buildReviewed(payload, localization: code)
                    .render(locale: Locale(identifier: code), template: { templates[$0] })
                let joinedNames = names.joined(separator: connector)
                let expected = String(format: advantage, locale: Locale(identifier: code), joinedNames as NSString)
                #expect(rendered == expected, "\(code) \(side)")
                if code.hasPrefix("zh-") {
                    #expect(rendered == names.joined(separator: "和") + (code == "zh-Hant" ? "佔先" : "占先"))
                }
            }
        }
    }

    /// 英文播报短语树（buildReviewed → build）的实际文案。
    /// 旧 builder 已删除；这里用真实 ScoreVoice.strings 断言生产输出。
    @Test func englishPhraseTreeRendersDocumentedCalls() throws {
        let cases = try Self.englishCases().map { ($0.label, try VoiceProductionCalls.text($0.payload, "en")) }
        #expect(cases.map(\.1) == Self.englishExpected, "\(cases)")
    }

    /// 英文生产文案：记分、换发球、换边、结果与暂停都来自 buildReviewed → build。
    /// 网球换边在英文生产里静音（空串），这里保留该行为而不是旧 builder 的 "Change ends"。
    static let englishExpected: [String] = [
        "5, 3",
        "Service over, 3, 5",
        "Change ends",
        "Alice to serve, love all",
        "8, 7",
        "11, 5. Game to Alice",
        "four, three",
        "11, 7",
        "Fifteen, love",
        "",
        "Hand out, 3, love",
        "20 seconds",
    ]

    static func englishCases() -> [(label: String, payload: VoiceAnnouncementPayload)] {
        [
            ("badminton.score", .init(gameType: .badminton, phase: .scoreChange, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 5, rightScore: 3, serverSide: .left)),
            ("badminton.serviceOver", .init(gameType: .badminton, phase: .scoreChange, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 5, rightScore: 3, serverSide: .right, serviceOver: true)),
            ("badminton.sideChange", .init(gameType: .badminton, phase: .sideChange, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 11, rightScore: 8)),
            ("pingpong.opening", .init(gameType: .pingpong, phase: .opening, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 0, rightScore: 0, serverSide: .left, serverName: "Alice")),
            ("pingpong.score", .init(gameType: .pingpong, phase: .scoreChange, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 8, rightScore: 7, serverSide: .left)),
            ("pingpong.setEnd", .init(gameType: .pingpong, phase: .setEnd, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 11, rightScore: 5, leftSets: 1, currentSet: 1, winnerSide: .left)),
            ("pickleball.score", .init(gameType: .pickleball, phase: .scoreChange, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 4, rightScore: 3, serverSide: .left)),
            ("pickleball.setEnd", .init(gameType: .pickleball, phase: .setEnd, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 11, rightScore: 7, leftSets: 1, currentSet: 1, winnerSide: .left)),
            ("tennis.point", .init(gameType: .tennis, phase: .scoreChange, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 1, rightScore: 0, serverSide: .left)),
            ("tennis.sideChange", .init(gameType: .tennis, phase: .sideChange, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 3, rightScore: 2)),
            ("squash.score", .init(gameType: .squash, phase: .scoreChange, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 3, rightScore: 0, serverSide: .left, serviceOver: true)),
            ("badminton.breakWarning", .init(gameType: .badminton, phase: .breakWarning, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 11, rightScore: 8, breakCue: .twentySeconds)),
        ]
    }
    @Test func productionCallsFollowDocumentedSportsAndNumericFallbacks() throws {
        func call(_ code: String, _ payload: VoiceAnnouncementPayload) throws -> String? {
            let templates = try VoiceProductionCalls.templates(code)
            return LocalizedVoiceAnnouncementBuilder.buildReviewed(payload, localization: code).render(
                locale: .init(identifier: code), template: { templates[$0] }
            )
        }
        var p = VoiceAnnouncementPayload(gameType: .badminton, phase: .scoreChange, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 29, rightScore: 29, serverSide: .left, criticalPoint: .gamePoint)
        #expect(try call("en", p) == "29, game point, all")
        #expect(try call("ja", p) == "トゥウェンティ ナイン、ゲームポイント、オール")
        p.gameType = .softTennis
        p.leftScore = 3; p.rightScore = 0; p.criticalPoint = nil
        #expect(try call("en", p) == "three, zero")
        #expect(try call("ja", p) == "スリー、ゼロ")
        p.rightScore = 3
        #expect(try call("en", p) == "Deuce")
        p.leftScore = 4; p.rightScore = 4
        #expect(try call("en", p) == "Deuce again")
        p.leftScore = 5
        #expect(try call("en", p) == "Advantage, server")
        #expect(try call("ja", p) == "アドバンテージサーバー")
        p.serverSide = .right
        #expect(try call("en", p) == "Advantage, receiver")
        p.phase = .breakResume
        #expect(try call("ja", p) == "ノータイム")
        p.gameType = .squash; p.phase = .scoreChange; p.leftScore = 3; p.rightScore = 0; p.serverSide = .left; p.serviceOver = true
        #expect(try call("en", p) == "Hand out, 3, love")
        p.phase = .setEnd; p.leftScore = 11; p.rightScore = 3; p.leftSets = 1; p.rightSets = 0; p.winnerSide = .left
        #expect(try call("en", p) == "11, 3, game to Alice. Alice leads 1 game to love")
        p.phase = .breakResume
        #expect(try call("en", p) == "Time")
        p.gameType = .pingpong
        #expect(try call("en", p) == "Time. 11, 3")
        p.phase = .opening; p.leftScore = 0; p.rightScore = 0
        #expect(try call("ja", p) == "ラヴオール")
        p.gameType = .padel; p.phase = .scoreChange; p.leftScore = 4; p.rightScore = 3; p.tennisDeuceMode = PadelDeuceMode.starPoint.rawValue
        #expect(try call("en", p) == "Advantage 1, Alice")
        p.starPointReturnedAdvantages = 1
        #expect(try call("en", p) == "Advantage 2, Alice")
        p.gameType = .tennis; p.leftScore = 2; p.rightScore = 3; p.serviceOver = false
        #expect(try call("ja", p) == "サーティー、フォーティー")
        // No precise Korean score-word table was located: use the displayed
        // numerical tennis score, never the internal point counters 2 and 3.
        #expect(try call("ko", p) == "30, 40")
        #expect(try call("fr", p) == "Trente, quarante")
        #expect(try call("es-ES", p) == "Treinta, cuarenta")
        p.leftScore = 3; p.rightScore = 3
        #expect(try call("fr", p) == "Quarante A")
        #expect(try call("ja", p) == "デュース")
        #expect(try call("ko", p) == "듀스")
        #expect(try call("zh-Hans", p) == "平分")
        p.returnedToDeuce = true
        #expect(try call("fr", p) == "Égalité")
        p.gameType = .softTennis
        #expect(try call("en", p) == "Deuce again")
        #expect(try call("ja", p) == "デュースアゲン")
        p.phase = .opening; p.maxSets = 7
        #expect(try call("ja", p) == "セブンゲームマッチ、プレーボール")
        p.phase = .scoreChange
        p.gameType = .squash; p.leftScore = 3; p.rightScore = 2; p.serviceOver = true
        #expect(try call("fr", p) == "Changement, 3, 2")
        #expect(try call("es-ES", p) == "Cambio, 3, 2")
        #expect(try call("pt-PT", p) == "Troca, 3, 2")
        p.gameType = .pingpong; p.leftScore = 4; p.rightScore = 4
        #expect(try call("zh-Hant", p) == "4平")
        for language in SportsVoiceLanguage.all {
            let code = language.localization
            let chinese = ["zh-Hans", "zh-Hant"].contains(code)
            let separator = chinese ? "比" : (code == "ja" ? "、" : ", ")
            let serverSeparator = chinese || code == "ja" ? "、" : ", "
            if chinese {
                let supportedSports = GameType.allCases.filter(VoiceAnnouncementSupport.isSupported)
                #expect(supportedSports.count == 15)
                p.phase = .scoreChange; p.rightScore = 0; p.serverSide = .left; p.isTieBreak = false; p.serverNumber = nil
                for sport in supportedSports {
                    p.gameType = sport
                    for score in [1, 2] {
                        p.leftScore = score
                        let spokenScore = [.tennis, .tennisDoubles, .padel].contains(sport) ? score * 15 : score
                        #expect(try call(code, p) == "\(spokenScore)比0", "\(code) \(sport)")
                    }
                }
                p.gameType = .pickleballDoubles; p.leftScore = 2; p.serverNumber = 2
                #expect(try call(code, p) == "2比0、2")
                p.serverNumber = nil
                for sport in [GameType.tennis, .tennisDoubles, .padel] {
                    p.gameType = sport; p.isTieBreak = true
                    #expect(try call(code, p) == "2比0", "\(code) \(sport) tie-break")
                }
                p.isTieBreak = false
            }
            for sport in [GameType.volleyball, .beachVolleyball, .airVolleyball, .shuttlecock] {
                p.gameType = sport; p.leftScore = 5; p.rightScore = 5; p.phase = .scoreChange; p.serviceOver = true; p.criticalPoint = .matchPoint; p.isInterval = true
                #expect(try call(code, p) == "5\(separator)5", "\(code) \(sport)")
                p.phase = .breakResume
                #expect(try call(code, p) == "5\(separator)5")
            }
            p.gameType = .pickleballDoubles; p.phase = .scoreChange; p.leftScore = 3; p.rightScore = 2; p.serverNumber = 2; p.serviceOver = false
            let expected = code == "en" ? "three, two, 2" : "3\(separator)2\(serverSeparator)2"
            #expect(try call(code, p) == expected)
            p.serverNumber = nil // Rally-scoring doubles uses two numbers.
            #expect(try call(code, p) == (code == "en" ? "three, two" : "3\(separator)2"))
        }
    }

    @Test func lostAdvantageKeepsTheDeuceTransitionAfterPointNormalization() throws {
        var before = TennisMatchState(leftName: "Alice", rightName: "Bob")
        before.leftPoints = 4; before.rightPoints = 3
        let result = TennisMatchReducer().reduce(state: before, intent: .pointWon(.right), at: 1)
        let payloads = TennisVoiceAnnouncementMapper.payloads(gameType: .tennis, before: before, after: result.state, intent: .pointWon(.right), events: result.events, completedSetScores: [])
        let p = try #require(payloads.first)
        #expect(p.leftScore == 3 && p.rightScore == 3)
        #expect(p.returnedToDeuce)
        let templates = try VoiceProductionCalls.templates("fr")
        #expect(LocalizedVoiceAnnouncementBuilder.buildReviewed(p, localization: "fr").render(locale: .init(identifier: "fr-FR"), template: { templates[$0] }) == "Égalité")
    }

    @Test func reviewedMatrixCoversAllGameTypesAndLanguages() throws {
        for language in SportsVoiceLanguage.all {
            let templates = try VoiceProductionCalls.templates(language.localization)
            for sport in GameType.allCases {
                for phase in Self.phases {
                    let p = VoiceAnnouncementPayload(gameType: sport, phase: phase, leftTeamName: "Alice %1$@", rightTeamName: "Bob", leftScore: 3, rightScore: 2, serverSide: .right, winnerSide: .left)
                    let rendered = LocalizedVoiceAnnouncementBuilder.buildReviewed(p, localization: language.localization).render(locale: .init(identifier: language.speechLocale), template: { templates[$0] })
                    #expect(rendered != nil, "\(language.localization) \(sport) \(phase)")
                    #expect(rendered?.contains("3-2") == false)
                    #expect(rendered?.contains("3–2") == false)
                    if ["zh-Hans", "zh-Hant"].contains(language.localization),
                       VoiceAnnouncementSupport.isSupported(sport),
                       [.opening, .scoreChange, .gameEnd, .setEnd, .matchEnd, .breakResume].contains(phase) {
                        #expect(rendered?.contains("比") == true, "\(language.localization) \(sport) \(phase)")
                    }
                }
            }
        }
    }
    @Test func missingTemplatesFailClosedAndNamesAreNeverKeys() {
        let message: VoiceAnnouncementMessage = "Advantage \("Alice %1$@")"
        #expect(message.render(locale: .init(identifier: "fr-FR"), template: { _ in nil }) == nil)
        #expect(message.render(locale: .init(identifier: "fr-FR"), template: { $0 == "Advantage %1$@" ? "Avantage %1$@" : nil }) == "Avantage Alice %1$@")
    }
    @Test func scoreCallsUseSportVocabularyAndPauseWithoutSpeakingSeparators() throws {
        func call(_ code: String, _ payload: VoiceAnnouncementPayload) throws -> String? {
            let templates = try VoiceProductionCalls.templates(code)
            return LocalizedVoiceAnnouncementBuilder.build(payload).render(
                locale: .init(identifier: code), template: { templates[$0] }
            )
        }
        var payload = VoiceAnnouncementPayload(
            gameType: .badminton, phase: .scoreChange,
            leftTeamName: "Alice", rightTeamName: "Bob",
            leftScore: 3, rightScore: 2, serverSide: .left
        )
        #expect(try call("en", payload) == "3, 2")
        #expect(try call("ja", payload) == "スリー、トゥ")
        payload.serverSide = .right
        #expect(try call("en", payload) == "2, 3")
        payload.serverSide = .left
        payload.rightScore = 0
        #expect(try call("en", payload) == "3, love")
        #expect(try call("ja", payload) == "スリー、ラブ")

        payload.gameType = .tennis
        payload.leftScore = 1
        #expect(try call("en", payload) == "Fifteen, love")
        #expect(try call("ja", payload) == "フィフティーン、ラブ")
        #expect(try call("ko", payload) == "피프틴, 러브")
        payload.rightScore = 1
        #expect(try call("en", payload) == "Fifteen all")
        #expect(try call("ja", payload) == "フィフティーンオール")
        #expect(try call("ko", payload) == "피프틴 올")
        payload.isTieBreak = true
        payload.leftScore = 3
        payload.rightScore = 2
        #expect(try call("en", payload) == "3, 2, Alice")

        // Loanwords used for tennis must not replace pickleball's plain counts.
        payload.gameType = .pickleball
        payload.leftScore = 15
        payload.rightScore = 14
        payload.serverNumber = 2
        #expect(try call("en", payload) == "fifteen, fourteen, 2")
        #expect(try call("ja", payload) == "15, 14, 2")
        #expect(try call("ko", payload) == "15, 14, 2")
    }
    /// 中文标准播报（buildChineseStandard）与 zh-Hans / zh-Hant 模板的实际文案。
    @Test func chineseStandardRendersEstablishedChineseCalls() throws {
        for code in ["zh-Hans", "zh-Hant"] {
            let templates = try VoiceProductionCalls.templates(code)
            let rendered = Self.chineseCases().map {
                LocalizedVoiceAnnouncementBuilder.buildChineseStandard($0.payload)
                    .render(locale: .init(identifier: code), template: { templates[$0] })
            }
            let expected = code == "zh-Hans" ? Self.chineseExpectedHans : Self.chineseExpectedHant
            #expect(rendered == expected, "\(code) \(rendered)")
        }
    }

    static let chineseExpectedHans: [String?] = [
        "5比3",
        "本局结束，第一局由Alice获胜，21比18",
        "8比7",
        "11比5，本局由Alice获胜",
        "30比15",
        "4比3",
        "换发球，3比0",
        "Alice发球，0比0",
        "平分",
        "交换场地",
    ]
    static let chineseExpectedHant: [String?] = [
        "5比3",
        "本局結束，第一局由Alice獲勝，21比18",
        "8比7",
        "11比5，本局由Alice獲勝",
        "30比15",
        "4比3",
        "換發球，3比0",
        "Alice發球，0比0",
        "平分",
        "交換場地",
    ]

    static func chineseCases() -> [(label: String, payload: VoiceAnnouncementPayload)] {
        [
            ("badminton.score", .init(gameType: .badminton, phase: .scoreChange, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 5, rightScore: 3, serverSide: .left)),
            ("badminton.setEnd", .init(gameType: .badminton, phase: .setEnd, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 21, rightScore: 18, leftSets: 1, currentSet: 1, winnerSide: .left)),
            ("pingpong.score", .init(gameType: .pingpong, phase: .scoreChange, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 8, rightScore: 7, serverSide: .left)),
            ("pingpong.setEnd", .init(gameType: .pingpong, phase: .setEnd, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 11, rightScore: 5, leftSets: 1, currentSet: 1, winnerSide: .left)),
            ("tennis.point", .init(gameType: .tennis, phase: .scoreChange, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 2, rightScore: 1, serverSide: .left)),
            ("pickleball.score", .init(gameType: .pickleball, phase: .scoreChange, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 4, rightScore: 3, serverSide: .left)),
            ("squash.score", .init(gameType: .squash, phase: .scoreChange, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 3, rightScore: 0, serverSide: .left, serviceOver: true)),
            ("shuttlecock.opening", .init(gameType: .shuttlecock, phase: .opening, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 0, rightScore: 0, serverSide: .left, serverName: "Alice")),
            ("softtennis.point", .init(gameType: .softTennis, phase: .scoreChange, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 3, rightScore: 3, serverSide: .left)),
            ("badminton.sideChange", .init(gameType: .badminton, phase: .sideChange, leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 11, rightScore: 8)),
        ]
    }

    @Test func everySupportedLanguageRendersEverySportScenario() throws {
        let samples = Self.samples()
        for language in SportsVoiceLanguage.all {
            let templates = try VoiceProductionCalls.templates(language.localization)
            var failures: [String] = []
            for payload in samples {
                let message = language.localization.hasPrefix("zh-")
                    ? LocalizedVoiceAnnouncementBuilder.buildChineseStandard(payload)
                    : LocalizedVoiceAnnouncementBuilder.build(payload)
                if message.render(locale: .init(identifier: language.speechLocale), template: { templates[$0] }) == nil {
                    failures.append("\(payload.gameType) \(payload.phase) \(payload.leftScore)-\(payload.rightScore)")
                }
            }
            #expect(failures.isEmpty, "\(language.localization): \(failures)")
        }
    }
    @Test func storedMatchStopsWhenUnsupportedAndRecoversAfterVoiceDownload() {
        func expectDecision(_ actual: SportsVoiceSessionGate.Decision, _ expected: SportsVoiceSessionGate.Decision) { #expect(actual == expected) }
        func expectBoolean(_ actual: Bool, _ expected: Bool) { #expect(actual == expected) }
        for code in SportsVoiceLanguage.all.map(\.localization) + ["ur"] {
            for version in [26, 27] {
                let language = SportsVoiceLanguage.resolve(localization: code, iosMajorVersion: version)
                var gate = SportsVoiceSessionGate()
                let id = UUID()
                expectBoolean(gate.beginSession(id), true)
                if language == nil {
                    expectDecision(gate.evaluate(language: language, voiceAvailable: true), .unsupported)
                    expectDecision(gate.evaluate(language: language, voiceAvailable: false), .unsupported)
                    continue
                }
                expectDecision(gate.evaluate(language: language, voiceAvailable: true), .ready)
                expectDecision(gate.evaluate(language: language, voiceAvailable: false), .missingVoice(showDownloadGuide: true))
                expectBoolean(gate.beginSession(id), false) // Reappearing/foregrounding is the same match.
                expectDecision(gate.evaluate(language: language, voiceAvailable: false), .missingVoice(showDownloadGuide: false))
                expectDecision(gate.evaluate(language: language, voiceAvailable: true), .ready)
                expectDecision(gate.evaluate(language: language, voiceAvailable: false), .missingVoice(showDownloadGuide: false))
                expectBoolean(gate.beginSession(UUID()), true)
                expectDecision(gate.evaluate(language: language, voiceAvailable: false), .missingVoice(showDownloadGuide: true))
                expectBoolean(gate.beginSession(id), true) // Restoring an earlier match retains its prompt budget.
                expectDecision(gate.evaluate(language: language, voiceAvailable: false), .missingVoice(showDownloadGuide: false))
            }
        }
    }
}
