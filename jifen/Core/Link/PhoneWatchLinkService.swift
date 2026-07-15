import Foundation
import LinkCore
import Observation
import ScoreCore

@MainActor
@Observable
final class PhoneWatchLinkService {
    private let transport = WatchConnectivityTransport()
    private var sequence: UInt64 = 0

    init() {
        transport.activate()
    }

    func startOnWatch(gameType: ScoreCore.GameType, maxSets: Int? = nil, basketballThreeXThree: Bool = false) {
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: UUID(),
            kind: .setupRequest,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: 0,
            sentAtEpochMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
            payload: LinkedScoreboardSetup(
                gameType: gameType,
                maxSets: maxSets,
                basketballThreeXThree: basketballThreeXThree
            )
        )
        Task {
            guard let data = try? JSONEncoder().encode(envelope) else { return }
            try? await transport.send(data)
        }
    }
}
