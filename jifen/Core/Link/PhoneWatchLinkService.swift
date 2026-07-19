import Foundation
import LinkCore
import Observation
import ScoreCore

@MainActor
@Observable
final class PhoneWatchLinkService {
    private struct ActiveSession {
        let sessionId: UUID
        let gameType: ScoreCore.GameType
        var revision: UInt64
    }

    private let transport = WatchConnectivityTransport()
    private var sequence: UInt64 = 0
    private var activeSession: ActiveSession?
    private(set) var connectivityStatus: WatchConnectivityStatus

    enum InteractiveStartError: LocalizedError {
        case watchUnavailable

        var errorDescription: String? {
            NSLocalizedString(
                "linked_score_watch_unavailable",
                value: "Apple Watch 未连接，请打开手表端全能计分器后重试。",
                comment: "Watch unavailable when starting linked scoreboard"
            )
        }
    }

    init() {
        connectivityStatus = transport.status
        transport.onStatusChange = { [weak self] status in
            DispatchQueue.main.async {
                self?.connectivityStatus = status
            }
        }
        transport.activate()
    }

    var canStartInteractiveSession: Bool {
        connectivityStatus.canStartInteractiveSession
    }

    func startOnWatch(state: BasketballMatchState) -> UUID {
        startSessionInBackground(
            gameType: state.gameMode == .threeXThree ? .threeBasketball : .basketball,
            basketballThreeXThree: state.gameMode == .threeXThree,
            initialSnapshot: .basketball(state)
        )
    }

    func startOnWatch(gameType: ScoreCore.GameType, state: RallyMatchState) -> UUID {
        startSessionInBackground(
            gameType: gameType,
            maxSets: state.rules.maxSets,
            initialSnapshot: .rally(state)
        )
    }

    func startInteractiveOnWatch(state: BasketballMatchState) async throws -> UUID {
        try await startInteractiveSession(
            gameType: state.gameMode == .threeXThree ? .threeBasketball : .basketball,
            basketballThreeXThree: state.gameMode == .threeXThree,
            initialSnapshot: .basketball(state)
        )
    }

    func startInteractiveOnWatch(gameType: ScoreCore.GameType, state: RallyMatchState) async throws -> UUID {
        try await startInteractiveSession(
            gameType: gameType,
            maxSets: state.rules.maxSets,
            initialSnapshot: .rally(state)
        )
    }

    func syncWatch(sessionId: UUID, state: BasketballMatchState) {
        let gameType: ScoreCore.GameType = state.gameMode == .threeXThree ? .threeBasketball : .basketball
        sendSnapshot(sessionId: sessionId, gameType: gameType, snapshot: .basketball(state))
    }

    func syncWatch(sessionId: UUID, gameType: ScoreCore.GameType, state: RallyMatchState) {
        sendSnapshot(sessionId: sessionId, gameType: gameType, snapshot: .rally(state))
    }

    func endWatchSession(_ sessionId: UUID) {
        guard activeSession?.sessionId == sessionId else { return }
        activeSession = nil
    }

    private func startSessionInBackground(
        gameType: ScoreCore.GameType,
        maxSets: Int? = nil,
        basketballThreeXThree: Bool = false,
        initialSnapshot: LinkedScoreboardSnapshot
    ) -> UUID {
        let request = makeSessionRequest(
            gameType: gameType,
            maxSets: maxSets,
            basketballThreeXThree: basketballThreeXThree,
            initialSnapshot: initialSnapshot
        )
        Task {
            try? await transport.send(request.data)
        }
        return request.sessionId
    }

    private func startInteractiveSession(
        gameType: ScoreCore.GameType,
        maxSets: Int? = nil,
        basketballThreeXThree: Bool = false,
        initialSnapshot: LinkedScoreboardSnapshot
    ) async throws -> UUID {
        guard canStartInteractiveSession else {
            throw InteractiveStartError.watchUnavailable
        }
        let request = makeSessionRequest(
            gameType: gameType,
            maxSets: maxSets,
            basketballThreeXThree: basketballThreeXThree,
            initialSnapshot: initialSnapshot
        )
        do {
            try await transport.send(request.data)
            return request.sessionId
        } catch {
            if activeSession?.sessionId == request.sessionId {
                activeSession = nil
            }
            throw error
        }
    }

    private func makeSessionRequest(
        gameType: ScoreCore.GameType,
        maxSets: Int?,
        basketballThreeXThree: Bool,
        initialSnapshot: LinkedScoreboardSnapshot
    ) -> (sessionId: UUID, data: Data) {
        let sessionId = UUID()
        activeSession = ActiveSession(sessionId: sessionId, gameType: gameType, revision: 0)
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: sessionId,
            kind: .setupRequest,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: 0,
            sentAtEpochMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
            payload: LinkedScoreboardSetup(
                gameType: gameType,
                maxSets: maxSets,
                basketballThreeXThree: basketballThreeXThree,
                initialSnapshot: initialSnapshot
            )
        )
        let data = (try? JSONEncoder().encode(envelope)) ?? Data()
        return (sessionId, data)
    }

    private func sendSnapshot(
        sessionId: UUID,
        gameType: ScoreCore.GameType,
        snapshot: LinkedScoreboardSnapshot
    ) {
        guard var activeSession,
              activeSession.sessionId == sessionId,
              activeSession.gameType == gameType else { return }
        activeSession.revision += 1
        self.activeSession = activeSession
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: sessionId,
            kind: .stateSnapshot,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: activeSession.revision,
            sentAtEpochMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
            payload: LinkedScoreboardSetup(
                gameType: gameType,
                maxSets: maxSets(for: snapshot),
                basketballThreeXThree: isThreeXThree(snapshot),
                initialSnapshot: snapshot
            )
        )
        Task {
            guard let data = try? JSONEncoder().encode(envelope) else { return }
            try? await transport.send(data)
        }
    }

    private func maxSets(for snapshot: LinkedScoreboardSnapshot) -> Int? {
        guard case .rally(let state) = snapshot else { return nil }
        return state.rules.maxSets
    }

    private func isThreeXThree(_ snapshot: LinkedScoreboardSnapshot) -> Bool {
        guard case .basketball(let state) = snapshot else { return false }
        return state.gameMode == .threeXThree
    }
}
