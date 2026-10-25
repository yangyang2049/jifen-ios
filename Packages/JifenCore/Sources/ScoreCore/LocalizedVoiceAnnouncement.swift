import Foundation

/// A semantic phrase tree. User names remain arguments; sports have explicit point vocabularies.
/// Core rules choose phrases; the host resolves templates from its own language bundle.
public indirect enum VoiceAnnouncementMessage: Equatable, Sendable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    case phrase(String, [VoiceAnnouncementMessage])
    case verbatim(String)
    case durationMinutes(Int)
    case setUnit(Int)
    case joined([VoiceAnnouncementMessage], separator: VoiceAnnouncementMessage)
    case capitalized(VoiceAnnouncementMessage)

    public init(stringLiteral value: String) {
        self = value.isEmpty ? .verbatim("") : .phrase(value, [])
    }
    public init(stringInterpolation value: StringInterpolation) {
        self = .phrase(value.template, value.arguments)
    }
    public struct StringInterpolation: StringInterpolationProtocol {
        var template = ""
        var arguments: [VoiceAnnouncementMessage] = []
        public init(literalCapacity: Int, interpolationCount: Int) { }
        public mutating func appendLiteral(_ value: String) { template += value }
        public mutating func appendInterpolation(_ value: VoiceAnnouncementMessage) { append(value) }
        public mutating func appendInterpolation(_ value: String) { append(.verbatim(value)) }
        public mutating func appendInterpolation(_ value: Int) { append(.verbatim(String(value))) }
        private mutating func append(_ value: VoiceAnnouncementMessage) {
            arguments.append(value)
            template += "%\(arguments.count)$@"
        }
    }
    public var isEmpty: Bool {
        if case .verbatim(let value) = self { return value.isEmpty }
        return false
    }
    /// Nil means a template is missing; never silently fall back to English.
    public func render(locale: Locale, template: (String) -> String?) -> String? {
        switch self {
        case .verbatim(let value): return value
        case .setUnit(let count):
            return template("set_unit." + Self.pluralCategory(count, locale: locale))
        case .durationMinutes(let minutes):
            return Duration.seconds(minutes * 60).formatted(.units(allowed: [.minutes], width: .wide).locale(locale))
        case .phrase(let key, let arguments):
            guard let format = template(key) else { return nil }
            var values: [CVarArg] = []
            for argument in arguments {
                guard let value = argument.render(locale: locale, template: template) else { return nil }
                values.append(value as NSString)
            }
            return String(format: format, locale: locale, arguments: values)
        case .joined(let messages, let separator):
            guard let separator = separator.render(locale: locale, template: template) else { return nil }
            var values: [String] = []
            for message in messages {
                guard let value = message.render(locale: locale, template: template) else { return nil }
                values.append(value)
            }
            return values.joined(separator: separator)
        case .capitalized(let message):
            guard let value = message.render(locale: locale, template: template) else { return nil }
            guard let first = value.first else { return value }
            return String(first).uppercased(with: locale) + value.dropFirst()
        }
    }
    private static func pluralCategory(_ n: Int, locale: Locale) -> String {
        let language = locale.language.languageCode?.identifier ?? "en"
        switch language {
        case "ar":
            if n == 0 { return "zero" }; if n == 1 { return "one" }; if n == 2 { return "two" }
            if (3...10).contains(n % 100) { return "few" }
            if (11...99).contains(n % 100) { return "many" }
        case "ru", "uk", "hr":
            if n % 10 == 1 && n % 100 != 11 { return "one" }
            if (2...4).contains(n % 10) && !(12...14).contains(n % 100) { return "few" }
            return "many"
        case "pl":
            if n == 1 { return "one" }
            if (2...4).contains(n % 10) && !(12...14).contains(n % 100) { return "few" }
            return "many"
        case "cs", "sk":
            if n == 1 { return "one" }; if (2...4).contains(n) { return "few" }
        case "sl":
            if n % 100 == 1 { return "one" }; if n % 100 == 2 { return "two" }
            if (3...4).contains(n % 100) { return "few" }
        default: if n == 1 { return "one" }
        }
        return "other"
    }

    public static func + (lhs: Self, rhs: Self) -> Self { .joined([lhs, rhs], separator: .verbatim("")) }
    public static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
}

private extension Array where Element == VoiceAnnouncementMessage {
    func voiceJoined(separator: VoiceAnnouncementMessage) -> VoiceAnnouncementMessage { .joined(self, separator: separator) }
}

