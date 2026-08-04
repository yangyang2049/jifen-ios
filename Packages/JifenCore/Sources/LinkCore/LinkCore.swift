import Foundation
import RecordCore
import ScoreCore

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

public enum LinkProtocol {
    public static let currentVersion = 1
    public static let capabilities: Set<LinkCapability> = [
        .independentMatches,
        .authorityEpoch,
        .correlatedRequests,
        .durableTerminalQueue,
        .latestSnapshotContext
    ]
}

public enum LinkCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case independentMatches
    case authorityEpoch
    case correlatedRequests
    case durableTerminalQueue
    case latestSnapshotContext
}

public struct LinkedMatchHandle: Codable, Equatable, Hashable, Sendable {
    public let sessionId: UUID
    public let matchId: UUID
    public let matchGeneration: UInt64

    public init(
        sessionId: UUID,
        matchId: UUID = UUID(),
        matchGeneration: UInt64 = 1
    ) {
        self.sessionId = sessionId
        self.matchId = matchId
        self.matchGeneration = max(1, matchGeneration)
    }

    public func nextMatch(matchId: UUID = UUID()) -> Self {
        Self(
            sessionId: sessionId,
            matchId: matchId,
            matchGeneration: matchGeneration + 1
        )
    }
}

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

/// Manual score resync is intentionally one-way: the phone follower asks and
/// the authoritative Watch controller answers with a fresh full snapshot.
public enum LinkManualResyncPolicy {
    public static func phoneCanRequest(role: LinkControlRole?) -> Bool {
        role == .phoneFollower
    }

    public static func watchCanRespond(role: LinkControlRole?) -> Bool {
        role == .watchController
    }
}

public enum LinkMessageKind: String, Codable, Sendable {
    case setupRequest
    case setupAccepted
    case setupRejected
    case matchStarted
    case stateSnapshot
    case acknowledgement
    case statusQuery
    case statusResponse
    case resyncRequest
    case takeoverByPhone
    case reclaimRequest
    case reclaimAccepted
    case reclaimDenied
    case matchFinished
    case recordAcknowledgement
    case scoreboardExitedToHome
    case watchBackgrounded
    case resumeDiscarded
    case sessionLeft
    case commonNamesSyncRequest
    case connectivityProbe
    case connectivityProbeResponse
}

public enum LinkedScoreboardSnapshot: Codable, Equatable, Sendable {
    case rally(RallyMatchState)
    case tennis(TennisMatchState)
    case archery(LinkedArcheryState)
    case eightBall(EightBallState)
    case nineBall(NineBallChaseState)
    case snooker(SnookerState)

    private enum CodingKeys: String, CodingKey {
        case kind
        case rally
        case tennis
        case archery
        case eightBall
        case nineBall
        case snooker
    }

    private enum Kind: String, Codable {
        case rally
        case tennis
        case archery
        case eightBall
        case nineBall
        case snooker
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .rally:
            self = .rally(try container.decode(RallyMatchState.self, forKey: .rally))
        case .tennis:
            self = .tennis(try container.decode(TennisMatchState.self, forKey: .tennis))
        case .archery:
            self = .archery(try container.decode(LinkedArcheryState.self, forKey: .archery))
        case .eightBall:
            self = .eightBall(try container.decode(EightBallState.self, forKey: .eightBall))
        case .nineBall:
            self = .nineBall(try container.decode(NineBallChaseState.self, forKey: .nineBall))
        case .snooker:
            self = .snooker(try container.decode(SnookerState.self, forKey: .snooker))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .rally(let state):
            try container.encode(Kind.rally, forKey: .kind)
            try container.encode(state, forKey: .rally)
        case .tennis(let state):
            try container.encode(Kind.tennis, forKey: .kind)
            try container.encode(state, forKey: .tennis)
        case .archery(let state):
            try container.encode(Kind.archery, forKey: .kind)
            try container.encode(state, forKey: .archery)
        case .eightBall(let state):
            try container.encode(Kind.eightBall, forKey: .kind)
            try container.encode(state, forKey: .eightBall)
        case .nineBall(let state):
            try container.encode(Kind.nineBall, forKey: .kind)
            try container.encode(state, forKey: .nineBall)
        case .snooker(let state):
            try container.encode(Kind.snooker, forKey: .kind)
            try container.encode(state, forKey: .snooker)
        }
    }

    public var rallyState: RallyMatchState? {
        guard case .rally(let state) = self else { return nil }
        return state
    }

    public var tennisState: TennisMatchState? {
        guard case .tennis(let state) = self else { return nil }
        return state
    }

    public var archeryState: LinkedArcheryState? {
        guard case .archery(let state) = self else { return nil }
        return state
    }

    public var eightBallState: EightBallState? {
        guard case .eightBall(let state) = self else { return nil }
        return state
    }

    public var nineBallState: NineBallChaseState? {
        guard case .nineBall(let state) = self else { return nil }
        return state
    }

    public var snookerState: SnookerState? {
        guard case .snooker(let state) = self else { return nil }
        return state
    }
}

/// Lightweight archery sync DTO projected from `ArcheryMatchState`.
public struct LinkedArcheryState: Codable, Equatable, Sendable {
    public var leftName: String
    public var rightName: String
    public var leftSetPoints: Int
    public var rightSetPoints: Int
    public var leftArrowSum: Int
    public var rightArrowSum: Int
    public var currentShooterIsLeft: Bool
    public var setNumber: Int
    public var finished: Bool
    public var sidesSwapped: Bool
    public var arrowsLeftThisSet: Int
    public var arrowsRightThisSet: Int
    public var arrowsPerSet: Int
    public var openingShooterIsLeft: Bool
    public var pendingSetNumber: Int
    public var pendingSetWinnerIsLeft: Bool?
    public var pendingLeftSetPoints: Int
    public var pendingRightSetPoints: Int
    public var closestToCenterPending: Bool

