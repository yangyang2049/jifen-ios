@preconcurrency import MultipeerConnectivity
import Combine
import Foundation
import LinkCore
import ScoreCore

enum LocalPeerRoomPhase: Equatable {
    case idle
    case advertising
    case browsing
    case connected
    case paused
    case failed(String)
}

struct LocalPeerJoinRequest: Codable, Identifiable, Equatable {
    let identity: SyncIdentity
    let role: SyncParticipantRole
    let code: String

    var id: UUID { identity.localID }
}

@MainActor
final class LocalPeerRoomManager: NSObject, ObservableObject {
    static let shared = LocalPeerRoomManager()
    static let serviceType = "jifen-score-v1"

    @Published private(set) var phase: LocalPeerRoomPhase = .idle
    @Published private(set) var room: SyncRoomDescriptor?
    @Published private(set) var localIdentity: SyncIdentity?
    @Published private(set) var localRole: SyncParticipantRole = .display
    @Published private(set) var participants: [SyncParticipant] = []
    @Published private(set) var pendingJoinRequests: [LocalPeerJoinRequest] = []
    @Published private(set) var lastEnvelope: RealtimeSyncEnvelope?
    @Published private(set) var lastError: String?

    var onEnvelope: ((RealtimeSyncEnvelope) -> Void)?

    private var peerID: MCPeerID?
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var invitationHandlers: [UUID: (Bool, MCSession?) -> Void] = [:]
    private var pendingPeers: [UUID: MCPeerID] = [:]
    private var requestsByPeerName: [String: LocalPeerJoinRequest] = [:]
    private var participantsByPeerName: [String: SyncParticipant] = [:]
    private var desiredJoinCode: String?
    private var desiredJoinRole: SyncParticipantRole = .display
    private var senderSequence: UInt64 = 0
    private var seenMessageIDs: Set<UUID> = []
    private var lastSequenceBySender: [UUID: UInt64] = [:]

    private override init() {
        super.init()
    }

    func createRoom() async {
        stop()
        do {
            let identity = try await AnonymousIdentityProvider.shared.currentIdentity()
            localIdentity = identity
            localRole = .hostController
            let descriptor = SyncRoomDescriptor(
                roomID: UUID(),
                shortCode: Self.makeShortCode(),
                hostIdentityID: identity.localID,
                roomSecret: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                expiresAt: Date().addingTimeInterval(5 * 60)
            )
            room = descriptor
            participants = [.init(id: identity.localID, displayName: identity.displayName, role: .hostController)]
            let peer = makePeerID(identity: identity)
            let session = makeSession(peer: peer)
            self.peerID = peer
            self.session = session
            let advertiser = MCNearbyServiceAdvertiser(
                peer: peer,
                discoveryInfo: [
                    "room": descriptor.roomID.uuidString,
                    "code": descriptor.shortCode,
                    "version": String(RealtimeSyncProtocol.currentVersion)
                ],
                serviceType: Self.serviceType
            )
            advertiser.delegate = self
            self.advertiser = advertiser
            advertiser.startAdvertisingPeer()
            phase = .advertising
        } catch {
            fail(error.localizedDescription)
        }
    }