/// Semantic phrase construction. Production calls use `buildReviewed` so a
/// translated phrase is never mistaken for a documented officiating convention.
public enum LocalizedVoiceAnnouncementBuilder {
    /// Sparse evidence matrix, documented in docs/sports-voice-score-calls-2026-10-03.md.
    /// Unverified sport/language combinations speak numbers, without borrowed cues.
    public static func buildReviewed(_ payload: VoiceAnnouncementPayload, localization: String) -> VoiceAnnouncementMessage {
        let english = localization == "en"
        let japanese = localization == "ja"
        let french = ["fr", "fr-CA"].contains(localization)
        let spanish = ["es-ES", "es-MX"].contains(localization)
        let portuguese = ["pt-PT", "pt-BR"].contains(localization)
        // ITTF HMO 2026 Appendix D, including the HKTTA Chinese translation
        // (printed pp. 106-107). Result calls are separate from live score calls.
        if ["zh-Hans", "zh-Hant"].contains(localization),
           VoiceAnnouncementSupport.isPingpong(payload.gameType),
           [.setEnd, .matchEnd].contains(payload.phase) {
            return reviewedTableTennisResultZh(payload)
        }
        // BWF Vocabulary 6.1-6.5; CTBA's 2025-11-17 bilingual rulebook,
        // printed p.54. Match results list game scores, not the games-won total.
        if ["zh-Hans", "zh-Hant"].contains(localization),
           VoiceAnnouncementSupport.isBadminton(payload.gameType),
           [.setEnd, .matchEnd].contains(payload.phase) {
            return reviewedBadmintonResultZh(payload)
        }
        // ITF 2026 II.G.4(e-h); CTA's published Chinese score-call vocabulary,
        // printed p.39. Game counts and set counts must remain distinct.
        if ["zh-Hans", "zh-Hant"].contains(localization),
           VoiceAnnouncementSupport.isTennis(payload.gameType),
           [.gameEnd, .setEnd, .matchEnd].contains(payload.phase) {
            return reviewedTennisResultZh(payload)
        }
        // WSF 2025 Appendix 2.1, Chinese edition approved by the General
        // Administration of Sport, PDF p.31: game/match winner and game scores.
        if ["zh-Hans", "zh-Hant"].contains(localization), payload.gameType == .squash,
           [.setEnd, .matchEnd].contains(payload.phase) {
            return reviewedSquashResultZh(payload)
        }
        if payload.gameType == .softTennis, english || japanese {
            return reviewedSoftTennis(payload)
        }
        if VoiceAnnouncementSupport.isPickleball(payload.gameType),
           [.opening, .scoreChange, .breakResume].contains(payload.phase) {
            if english { return payload.phase == .breakResume ? buildBreak(payload) : buildPickleballScoreChange(payload) }
            // USAP 2026 6.B / 14.A.3: the server number is essential in
            // traditional doubles, absent in singles and rally-scoring doubles.
            let server = resolveServerSide(payload)
            let args: [VoiceAnnouncementMessage] = [.verbatim(String(scoreOf(payload, server))), .verbatim(String(scoreOf(payload, server.opposite)))]
            if let number = payload.serverNumber, number == 1 || number == 2 {
                return .phrase("score.numbers.three", args + [.verbatim(String(number))])
            }
            return .phrase("score.numbers", args)
        }
        if VoiceAnnouncementSupport.isBadminton(payload.gameType), english || japanese {
            switch payload.phase {
            case .scoreChange:
                if payload.leftScore == payload.rightScore, let point = payload.criticalPoint {
                    let cue: VoiceAnnouncementMessage = point == .matchPoint ? "match point" : "game point"
                    let score: VoiceAnnouncementMessage = .phrase("badminton.critical.all", [badmintonNumber(payload.leftScore), cue])
                    return payload.serviceOver ? "Service over, \(score)" : score
                }
                return buildBadmintonScoreChange(payload)
            case .opening: return buildOpening(payload)
            case .breakResume: return buildBreak(payload)
            case .sideChange: return "Change ends"
            case .breakWarning:
                return payload.breakCue == .twentySeconds ? "20 seconds" : ""
            case .setEnd, .matchEnd:
                if english { return build(payload) }
            case .gameEnd, .breakStart: return ""
            }
        }
        if VoiceAnnouncementSupport.isTennis(payload.gameType) {
            if english {
                switch payload.phase {
                case .opening: return "\(resolveServerName(payload)) to serve, play"
                case .breakWarning, .breakResume: return payload.phase == .breakResume || payload.breakCue == .time ? "Time" : ""
                case .sideChange, .breakStart: return ""
                default: return build(payload)
                }
            }
            if french || spanish {
                switch payload.phase {
                case .opening: return .phrase("tennis.opening", [.verbatim(resolveServerName(payload))])
                case .scoreChange where payload.isTieBreak: return buildTennisTieBreak(payload)
                case .gameEnd, .setEnd, .matchEnd: return build(payload)
                default: break
                }
            }
            // Native point vocabularies are documented separately from numbers
            // in a tie-break and from the full match/result announcements.
            if payload.phase == .scoreChange, !payload.isTieBreak {
                if japanese || french || spanish {
                    if japanese, payload.tennisDeuceMode == "no_ad", payload.leftScore == payload.rightScore,
                       payload.leftScore >= 3 { return plainScore(payload) }
                    return reviewedNativeTennisPoint(payload)
                }
                if ["ko", "zh-Hans", "zh-Hant"].contains(localization),
                   min(payload.leftScore, payload.rightScore) >= 3,
                   payload.tennisDeuceMode != "no_ad" {
                    return reviewedNativeTennisPoint(payload)
                }
            }
        }
        if english, VoiceAnnouncementSupport.isPingpong(payload.gameType) {
            switch payload.phase {
            case .breakResume: return "Time" + ". " + buildTableTennisScoreChange(payload)
            case .breakWarning: return payload.breakCue == .time ? "Time" : ""
            case .sideChange, .breakStart: return ""
            default: return build(payload)
            }
        }
        if japanese, VoiceAnnouncementSupport.isPingpong(payload.gameType),
           [.opening, .scoreChange].contains(payload.phase), payload.leftScore == 0, payload.rightScore == 0 {
            return .phrase("pingpong.love.all", [])
        }
        if localization.hasPrefix("zh-"), VoiceAnnouncementSupport.isPingpong(payload.gameType),
           payload.phase == .scoreChange, payload.leftScore == payload.rightScore {
            return .phrase("pingpong.score.all", [.verbatim(String(payload.leftScore))])
        }
        if english, payload.gameType == .squash { return reviewedSquash(payload) }
        if french || spanish || portuguese, payload.gameType == .squash, payload.phase == .scoreChange {
            return reviewedSquash(payload)
        }
        if english, payload.gameType == .padel {
            switch payload.phase {
            case .scoreChange:
                if payload.isTieBreak { return plainScore(payload) }
                if payload.tennisDeuceMode == PadelDeuceMode.starPoint.rawValue,
                   let advantage = softPadelAdvantage(payload) {
                    let number = min(2, max(1, payload.starPointReturnedAdvantages + 1))
                    return .phrase("padel.advantage.number", [.verbatim(String(number)), namedTeam(payload, advantage)])
                }
                return buildPadel(payload)
            case .gameEnd: return "Game"
            default: break
            }
        }
        // A local-language rule permits numeric TT calls; no invented "all"
        // translation, service-change prefix or other sport's jargon is needed.
        return numericFallback(payload)
    }