    public init(
        leftName: String = "红方",
        rightName: String = "蓝方",
        leftSetPoints: Int = 0,
        rightSetPoints: Int = 0,
        leftArrowSum: Int = 0,
        rightArrowSum: Int = 0,
        currentShooterIsLeft: Bool = true,
        setNumber: Int = 1,
        finished: Bool = false,
        sidesSwapped: Bool = false,
        arrowsLeftThisSet: Int = 0,
        arrowsRightThisSet: Int = 0,
        arrowsPerSet: Int = 3,
        openingShooterIsLeft: Bool = true,
        pendingSetNumber: Int = 0,
        pendingSetWinnerIsLeft: Bool? = nil,
        pendingLeftSetPoints: Int = 0,
        pendingRightSetPoints: Int = 0,
        closestToCenterPending: Bool = false
    ) {
        self.leftName = leftName
        self.rightName = rightName
        self.leftSetPoints = leftSetPoints
        self.rightSetPoints = rightSetPoints
        self.leftArrowSum = leftArrowSum
        self.rightArrowSum = rightArrowSum
        self.currentShooterIsLeft = currentShooterIsLeft
        self.setNumber = setNumber
        self.finished = finished
        self.sidesSwapped = sidesSwapped
        self.arrowsLeftThisSet = arrowsLeftThisSet
        self.arrowsRightThisSet = arrowsRightThisSet
        self.arrowsPerSet = arrowsPerSet
        self.openingShooterIsLeft = openingShooterIsLeft
        self.pendingSetNumber = pendingSetNumber
        self.pendingSetWinnerIsLeft = pendingSetWinnerIsLeft
        self.pendingLeftSetPoints = pendingLeftSetPoints
        self.pendingRightSetPoints = pendingRightSetPoints
        self.closestToCenterPending = closestToCenterPending
    }

    public init(match: ArcheryMatchState) {
        self.init(
            leftName: match.leftName,
            rightName: match.rightName,
            leftSetPoints: match.leftSetPoints,
            rightSetPoints: match.rightSetPoints,
            leftArrowSum: match.leftArrowSum,
            rightArrowSum: match.rightArrowSum,
            currentShooterIsLeft: match.currentShooterIsLeft,
            setNumber: match.currentSet,
            finished: match.finished,
            sidesSwapped: match.sidesSwapped,
            arrowsLeftThisSet: match.arrowsLeftThisSet,
            arrowsRightThisSet: match.arrowsRightThisSet,
            arrowsPerSet: match.arrowsPerSet,
            openingShooterIsLeft: match.openingShooterIsLeft,
            pendingSetNumber: match.pendingSetNumber,
            pendingSetWinnerIsLeft: match.pendingSetWinnerIsLeft,
            pendingLeftSetPoints: match.pendingLeftSetPoints,
            pendingRightSetPoints: match.pendingRightSetPoints,
            closestToCenterPending: match.closestToCenterPending
        )
    }

    public func applying(to match: inout ArcheryMatchState) {
        match.leftName = leftName
        match.rightName = rightName
        match.leftSetPoints = leftSetPoints
        match.rightSetPoints = rightSetPoints
        match.leftArrowSum = leftArrowSum
        match.rightArrowSum = rightArrowSum
        match.currentShooterIsLeft = currentShooterIsLeft
        match.currentSet = max(1, setNumber)
        match.finished = finished
        match.sidesSwapped = sidesSwapped
        match.arrowsLeftThisSet = max(0, arrowsLeftThisSet)
        match.arrowsRightThisSet = max(0, arrowsRightThisSet)
        match.arrowsPerSet = max(1, arrowsPerSet)
        match.openingShooterIsLeft = openingShooterIsLeft
        match.pendingSetNumber = max(0, pendingSetNumber)
        match.pendingSetWinnerIsLeft = pendingSetWinnerIsLeft
        match.pendingLeftSetPoints = max(0, pendingLeftSetPoints)
        match.pendingRightSetPoints = max(0, pendingRightSetPoints)
        match.closestToCenterPending = closestToCenterPending
        if finished {
            match.pendingSetNumber = 0
            match.closestToCenterPending = false
        }
    }
}

public struct EmptyLinkPayload: Codable, Equatable, Sendable {
    public init() {}
}

public struct LinkAuthorityTransferPayload: Codable, Equatable, Sendable {
    public var snapshot: LinkedScoreboardSnapshot?
    public var detailedActions: [DetailedScoreAction]
    public var baseRevision: UInt64

    public init(
        snapshot: LinkedScoreboardSnapshot? = nil,
        detailedActions: [DetailedScoreAction] = [],
        baseRevision: UInt64
    ) {
        self.snapshot = snapshot
        self.detailedActions = detailedActions
        self.baseRevision = baseRevision
    }
}

public enum LinkResumeDiscardReason: String, Codable, Sendable {
    case resumeBarClose
    case newScoreboardStart
    case expired
}

public struct LinkResumeDiscardPayload: Codable, Equatable, Sendable {
    public let reason: LinkResumeDiscardReason

    public init(reason: LinkResumeDiscardReason) {
        self.reason = reason
    }
}

public struct LinkAcknowledgementPayload: Codable, Equatable, Sendable {
    public var acknowledgedMessageId: UUID
    public var acknowledgedRevision: UInt64
    public var authoritativeSnapshot: LinkedScoreboardSnapshot?
    public var detailedActions: [DetailedScoreAction]

    public init(
        acknowledgedMessageId: UUID,
        acknowledgedRevision: UInt64,
        authoritativeSnapshot: LinkedScoreboardSnapshot? = nil,
        detailedActions: [DetailedScoreAction] = []
    ) {
        self.acknowledgedMessageId = acknowledgedMessageId
        self.acknowledgedRevision = acknowledgedRevision
        self.authoritativeSnapshot = authoritativeSnapshot
        self.detailedActions = detailedActions
    }
}

public struct LinkMatchFinishedPayload: Codable, Equatable, Sendable {
    public var snapshot: LinkedScoreboardSnapshot
    public var recordId: String
    public var winnerSide: MatchSide?
    public var manualEnd: Bool
    public var startTimeEpochMilliseconds: Int64
    public var endTimeEpochMilliseconds: Int64
    public var durationSeconds: Double
    public var totalScoreChanges: Int
    public var detailedActions: [DetailedScoreAction]
    public var participantNames: [String]

