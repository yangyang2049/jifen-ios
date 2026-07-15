import Foundation
import LinkCore
import Observation

struct LinkedSetupRequest: Equatable {
    let sessionId: UUID
    let setup: LinkedScoreboardSetup
}

struct LinkedSnapshotUpdate: Equatable {
    let sessionId: UUID
    let revision: UInt64
    let snapshot: LinkedScoreboardSnapshot
}

@MainActor
@Observable
final class WatchLinkService {
    var requestedSetup: LinkedSetupRequest?
    var latestSnapshot: LinkedSnapshotUpdate?

    private let transport = WatchConnectivityTransport()
    private var revisionGate = LinkRevisionGate()

    init() {
        transport.onReceive = { [weak self] data in
            DispatchQueue.main.async {
                self?.receive(data)
            }
        }
        transport.activate()
    }

    func clearRequestedSetup() {
        requestedSetup = nil
    }

    private func receive(_ data: Data) {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkedScoreboardSetup>.self, from: data),
              envelope.protocolVersion == LinkProtocol.currentVersion,
              envelope.sender == .phone else { return }
        switch envelope.kind {
        case .setupRequest:
            guard revisionGate.beginSession(envelope.sessionId, initialRevision: envelope.sessionRevision) else { return }
            latestSnapshot = nil
            requestedSetup = .init(sessionId: envelope.sessionId, setup: envelope.payload)
        case .stateSnapshot:
            guard let snapshot = envelope.payload.initialSnapshot,
                  revisionGate.accept(sessionId: envelope.sessionId, revision: envelope.sessionRevision) else { return }
            latestSnapshot = .init(
                sessionId: envelope.sessionId,
                revision: envelope.sessionRevision,
                snapshot: snapshot
            )
        default:
            return
        }
    }
}
