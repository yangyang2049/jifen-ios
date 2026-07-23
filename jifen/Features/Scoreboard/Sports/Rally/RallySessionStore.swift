import Foundation
import Observation
import PersistenceCore
import RecordCore
import ScoreCore
import SessionCore

@MainActor
@Observable
final class RallySessionStore {
    private let core: ScoreSessionCore<RallyMatchReducer>
    private let archiveRepository: SessionArchiveRepository
    private var detailedActions: [DetailedScoreAction]

    private(set) var state: RallyMatchState
    let gameType: ScoreCore.GameType
    let sessionId: UUID
    let startedAt: Date

    /// HOS-aligned screen placement derived from engine `sidesSwapped`.
    var teamScreenLayout: TeamScreenLayout {
        TeamScreenLayout(sidesSwapped: state.sidesSwapped)
    }

    /// Geometric MatchSide for a team identity under current layout.
    func geometricSide(for team: TeamID) -> MatchSide {
        teamScreenLayout.geometricSide(for: team, sidesSwappedInEngine: state.sidesSwapped)
    }

    convenience init(
        leftName: String,
        rightName: String,
        gameType: ScoreCore.GameType,
        rules: RallyRuleSet,
        participants: [SessionParticipant]? = nil,
        openingServer: MatchSide = .left
    ) {
        let providedParticipants = participants?.filter { !$0.name.isEmpty }
        let initial = RallyMatchEngine.initial(
            leftName: leftName,
            rightName: rightName,
            rules: rules,
            openingServer: openingServer,
            doubles: Self.doublesState(
                for: gameType,
                participants: providedParticipants,
                openingServer: openingServer
            )
        )
        self.init(gameType: gameType, state: initial, participants: providedParticipants)
    }

    convenience init(
        gameType: ScoreCore.GameType,
        state: RallyMatchState,
        participants: [SessionParticipant]? = nil
    ) {
        let sessionParticipants = participants ?? [
            .init(id: "left", name: state.leftName, role: "team"),
            .init(id: "right", name: state.rightName, role: "team")
        ]
        let session = ScoreSession<RallyMatchState, RallyMatchEvent>(
            gameType: gameType,
            ruleFamily: .s1,
            reducerType: ScoreboardKernelRegistry.descriptor(for: gameType).reducerType,
            state: state,
            participants: sessionParticipants,
            metadata: .init(extras: ["startedAtEpochMilliseconds": String(Int64(Date().timeIntervalSince1970 * 1_000))])
        )
        self.init(session: session)
    }