    public init(
        snapshot: LinkedScoreboardSnapshot,
        recordId: String,
        winnerSide: MatchSide? = nil,
        manualEnd: Bool = false,
        startTimeEpochMilliseconds: Int64 = 0,
        endTimeEpochMilliseconds: Int64 = 0,
        durationSeconds: Double = 0,
        totalScoreChanges: Int = 0,
        detailedActions: [DetailedScoreAction] = [],
        participantNames: [String] = []
    ) {
        self.snapshot = snapshot
        self.recordId = recordId
        self.winnerSide = winnerSide
        self.manualEnd = manualEnd
        self.startTimeEpochMilliseconds = startTimeEpochMilliseconds
        self.endTimeEpochMilliseconds = endTimeEpochMilliseconds
        self.durationSeconds = durationSeconds
        self.totalScoreChanges = totalScoreChanges
        self.detailedActions = detailedActions
        self.participantNames = participantNames
    }
}

public struct LinkStatusPayload: Codable, Equatable, Sendable {
    public var role: LinkControlRole
    public var revision: UInt64
    public var reachable: Bool
    public var capabilities: Set<LinkCapability>

    public init(
        role: LinkControlRole,
        revision: UInt64,
        reachable: Bool = true,
        capabilities: Set<LinkCapability> = LinkProtocol.capabilities
    ) {
        self.role = role
        self.revision = revision
        self.reachable = reachable
        self.capabilities = capabilities
    }
}

public struct PhoneLinkResumeContext: Codable, Equatable, Sendable {
    public var handle: LinkedMatchHandle
    public var setup: LinkedScoreboardSetup
    public var role: LinkControlRole
    public var authorityEpoch: UInt64
    public var revision: UInt64
    public var latestAuthoritativeSnapshot: LinkedScoreboardSnapshot?
    public var detailedActions: [DetailedScoreAction]
    public var completedMatchIds: Set<UUID>
    public var pendingTerminalMessageIds: Set<UUID>

    public init(
        handle: LinkedMatchHandle,
        setup: LinkedScoreboardSetup,
        role: LinkControlRole,
        authorityEpoch: UInt64,
        revision: UInt64,
        latestAuthoritativeSnapshot: LinkedScoreboardSnapshot?,
        detailedActions: [DetailedScoreAction],
        completedMatchIds: Set<UUID>,
        pendingTerminalMessageIds: Set<UUID>
    ) {
        self.handle = handle
        self.setup = setup
        self.role = role
        self.authorityEpoch = authorityEpoch
        self.revision = revision
        self.latestAuthoritativeSnapshot = latestAuthoritativeSnapshot
        self.detailedActions = detailedActions
        self.completedMatchIds = completedMatchIds
        self.pendingTerminalMessageIds = pendingTerminalMessageIds
    }
}

public struct WatchLinkResumeContext: Codable, Equatable, Sendable {
    public var handle: LinkedMatchHandle
    public var setup: LinkedScoreboardSetup
    public var role: LinkControlRole
    public var authorityEpoch: UInt64
    public var revision: UInt64
    public var latestAuthoritativeSnapshot: LinkedScoreboardSnapshot?
    public var detailedActions: [DetailedScoreAction]
    public var completedMatchIds: Set<UUID>
    public var pendingTerminalMessageIds: Set<UUID>

    public init(
        handle: LinkedMatchHandle,
        setup: LinkedScoreboardSetup,
        role: LinkControlRole,
        authorityEpoch: UInt64,
        revision: UInt64,
        latestAuthoritativeSnapshot: LinkedScoreboardSnapshot?,
        detailedActions: [DetailedScoreAction],
        completedMatchIds: Set<UUID>,
        pendingTerminalMessageIds: Set<UUID>
    ) {
        self.handle = handle
        self.setup = setup
        self.role = role
        self.authorityEpoch = authorityEpoch
        self.revision = revision
        self.latestAuthoritativeSnapshot = latestAuthoritativeSnapshot
        self.detailedActions = detailedActions
        self.completedMatchIds = completedMatchIds
        self.pendingTerminalMessageIds = pendingTerminalMessageIds
    }
}

public protocol LinkClock: Sendable {
    func nowEpochMilliseconds() -> Int64
}

public struct SystemLinkClock: LinkClock {
    public init() {}

    public func nowEpochMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }
}

/// Short-lived retry state for interactive control messages.
public struct LinkControlRetryQueue: Equatable, Sendable {
    public struct PendingItem: Codable, Equatable, Sendable {
        public var messageId: UUID
        public var sessionId: UUID
        public var revision: UInt64
        public var data: Data
        public var attempts: Int
        public var lastSentAtEpochMilliseconds: Int64

        public init(
            messageId: UUID,
            sessionId: UUID,
            revision: UInt64,
            data: Data,
            attempts: Int = 0,
            lastSentAtEpochMilliseconds: Int64
        ) {
            self.messageId = messageId
            self.sessionId = sessionId
            self.revision = revision
            self.data = data
            self.attempts = attempts
            self.lastSentAtEpochMilliseconds = lastSentAtEpochMilliseconds
        }
    }

    public static let retryIntervalMilliseconds: Int64 = 3_000
    public static let maxRetries = 2

    public private(set) var pending: PendingItem?

    public init() {}

    public mutating func enqueue(_ item: PendingItem) {
        pending = item
    }

    public mutating func acknowledge(messageId: UUID) -> Bool {
        guard pending?.messageId == messageId else { return false }
        pending = nil
        return true
    }

    public mutating func clear() {
        pending = nil
    }

    /// Returns data to resend when due; nil if nothing pending or still within interval / exhausted.
    public mutating func retryIfDue(
        nowEpochMilliseconds: Int64,
        retainAfterExhaustion: Bool = false
    ) -> Data? {
        guard var item = pending else { return nil }
        guard nowEpochMilliseconds - item.lastSentAtEpochMilliseconds >= Self.retryIntervalMilliseconds else {
            return nil
        }
        guard item.attempts < Self.maxRetries else {
            if retainAfterExhaustion {
                item.attempts = 0
                item.lastSentAtEpochMilliseconds = nowEpochMilliseconds
                pending = item
                return item.data
            }
            pending = nil
            return nil
        }
        item.attempts += 1
        item.lastSentAtEpochMilliseconds = nowEpochMilliseconds
        pending = item
        return item.data
    }
}