    private static func reviewedTableTennisResultZh(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        guard let winner = payload.winnerSide else {
            return payload.phase == .matchEnd ? "比赛结束" : "本局结束"
        }
        let name = winnerName(payload)
        let score = VoiceAnnouncementMessage.phrase("score.numbers", [
            .verbatim(String(scoreOf(payload, winner))), .verbatim(String(scoreOf(payload, winner.opposite)))
        ])
        let game = max(1, payload.currentSet ?? (payload.leftSets + payload.rightSets))
        if payload.phase == .setEnd {
            return .phrase("pingpong.result.game", [score, name, .verbatim(String(game))])
        }
        let games = VoiceAnnouncementMessage.phrase("score.numbers", [
            .verbatim(String(scoreOfSets(payload, winner))), .verbatim(String(scoreOfSets(payload, winner.opposite)))
        ])
        if payload.isManualEnd { return .phrase("pingpong.result.manual", [name, games]) }
        return .phrase("pingpong.result.match", [score, name, .verbatim(String(game)), games])
    }

    private static func reviewedBadmintonResultZh(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        guard let winner = payload.winnerSide else {
            return payload.phase == .matchEnd ? "比赛结束" : "本局结束"
        }
        let name = winnerName(payload)
        if payload.phase == .setEnd {
            let game = max(1, payload.currentSet ?? (payload.leftSets + payload.rightSets))
            let score = VoiceAnnouncementMessage.phrase("score.numbers", [
                .verbatim(String(scoreOf(payload, winner))), .verbatim(String(scoreOf(payload, winner.opposite)))
            ])
            var line = VoiceAnnouncementMessage.phrase("badminton.result.game", [.verbatim(String(game)), name, score])
            if payload.leftSets == 1, payload.rightSets == 1 { line += "，" + .phrase("badminton.result.one.all", []) }
            return line
        }
        if payload.isManualEnd { return "比赛结束，\(name)获胜" }
        let scores = resolveSetScoreList(payload).map { score in
            VoiceAnnouncementMessage.phrase("score.numbers", [
                .verbatim(String(winner == .left ? score.leftGames : score.rightGames)),
                .verbatim(String(winner == .left ? score.rightGames : score.leftGames))
            ])
        }.voiceJoined(separator: "、")
        return .phrase("badminton.result.match", [name, scores])
    }

    private static func reviewedTennisResultZh(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        guard let winner = payload.winnerSide else {
            return payload.phase == .matchEnd ? "比赛结束" : (payload.phase == .setEnd ? "本盘结束" : "本局结束")
        }
        func pair(_ a: Int, _ b: Int) -> VoiceAnnouncementMessage {
            .phrase("score.numbers", [.verbatim(String(a)), .verbatim(String(b))])
        }
        let name = winnerName(payload)
        let set = max(1, payload.currentSet ?? (payload.leftSets + payload.rightSets))
        if payload.phase == .gameEnd {
            if payload.leftScore == payload.rightScore {
                return .phrase(payload.isTieBreak ? "tennis.result.game.tiebreak" : "tennis.result.game.all",
                    [name, .verbatim(String(set)), .verbatim(String(payload.leftScore))])
            }
            let lead: MatchSide = payload.leftScore > payload.rightScore ? .left : .right
            return .phrase("tennis.result.game.lead", [name, .verbatim(String(set)),
                pair(scoreOf(payload, lead), scoreOf(payload, lead.opposite)), namedTeam(payload, lead)])
        }
        if payload.phase == .setEnd {
            var line = VoiceAnnouncementMessage.phrase("tennis.result.set", [.verbatim(String(set)), name,
                pair(scoreOf(payload, winner), scoreOf(payload, winner.opposite))])
            if payload.leftSets == payload.rightSets {
                line += .verbatim("。") + .phrase("tennis.result.sets.all", [.verbatim(String(payload.leftSets))])
            } else {
                let lead: MatchSide = payload.leftSets > payload.rightSets ? .left : .right
                line += .verbatim("。") + .phrase("tennis.result.sets.lead", [
                    pair(scoreOfSets(payload, lead), scoreOfSets(payload, lead.opposite)), namedTeam(payload, lead)])
            }
            return line
        }
        if payload.isManualEnd { return "比赛结束，\(name)获胜" }
        if payload.isTieBreak, payload.leftSets == 0, payload.rightSets == 0 {
            return .phrase("tennis.result.match.tiebreak", [name, pair(scoreOf(payload, winner), scoreOf(payload, winner.opposite))])
        }
        let scores = resolveSetScoreList(payload).map { score in
            pair(winner == .left ? score.leftGames : score.rightGames, winner == .left ? score.rightGames : score.leftGames)
        }.voiceJoined(separator: "、")
        return .phrase("tennis.result.match", [name,
            pair(scoreOfSets(payload, winner), scoreOfSets(payload, winner.opposite)), scores])
    }

    private static func reviewedSquashResultZh(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        guard let winner = payload.winnerSide else {
            return payload.phase == .matchEnd ? "比赛结束" : "本局结束"
        }
        func pair(_ a: Int, _ b: Int) -> VoiceAnnouncementMessage {
            .phrase("score.numbers", [.verbatim(String(a)), .verbatim(String(b))])
        }
        let name = winnerName(payload)
        let points = pair(scoreOf(payload, winner), scoreOf(payload, winner.opposite))
        if payload.phase == .setEnd {
            var line = VoiceAnnouncementMessage.phrase("squash.result.game", [points, name])
            if payload.leftSets == payload.rightSets {
                line += .verbatim("。") + .phrase("squash.result.games.all", [.verbatim(String(payload.leftSets))])
            } else {
                let lead: MatchSide = payload.leftSets > payload.rightSets ? .left : .right
                line += .verbatim("。") + .phrase("squash.result.leads", [namedTeam(payload, lead),
                    pair(scoreOfSets(payload, lead), scoreOfSets(payload, lead.opposite))])
            }
            return line
        }
        if payload.isManualEnd { return "比赛结束，\(name)获胜" }
        let scores = resolveSetScoreList(payload).map { score in
            pair(winner == .left ? score.leftGames : score.rightGames, winner == .left ? score.rightGames : score.leftGames)
        }.voiceJoined(separator: "、")
        return .phrase("squash.result.match", [points, name,
            pair(scoreOfSets(payload, winner), scoreOfSets(payload, winner.opposite)), scores])
    }