    private init(session: ScoreSession<RallyMatchState, RallyMatchEvent>) {
        gameType = session.gameType
        sessionId = session.sessionId
        let startedMilliseconds = session.metadata.extras["startedAtEpochMilliseconds"].flatMap(Int64.init)
        startedAt = startedMilliseconds.map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) } ?? Date()
        core = ScoreSessionCore(seedSession: session, reducer: RallyMatchReducer(), shouldFinish: { _, state in state.finished })
        archiveRepository = SessionArchiveRepository()
        state = session.state
        detailedActions = ScoreboardRecordManager.shared.getRecordById(session.sessionId.uuidString)?.detailedActions ?? []
    }

    convenience init?(restoring sessionId: UUID) {
        let url = SessionArchiveRepository.snapshotURL(sessionId: sessionId)
        guard let data = try? Data(contentsOf: url),
              let session = try? JSONDecoder().decode(ScoreSession<RallyMatchState, RallyMatchEvent>.self, from: data),
              session.status == .live else {
            return nil
        }
        self.init(session: session)
    }

    func send(_ intent: RallyMatchIntent, onEvents: (([RallyMatchEvent]) -> Void)? = nil) {
        Task { [weak self, core] in
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            guard case .accepted(let session, let events) = await core.dispatch(actorId: "phone", intent: intent, at: now),
                  let self else { return }
            self.state = session.state
            onEvents?(events)
            try? await self.archiveRepository.save(session)
            self.append(events: events, at: now, state: session.state)
            self.persistRecord(session)
        }
    }

    func undo(completion: ((Bool) -> Void)? = nil) {
        Task { [weak self, core] in
            guard await core.undo(actorId: "phone"), let self else {
                completion?(false)
                return
            }
            let session = await core.snapshot()
            self.state = session.state
            completion?(true)
            try? await self.archiveRepository.save(session)
            self.detailedActions.append(.init(type: .undo, epochMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000), scores: [session.state.leftPoints, session.state.rightPoints], setScores: [session.state.leftSets, session.state.rightSets], setNumber: session.state.currentSet, operationCode: "undo"))
            self.persistRecord(session)
        }
    }

    func persistSnapshot(completion: ((Bool) -> Void)? = nil) {
        Task { [core, archiveRepository] in
            let session = await core.snapshot()
            do {
                try await archiveRepository.save(session)
                self.persistRecord(session)
                completion?(true)
            } catch {
                completion?(false)
            }
        }
    }

    func replaceDisplayedState(_ state: RallyMatchState) {
        self.state = state
    }

    private func append(events: [RallyMatchEvent], at milliseconds: Int64, state: RallyMatchState) {
        for event in events {
            switch event {
            case .pointScored(let side, let left, let right):
                detailedActions.append(.init(type: .scoreChanged, epochMilliseconds: milliseconds, team: side == .left ? .team1 : .team2, scores: [left, right], setScores: [state.leftSets, state.rightSets], setNumber: state.currentSet, scoreChange: 1, operationCode: "point"))
            case .sideOut(_, let left, let right):
                detailedActions.append(.init(type: .stateChanged, epochMilliseconds: milliseconds, scores: [left, right], setScores: [state.leftSets, state.rightSets], setNumber: state.currentSet, operationCode: "side_out"))
            case .setCompleted(let winner, let number, let left, let right, let leftSets, let rightSets):
                detailedActions.append(.init(type: .setFinished, epochMilliseconds: milliseconds, team: winner == .left ? .team1 : .team2, scores: [left, right], setScores: [leftSets, rightSets], setNumber: number, winner: winner == .left ? .team1 : .team2, operationCode: "set_completed"))
            case .sidesExchanged:
                detailedActions.append(.init(type: .sideChanged, epochMilliseconds: milliseconds, scores: [state.leftPoints, state.rightPoints], setScores: [state.leftSets, state.rightSets], setNumber: state.currentSet, operationCode: "exchange_sides"))
            case .sidesExchangeReminder:
                detailedActions.append(.init(type: .stateChanged, epochMilliseconds: milliseconds, scores: [state.leftPoints, state.rightPoints], setNumber: state.currentSet, operationCode: "side_change_reminder"))
            case .matchReset:
                detailedActions.append(.init(type: .reset, epochMilliseconds: milliseconds, scores: [0, 0], setScores: [0, 0], operationCode: "reset"))
            case .matchFinished(let winner):
                detailedActions.append(.init(type: .matchFinished, epochMilliseconds: milliseconds, scores: [state.leftPoints, state.rightPoints], setScores: [state.leftSets, state.rightSets], winner: winner == .left ? .team1 : (winner == .right ? .team2 : nil), operationCode: "finish"))
            }
        }
    }

    private func persistRecord(_ session: ScoreSession<RallyMatchState, RallyMatchEvent>) {
        guard let appGameType = GameType(scoreCoreGameType: gameType) else { return }
        let snapshot = try? JSONEncoder().encode(session)
        let winner: String? = state.finished && state.leftSets != state.rightSets ? (state.leftSets > state.rightSets ? "left" : "right") : nil
        let record = ScoreboardRecord(
            id: sessionId.uuidString,
            gameType: appGameType,
            startTime: startedAt,
            endTime: state.finished ? Date() : nil,
            duration: Date().timeIntervalSince(startedAt),
            team1Name: state.leftName,
            team2Name: state.rightName,
            team1FinalScore: state.leftPoints,
            team2FinalScore: state.rightPoints,
            team1SetScore: state.leftSets,
            team2SetScore: state.rightSets,
            winner: winner,
            detailedActions: detailedActions,
            setResults: ScoreboardRecordActionAdapter.setResults(from: detailedActions),
            totalScoreChanges: detailedActions.count,
            projectConfiguration: [
                "maxSets": AnyCodable(state.rules.maxSets),
                "pointsPerSet": AnyCodable(state.rules.pointsToWinSet),
                "autoChangeSides": AnyCodable(state.rules.autoChangeSides)
            ],
            stateSnapshot: snapshot,
            status: state.finished ? .finished : .draft
        )
        try? ScoreboardRecordManager.shared.saveScoreboardRecord(record)
        ScoreboardRecordsViewModel.shared.refreshRecords()
    }

    private static func doublesState(
        for gameType: ScoreCore.GameType,
        participants: [SessionParticipant]?,
        openingServer: MatchSide
    ) -> RallyDoublesState? {
        let namesByID = (participants ?? []).reduce(into: [String: String]()) { names, participant in
            names[participant.id] = participant.name
        }
        let names = [
            namesByID["left-top"] ?? "红A",
            namesByID["right-top"] ?? "蓝A",
            namesByID["left-bottom"] ?? "红B",
            namesByID["right-bottom"] ?? "蓝B"
        ]
        switch gameType {
        case .pingpongDoubles:
            return .pingPong(
                playerNames: names,
                openingServerSlotIndex: openingServer == .left ? 0 : 1,
                openingReceiverSlotIndex: openingServer == .left ? 1 : 0
            )
        case .badmintonDoubles:
            return .badminton(playerNames: names, servingTeam0: openingServer == .left)
        case .pickleballDoubles:
            return .pickleball(playerNames: names, servingTeam0: openingServer == .left)
        case .foosballDoubles:
            return .foosball(playerNames: names)
        default:
            return nil
        }
    }
}