/// A true multi-item outbox for durable terminal messages. Items are keyed by
/// message id and retain their match identity so one match can never overwrite
/// another match in the same linked session.
public struct LinkDurableOutbox: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public let messageId: UUID
        public let handle: LinkedMatchHandle
        public var data: Data
        public var attempts: Int
        public var lastSentAtEpochMilliseconds: Int64

        public init(
            messageId: UUID,
            handle: LinkedMatchHandle,
            data: Data,
            attempts: Int = 0,
            lastSentAtEpochMilliseconds: Int64
        ) {
            self.messageId = messageId
            self.handle = handle
            self.data = data
            self.attempts = attempts
            self.lastSentAtEpochMilliseconds = lastSentAtEpochMilliseconds
        }
    }

    public static let retryIntervalMilliseconds: Int64 = 3_000
    public private(set) var items: [Item]

    public init(items: [Item] = []) {
        var seen = Set<UUID>()
        self.items = items.filter { seen.insert($0.messageId).inserted }
    }

    public var isEmpty: Bool { items.isEmpty }

    public mutating func enqueue(_ item: Item) {
        if let index = items.firstIndex(where: { $0.messageId == item.messageId }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    @discardableResult
    public mutating func acknowledge(messageId: UUID) -> Item? {
        guard let index = items.firstIndex(where: { $0.messageId == messageId }) else {
            return nil
        }
        return items.remove(at: index)
    }

    public func contains(sessionId: UUID, matchId: UUID) -> Bool {
        items.contains {
            $0.handle.sessionId == sessionId && $0.handle.matchId == matchId
        }
    }

    /// Durable terminal messages never expire. Every due item is returned and
    /// retained until an explicit acknowledgement removes it.
    public mutating func retryDue(nowEpochMilliseconds: Int64) -> [Data] {
        var due: [Data] = []
        for index in items.indices {
            guard nowEpochMilliseconds - items[index].lastSentAtEpochMilliseconds
                    >= Self.retryIntervalMilliseconds else { continue }
            items[index].attempts += 1
            items[index].lastSentAtEpochMilliseconds = nowEpochMilliseconds
            due.append(items[index].data)
        }
        return due
    }

    public mutating func removeAll(sessionId: UUID) {
        items.removeAll { $0.handle.sessionId == sessionId }
    }
}

/// A user-requested linked-session end that waits until every terminal message
/// for the same session has been acknowledged.
public struct LinkPendingSessionEnd: Codable, Equatable, Sendable {
    public let handle: LinkedMatchHandle
    public let authorityEpoch: UInt64
    public let revision: UInt64

    public init(
        handle: LinkedMatchHandle,
        authorityEpoch: UInt64,
        revision: UInt64
    ) {
        self.handle = handle
        self.authorityEpoch = authorityEpoch
        self.revision = revision
    }
}

public struct LinkedScoreboardSetup: Codable, Equatable, Sendable {
    public let gameType: GameType
    public let maxSets: Int?
    public let initialSnapshot: LinkedScoreboardSnapshot?
    public let detailedActions: [DetailedScoreAction]
    public let participantNames: [String]
    public let capabilities: Set<LinkCapability>

    public init(
        gameType: GameType,
        maxSets: Int? = nil,
        initialSnapshot: LinkedScoreboardSnapshot? = nil,
        detailedActions: [DetailedScoreAction] = [],
        participantNames: [String] = [],
        capabilities: Set<LinkCapability> = LinkProtocol.capabilities
    ) {
        self.gameType = gameType
        self.maxSets = maxSets
        self.initialSnapshot = initialSnapshot
        self.detailedActions = detailedActions
        self.participantNames = participantNames
        self.capabilities = capabilities
    }
}

public struct LinkEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public let protocolVersion: Int
    public let capabilities: Set<LinkCapability>
    public let messageId: UUID
    public let correlationId: UUID?
    public let sessionId: UUID
    public let matchId: UUID
    public let matchGeneration: UInt64
    public let authorityEpoch: UInt64
    public let kind: LinkMessageKind
    public let sender: LinkPeer
    public let senderSequence: UInt64
    public let sessionRevision: UInt64
    public let sentAtEpochMilliseconds: Int64
    public let payload: Payload

    public init(
        protocolVersion: Int = LinkProtocol.currentVersion,
        capabilities: Set<LinkCapability> = LinkProtocol.capabilities,
        messageId: UUID = UUID(),
        correlationId: UUID? = nil,
        sessionId: UUID,
        matchId: UUID? = nil,
        matchGeneration: UInt64 = 1,
        authorityEpoch: UInt64 = 0,
        kind: LinkMessageKind,
        sender: LinkPeer,
        senderSequence: UInt64,
        sessionRevision: UInt64,
        sentAtEpochMilliseconds: Int64,
        payload: Payload
    ) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.messageId = messageId
        self.correlationId = correlationId
        self.sessionId = sessionId
        self.matchId = matchId ?? sessionId
        self.matchGeneration = max(1, matchGeneration)
        self.authorityEpoch = authorityEpoch
        self.kind = kind
        self.sender = sender
        self.senderSequence = senderSequence
        self.sessionRevision = sessionRevision
        self.sentAtEpochMilliseconds = sentAtEpochMilliseconds
        self.payload = payload
    }

    public var handle: LinkedMatchHandle {
        LinkedMatchHandle(
            sessionId: sessionId,
            matchId: matchId,
            matchGeneration: matchGeneration
        )
    }
}

public struct LinkRevisionGate: Equatable, Sendable {
    public enum Disposition: Equatable, Sendable {
        case newer
        case duplicateOrOlder
        case wrongSession
    }

    public private(set) var activeHandle: LinkedMatchHandle?
    public private(set) var latestRevision: UInt64?

    public var activeSessionId: UUID? { activeHandle?.sessionId }

    public init() {}

    @discardableResult
    public mutating func beginSession(_ sessionId: UUID, initialRevision: UInt64 = 0) -> Bool {
        beginMatch(
            LinkedMatchHandle(sessionId: sessionId, matchId: sessionId),
            initialRevision: initialRevision
        )
    }

    @discardableResult
    public mutating func beginMatch(
        _ handle: LinkedMatchHandle,
        initialRevision: UInt64 = 0
    ) -> Bool {
        guard activeHandle != handle else { return false }
        activeHandle = handle
        latestRevision = initialRevision
        return true
    }

