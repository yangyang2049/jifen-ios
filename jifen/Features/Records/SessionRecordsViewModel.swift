import Foundation
import Observation
import PersistenceCore
import RecordCore
import ScoreCore
import SessionCore

@MainActor
@Observable
final class SessionRecordsViewModel {
    struct Record: Identifiable {
        let entry: SessionArchiveEntry
        let scoreText: String?

        var id: UUID { entry.sessionId }
        var gameName: String { entry.gameType.v2DisplayName }
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
            guard let session = try? JSONDecoder().decode(ScoreSession<BasketballMatchState, BasketballMatchEvent>.self, from: data) else { return nil }
            return "\(session.state.leftScore) : \(session.state.rightScore)"
        case .pingpong, .pingpongDoubles, .badminton, .badmintonDoubles, .pickleball, .pickleballDoubles,
             .volleyball, .airVolleyball, .beachVolleyball, .foosball, .foosballDoubles:
            guard let session = try? JSONDecoder().decode(ScoreSession<RallyMatchState, RallyMatchEvent>.self, from: data) else { return nil }
            return "\(session.state.leftPoints) : \(session.state.rightPoints)"
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

        if let session = try? JSONDecoder().decode(ScoreSession<RallyMatchState, RallyMatchEvent>.self, from: data) {
            var actions: [DetailedScoreAction] = []
            var sets = [0, 0]
            for event in session.events {
                switch event {
                case .pointScored(let side, let left, let right):
                    actions.append(.init(type: .scoreChanged, team: side == .left ? .team1 : .team2, scores: [left, right], setScores: sets, setNumber: sets[0] + sets[1] + 1, scoreChange: 1, operationCode: "point"))
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
            saveMigratedRecord(id: id, gameType: gameType, started: startDate(session.metadata), names: (session.state.leftName, session.state.rightName), scores: (session.state.leftPoints, session.state.rightPoints), sets: (session.state.leftSets, session.state.rightSets), finished: session.state.finished, actions: actions, snapshot: data)
        } else if let session = try? JSONDecoder().decode(ScoreSession<BasketballMatchState, BasketballMatchEvent>.self, from: data) {
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
            saveMigratedRecord(id: id, gameType: gameType, started: startDate(session.metadata), names: (session.state.leftName, session.state.rightName), scores: (session.state.leftScore, session.state.rightScore), sets: nil, finished: session.state.finished, actions: actions, snapshot: data)
        }
    }

    private static func saveMigratedRecord(id: String, gameType: GameType, started: Date, names: (String, String), scores: (Int, Int), sets: (Int, Int)?, finished: Bool, actions: [DetailedScoreAction], snapshot: Data) {
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
            stateSnapshot: snapshot,
            status: finished ? .finished : .draft
        )
        try? ScoreboardRecordManager.shared.saveScoreboardRecord(record)
    }

    private static func startDate(_ metadata: SessionMetadata) -> Date {
        metadata.extras["startedAtEpochMilliseconds"].flatMap(Int64.init)
            .map { Date(timeIntervalSince1970: Double($0) / 1_000) } ?? Date()
    }
}

private extension ScoreCore.GameType {
    var v2DisplayName: String {
        switch self {
        case .basketball: return "篮球"
        case .threeBasketball: return "篮球 3x3"
        case .pingpong, .pingpongDoubles: return "乒乓球"
        case .badminton, .badmintonDoubles: return "羽毛球"
        case .pickleball, .pickleballDoubles: return "匹克球"
        case .volleyball: return "排球"
        case .airVolleyball: return "气排球"
        case .beachVolleyball: return "沙滩排球"
        case .tennis, .tennisDoubles: return "网球"
        default: return rawValue
        }
    }
}

typealias V2SessionRecordsViewModel = SessionRecordsViewModel