    private static func reviewedNativeTennisPoint(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        if payload.leftScore == 0, payload.rightScore == 0 { return plainScore(payload) }
        if min(payload.leftScore, payload.rightScore) >= 3 {
            if payload.leftScore == payload.rightScore {
                if payload.tennisDeuceMode == "no_ad" { return .phrase("tennis.deciding.point", []) }
                return .phrase(payload.leftScore == 3 && !payload.returnedToDeuce ? "tennis.deuce.first" : "tennis.deuce.again", [])
            }
            return .phrase("tennis.advantage.name", [namedTeam(payload, payload.leftScore > payload.rightScore ? .left : .right)])
        }
        return buildTennisNormalPoint(payload)
    }

    private static func numericFallback(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        switch payload.phase {
        case .breakStart, .breakWarning, .sideChange: return ""
        case .opening, .scoreChange, .gameEnd, .setEnd, .matchEnd, .breakResume: return plainScore(payload)
        }
    }

    private static func plainScore(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        var first = payload.leftScore
        var second = payload.rightScore
        if VoiceAnnouncementSupport.isTennisFamily(payload.gameType) && payload.gameType != .softTennis,
           !payload.isTieBreak, [.opening, .scoreChange, .breakResume].contains(payload.phase) {
            // Payloads contain point counts, not the displayed 0/15/30/40 score.
            let points = [0, 15, 30, 40]
            first = points[min(3, max(0, first))]
            second = points[min(3, max(0, second))]
        }
        if VoiceAnnouncementSupport.isTennis(payload.gameType), payload.isTieBreak,
           payload.phase == .scoreChange {
            (first, second) = (max(first, second), min(first, second))
        } else if [.opening, .scoreChange, .breakResume].contains(payload.phase),
                  VoiceAnnouncementSupport.isBadminton(payload.gameType) || VoiceAnnouncementSupport.isPingpong(payload.gameType)
                    || VoiceAnnouncementSupport.isTennisFamily(payload.gameType) || VoiceAnnouncementSupport.isPickleball(payload.gameType)
                    || payload.gameType == .squash,
                  resolveServerSide(payload) == .right {
            (first, second) = (second, first)
        }
        return .phrase("score.numbers", [.verbatim(String(first)), .verbatim(String(second))])
    }

    private static func reviewedSoftTennis(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        func number(_ n: Int) -> VoiceAnnouncementMessage {
            (0...6).contains(n) ? .phrase("softtennis.number.\(n)", []) : .verbatim(String(n))
        }
        func score() -> VoiceAnnouncementMessage {
            let server = resolveServerSide(payload)
            let first = scoreOf(payload, server), second = scoreOf(payload, server.opposite)
            return first == second
                ? .phrase("softtennis.score.all", [number(first)])
                : .phrase("score.numbers", [number(first), number(second)])
        }
        switch payload.phase {
        case .opening:
            guard let games = payload.maxSets, [7, 9].contains(games) else { return plainScore(payload) }
            return .phrase("softtennis.opening", [.phrase("softtennis.match.games.\(games)", [])])
        case .scoreChange:
            if payload.leftScore == payload.rightScore, payload.leftScore >= (payload.isTieBreak ? 6 : 3) {
                return .phrase(payload.leftScore == (payload.isTieBreak ? 6 : 3) && !payload.returnedToDeuce ? "softtennis.deuce" : "softtennis.deuce.again", [])
            }
            if let advantage = softTennisAdvantage(payload) {
                return .phrase(advantage == resolveServerSide(payload) ? "softtennis.advantage.server" : "softtennis.advantage.receiver", [])
            }
            if payload.leftScore == 0, payload.rightScore == 0 { return plainScore(payload) }
            return score()
        case .gameEnd: return .phrase("softtennis.game", [])
        case .setEnd, .matchEnd: return .phrase("softtennis.game.set", [])
        case .sideChange: return .phrase("softtennis.change.sides", [])
        case .breakResume: return .phrase("softtennis.no.time", [])
        case .breakStart: return .phrase("softtennis.time", [])
        case .breakWarning: return ""
        }
    }

    private static func softPadelAdvantage(_ payload: VoiceAnnouncementPayload) -> MatchSide? {
        guard min(payload.leftScore, payload.rightScore) >= 3, abs(payload.leftScore - payload.rightScore) == 1 else { return nil }
        return payload.leftScore > payload.rightScore ? .left : .right
    }

    private static func reviewedSquash(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        func number(_ n: Int) -> VoiceAnnouncementMessage { n == 0 ? .phrase("squash.zero", []) : .verbatim(String(n)) }
        func score(_ side: MatchSide) -> VoiceAnnouncementMessage {
            let first = scoreOf(payload, side), second = scoreOf(payload, side.opposite)
            return first == second ? .phrase("squash.score.all", [number(first)]) : .phrase("score.numbers", [number(first), number(second)])
        }
        switch payload.phase {
        case .opening: return buildSquash(payload)
        case .scoreChange:
            var line = score(resolveServerSide(payload))
            if payload.serviceOver { line = .phrase("squash.hand.out", [line]) }
            if payload.leftScore == 10, payload.rightScore == 10 { line += ", " + .phrase("squash.two.clear", []) }
            else if let point = payload.criticalPoint { line += ", " + .phrase(point == .matchBall ? "squash.match.ball" : "squash.game.ball", []) }
            return line
        case .setEnd:
            guard hasWinner(payload) else { return plainScore(payload) }
            var line: VoiceAnnouncementMessage = .phrase("squash.game.to", [score(resolveWinnerSide(payload)), winnerName(payload)])
            if payload.leftSets == payload.rightSets {
                line += ". " + .phrase("squash.games.all", [number(payload.leftSets)])
            } else {
                let leader: MatchSide = payload.leftSets > payload.rightSets ? .left : .right
                let won = scoreOfSets(payload, leader)
                line += ". " + .phrase("squash.leads", [namedTeam(payload, leader), number(won), .phrase(won == 1 ? "squash.game.unit" : "squash.games.unit", []), number(scoreOfSets(payload, leader.opposite))])
            }
            return line
        case .matchEnd:
            guard hasWinner(payload), !payload.isManualEnd else { return plainScore(payload) }
            let winner = resolveWinnerSide(payload)
            let scores = resolveSetScoreList(payload).map { value -> VoiceAnnouncementMessage in
                .phrase("score.numbers", [number(winner == .left ? value.leftGames : value.rightGames), number(winner == .left ? value.rightGames : value.leftGames)])
            }.voiceJoined(separator: ", ")
            return .phrase("squash.match.to", [score(winner), winnerName(payload), number(scoreOfSets(payload, winner)), number(scoreOfSets(payload, winner.opposite)), scores])
        case .breakResume: return "Time"
        case .breakWarning: return payload.breakCue == .twentySeconds ? "" : buildBreak(payload)
        case .breakStart, .gameEnd, .sideChange: return ""
        }
    }