    @discardableResult
    public mutating func accept(sessionId: UUID, revision: UInt64) -> Bool {
        classify(sessionId: sessionId, revision: revision) == .newer
    }

    /// Advances only for a newer value. Receivers should still ACK
    /// `.duplicateOrOlder`: the original ACK may have been lost.
    @discardableResult
    public mutating func classify(sessionId: UUID, revision: UInt64) -> Disposition {
        guard activeHandle?.sessionId == sessionId else { return .wrongSession }
        guard revision > (latestRevision ?? 0) else { return .duplicateOrOlder }
        latestRevision = revision
        return .newer
    }

    @discardableResult
    public mutating func classify(
        handle: LinkedMatchHandle,
        revision: UInt64
    ) -> Disposition {
        guard activeHandle == handle else { return .wrongSession }
        guard revision > (latestRevision ?? 0) else { return .duplicateOrOlder }
        latestRevision = revision
        return .newer
    }

    public mutating func endSession(_ sessionId: UUID) {
        guard activeHandle?.sessionId == sessionId else { return }
        activeHandle = nil
        latestRevision = nil
    }
}

public struct LinkSessionStateMachine: Codable, Equatable, Sendable {
    public enum Lifecycle: String, Codable, Equatable, Sendable {
        case starting
        case active
        case matchFinished
        case ended
    }

    public enum AuthorityTransferKind: String, Codable, Equatable, Sendable {
        case phoneTakeover
        case watchReclaim
        case forcedPhoneTakeover
    }

    public struct PendingAuthorityTransfer: Codable, Equatable, Sendable {
        public let correlationId: UUID
        public let targetRole: LinkControlRole
        public let kind: AuthorityTransferKind
        public let previousEpoch: UInt64
        public private(set) var preparedEpoch: UInt64?

        fileprivate init(
            correlationId: UUID,
            targetRole: LinkControlRole,
            kind: AuthorityTransferKind,
            previousEpoch: UInt64
        ) {
            self.correlationId = correlationId
            self.targetRole = targetRole
            self.kind = kind
            self.previousEpoch = previousEpoch
            preparedEpoch = nil
        }

        fileprivate mutating func prepare(epoch: UInt64) {
            preparedEpoch = epoch
        }
    }

    public enum Validation: Equatable, Sendable {
        case current
        case duplicateOrOlder
        case wrongSession
        case wrongMatch
        case staleAuthority
        case endedSession
    }

    public private(set) var handle: LinkedMatchHandle
    public private(set) var role: LinkControlRole
    public private(set) var authorityEpoch: UInt64
    public private(set) var revision: UInt64
    public private(set) var completedMatchIds: Set<UUID>
    public private(set) var lifecycle: Lifecycle
    public private(set) var setupCorrelationId: UUID?
    public private(set) var pendingAuthorityTransfer: PendingAuthorityTransfer?
    public private(set) var pendingAcknowledgementIds: Set<UUID>

    public init(
        handle: LinkedMatchHandle,
        role: LinkControlRole,
        authorityEpoch: UInt64 = 0,
        revision: UInt64 = 0,
        completedMatchIds: Set<UUID> = [],
        lifecycle: Lifecycle = .active,
        pendingAcknowledgementIds: Set<UUID> = []
    ) {
        self.handle = handle
        self.role = role
        self.authorityEpoch = authorityEpoch
        self.revision = revision
        self.completedMatchIds = completedMatchIds
        self.lifecycle = lifecycle
        setupCorrelationId = nil
        pendingAuthorityTransfer = nil
        self.pendingAcknowledgementIds = pendingAcknowledgementIds
    }

    @discardableResult
    public mutating func beginSetup(correlationId: UUID) -> Bool {
        guard lifecycle != .ended else { return false }
        lifecycle = .starting
        setupCorrelationId = correlationId
        return true
    }

    @discardableResult
    public mutating func resolveSetup(
        correlationId: UUID,
        acceptedRole: LinkControlRole?
    ) -> Bool {
        guard lifecycle == .starting,
              setupCorrelationId == correlationId else { return false }
        setupCorrelationId = nil
        guard let acceptedRole else {
            lifecycle = .ended
            pendingAuthorityTransfer = nil
            return true
        }
        role = acceptedRole
        lifecycle = .active
        return true
    }

    @discardableResult
    public mutating func beginNextMatch(matchId: UUID = UUID()) -> LinkedMatchHandle {
        handle = handle.nextMatch(matchId: matchId)
        revision = 0
        lifecycle = .active
        setupCorrelationId = nil
        pendingAuthorityTransfer = nil
        return handle
    }

    @discardableResult
    public mutating func advanceRevision() -> UInt64 {
        revision += 1
        return revision
    }

    public mutating func accept(
        handle incoming: LinkedMatchHandle,
        authorityEpoch incomingEpoch: UInt64,
        revision incomingRevision: UInt64
    ) -> Validation {
        guard lifecycle != .ended else { return .endedSession }
        guard incoming.sessionId == handle.sessionId else { return .wrongSession }
        guard incomingEpoch >= authorityEpoch else { return .staleAuthority }
        if incoming.matchGeneration < handle.matchGeneration {
            return .wrongMatch
        }
        if incoming.matchGeneration == handle.matchGeneration,
           incoming.matchId != handle.matchId {
            return .wrongMatch
        }
        if incoming.matchGeneration > handle.matchGeneration {
            handle = incoming
            authorityEpoch = incomingEpoch
            revision = incomingRevision
            lifecycle = .active
            setupCorrelationId = nil
            pendingAuthorityTransfer = nil
            return .current
        }
        guard incomingRevision > revision else { return .duplicateOrOlder }
        authorityEpoch = incomingEpoch
        revision = incomingRevision
        return .current
    }

    @discardableResult
    public mutating func transferAuthority(to role: LinkControlRole) -> UInt64 {
        authorityEpoch += 1
        self.role = role
        lifecycle = .active
        pendingAuthorityTransfer = nil
        return authorityEpoch
    }

    public mutating func adoptAuthority(role: LinkControlRole, epoch: UInt64) -> Bool {
        guard lifecycle != .ended else { return false }
        guard epoch >= authorityEpoch else { return false }
        authorityEpoch = epoch
        self.role = role
        lifecycle = .active
        return true
    }

