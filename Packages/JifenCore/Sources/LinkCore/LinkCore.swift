import Foundation
import ScoreCore

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

public enum LinkPeer: String, Codable, Sendable {
    case phone
    case watch
}

public enum LinkControlRole: String, Codable, Sendable {
    case phoneController
    case phoneFollower
    case watchController
    case watchFollower
}

public enum LinkMessageKind: String, Codable, Sendable {
    case setupRequest
    case setupAccepted
    case setupRejected
    case stateSnapshot
    case acknowledgement
    case negativeAcknowledgement
    case statusQuery
    case statusResponse
    case resyncRequest
    case takeoverByPhone
    case reclaimRequest
    case reclaimAccepted
    case reclaimDenied
    case matchFinished
    case recordAcknowledgement
    case sessionLeft
}

public struct LinkEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public let protocolVersion: Int
    public let messageId: UUID
    public let sessionId: UUID
    public let kind: LinkMessageKind
    public let sender: LinkPeer
    public let senderSequence: UInt64
    public let sessionRevision: UInt64
    public let sentAtEpochMilliseconds: Int64
    public let payload: Payload

    public init(
        protocolVersion: Int = 1,
        messageId: UUID = UUID(),
        sessionId: UUID,
        kind: LinkMessageKind,
        sender: LinkPeer,
        senderSequence: UInt64,
        sessionRevision: UInt64,
        sentAtEpochMilliseconds: Int64,
        payload: Payload
    ) {
        self.protocolVersion = protocolVersion
        self.messageId = messageId
        self.sessionId = sessionId
        self.kind = kind
        self.sender = sender
        self.senderSequence = senderSequence
        self.sessionRevision = sessionRevision
        self.sentAtEpochMilliseconds = sentAtEpochMilliseconds
        self.payload = payload
    }
}

public protocol LinkTransport: Sendable {
    func send(_ data: Data) async throws
}

#if canImport(WatchConnectivity)
public enum WatchConnectivityTransportError: Error, Equatable, Sendable {
    case sessionNotActivated
}

/// A binary transport shared by the phone and Watch targets.
public final class WatchConnectivityTransport: NSObject, @unchecked Sendable, LinkTransport {
    public typealias ReceiveHandler = @Sendable (Data) -> Void

    private static let userInfoPayloadKey = "jifen.link.payload"
    private let session: WCSession
    public var onReceive: ReceiveHandler?

    public init(session: WCSession = .default) {
        self.session = session
        super.init()
    }

    public func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    public func send(_ data: Data) async throws {
        guard session.activationState == .activated else {
            throw WatchConnectivityTransportError.sessionNotActivated
        }
        if session.isReachable {
            session.sendMessageData(data, replyHandler: nil, errorHandler: nil)
        } else {
            session.transferUserInfo([Self.userInfoPayloadKey: data])
        }
    }
}

extension WatchConnectivityTransport: WCSessionDelegate {
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    public func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        onReceive?(messageData)
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[Self.userInfoPayloadKey] as? Data else { return }
        onReceive?(data)
    }

#if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}

    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
#endif
}
#endif
