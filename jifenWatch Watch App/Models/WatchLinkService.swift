import Foundation
import LinkCore
import Observation

@MainActor
@Observable
final class WatchLinkService {
    var requestedSetup: LinkedScoreboardSetup?

    private let transport = WatchConnectivityTransport()

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
              envelope.kind == .setupRequest,
              envelope.sender == .phone else { return }
        requestedSetup = envelope.payload
    }
}