    func joinRoom(code: String, role: SyncParticipantRole) async {
        stop()
        let normalized = code.filter(\.isNumber)
        guard normalized.count == 6 else {
            fail(NSLocalizedString("sync_invalid_code", value: "请输入 6 位同步码", comment: ""))
            return
        }
        do {
            let identity = try await AnonymousIdentityProvider.shared.currentIdentity()
            localIdentity = identity
            localRole = role == .hostController ? .remoteController : role
            desiredJoinCode = normalized
            desiredJoinRole = localRole
            let peer = makePeerID(identity: identity)
            let session = makeSession(peer: peer)
            self.peerID = peer
            self.session = session
            let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.serviceType)
            browser.delegate = self
            self.browser = browser
            browser.startBrowsingForPeers()
            phase = .browsing
        } catch {
            fail(error.localizedDescription)
        }
    }

    func approve(_ request: LocalPeerJoinRequest) {
        guard let handler = invitationHandlers.removeValue(forKey: request.id) else { return }
        pendingJoinRequests.removeAll { $0.id == request.id }
        handler(true, session)
    }

    func reject(_ request: LocalPeerJoinRequest) {
        invitationHandlers.removeValue(forKey: request.id)?(false, nil)
        pendingJoinRequests.removeAll { $0.id == request.id }
        pendingPeers.removeValue(forKey: request.id)
    }

    func removeParticipant(_ participant: SyncParticipant) {
        guard participant.role != .hostController,
              let peer = session?.connectedPeers.first(where: { participantsByPeerName[$0.displayName]?.id == participant.id }) else { return }
        sendControl(kind: .participantRemoved, to: [peer])
        participantsByPeerName.removeValue(forKey: peer.displayName)
        rebuildParticipants()
    }

    func send(_ envelope: RealtimeSyncEnvelope) {
        guard let session, !session.connectedPeers.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(envelope)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func broadcastPayload<T: Encodable>(
        _ payload: T,
        kind: RealtimeSyncMessageKind,
        gameType: ScoreCore.GameType? = nil,
        sessionID: UUID? = nil,
        revision: UInt64 = 0
    ) {
        guard let room, let localIdentity else { return }
        do {
            senderSequence += 1
            send(RealtimeSyncEnvelope(
                roomID: room.roomID,
                sessionID: sessionID,
                gameType: gameType,
                senderID: localIdentity.localID,
                senderRole: localRole,
                senderSequence: senderSequence,
                sessionRevision: revision,
                sentAtEpochMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
                kind: kind,
                payload: try RealtimeSyncEnvelope.encodePayload(payload)
            ))
        } catch {
            fail(error.localizedDescription)
        }
    }

    func setPaused(_ paused: Bool) {
        guard localRole == .hostController else { return }
        phase = paused ? .paused : (session?.connectedPeers.isEmpty == false ? .connected : .advertising)
        broadcastPayload(["paused": paused], kind: paused ? .controllerPaused : .controllerResumed)
    }

    func stop() {
        if localRole == .hostController, session?.connectedPeers.isEmpty == false {
            sendControl(kind: .roomEnded, to: session?.connectedPeers ?? [])
        }
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        peerID = nil
        room = nil
        participants = []
        pendingJoinRequests = []
        invitationHandlers.removeAll()
        pendingPeers.removeAll()
        requestsByPeerName.removeAll()
        participantsByPeerName.removeAll()
        desiredJoinCode = nil
        senderSequence = 0
        seenMessageIDs.removeAll(keepingCapacity: true)
        lastSequenceBySender.removeAll(keepingCapacity: true)
        phase = .idle
        lastError = nil
    }

    var shareURL: URL? {
        guard let room else { return nil }
        var components = URLComponents()
        components.scheme = "jifen"
        components.host = "sync"
        components.path = "/join"
        components.queryItems = [
            URLQueryItem(name: "v", value: String(RealtimeSyncProtocol.currentVersion)),
            URLQueryItem(name: "room", value: room.roomID.uuidString),
            URLQueryItem(name: "code", value: room.shortCode),
            URLQueryItem(name: "secret", value: room.roomSecret)
        ]
        return components.url
    }

    private func makePeerID(identity: SyncIdentity) -> MCPeerID {
        MCPeerID(displayName: "\(identity.displayName.prefix(28))|\(identity.localID.uuidString.prefix(8))")
    }

    private func makeSession(peer: MCPeerID) -> MCSession {
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        return session
    }

    private func sendRoomHello(to peers: [MCPeerID]) {
        guard let room, let identity = localIdentity else { return }
        do {
            let payload = try JSONEncoder().encode(room)
            senderSequence += 1
            let envelope = RealtimeSyncEnvelope(
                roomID: room.roomID,
                senderID: identity.localID,
                senderRole: .hostController,
                senderSequence: senderSequence,
                sessionRevision: 0,
                sentAtEpochMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
                kind: .hello,
                payload: payload
            )
            let data = try JSONEncoder().encode(envelope)
            try session?.send(data, toPeers: peers, with: .reliable)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func sendControl(kind: RealtimeSyncMessageKind, to peers: [MCPeerID]) {
        guard let room, let identity = localIdentity, !peers.isEmpty else { return }
        do {
            senderSequence += 1
            let envelope = RealtimeSyncEnvelope(
                roomID: room.roomID,
                senderID: identity.localID,
                senderRole: localRole,
                senderSequence: senderSequence,
                sessionRevision: 0,
                sentAtEpochMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
                kind: kind
            )
            try session?.send(JSONEncoder().encode(envelope), toPeers: peers, with: .reliable)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func receive(_ data: Data, from peer: MCPeerID) {
        do {
            let envelope = try JSONDecoder().decode(RealtimeSyncEnvelope.self, from: data)
            guard envelope.protocolVersion == RealtimeSyncProtocol.currentVersion else { return }
            guard !seenMessageIDs.contains(envelope.id) else { return }
            let previousSequence = lastSequenceBySender[envelope.senderID] ?? 0
            guard envelope.senderSequence > previousSequence else { return }
            if previousSequence > 0, envelope.senderSequence > previousSequence + 1,
               localRole != .hostController {
                broadcastPayload(
                    ["reason": "sequence_gap"],
                    kind: .resyncRequest,
                    sessionID: envelope.sessionID,
                    revision: envelope.sessionRevision
                )
            }
            seenMessageIDs.insert(envelope.id)
            lastSequenceBySender[envelope.senderID] = envelope.senderSequence
            if seenMessageIDs.count > 2_048 { seenMessageIDs = [envelope.id] }
            if envelope.kind == .hello,
               let descriptor = try? envelope.decodePayload(SyncRoomDescriptor.self) {
                room = descriptor
            }
            if envelope.kind == .roomEnded || envelope.kind == .participantRemoved {
                stop()
                return
            }
            if envelope.kind == .resyncRequest, localRole == .hostController {
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()
                return
            }
            lastEnvelope = envelope
            onEnvelope?(envelope)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func peerStateChanged(_ peer: MCPeerID, state: MCSessionState) {
        switch state {
        case .connected:
            if localRole == .hostController {
                if let request = requestsByPeerName[peer.displayName] {
                    participantsByPeerName[peer.displayName] = SyncParticipant(
                        id: request.identity.localID,
                        displayName: request.identity.displayName,
                        role: request.role
                    )
                }
                sendRoomHello(to: [peer])
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()
            } else if let identity = localIdentity {
                participantsByPeerName[peer.displayName] = SyncParticipant(
                    id: room?.hostIdentityID ?? UUID(),
                    displayName: peer.displayName.components(separatedBy: "|").first ?? peer.displayName,
                    role: .hostController
                )
                participantsByPeerName[makePeerID(identity: identity).displayName] = SyncParticipant(
                    id: identity.localID,
                    displayName: identity.displayName,
                    role: localRole
                )
            }
            phase = .connected
        case .notConnected:
            participantsByPeerName.removeValue(forKey: peer.displayName)
            if session?.connectedPeers.isEmpty == true {
                phase = localRole == .hostController ? .advertising : .browsing
            }
        case .connecting:
            break
        @unknown default:
            break
        }
        rebuildParticipants()
    }

    private func rebuildParticipants() {
        var result: [SyncParticipant] = []
        if let identity = localIdentity {
            result.append(.init(id: identity.localID, displayName: identity.displayName, role: localRole))
        }
        result.append(contentsOf: participantsByPeerName.values.filter { participant in
            !result.contains(where: { $0.id == participant.id })
        })
        participants = result.sorted { lhs, rhs in
            if lhs.role == .hostController { return true }
            if rhs.role == .hostController { return false }
            return lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func fail(_ message: String) {
        lastError = message
        phase = .failed(message)
    }

    private static func makeShortCode() -> String {
        String(format: "%06d", Int.random(in: 0 ... 999_999))
    }
}

extension LocalPeerRoomManager: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        Task { @MainActor in
            guard let context,
                  let request = try? JSONDecoder().decode(LocalPeerJoinRequest.self, from: context),
                  request.code == room?.shortCode,
                  ((room?.expiresAt) ?? .distantPast) > Date(),
                  participants.count + pendingJoinRequests.count < RealtimeSyncProtocol.maximumParticipants else {
                invitationHandler(false, nil)
                return
            }
            requestsByPeerName[peerID.displayName] = request
            pendingPeers[request.id] = peerID
            invitationHandlers[request.id] = invitationHandler
            pendingJoinRequests.removeAll { $0.id == request.id }
            pendingJoinRequests.append(request)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in fail(error.localizedDescription) }
    }
}

extension LocalPeerRoomManager: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            guard let desiredJoinCode,
                  info?["code"] == desiredJoinCode,
                  let localIdentity,
                  let session else { return }
            browser.stopBrowsingForPeers()
            let request = LocalPeerJoinRequest(identity: localIdentity, role: desiredJoinRole, code: desiredJoinCode)
            guard let context = try? JSONEncoder().encode(request) else { return }
            browser.invitePeer(peerID, to: session, withContext: context, timeout: 30)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in fail(error.localizedDescription) }
    }
}

extension LocalPeerRoomManager: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in peerStateChanged(peerID, state: state) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in receive(data, from: peerID) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