    /// Chinese officiating has different set/result wording from the international calls.
    /// Keep that established style, while resolving every phrase in the application layer.
    public static func buildChineseStandard(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        ChineseStandardVoiceAnnouncementBuilder.build(payload)
    }
    public static func build(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        if payload.gameType == .squash { return buildSquash(payload) }
        if payload.gameType == .shuttlecock { return buildShuttlecock(payload) }
        if payload.gameType == .softTennis { return buildSoftTennis(payload) }
        if payload.gameType == .padel { return buildPadel(payload) }
        switch payload.phase {
        case .breakStart, .breakWarning, .breakResume:
            return buildBreak(payload)
        case .opening:
            return buildOpening(payload)
        case .scoreChange:
            if VoiceAnnouncementSupport.isPingpong(payload.gameType) {
                return buildTableTennisScoreChange(payload)
            }
            if VoiceAnnouncementSupport.isTennis(payload.gameType) {
                return buildTennisScoreChange(payload)
            }
            if VoiceAnnouncementSupport.isPickleball(payload.gameType) {
                return buildPickleballScoreChange(payload)
            }
            return buildBadmintonScoreChange(payload)
        case .gameEnd:
            return VoiceAnnouncementSupport.isTennis(payload.gameType) ? buildTennisGameEnd(payload) : ""
        case .setEnd:
            if VoiceAnnouncementSupport.isTennis(payload.gameType) {
                return buildTennisSetEnd(payload, isMatchEnd: false)
            }
            if VoiceAnnouncementSupport.isPingpong(payload.gameType) {
                return buildTableTennisSetEnd(payload)
            }
            if VoiceAnnouncementSupport.isPickleball(payload.gameType) {
                return buildPickleballEnd(payload, isMatchEnd: false)
            }
            return buildBadmintonSetEnd(payload)
        case .matchEnd:
            if VoiceAnnouncementSupport.isTennis(payload.gameType) {
                return buildTennisSetEnd(payload, isMatchEnd: true)
            }
            if VoiceAnnouncementSupport.isPingpong(payload.gameType) {
                return buildTableTennisMatchEnd(payload)
            }
            if VoiceAnnouncementSupport.isPickleball(payload.gameType) {
                return buildPickleballEnd(payload, isMatchEnd: true)
            }
            return buildBadmintonMatchEnd(payload)
        case .sideChange:
            return "Change ends"
        }
    }

    private static func buildBreak(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        if payload.phase == .breakWarning {
            return switch payload.breakCue {
            case .twentySeconds: "20 seconds"
            case .halfTime: "Half-time"
            case .fifteenSeconds: "15 seconds"
            case .time: "Time"
            case nil: ""
            }
        }
        if payload.phase == .breakStart {
            guard VoiceAnnouncementSupport.isPickleball(payload.gameType) else { return "" }
            let minutes = max(1, (payload.breakDurationSeconds ?? 0) / 60)
            let duration = VoiceAnnouncementMessage.durationMinutes(minutes)
            if (payload.breakDurationSeconds ?? 0) >= 120 {
                return "Interval, \(duration)"
            }
            var result: VoiceAnnouncementMessage = ""
            if payload.leftScore != 0 || payload.rightScore != 0 {
                result = buildPickleballScoreChange(payload) + ". "
            }
            result += "Time-out"
            if payload.sideChange { result += ", change ends" }
            return result + ", \(duration)"
        }
        guard payload.phase == .breakResume else { return "" }
        if VoiceAnnouncementSupport.isBadminton(payload.gameType) {
            let server = resolveServerSide(payload)
            return "\(sideFirstNumeric(payload, server)), play"
        }
        if VoiceAnnouncementSupport.isPingpong(payload.gameType) {
            return "Time. Game \(payload.currentSet ?? 1). \(resolveServerName(payload)) serves, love all"
        }
        if payload.gameType == .squash {
            return "Time. Game \(payload.currentSet ?? 1). \(resolveServerName(payload)) to serve, love all"
        }
        if payload.gameType == .shuttlecock {
            return "Time. Game \(payload.currentSet ?? 1), \(resolveServerName(payload)) serves, 0-0"
        }
        if VoiceAnnouncementSupport.isPickleball(payload.gameType) {
            return "Time in, \(buildPickleballScoreChange(payload))"
        }
        return "Time"
    }

    private static func buildSquash(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        switch payload.phase {
        case .opening:
            let receiver = payload.receiverName ?? teamName(payload, resolveServerSide(payload).opposite)
            return "\(resolveServerName(payload)) to serve, \(receiver) to receive, best of \(payload.maxSets ?? 5) games, love all"
        case .scoreChange:
            let server = resolveServerSide(payload)
            var line = sideFirstNumeric(payload, server)
            if payload.serviceOver { line = "Hand out, \(line)" }
            if payload.leftScore == 10, payload.rightScore == 10 {
                line += ", a player must win by 2 points"
            } else if let point = payload.criticalPoint {
                let cue: VoiceAnnouncementMessage = point == .matchBall ? "Match ball" : "Game ball"
                line += ", \(cue)"
            }
            return line
        case .setEnd: return buildBadmintonSetEnd(payload)
        case .matchEnd: return buildBadmintonMatchEnd(payload)
        case .sideChange: return "Change ends"
        case .breakStart, .breakWarning, .breakResume: return buildBreak(payload)
        case .gameEnd: return ""
        }
    }

    private static func buildShuttlecock(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        switch payload.phase {
        case .opening: return "\(resolveServerName(payload)) serves, 0-0"
        case .scoreChange: return sideFirstNumeric(payload, resolveServerSide(payload))
        case .setEnd: return buildBadmintonSetEnd(payload)
        case .matchEnd: return buildBadmintonMatchEnd(payload)
        case .sideChange: return "Change ends"
        case .breakStart, .breakWarning, .breakResume: return buildBreak(payload)
        case .gameEnd: return ""
        }
    }

