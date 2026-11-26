import Foundation
import LinkCore
import RecordCore
import ScoreCore

public enum LinkedScoreboardIntent: Codable, Equatable, Sendable {
    case rally(RallyMatchIntent)
    case tennis(TennisMatchIntent)
    case archery(ArcheryMatchIntent)
    case eightBall(EightBallIntent)
    case nineBall(NineBallChaseIntent)
    case snooker(SnookerIntent)
    case football(FootballMatchIntent)
    case shotTraining(ShotTrainingIntent)
    case undo(targetOpId: UUID?)
    case finish
    case nextMatch(matchId: UUID, matchGeneration: UInt64)

    /// Counts dropped score edits without counting a finish request, name edit, or clock control.
    public var isScoring: Bool {
        switch self {
        case .rally(.pointWon), .rally(.adjustPoints), .rally(.adjustSets),
             .tennis(.pointWon), .tennis(.adjustPoints), .tennis(.adjustGames), .tennis(.adjustSets),
             .archery(.recordArrow), .archery(.completeSet), .archery(.adjustArrowSum), .archery(.adjustSetPoints),
             .eightBall(.addRack), .eightBall(.applyPot), .eightBall(.adminAdjust),
             .nineBall(.chaseEvent), .nineBall(.chaseTransfer), .nineBall(.tournamentEvent),
             .nineBall(.deltaTotal), .nineBall(.adminSetTotals), .nineBall(.adminCorrect),
             .snooker(.potBallAsSide), .snooker(.foulFromSide), .snooker(.potBall),
             .snooker(.foul), .snooker(.settleFrame), .snooker(.adminCorrect),
             .football(.goal), .football(.subtractGoal),
             .shotTraining(.recordShot), .shotTraining(.undoLastShot):
            true
        default:
            false
        }
    }

    var needsAuthoritativeSnapshot: Bool {
        switch self {
        case .undo, .finish, .nextMatch: true
        default: false
        }
    }

    // These sport-specific controls bypass the shared finish, undo, and next-match policy.
    var usesSportSpecificSessionControl: Bool {
        switch self {
        case .rally(.finish), .rally(.reset), .tennis(.finish), .tennis(.reset),
             .archery(.finish), .archery(.reset), .eightBall(.finishMatch), .eightBall(.reset),
             .nineBall(.finishMatch), .nineBall(.resetScores), .snooker(.finishMatch), .snooker(.reset),
             .football(.finish), .football(.reset),
             .shotTraining(.finish), .shotTraining(.reset), .shotTraining(.undoLastShot):
            true
        default:
            false
        }
    }
}

public struct LinkOperation: Codable, Equatable, Identifiable, Sendable {
    public let opId: UUID
    public let handle: LinkedMatchHandle
    public let origin: LinkPeer
    public let clientSeq: UInt64
    public let baseRevision: UInt64
    public let createdAtEpochMilliseconds: Int64
    public let intent: LinkedScoreboardIntent
    public var id: UUID { opId }

    public init(
        opId: UUID,
        handle: LinkedMatchHandle,
        origin: LinkPeer,
        clientSeq: UInt64,
        baseRevision: UInt64,
        createdAtEpochMilliseconds: Int64,
        intent: LinkedScoreboardIntent
    ) {
        self.opId = opId
        self.handle = handle
        self.origin = origin
        self.clientSeq = clientSeq
        self.baseRevision = baseRevision
        self.createdAtEpochMilliseconds = createdAtEpochMilliseconds
        self.intent = intent
    }
}

public enum LinkOperationOutcome: String, Codable, Equatable, Sendable {
    case accepted
    case rejected
}

/// Stable wire codes. Presentation and diagnostics can map these to localized copy.
public enum LinkOperationRejectionReason: String, Codable, Sendable {
    case matchFinished
    case invalidBaseRevision
    case reducerRejected
    case undoTargetUnavailable
    case invalidNextMatch
    case unsupportedSessionControl
}

public struct LinkOperationCommitPayload: Codable, Equatable, Sendable {
    public let committedRevision: UInt64
    public let op: LinkOperation
    public let outcome: LinkOperationOutcome
    public let effectiveEpochMilliseconds: Int64
    public let timeWasClamped: Bool
    public let rejectionReason: String?
    public let stateHash: UInt64
    public let authoritativeSnapshot: LinkedScoreboardSnapshot?
    public let deltaActions: [DetailedScoreAction]

    public init(
        committedRevision: UInt64,
        op: LinkOperation,
        outcome: LinkOperationOutcome,
        effectiveEpochMilliseconds: Int64,
        timeWasClamped: Bool,
        rejectionReason: String? = nil,
        stateHash: UInt64,
        authoritativeSnapshot: LinkedScoreboardSnapshot? = nil,
        deltaActions: [DetailedScoreAction] = []
    ) {
        self.committedRevision = committedRevision
        self.op = op
        self.outcome = outcome
        self.effectiveEpochMilliseconds = effectiveEpochMilliseconds
        self.timeWasClamped = timeWasClamped
        self.rejectionReason = rejectionReason
        self.stateHash = stateHash
        self.authoritativeSnapshot = authoritativeSnapshot
        self.deltaActions = deltaActions
    }
}

extension LinkOperationCommitPayload: LinkOperationJournalOutcome {
    public var journalOperationID: UUID { op.opId }
    public var journalOperationHandle: LinkedMatchHandle { op.handle }
}

/// The small part of a journal receipt needed to reconcile one submitted Watch operation.
public struct LinkProcessedOperation: Codable, Equatable, Sendable {
    public let opId: UUID
    public let clientSeq: UInt64
    public let committedRevision: UInt64
    public let outcome: LinkOperationOutcome
    public let rejectionReason: String?

    public init(commit: LinkOperationCommitPayload) {
        opId = commit.op.opId
        clientSeq = commit.op.clientSeq
        committedRevision = commit.committedRevision
        outcome = commit.outcome
        rejectionReason = commit.rejectionReason
    }
}

public struct LinkAuthoritativeCheckpoint: Codable, Equatable, Sendable {
    public let handle: LinkedMatchHandle
    public let committedRevision: UInt64
    public let watchClientSeq: UInt64
    public let effectiveEpochMilliseconds: Int64
    public let snapshot: LinkedScoreboardSnapshot
    public let stateHash: UInt64
    public let watchResults: [LinkProcessedOperation]

    public init(
        handle: LinkedMatchHandle,
        committedRevision: UInt64,
        watchClientSeq: UInt64,
        effectiveEpochMilliseconds: Int64,
        snapshot: LinkedScoreboardSnapshot,
        stateHash: UInt64,
        watchResults: [LinkProcessedOperation]
    ) {
        self.handle = handle
        self.committedRevision = committedRevision
        self.watchClientSeq = watchClientSeq
        self.effectiveEpochMilliseconds = effectiveEpochMilliseconds
        self.snapshot = snapshot
        self.stateHash = stateHash
        self.watchResults = watchResults
    }
}

public enum LinkIntentTransition<State> {
    case accepted(state: State, deltaActions: [DetailedScoreAction] = [])
    case rejected(LinkOperationRejectionReason)
}
