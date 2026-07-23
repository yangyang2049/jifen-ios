import Foundation
import Observation
import PersistenceCore
import ScoreCore
import SessionCore

/// Thin session host for archery — mirrors Basketball/Rally SessionStore pattern.
@MainActor
@Observable
final class ArcherySessionStore {
    private let core: ScoreSessionCore<ArcheryMatchReducer>
    private let archiveRepository = SessionArchiveRepository()

    private(set) var state: ArcheryMatchState
    let sessionId: UUID

    convenience init(leftName: String, rightName: String, openingShooterIsLeft: Bool = true) {
        let descriptor = ScoreboardKernelRegistry.descriptor(for: .archeryDual)
        let initial = ArcheryMatchState(
            leftName: leftName,
            rightName: rightName,
            currentShooterIsLeft: openingShooterIsLeft,
            openingShooterIsLeft: openingShooterIsLeft
        )
        let session = ScoreSession<ArcheryMatchState, ArcheryMatchEvent>(
            gameType: .archeryDual,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: initial,
            participants: [
                .init(id: "left", name: initial.leftName, role: "team"),
                .init(id: "right", name: initial.rightName, role: "team")
            ]
        )
        self.init(session: session)
    }

    private init(session: ScoreSession<ArcheryMatchState, ArcheryMatchEvent>) {
        sessionId = session.sessionId
        state = session.state
        core = ScoreSessionCore(
            seedSession: session,
            reducer: ArcheryMatchReducer(),
            shouldFinish: { _, state in state.finished }
        )
    }

    func send(_ intent: ArcheryMatchIntent) {
        Task { [weak self] in
            guard let self else { return }
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            let result = await core.dispatch(actorId: "phone", intent: intent, at: now)
            guard case .accepted(let session, _) = result else { return }
            self.state = session.state
            try? await archiveRepository.save(session)
        }
    }

    func undo() {
        Task { [weak self] in
            guard let self, await core.undo(actorId: "phone") else { return }
            let session = await core.snapshot()
            self.state = session.state
            try? await archiveRepository.save(session)
        }
    }
}