    private static func buildSoftTennis(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        switch payload.phase {
        case .opening:
            let games = payload.maxSets == 9 ? 9 : 7
            return "\(games)-game match, play ball"
        case .scoreChange:
            if payload.leftScore == payload.rightScore,
               ((!payload.isTieBreak && payload.leftScore >= 3) || (payload.isTieBreak && payload.leftScore >= 6)) {
                return "Deuce"
            }
            if let advantage = softTennisAdvantage(payload) {
                return "Advantage \(namedTeam(payload, advantage))"
            }
            return sideFirstNumeric(payload, resolveServerSide(payload))
        case .gameEnd:
            return "Game \(winnerName(payload)). \(payload.leftScore)-\(payload.rightScore)"
        case .setEnd, .matchEnd:
            return "Game set. Match to \(winnerName(payload)), \(formatGameScoreByWinner(.init(leftGames: payload.leftScore, rightGames: payload.rightScore), resolveWinnerSide(payload)))"
        case .sideChange: return "Change ends"
        case .breakStart, .breakWarning, .breakResume: return buildBreak(payload)
        }
    }

    private static func buildPadel(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        if payload.phase == .scoreChange, !payload.isTieBreak, payload.leftScore == 3, payload.rightScore == 3 {
            switch payload.tennisDeuceMode {
            case PadelDeuceMode.goldenPoint.rawValue: return "Golden point, receiver's choice"
            case PadelDeuceMode.starPoint.rawValue:
                return switch min(2, max(0, payload.starPointReturnedAdvantages)) {
                case 0: "Deuce 1"
                case 1: "Deuce 2"
                default: "Deuce 3, Star point"
                }
            default: break
            }
        }
        return buildTennisFamily(payload)
    }

    private static func buildTennisFamily(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        switch payload.phase {
        case .opening: return "Match start, \(resolveServerName(payload)) to serve"
        case .scoreChange: return buildTennisScoreChange(payload)
        case .gameEnd: return buildTennisGameEnd(payload)
        case .setEnd: return buildTennisSetEnd(payload, isMatchEnd: false)
        case .matchEnd: return buildTennisSetEnd(payload, isMatchEnd: true)
        case .sideChange: return "Change ends"
        case .breakStart, .breakWarning, .breakResume: return buildBreak(payload)
        }
    }

    private static func buildOpening(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        if VoiceAnnouncementSupport.isTennis(payload.gameType), payload.isTieBreak {
            let format: VoiceAnnouncementMessage = payload.tieBreakTarget == 10
                ? "10-point match tie-break"
                : "7-point tie-break match"
            return "\(format). \(resolveServerName(payload)) to serve"
        }
        if VoiceAnnouncementSupport.isTennis(payload.gameType) {
            return "\(resolveServerName(payload)) to serve, play"
        }
        if VoiceAnnouncementSupport.isPickleball(payload.gameType) {
            return buildPickleballScoreChange(payload)
        }
        let server = resolveServerName(payload)
        if VoiceAnnouncementSupport.isBadminton(payload.gameType) {
            if let receiver = payload.receiverName, !receiver.isEmpty,
               payload.gameType == .badmintonDoubles {
                return "\(server) to serve to \(receiver), love all, play"
            }
            return "\(server) to serve, love all, play"
        }
        return "\(server) to serve, love all"
    }

    private static func buildPickleballScoreChange(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        let server = resolveServerSide(payload)
        let first = scoreOf(payload, server)
        let second = scoreOf(payload, server == .left ? .right : .left)
        let line: VoiceAnnouncementMessage
        if let number = payload.serverNumber, number == 1 || number == 2 {
            line = "\(pickleballNumber(first)), \(pickleballNumber(second)), \(number)"
        } else {
            line = "\(pickleballNumber(first)), \(pickleballNumber(second))"
        }
        if payload.serviceOver { return "Side out, \(line)" }
        if payload.secondServer { return "Second server, \(line)" }
        return line
    }

    private static func pickleballNumber(_ value: Int) -> VoiceAnnouncementMessage {
        switch value {
        case 0: return "zero"
        case 1: return "one"
        case 2: return "two"
        case 3: return "three"
        case 4: return "four"
        case 5: return "five"
        case 6: return "six"
        case 7: return "seven"
        case 8: return "eight"
        case 9: return "nine"
        case 10: return "ten"
        case 11: return "eleven"
        case 12: return "twelve"
        case 13: return "thirteen"
        case 14: return "fourteen"
        case 15: return "fifteen"
        default: return "\(value)"
        }
    }

    private static func buildBadmintonScoreChange(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        let server = resolveServerSide(payload)
        let first = scoreOf(payload, server)
        let second = scoreOf(payload, server.opposite)
        let line: VoiceAnnouncementMessage
        if let criticalPoint = payload.criticalPoint {
            let cue: VoiceAnnouncementMessage = criticalPoint == .matchPoint ? "match point" : "game point"
            let firstLabel = VoiceAnnouncementSupport.isBadminton(payload.gameType) ? badmintonNumber(first) : .verbatim(String(first))
            let secondLabel = VoiceAnnouncementSupport.isBadminton(payload.gameType) ? badmintonNumber(second) : .verbatim(String(second))
            line = "\(firstLabel), \(cue), \(secondLabel)"
        } else {
            let score = VoiceAnnouncementSupport.isBadminton(payload.gameType) ? badmintonScore(first, second) : numericScore(first, second)
            line = score + (payload.isInterval ? ", interval" : "")
        }
        return payload.serviceOver ? "Service over, \(line)" : line
    }

    private static func buildBadmintonSetEnd(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        guard hasWinner(payload) else { return "Game" }
        let winnerName = winnerName(payload)
        let setNumber = payload.currentSet ?? 1
        let ordinal = formatSetNumber(setNumber)
        let gameScore = sideFirstNumeric(payload, resolveWinnerSide(payload))
        var message: VoiceAnnouncementMessage = "Game. \(capitalizeFirst(ordinal)) game won by \(winnerName), \(gameScore)"
        if payload.leftSets == payload.rightSets, payload.leftSets > 0 {
            message += payload.leftSets == 1 ? ". One game all" : ". \(payload.leftSets) games all"
        }
        return message
    }