    @discardableResult
    public mutating func beginAuthorityTransfer(
        correlationId: UUID,
        targetRole: LinkControlRole,
        kind: AuthorityTransferKind
    ) -> Bool {
        guard lifecycle != .ended,
              pendingAuthorityTransfer == nil else { return false }
        pendingAuthorityTransfer = PendingAuthorityTransfer(
            correlationId: correlationId,
            targetRole: targetRole,
            kind: kind,
            previousEpoch: authorityEpoch
        )
        return true
    }

    @discardableResult
    public mutating func prepareAuthorityTransfer(
        correlationId: UUID,
        epoch: UInt64
    ) -> Bool {
        guard var pending = pendingAuthorityTransfer,
              pending.correlationId == correlationId,
              epoch > authorityEpoch else { return false }
        pending.prepare(epoch: epoch)
        pendingAuthorityTransfer = pending
        authorityEpoch = epoch
        return true
    }

    @discardableResult
    public mutating func commitAuthorityTransfer(correlationId: UUID) -> Bool {
        guard let pending = pendingAuthorityTransfer,
              pending.correlationId == correlationId,
              let preparedEpoch = pending.preparedEpoch,
              preparedEpoch == authorityEpoch else { return false }
        authorityEpoch = preparedEpoch
        role = pending.targetRole
        lifecycle = .active
        pendingAuthorityTransfer = nil
        return true
    }

    @discardableResult
    public mutating func rejectAuthorityTransfer(correlationId: UUID) -> Bool {
        guard let pending = pendingAuthorityTransfer,
              pending.correlationId == correlationId else {
            return false
        }
        authorityEpoch = pending.previousEpoch
        pendingAuthorityTransfer = nil
        return true
    }

    @discardableResult
    public mutating func forceAuthority(
        to role: LinkControlRole,
        kind: AuthorityTransferKind = .forcedPhoneTakeover
    ) -> UInt64 {
        _ = kind
        authorityEpoch += 1
        self.role = role
        lifecycle = .active
        pendingAuthorityTransfer = nil
        return authorityEpoch
    }

    public mutating func registerPendingAcknowledgement(_ messageId: UUID) {
        pendingAcknowledgementIds.insert(messageId)
    }

    @discardableResult
    public mutating func acknowledge(messageId: UUID) -> Bool {
        pendingAcknowledgementIds.remove(messageId) != nil
    }

    @discardableResult
    public mutating func markFinished(matchId: UUID) -> Bool {
        let inserted = completedMatchIds.insert(matchId).inserted
        if matchId == handle.matchId {
            lifecycle = .matchFinished
        }
        return inserted
    }

    public mutating func endSession() {
        lifecycle = .ended
        setupCorrelationId = nil
        pendingAuthorityTransfer = nil
    }
}

public protocol LinkTransport: Sendable {
    var isReachable: Bool { get }
    func sendRealtime(_ data: Data) async throws
    func publishLatestSnapshot(_ data: Data) throws
    func enqueueDurable(_ data: Data) throws
}

/// Persistence boundary for link resume contexts and durable outboxes.
public protocol LinkDataStore: Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data, forKey key: String)
    func removeObject(forKey key: String)
}

public final class UserDefaultsLinkDataStore: @unchecked Sendable, LinkDataStore {
    public static let standard = UserDefaultsLinkDataStore(defaults: .standard)

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func set(_ data: Data, forKey key: String) {
        defaults.set(data, forKey: key)
    }

    public func removeObject(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}

#if canImport(WatchConnectivity)
public enum WatchConnectivityTransportError: Error, Equatable, Sendable {
    case sessionNotActivated
    case peerNotReachable
}

public struct WatchConnectivityStatus: Equatable, Sendable {
    public let isSupported: Bool
    public let isActivated: Bool
    public let isPaired: Bool
    public let isWatchAppInstalled: Bool
    public let isReachable: Bool

    public init(
        isSupported: Bool,
        isActivated: Bool,
        isPaired: Bool,
        isWatchAppInstalled: Bool,
        isReachable: Bool
    ) {
        self.isSupported = isSupported
        self.isActivated = isActivated
        self.isPaired = isPaired
        self.isWatchAppInstalled = isWatchAppInstalled
        self.isReachable = isReachable
    }

    public var canStartInteractiveSession: Bool {
        isSupported && isActivated && isPaired && isWatchAppInstalled && isReachable
    }
}

/// Complete service-facing transport surface. Production uses
/// `WatchConnectivityTransport`; tests can provide a deterministic fake.
public protocol WatchLinkTransport: AnyObject, LinkTransport {
    var status: WatchConnectivityStatus { get }
    var receivedApplicationContext: [String: Any] { get }

    var onReceive: (@Sendable (Data) -> Void)? { get set }
    var onSendError: (@Sendable (Error) -> Void)? { get set }
    var onStatusChange: (@Sendable (WatchConnectivityStatus) -> Void)? { get set }
    var onApplicationContext: (@Sendable ([String: Any]) -> Void)? { get set }
    var onWatchRecordData: (@Sendable (Data) -> Void)? { get set }
    var onCommonNameUsageData: (@Sendable (Data) -> Void)? { get set }
    var onCommonNameMutationsData: (@Sendable (Data) -> Void)? { get set }
    var onCommonNameMutationAckData: (@Sendable (Data) -> Void)? { get set }

    func activate()
    func refreshStatus()
    func sendInteractive(_ data: Data) throws
    func updateApplicationContext(_ context: [String: Any]) throws
    func transferWatchRecord(_ data: Data) throws
    func transferCommonNameUsage(_ data: Data) throws
    func transferCommonNameMutations(_ data: Data) throws
    func transferCommonNameMutationAcknowledgement(_ data: Data) throws

    /// Phone → Watch: ask the watch for any finished-record transfers it queued but the phone never received.
    func requestPendingWatchRecords()
    /// Watch → Phone: send the queued pending record datas back to the phone.
    func sendPendingWatchRecords(_ datas: [Data])
    /// Phone → Watch: tell the watch to drop the given pending record ids after the phone ingested them.
    func clearPendingWatchRecords(ids: [String])

