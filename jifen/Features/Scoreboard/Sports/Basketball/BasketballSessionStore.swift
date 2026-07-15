import Foundation
import Observation
import PersistenceCore
import RecordCore
import ScoreCore
import SessionCore

@MainActor
@Observable
final class BasketballSessionStore {
    private let core: ScoreSessionCore<BasketballMatchReducer>
    private let snapshotStore: AtomicJSONFileStore<ScoreSession<BasketballMatchState, BasketballMatchEvent>>
    private let archiveIndex: SessionArchiveIndex
    private var clockTask: Task<Void, Never>?

    private(set) var state: BasketballMatchState

    init(leftName: String, rightName: String, gameMode: BasketballGameMode = .fiveVFive) {
        let initial = BasketballMatchEngine.initial(
            leftName: leftName,
            rightName: rightName,
            gameMode: gameMode
        )
        let session = ScoreSession<BasketballMatchState, BasketballMatchEvent>(
            gameType: gameMode == .threeXThree ? .threeBasketball : .basketball,
            ruleFamily: .s2,
            reducerType: "basketball/v1",
            state: initial,
            participants: [
                .init(id: "left", name: initial.leftName, role: "team"),
                .init(id: "right", name: initial.rightName, role: "team")
            ]
        )
        self.core = ScoreSessionCore(
            seedSession: session,
            reducer: BasketballMatchReducer(),
            shouldFinish: { _, state in state.finished }
        )
        self.snapshotStore = AtomicJSONFileStore(fileURL: Self.snapshotURL(for: session.sessionId))
        self.archiveIndex = SessionArchiveIndex(fileURL: Self.archiveIndexURL())
        self.state = initial
    }

    func send(_ intent: BasketballMatchIntent, recordsUndo: Bool = true) {
        Task { [weak self, core] in
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            let result = if recordsUndo {
                await core.dispatch(actorId: "phone", intent: intent, at: now)
            } else {
                await core.dispatchNonUndoable(actorId: "phone", intent: intent, at: now)
            }
            guard case .accepted(let session, _) = result, let self else { return }
            self.state = session.state
        }
    }

    func undo() {
        Task { [weak self, core] in
            guard await core.undo(actorId: "phone"), let self else { return }
            self.state = await core.snapshot().state
        }
    }

    func startClock() {
        guard clockTask == nil else { return }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.send(.tickClock, recordsUndo: false)
            }
        }
    }

    func stopClock() {
        clockTask?.cancel()
        clockTask = nil
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
}