    private static func buildBadmintonMatchEnd(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        guard hasWinner(payload) else { return "Match over" }
        let winnerName = winnerName(payload)
        if payload.isManualEnd { return "Match won by \(winnerName)" }
        let winnerSide = resolveWinnerSide(payload)
        return "Game. Match won by \(winnerName), \(buildMatchScoreList(payload, winnerSide))"
    }

    private static func buildTableTennisScoreChange(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        if payload.leftScore == 0, payload.rightScore == 0 {
            let server = resolveServerName(payload)
            return "\(server) to serve, love all"
        }
        return sideFirstNumeric(payload, resolveServerSide(payload))
    }

    private static func buildTableTennisSetEnd(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        guard hasWinner(payload) else { return "Game over" }
        let winnerName = winnerName(payload)
        let gameScore = sideFirstNumeric(payload, resolveWinnerSide(payload))
        return "\(gameScore). Game to \(winnerName)"
    }

    private static func buildTableTennisMatchEnd(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        guard hasWinner(payload) else { return "Match over" }
        let winner = winnerName(payload)
        let winnerSide = resolveWinnerSide(payload)
        if payload.isManualEnd {
            let won = scoreOfSets(payload, winnerSide)
            let lost = scoreOfSets(payload, winnerSide.opposite)
            return "Match to \(winner). \(winner) wins \(won) games to \(lost)"
        }
        let gameScore = sideFirstNumeric(payload, winnerSide)
        let won = scoreOfSets(payload, winnerSide)
        let lost = scoreOfSets(payload, winnerSide.opposite)
        return "\(gameScore). Game and match to \(winner). \(winner) wins \(won) games to \(lost)"
    }

    private static func buildPickleballEnd(_ payload: VoiceAnnouncementPayload, isMatchEnd: Bool) -> VoiceAnnouncementMessage {
        guard hasWinner(payload) else { return isMatchEnd ? "Match over" : "Game over" }
        if payload.isManualEnd { return "Match. \(winnerName(payload)) wins" }
        let score = sideFirstNumeric(payload, resolveWinnerSide(payload))
        let winner = winnerName(payload)
        return isMatchEnd
            ? "Point. Game. Match. \(score). \(winner) wins"
            : "Point. Game. \(score). \(winner) wins"
    }

    private static func buildTennisScoreChange(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        payload.isTieBreak ? buildTennisTieBreak(payload) : buildTennisNormalPoint(payload)
    }

    private static func buildTennisNormalPoint(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        let leftScore = payload.leftScore
        let rightScore = payload.rightScore
        if leftScore >= 3, rightScore >= 3 {
            if leftScore == rightScore {
                return payload.tennisDeuceMode == "no_ad"
                    ? "Deciding point, receiver's choice"
                    : "Deuce"
            }
            let advantageSide: MatchSide = leftScore > rightScore ? .left : .right
            return "Advantage \(namedTeam(payload, advantageSide))"
        }
        let serverSide = resolveServerSide(payload)
        let serverLabel = tennisPointLabel(scoreOf(payload, serverSide))
        let receiverLabel = tennisPointLabel(scoreOf(payload, serverSide.opposite))
        if serverLabel == receiverLabel {
            return .phrase("tennis.score.all", [capitalizeFirst(serverLabel)])
        }
        return "\(capitalizeFirst(serverLabel))-\(receiverLabel)"
    }

    private static func buildTennisTieBreak(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        if payload.leftScore == payload.rightScore {
            return "\(payload.leftScore)-all"
        }
        let leaderSide: MatchSide = payload.leftScore > payload.rightScore ? .left : .right
        let leader = scoreOf(payload, leaderSide)
        let trailer = scoreOf(payload, leaderSide.opposite)
        let leaderLabel: VoiceAnnouncementMessage = leader == 0 ? "zero" : VoiceAnnouncementMessage.verbatim(String(leader))
        let trailerLabel: VoiceAnnouncementMessage = trailer == 0 ? "zero" : VoiceAnnouncementMessage.verbatim(String(trailer))
        return "\(leaderLabel)-\(trailerLabel) \(namedTeam(payload, leaderSide))"
    }

    private static func buildTennisGameEnd(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        guard hasWinner(payload) else { return "Game over" }
        let winnerName = winnerName(payload)
        let leftGames = payload.leftScore
        let rightGames = payload.rightScore
        if leftGames == rightGames, payload.isTieBreak {
            return "Game \(winnerName). \(leftGames) games all. Tie-break"
        }
        if leftGames == rightGames {
            return "Game \(winnerName). \(leftGames) games all"
        }
        let leaderSide: MatchSide = leftGames > rightGames ? .left : .right
        let leaderGames = max(leftGames, rightGames)
        let trailingGames = min(leftGames, rightGames)
        let leaderName = namedTeam(payload, leaderSide)
        let setNumber = payload.currentSet ?? 1
        return "Game \(winnerName). \(leaderName) leads \(leaderGames) games to \(trailingGames), \(formatSetNumber(setNumber)) set"
    }

    private static func buildTennisSetEnd(_ payload: VoiceAnnouncementPayload, isMatchEnd: Bool) -> VoiceAnnouncementMessage {
        guard hasWinner(payload) else { return isMatchEnd ? "Match over" : "Set over" }
        let winnerName = winnerName(payload)
        let winnerSide = resolveWinnerSide(payload)
        if isMatchEnd {
            if payload.isManualEnd {
                let won = scoreOfSets(payload, winnerSide)
                let lost = scoreOfSets(payload, winnerSide.opposite)
                let unit = VoiceAnnouncementMessage.setUnit(won)
                return "Match \(winnerName), \(won) \(unit) to \(lost)"
            }
            if payload.isTieBreak, payload.leftSets == 0, payload.rightSets == 0 {
                return "Match \(winnerName), \(sideFirstNumeric(payload, winnerSide))"
            }
            let won = scoreOfSets(payload, winnerSide)
            let lost = scoreOfSets(payload, winnerSide.opposite)
            return "Game, set and match \(winnerName), \(won) sets to \(lost), \(buildMatchScoreList(payload, winnerSide))"
        }
        let setNumber = payload.currentSet ?? 1
        let winnerGames = scoreOf(payload, winnerSide)
        let loserGames = scoreOf(payload, winnerSide.opposite)
        let setScore: VoiceAnnouncementMessage = "\(winnerGames) games to \(loserGames)"
        return "Game and \(formatSetNumber(setNumber)) set \(winnerName), \(setScore)"
    }