    /// Watch side: triggered when the phone asks for pending records; respond via `sendPendingWatchRecords`.
    var onCatchUpRequest: (@Sendable () -> Void)? { get set }
    /// Watch side: triggered when the phone confirms ingest of the given ids; drop them from the queue.
    var onClearPendingRequest: (@Sendable ([String]) -> Void)? { get set }
    /// Phone side: invoked when the watch sends back pending record datas.
    var onPendingRecords: (@Sendable ([Data]) -> Void)? { get set }
}

/// A binary transport shared by the phone and Watch targets.
public final class WatchConnectivityTransport: NSObject, @unchecked Sendable, WatchLinkTransport {
    public typealias ReceiveHandler = @Sendable (Data) -> Void
    public typealias DictionaryHandler = @Sendable ([String: Any]) -> Void

    private static let durableLinkPayloadKey = "jifen.link.terminal"
    private static let latestLinkSnapshotContextKey = "jifen.link.latest_snapshot"
    public static let commonNamesContextKey = "jifen.common_names.v1"
    public static let watchRecordUserInfoKey = "jifen.watch_record.v1"
    public static let commonNameUsageUserInfoKey = "jifen.common_name_usage.v1"
    public static let commonNameMutationsUserInfoKey = "jifen.common_name_mutations.v1"
    public static let commonNameMutationAckUserInfoKey = "jifen.common_name_mutation_ack.v1"
    /// Phone → Watch: ask the watch for finished-record transfers it queued but the phone never received.
    public static let catchUpRequestMessageKey = "jifen.link.catch_up_request"
    /// Watch → Phone: queued pending record datas.
    public static let pendingRecordsMessageKey = "jifen.link.pending_records"
    /// Phone → Watch: ids the phone ingested, for the watch to drop from its queue.
    public static let clearPendingMessageKey = "jifen.link.clear_pending"

    private let session: WCSession
    public var onReceive: ReceiveHandler?
    public var onSendError: (@Sendable (Error) -> Void)?
    public var onStatusChange: (@Sendable (WatchConnectivityStatus) -> Void)?
    /// Latest application context from the peer (phone→watch common names, etc.).
    public var onApplicationContext: DictionaryHandler?
    /// Queued watch→phone finished-record payloads.
    public var onWatchRecordData: ReceiveHandler?
    /// Queued watch→phone common-name usage events.
    public var onCommonNameUsageData: ReceiveHandler?
    /// Offline-capable watch→phone common-name edit batches.
    public var onCommonNameMutationsData: ReceiveHandler?
    /// Offline-capable phone→watch canonical results for edit batches.
    public var onCommonNameMutationAckData: ReceiveHandler?
    /// Watch side: phone asked for pending records.
    public var onCatchUpRequest: (@Sendable () -> Void)?
    /// Watch side: phone confirmed ingest of these ids.
    public var onClearPendingRequest: (@Sendable ([String]) -> Void)?
    /// Phone side: watch sent back pending record datas.
    public var onPendingRecords: (@Sendable ([Data]) -> Void)?

    public init(session: WCSession = .default) {
        self.session = session
        super.init()
    }

    public func activate() {
        guard WCSession.isSupported() else {
            reportStatus()
            return
        }
        session.delegate = self
        session.activate()
    }

    /// Re-read WCSession flags and notify listeners (e.g. settings “刷新连接”).
    public func refreshStatus() {
        reportStatus()
    }

    public var status: WatchConnectivityStatus {
        #if os(iOS)
        let isPaired = session.isPaired
        let isWatchAppInstalled = session.isWatchAppInstalled
        #else
        let isPaired = true
        let isWatchAppInstalled = true
        #endif
        return WatchConnectivityStatus(
            isSupported: WCSession.isSupported(),
            isActivated: session.activationState == .activated,
            isPaired: isPaired,
            isWatchAppInstalled: isWatchAppInstalled,
            isReachable: session.isReachable
        )
    }

    /// Current application context received from the peer (may be empty).
    public var receivedApplicationContext: [String: Any] {
        session.receivedApplicationContext
    }

    public var isReachable: Bool {
        status.isReachable
    }

    public func sendRealtime(_ data: Data) async throws {
        guard session.activationState == .activated else {
            throw WatchConnectivityTransportError.sessionNotActivated
        }
        guard session.isReachable else {
            throw WatchConnectivityTransportError.peerNotReachable
        }
        session.sendMessageData(
            data,
            replyHandler: nil,
            errorHandler: { [weak self] error in self?.onSendError?(error) }
        )
    }

    public func publishLatestSnapshot(_ data: Data) throws {
        guard session.activationState == .activated else {
            throw WatchConnectivityTransportError.sessionNotActivated
        }
        var context = session.applicationContext
        context[Self.latestLinkSnapshotContextKey] = data
        try session.updateApplicationContext(context)
    }

    public func enqueueDurable(_ data: Data) throws {
        guard session.activationState == .activated else {
            throw WatchConnectivityTransportError.sessionNotActivated
        }
        session.transferUserInfo([Self.durableLinkPayloadKey: data])
    }

    /// Send only while the counterpart is currently reachable. Used by settings diagnostics.
    public func sendInteractive(_ data: Data) throws {
        guard session.activationState == .activated else {
            throw WatchConnectivityTransportError.sessionNotActivated
        }
        guard session.isReachable else {
            throw WatchConnectivityTransportError.peerNotReachable
        }
        session.sendMessageData(data, replyHandler: nil, errorHandler: nil)
    }

    /// Push a small always-latest dictionary to the peer (used for common-names auto sync).
    public func updateApplicationContext(_ context: [String: Any]) throws {
        guard session.activationState == .activated else {
            throw WatchConnectivityTransportError.sessionNotActivated
        }
        var merged = session.applicationContext
        for (key, value) in context {
            merged[key] = value
        }
        try session.updateApplicationContext(merged)
    }

