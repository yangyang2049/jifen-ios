import Foundation
import Observation
import OSLog
import PersistenceCore
import RecordCore
import ScoreCore
import SessionCore

@MainActor
@Observable
final class SessionRecordsViewModel {
    private static let logger = Logger(
        subsystem: "com.douhua.jifen.ios",
        category: "ArchiveMigration"
    )
    struct Record: Identifiable {
        let entry: SessionArchiveEntry
        let scoreText: String?

        var id: UUID { entry.sessionId }
        var gameName: String { entry.gameType.v2DisplayName }
        var gameEmoji: String {
            GameType(scoreCoreGameType: entry.gameType)?.icon ?? "🏆"
        }
        var teamsText: String {
            let names = entry.participants.map(\.name).filter { !$0.isEmpty }
            return names.count >= 2 ? "\(names[0]) vs \(names[1])" : names.joined(separator: " vs ")
        }
        var timestamp: TimeInterval { TimeInterval(entry.updatedAtEpochMilliseconds) / 1_000 }
        var dateString: String {
            Self.dateFormatter.string(from: Date(timeIntervalSince1970: timestamp))
        }
        var timeText: String {
            Self.timeFormatter.string(from: Date(timeIntervalSince1970: timestamp))
        }

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()

        private static let timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter
        }()
    }

    private(set) var records: [Record] = []
    private(set) var isLoading = false

    private let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

    func reload() {
        guard !isLoading else { return }
        isLoading = true
        let repository = SessionArchiveRepository()
        Task {
            let entries = (try? await repository.entries()) ?? []
            for entry in entries { Self.migrateArchiveToV4(entry, applicationSupport: applicationSupport) }
            let loaded = entries.map { entry in
                Record(entry: entry, scoreText: Self.scoreText(for: entry, applicationSupport: applicationSupport))
            }
            records = loaded
            ScoreboardRecordsViewModel.shared.refreshRecordsImmediately()
            isLoading = false
        }
    }

    func delete(_ record: Record) {
        let repository = SessionArchiveRepository()
        Task {
            try? await repository.remove(sessionId: record.entry.sessionId)
            records.removeAll { $0.id == record.id }
        }
    }

    func clearAll() {
        records = []
        let repository = SessionArchiveRepository()
        Task {
            try? await repository.clear()
        }
    }

    private static func scoreText(for entry: SessionArchiveEntry, applicationSupport: URL) -> String? {
        let url = applicationSupport.appendingPathComponent("jifen-v2").appendingPathComponent(entry.snapshotPath)
        guard let data = try? Data(contentsOf: url) else { return nil }

        switch entry.gameType {
        case .basketball, .threeBasketball:
            let session = (try? JSONDecoder().decode(
                ScoreSessionResumeBundle<BasketballMatchState, BasketballMatchEvent, BasketballMatchIntent>.self,
                from: data
            ))?.currentSession ?? (try? JSONDecoder().decode(
                ScoreSession<BasketballMatchState, BasketballMatchEvent>.self,
                from: data
            ))
            guard let session else { return nil }
            return "\(session.state.leftScore) : \(session.state.rightScore)"
        case .pingpong, .pingpongDoubles, .badminton, .badmintonDoubles, .pickleball, .pickleballDoubles,
             .volleyball, .airVolleyball, .beachVolleyball, .foosball, .foosballDoubles:
            let session = (try? JSONDecoder().decode(
                ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>.self,
                from: data
            ))?.currentSession ?? (try? JSONDecoder().decode(
                ScoreSession<RallyMatchState, RallyMatchEvent>.self,
                from: data
            ))
            guard let session else { return nil }
            return "\(session.state.leftPoints) : \(session.state.rightPoints)"
        case .tennis, .tennisDoubles:
            let session = (try? JSONDecoder().decode(
                ScoreSessionResumeBundle<TennisMatchState, TennisMatchEvent, TennisMatchIntent>.self,
                from: data
            ))?.currentSession ?? (try? JSONDecoder().decode(
                ScoreSession<TennisMatchState, TennisMatchEvent>.self,
                from: data
            ))
            guard let session else { return nil }
            return "\(session.state.leftSets) : \(session.state.rightSets)"
        case .eightBall:
            let session = (try? JSONDecoder().decode(
                ScoreSessionResumeBundle<EightBallState, EightBallEvent, EightBallIntent>.self,
                from: data
            ))?.currentSession ?? (try? JSONDecoder().decode(
                ScoreSession<EightBallState, EightBallEvent>.self,
                from: data
            ))
            guard let session else { return nil }
            return "\(session.state.leftPoints) : \(session.state.rightPoints)"
        case .nineBall:
            let session = (try? JSONDecoder().decode(
                ScoreSessionResumeBundle<NineBallChaseState, NineBallChaseEvent, NineBallChaseIntent>.self,
                from: data
            ))?.currentSession ?? (try? JSONDecoder().decode(
                ScoreSession<NineBallChaseState, NineBallChaseEvent>.self,
                from: data
            ))
            guard let session else { return nil }
            return session.state.playerPoints
                .prefix(session.state.playerCount)
                .map(String.init)
                .joined(separator: " : ")
        case .snooker:
            let session = (try? JSONDecoder().decode(
                ScoreSessionResumeBundle<SnookerState, SnookerEvent, SnookerIntent>.self,
                from: data
            ))?.currentSession ?? (try? JSONDecoder().decode(
                ScoreSession<SnookerState, SnookerEvent>.self,
                from: data
            ))
            guard let session else { return nil }
            let state = session.state
            return state.maxFrames > 1
                ? "\(state.leftFrames) : \(state.rightFrames)"
                : "\(state.leftScore) : \(state.rightScore)"
        default:
            return nil
        }
    }

    private static func migrateArchiveToV4(_ entry: SessionArchiveEntry, applicationSupport: URL) {
        let id = entry.sessionId.uuidString
        guard ScoreboardRecordManager.shared.getRecordById(id) == nil,
              let gameType = GameType(scoreCoreGameType: entry.gameType) else { return }
        let url = applicationSupport.appendingPathComponent("jifen-v2").appendingPathComponent(entry.snapshotPath)
        guard let data = try? Data(contentsOf: url) else { return }
        let sessionData = normalizedSessionData(for: entry.gameType, archiveData: data) ?? data

        if let session = try? JSONDecoder().decode(ScoreSession<RallyMatchState, RallyMatchEvent>.self, from: sessionData) {
            var actions: [DetailedScoreAction] = []
            var sets = [0, 0]
            for event in session.events {
                switch event {
                case .pointScored(let side, let left, let right):
                    actions.append(.init(type: .scoreChanged, team: side == .left ? .team1 : .team2, scores: [left, right], setScores: sets, setNumber: sets[0] + sets[1] + 1, scoreChange: 1, operationCode: "point"))
                case .pointsAdjusted(let side, let delta, let left, let right):
                    actions.append(.init(type: .scoreChanged, team: side == .left ? .team1 : .team2, scores: [left, right], setScores: sets, setNumber: sets[0] + sets[1] + 1, scoreChange: delta, operationCode: "adjust"))
                case .sideOut(_, let left, let right):
                    actions.append(.init(type: .stateChanged, scores: [left, right], setScores: sets, setNumber: sets[0] + sets[1] + 1, operationCode: "side_out"))
                case .setCompleted(let winner, let number, let left, let right, let leftSets, let rightSets):
                    sets = [leftSets, rightSets]
                    actions.append(.init(type: .setFinished, team: winner == .left ? .team1 : .team2, scores: [left, right], setScores: sets, setNumber: number, winner: winner == .left ? .team1 : .team2, operationCode: "set_completed"))
                case .sidesExchangeReminder:
                    actions.append(.init(type: .stateChanged, scores: [session.state.leftPoints, session.state.rightPoints], operationCode: "side_change_reminder"))
                case .sidesExchanged:
                    actions.append(.init(type: .sideChanged, scores: [session.state.leftPoints, session.state.rightPoints], operationCode: "exchange_sides"))
                case .matchFinished(let winner):
                    actions.append(.init(type: .matchFinished, scores: [session.state.leftPoints, session.state.rightPoints], setScores: [session.state.leftSets, session.state.rightSets], winner: winner == .left ? .team1 : (winner == .right ? .team2 : nil), operationCode: "finish"))
                case .matchReset:
                    actions.append(.init(type: .reset, scores: [0, 0], setScores: [0, 0], operationCode: "reset"))
                }
            }
            saveMigratedRecord(
                id: id,
                gameType: gameType,
                started: startDate(session.metadata),
                names: (session.state.leftName, session.state.rightName),
                scores: (session.state.leftPoints, session.state.rightPoints),
                sets: (session.state.leftSets, session.state.rightSets),
                finished: session.state.finished,
                actions: actions,
                snapshot: data,
                projectConfiguration: ScoreboardRecordConfiguration.rally(
                    gameType: session.gameType,
                    state: session.state,
                    voiceAnnouncement: false
                )
            )
        } else if let session = try? JSONDecoder().decode(ScoreSession<BasketballMatchState, BasketballMatchEvent>.self, from: sessionData) {
            let actions = session.events.compactMap { event -> DetailedScoreAction? in
                guard case .stateChanged(let at, let intent, let before, let after) = event, intent != .tickClock else { return nil }
                if before.leftScore != after.leftScore || before.rightScore != after.rightScore {
                    let isLeft = before.leftScore != after.leftScore
                    let delta = isLeft ? after.leftScore - before.leftScore : after.rightScore - before.rightScore
                    return .init(type: .scoreChanged, epochMilliseconds: at, team: isLeft ? .team1 : .team2, scores: [after.leftScore, after.rightScore], periodNumber: after.currentPeriod, scoreChange: delta, operationCode: "basketball_score")
                }
                switch intent {
                case .addFoul(let side), .removeFoul(let side): return .init(type: .foul, epochMilliseconds: at, team: side == .left ? .team1 : .team2, scores: [after.leftScore, after.rightScore], periodNumber: after.currentPeriod, operationCode: String(describing: intent))
                case .useTimeout(let side): return .init(type: .timeout, epochMilliseconds: at, team: side == .left ? .team1 : .team2, scores: [after.leftScore, after.rightScore], periodNumber: after.currentPeriod, operationCode: "timeout")
                case .advanceToNextPeriod, .enterOvertime: return .init(type: .periodFinished, epochMilliseconds: at, scores: [after.leftScore, after.rightScore], periodNumber: before.currentPeriod, operationCode: "period_finished")
                case .reset: return .init(type: .reset, epochMilliseconds: at, scores: [0, 0], operationCode: "reset")
                case .finish: return .init(type: .matchFinished, epochMilliseconds: at, scores: [after.leftScore, after.rightScore], periodNumber: after.currentPeriod, operationCode: "finish")
                default: return .init(type: .stateChanged, epochMilliseconds: at, scores: [after.leftScore, after.rightScore], periodNumber: after.currentPeriod, operationCode: String(describing: intent))
                }
            }
            saveMigratedRecord(
                id: id,
                gameType: gameType,
                started: startDate(session.metadata),
                names: (session.state.leftName, session.state.rightName),
                scores: (session.state.leftScore, session.state.rightScore),
                sets: nil,
                finished: session.state.finished,
                actions: actions,
                snapshot: data,
                projectConfiguration: [ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(session.gameType.rawValue)]
            )
        } else if let session = try? JSONDecoder().decode(ScoreSession<TennisMatchState, TennisMatchEvent>.self, from: sessionData) {
            let state = session.state
            let pointOnly = state.rules.setScoringMode == .tiebreakOnly
            saveMigratedRecord(
                id: id,
                gameType: gameType,
                started: startDate(session.metadata),
                names: (state.leftName, state.rightName),
                scores: (pointOnly ? state.leftPoints : state.leftGames, pointOnly ? state.rightPoints : state.rightGames),
                sets: (state.leftSets, state.rightSets),
                finished: state.finished,
                actions: [],
                snapshot: data,
                projectConfiguration: ScoreboardRecordConfiguration.tennis(
                    gameType: session.gameType,
                    state: state,
                    voiceAnnouncement: false
                )
            )
        } else if let session = try? JSONDecoder().decode(ScoreSession<EightBallState, EightBallEvent>.self, from: sessionData) {
            let state = session.state
            let names = migratedNames(session.participants)
            var configuration: [String: AnyCodable] = [
                ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(session.gameType.rawValue),
                "maxSets": AnyCodable(state.targetPoints),
                "eightBallHandicapRacks": AnyCodable(state.handicapRacks),
                "eightBallHandicapBeneficiary": AnyCodable(state.handicapBeneficiary == .left ? "team1" : (state.handicapBeneficiary == .right ? "team2" : "none"))
            ]
            configuration["targetScore"] = AnyCodable(state.targetPoints)
            saveMigratedRecord(id: id, gameType: gameType, started: startDate(session.metadata), names: names, scores: (state.leftPoints, state.rightPoints), sets: nil, finished: state.finished, actions: [], snapshot: data, projectConfiguration: configuration)
        } else if let session = try? JSONDecoder().decode(ScoreSession<NineBallChaseState, NineBallChaseEvent>.self, from: sessionData) {
            let state = session.state
            let names = (0..<state.playerCount).map { state.resolvedName(at: $0) }
            let players = names.enumerated().map { index, name in
                AnyCodable(["name": AnyCodable(name), "finalScore": AnyCodable(state.playerPoints[index])])
            }
            let configuration: [String: AnyCodable] = [
                ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(session.gameType.rawValue),
                "playerCount": AnyCodable(state.playerCount),
                "nineBallBigGold": AnyCodable(state.config.bigGold),
                "nineBallSmallGold": AnyCodable(state.config.smallGold),
                "nineBallGoldenNine": AnyCodable(state.config.goldenNine),
                "nineBallNormalWin": AnyCodable(state.config.normalWin),
                "nineBallBallInHand": AnyCodable(state.config.ballInHand),
                "nineBallFoul": AnyCodable(state.config.foul)
            ]
            saveMigratedRecord(
                id: id,
                gameType: gameType,
                started: startDate(session.metadata),
                names: (names.first ?? "P1", names.dropFirst().first ?? "P2"),
                scores: (state.leftPoints, state.rightPoints),
                sets: nil,
                finished: state.finished,
                actions: [],
                snapshot: data,
                extraData: ["players": AnyCodable(players), "playerCount": AnyCodable(state.playerCount)],
                projectConfiguration: configuration
            )
        } else if let session = try? JSONDecoder().decode(ScoreSession<SnookerState, SnookerEvent>.self, from: sessionData) {
            let state = session.state
            let names = migratedNames(session.participants)
            saveMigratedRecord(
                id: id,
                gameType: gameType,
                started: startDate(session.metadata),
                names: names,
                scores: (state.maxFrames > 1 ? state.leftFrames : state.leftScore, state.maxFrames > 1 ? state.rightFrames : state.rightScore),
                sets: state.maxFrames > 1 ? (state.leftFrames, state.rightFrames) : nil,
                finished: state.finished,
                actions: [],
                snapshot: data,
                projectConfiguration: [
                    ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(session.gameType.rawValue),
                    "maxSets": AnyCodable(state.maxFrames),
                    "servingSide": AnyCodable(state.firstBreaker.rawValue)
                ]
            )
        }
    }

    private static func saveMigratedRecord(
        id: String,
        gameType: GameType,
        started: Date,
        names: (String, String),
        scores: (Int, Int),
        sets: (Int, Int)?,
        finished: Bool,
        actions: [DetailedScoreAction],
        snapshot: Data,
        extraData: [String: AnyCodable]? = nil,
        projectConfiguration: [String: AnyCodable]? = nil
    ) {
        let winner = finished && scores.0 != scores.1 ? (scores.0 > scores.1 ? "left" : "right") : nil
        let record = ScoreboardRecord(
            id: id,
            gameType: gameType,
            startTime: started,
            endTime: finished ? Date() : nil,
            duration: Date().timeIntervalSince(started),
            team1Name: names.0,
            team2Name: names.1,
            team1FinalScore: scores.0,
            team2FinalScore: scores.1,
            team1SetScore: sets?.0,
            team2SetScore: sets?.1,
            winner: winner,
            detailedActions: actions,
            setResults: ScoreboardRecordActionAdapter.setResults(from: actions),
            totalScoreChanges: actions.count,
            extraData: extraData,
            projectConfiguration: projectConfiguration,
            stateSnapshot: snapshot,
            status: finished ? .finished : .draft
        )
        do {
            try ScoreboardRecordManager.shared.saveScoreboardRecord(record)
        } catch {
            logger.error("Failed to migrate archive \(id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    static func normalizedSessionData(for gameType: ScoreCore.GameType, archiveData: Data) -> Data? {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        switch gameType {
        case .basketball, .threeBasketball:
            return (try? decoder.decode(ScoreSessionResumeBundle<BasketballMatchState, BasketballMatchEvent, BasketballMatchIntent>.self, from: archiveData))
                .flatMap { try? encoder.encode($0.currentSession) }
        case .pingpong, .pingpongDoubles, .badminton, .badmintonDoubles, .pickleball, .pickleballDoubles,
             .volleyball, .airVolleyball, .beachVolleyball, .foosball, .foosballDoubles:
            return (try? decoder.decode(ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>.self, from: archiveData))
                .flatMap { try? encoder.encode($0.currentSession) }
        case .tennis, .tennisDoubles:
            return (try? decoder.decode(ScoreSessionResumeBundle<TennisMatchState, TennisMatchEvent, TennisMatchIntent>.self, from: archiveData))
                .flatMap { try? encoder.encode($0.currentSession) }
        case .eightBall:
            return (try? decoder.decode(ScoreSessionResumeBundle<EightBallState, EightBallEvent, EightBallIntent>.self, from: archiveData))
                .flatMap { try? encoder.encode($0.currentSession) }
        case .nineBall:
            return (try? decoder.decode(ScoreSessionResumeBundle<NineBallChaseState, NineBallChaseEvent, NineBallChaseIntent>.self, from: archiveData))
                .flatMap { try? encoder.encode($0.currentSession) }
        case .snooker:
            return (try? decoder.decode(ScoreSessionResumeBundle<SnookerState, SnookerEvent, SnookerIntent>.self, from: archiveData))
                .flatMap { try? encoder.encode($0.currentSession) }
        default:
            return nil
        }
    }

    private static func migratedNames(_ participants: [SessionParticipant]) -> (String, String) {
        let names = participants.map(\.name).filter { !$0.isEmpty }
        return (
            names.first ?? NSLocalizedString("red_team", value: "Red Team", comment: ""),
            names.dropFirst().first ?? NSLocalizedString("blue_team", value: "Blue Team", comment: "")
        )
    }

    private static func startDate(_ metadata: SessionMetadata) -> Date {
        metadata.extras["startedAtEpochMilliseconds"].flatMap(Int64.init)
            .map { Date(timeIntervalSince1970: Double($0) / 1_000) } ?? Date()
    }
}

private extension ScoreCore.GameType {
    var v2DisplayName: String {
        switch self {
        case .basketball:
            return NSLocalizedString("game_basketball", value: "Basketball", comment: "")
        case .threeBasketball:
            return NSLocalizedString("game_three_basketball", value: "3x3 Basketball", comment: "")
        case .pingpong, .pingpongDoubles, .badminton, .badmintonDoubles,
             .pickleball, .pickleballDoubles, .tennis, .tennisDoubles,
             .foosball, .foosballDoubles:
            return scoreboardDisplayName
        case .volleyball:
            return NSLocalizedString("game_volleyball", value: "Volleyball", comment: "")
        case .airVolleyball:
            return NSLocalizedString("game_air_volleyball", value: "Air Volleyball", comment: "")
        case .beachVolleyball:
            return NSLocalizedString("game_beach_volleyball", value: "Beach Volleyball", comment: "")
        default: return rawValue
        }
    }
}
