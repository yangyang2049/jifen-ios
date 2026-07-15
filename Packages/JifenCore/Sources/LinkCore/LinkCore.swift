import Foundation
import ScoreCore

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
