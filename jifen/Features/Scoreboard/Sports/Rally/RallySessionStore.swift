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
    private let snapshotStore: AtomicJSONFileStore<ScoreSession<RallyMatchState, RallyMatchEvent>>
    private let archiveIndex: SessionArchiveIndex

    private(set) var state: RallyMatchState

    init(
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
        let sessionParticipants = providedParticipants ?? [
            .init(id: "left", name: initial.leftName, role: "team"),
            .init(id: "right", name: initial.rightName, role: "team")
        ]
        let session = ScoreSession<RallyMatchState, RallyMatchEvent>(
            gameType: gameType,
            ruleFamily: .s1,
            reducerType: "rally/v1",
            state: initial,
            participants: sessionParticipants
        )
        core = ScoreSessionCore(seedSession: session, reducer: RallyMatchReducer(), shouldFinish: { _, state in state.finished })
        snapshotStore = AtomicJSONFileStore(fileURL: Self.snapshotURL(for: session.sessionId))
        archiveIndex = SessionArchiveIndex(fileURL: Self.archiveIndexURL())
        state = initial
    }

    func send(_ intent: RallyMatchIntent) {
        Task { [weak self, core] in
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            guard case .accepted(let session, _) = await core.dispatch(actorId: "phone", intent: intent, at: now), let self else { return }
            self.state = session.state
        }
    }

    func undo() {
        Task { [weak self, core] in
            guard await core.undo(actorId: "phone"), let self else { return }
            self.state = await core.snapshot().state
        }
    }

    func persistSnapshot() {
        Task { [core, snapshotStore, archiveIndex] in
            let session = await core.snapshot()
            try? await snapshotStore.save(session)
            try? await archiveIndex.upsert(.init(
                sessionId: session.sessionId,
                gameType: session.gameType,
                source: .phoneLocal,
                snapshotPath: "sessions/\(session.sessionId.uuidString).json",
                participants: session.participants,
                status: session.status,
                updatedAtEpochMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
            ))
        }
    }

    private static func snapshotURL(for sessionId: UUID) -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jifen-v2/sessions", isDirectory: true)
        return directory.appendingPathComponent("\(sessionId.uuidString).json")
    }

    private static func archiveIndexURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jifen-v2/session-index.json")
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
        default:
            return nil
        }
    }
}
