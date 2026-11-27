import Foundation
import LinkCore
import RecordCore

/// A Watch asks the host to repair its confirmed state after reconnect, a gap,
/// or a state hash mismatch. Pending IDs select the durable processing receipts
/// the Watch needs before it can remove operations from its queue.
public struct LinkIntentRecoveryRequest: Codable, Equatable, Sendable {
    public let confirmedRevision: UInt64
    public let pendingOperationIds: [UUID]

    public init(confirmedRevision: UInt64, pendingOperationIds: [UUID]) {
        self.confirmedRevision = confirmedRevision
        self.pendingOperationIds = pendingOperationIds
    }
}

/// The score and history are from the same phone checkpoint. Resync must carry
/// history because a missing commit may have removed or added record actions.
public struct LinkIntentRecoveryPayload: Codable, Equatable, Sendable {
    public let checkpoint: LinkAuthoritativeCheckpoint
    public let detailedActions: [DetailedScoreAction]
    public let nextMatchHandle: LinkedMatchHandle?
    public let finishedPayload: LinkMatchFinishedPayload?

    public init(
        checkpoint: LinkAuthoritativeCheckpoint,
        detailedActions: [DetailedScoreAction],
        nextMatchHandle: LinkedMatchHandle? = nil,
        finishedPayload: LinkMatchFinishedPayload? = nil
    ) {
        self.checkpoint = checkpoint
        self.detailedActions = detailedActions
        self.nextMatchHandle = nextMatchHandle
        self.finishedPayload = finishedPayload
    }
}