    private static func namedTeam(_ payload: VoiceAnnouncementPayload, _ side: MatchSide) -> VoiceAnnouncementMessage {
        let names = side == .right ? payload.rightPlayerNames : payload.leftPlayerNames
        return names.isEmpty ? .verbatim(side == .right ? payload.rightTeamName : payload.leftTeamName) : .joined(names.map(VoiceAnnouncementMessage.verbatim), separator: " and ")
    }

    private static func winnerName(_ payload: VoiceAnnouncementPayload) -> VoiceAnnouncementMessage {
        if let winnerName = payload.winnerName, !winnerName.isEmpty {
            return .verbatim(winnerName)
        }
        return namedTeam(payload, resolveWinnerSide(payload))
    }

    private static func numericScore(_ first: Int, _ second: Int) -> VoiceAnnouncementMessage {
        // The score template inserts a pause between counts; it must not speak a dash or add "to".
        first == second ? "\(first)-all" : "\(first) to \(second)"
    }

    private static func sideFirstNumeric(_ payload: VoiceAnnouncementPayload, _ side: MatchSide) -> VoiceAnnouncementMessage {
        VoiceAnnouncementSupport.isBadminton(payload.gameType)
            ? badmintonScore(scoreOf(payload, side), scoreOf(payload, side.opposite))
            : numericScore(scoreOf(payload, side), scoreOf(payload, side.opposite))
    }

    private static func badmintonNumber(_ score: Int) -> VoiceAnnouncementMessage {
        // BWF's normal score vocabulary is a closed 0...30 inventory. Custom
        // scores outside that range remain numeric arguments, never user-name keys.
        (0...30).contains(score) ? .phrase("badminton.number.\(score)", []) : .verbatim(String(score))
    }

    private static func badmintonScore(_ first: Int, _ second: Int) -> VoiceAnnouncementMessage {
        first == second
            ? .phrase("%1$@-all", [badmintonNumber(first)])
            : .phrase("%1$@ to %2$@", [badmintonNumber(first), badmintonNumber(second)])
    }

    private static func formatSetNumber(_ setNumber: Int) -> VoiceAnnouncementMessage {
        let labels: [VoiceAnnouncementMessage] = ["", "first", "second", "third", "fourth", "fifth"]
        if setNumber >= 1, setNumber < labels.count {
            return labels[setNumber]
        }
        return "\(setNumber)th"
    }

    private static func formatGameScoreByWinner(_ score: VoiceSetScore, _ winnerSide: MatchSide) -> VoiceAnnouncementMessage {
        winnerSide == .right
            ? numericScore(score.rightGames, score.leftGames)
            : numericScore(score.leftGames, score.rightGames)
    }

    private static func buildMatchScoreList(_ payload: VoiceAnnouncementPayload, _ winnerSide: MatchSide) -> VoiceAnnouncementMessage {
        resolveSetScoreList(payload)
            .map { score in
                if VoiceAnnouncementSupport.isBadminton(payload.gameType) {
                    return winnerSide == .right
                        ? badmintonScore(score.rightGames, score.leftGames)
                        : badmintonScore(score.leftGames, score.rightGames)
                }
                return formatGameScoreByWinner(score, winnerSide)
            }
            .voiceJoined(separator: ", ")
    }

    private static func tennisPointLabel(_ score: Int) -> VoiceAnnouncementMessage {
        switch score {
        case ...0: return "tennis.point.love"
        case 1: return "tennis.point.fifteen"
        case 2: return "tennis.point.thirty"
        default: return "tennis.point.forty"
        }
    }

    private static func resolveServerSide(_ payload: VoiceAnnouncementPayload) -> MatchSide {
        payload.serverSide ?? .left
    }

    private static func resolveWinnerSide(_ payload: VoiceAnnouncementPayload) -> MatchSide {
        if let winnerSide = payload.winnerSide { return winnerSide }
        return payload.rightScore > payload.leftScore ? .right : .left
    }

    private static func teamName(_ payload: VoiceAnnouncementPayload, _ side: MatchSide) -> String {
        side == .right ? payload.rightTeamName : payload.leftTeamName
    }

    private static func hasWinner(_ payload: VoiceAnnouncementPayload) -> Bool {
        payload.winnerSide != nil || !(payload.winnerName?.isEmpty ?? true)
    }

    private static func resolveServerName(_ payload: VoiceAnnouncementPayload) -> String {
        if let serverName = payload.serverName, !serverName.isEmpty {
            return serverName
        }
        return teamName(payload, resolveServerSide(payload))
    }

    private static func scoreOfSets(_ payload: VoiceAnnouncementPayload, _ side: MatchSide) -> Int {
        side == .right ? payload.rightSets : payload.leftSets
    }

    private static func scoreOf(_ payload: VoiceAnnouncementPayload, _ side: MatchSide) -> Int {
        side == .right ? payload.rightScore : payload.leftScore
    }

    private static func resolveSetScoreList(_ payload: VoiceAnnouncementPayload) -> [VoiceSetScore] {
        if !payload.setScores.isEmpty { return payload.setScores }
        return [VoiceSetScore(leftGames: payload.leftScore, rightGames: payload.rightScore)]
    }

    private static func softTennisAdvantage(_ payload: VoiceAnnouncementPayload) -> MatchSide? {
        let edge = payload.isTieBreak ? 7 : 4
        if payload.leftScore >= edge, payload.leftScore - payload.rightScore == 1 { return .left }
        if payload.rightScore >= edge, payload.rightScore - payload.leftScore == 1 { return .right }
        return nil
    }

    private static func capitalizeFirst(_ value: VoiceAnnouncementMessage) -> VoiceAnnouncementMessage {
        .capitalized(value)
    }
}