    /// Queue a finished watch record for delivery even when the peer is not reachable.
    public func transferWatchRecord(_ data: Data) throws {
        #if DEBUG
        print("[LinkCore] transferWatchRecord called, activationState=\(session.activationState.rawValue) size=\(data.count)")
        #endif
        guard session.activationState == .activated else {
            #if DEBUG
            print("[LinkCore] transferWatchRecord skipped: session NOT activated (\(session.activationState.rawValue))")
            #endif
            throw WatchConnectivityTransportError.sessionNotActivated
        }
        session.transferUserInfo([Self.watchRecordUserInfoKey: data])
        #if DEBUG
        print("[LinkCore] transferWatchRecord enqueued userInfo to phone")
        #endif
    }

    /// Queue a name-usage event even if the phone is currently unreachable.
    public func transferCommonNameUsage(_ data: Data) throws {
        guard session.activationState == .activated else {
            throw WatchConnectivityTransportError.sessionNotActivated
        }
        session.transferUserInfo([Self.commonNameUsageUserInfoKey: data])
    }

    public func transferCommonNameMutations(_ data: Data) throws {
        guard session.activationState == .activated else {
            throw WatchConnectivityTransportError.sessionNotActivated
        }
        session.transferUserInfo([Self.commonNameMutationsUserInfoKey: data])
    }

    public func transferCommonNameMutationAcknowledgement(_ data: Data) throws {
        guard session.activationState == .activated else {
            throw WatchConnectivityTransportError.sessionNotActivated
        }
        session.transferUserInfo([Self.commonNameMutationAckUserInfoKey: data])
    }

    /// Phone side: ask the watch for queued finished-record transfers it queued but the phone never received.
    public func requestPendingWatchRecords() {
        #if DEBUG
        print("[LinkCore] requestPendingWatchRecords (phone → watch)")
        #endif
        guard session.activationState == .activated, session.isReachable else {
            #if DEBUG
            print("[LinkCore] requestPendingWatchRecords skipped: activated=\(session.activationState.rawValue) reachable=\(session.isReachable)")
            #endif
            return
        }
        session.sendMessage([Self.catchUpRequestMessageKey: true], replyHandler: nil) { error in
            #if DEBUG
            print("[LinkCore] requestPendingWatchRecords send failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Watch side: respond with the queued pending record datas.
    public func sendPendingWatchRecords(_ datas: [Data]) {
        #if DEBUG
        print("[LinkCore] sendPendingWatchRecords count=\(datas.count) (watch → phone)")
        #endif
        guard session.activationState == .activated, session.isReachable else {
            #if DEBUG
            print("[LinkCore] sendPendingWatchRecords skipped: activated=\(session.activationState.rawValue) reachable=\(session.isReachable)")
            #endif
            return
        }
        session.sendMessage([Self.pendingRecordsMessageKey: datas], replyHandler: nil) { error in
            #if DEBUG
            print("[LinkCore] sendPendingWatchRecords send failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Phone side: tell the watch to drop the given pending ids after the phone ingested them.
    public func clearPendingWatchRecords(ids: [String]) {
        #if DEBUG
        print("[LinkCore] clearPendingWatchRecords ids=\(ids) (phone → watch)")
        #endif
        guard session.activationState == .activated, session.isReachable else {
            #if DEBUG
            print("[LinkCore] clearPendingWatchRecords skipped: activated=\(session.activationState.rawValue) reachable=\(session.isReachable)")
            #endif
            return
        }
        session.sendMessage([Self.clearPendingMessageKey: ids], replyHandler: nil) { error in
            #if DEBUG
            print("[LinkCore] clearPendingWatchRecords send failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func reportStatus() {
        onStatusChange?(status)
    }

    private func deliverApplicationContextIfNeeded() {
        let context = session.receivedApplicationContext
        guard !context.isEmpty else { return }
        if let data = context[Self.latestLinkSnapshotContextKey] as? Data {
            onReceive?(data)
        }
        onApplicationContext?(context)
    }
}

extension WatchConnectivityTransport: WCSessionDelegate {
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        #if DEBUG
        #if !os(watchOS)
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        #else
        let paired = "n/a"
        let installed = "n/a"
        #endif
        print("[LinkCore] activationDidComplete state=\(activationState.rawValue) paired=\(paired) reachable=\(session.isReachable) installed=\(installed) error=\(error?.localizedDescription ?? "nil")")
        #endif
        reportStatus()
        deliverApplicationContextIfNeeded()
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        #if DEBUG
        print("[LinkCore] reachabilityDidChange reachable=\(session.isReachable)")
        #endif
        reportStatus()
    }

    public func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        onReceive?(messageData)
    }

    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        #if DEBUG
        print("[LinkCore] didReceiveMessage keys=\(message.keys.map { String(describing: $0) })")
        #endif
        if message[Self.catchUpRequestMessageKey] != nil {
            onCatchUpRequest?()
            return
        }
        if let ids = message[Self.clearPendingMessageKey] as? [String] {
            onClearPendingRequest?(ids)
            return
        }
        if let datas = message[Self.pendingRecordsMessageKey] as? [Data] {
            onPendingRecords?(datas)
            return
        }
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        #if DEBUG
        print("[LinkCore] didReceiveUserInfo keys=\(userInfo.keys.map { String(describing: $0) })")
        #endif
        if let mutationsData = userInfo[Self.commonNameMutationsUserInfoKey] as? Data {
            onCommonNameMutationsData?(mutationsData)
            return
        }
        if let acknowledgementData = userInfo[Self.commonNameMutationAckUserInfoKey] as? Data {
            onCommonNameMutationAckData?(acknowledgementData)
            return
        }
        if let usageData = userInfo[Self.commonNameUsageUserInfoKey] as? Data {
            onCommonNameUsageData?(usageData)
            return
        }
        if let recordData = userInfo[Self.watchRecordUserInfoKey] as? Data {
            #if DEBUG
            print("[LinkCore] didReceiveUserInfo: watchRecordUserInfoKey, size=\(recordData.count)")
            #endif
            onWatchRecordData?(recordData)
            return
        }
        guard let data = userInfo[Self.durableLinkPayloadKey] as? Data else { return }
        onReceive?(data)
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext[Self.latestLinkSnapshotContextKey] as? Data {
            onReceive?(data)
        }
        onApplicationContext?(applicationContext)
    }

#if os(iOS)
    public func sessionWatchStateDidChange(_ session: WCSession) {
        reportStatus()
    }

    public func sessionDidBecomeInactive(_ session: WCSession) {}

    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
#endif
}
#endif
