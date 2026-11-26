import Foundation
import RecordCore
import ScoreCore

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

public enum LinkProtocol {
    public static let currentVersion = 1
    /// Oldest peer protocol version this build accepts in a handshake.
    public static let minimumSupportedVersion = 1

    /// Capabilities every peer must advertise before a linked session starts.
    public static let requiredCapabilities: Set<LinkCapability> = [
        .independentMatches,
        .correlatedRequests,
        .durableTerminalQueue
    ]

    /// `applicationContext` common-names partition byte budget (see
    /// `CommonNamesSyncSnapshot.budgetConstrainedData`).
    public static let commonNamesContextBudgetBytes = 24_000

    /// Everything this build understands. Handshakes intersect both sides so
    /// older peers keep working and newer additions degrade gracefully.
    public static let capabilities: Set<LinkCapability> = [
        .independentMatches,
        .correlatedRequests,
        .durableTerminalQueue,
        .latestSnapshotContext,
        .compressedFinish,
        .deltaActions,
        .fileTransfer
    ]

    /// Open-subset handshake check: required capabilities must all be present,
    /// unknown extra capabilities from a newer peer are tolerated (and simply
    /// unused by this build). Returns the negotiated intersection.
    public static func negotiate(
        local: Set<LinkCapability>,
        peer: Set<LinkCapability>
    ) -> Set<LinkCapability>? {
        guard requiredCapabilities.isSubset(of: peer) else { return nil }
        return local.intersection(peer)
    }
}

/// Open capability token. Unlike the previous closed enum, unknown values from
/// a future peer decode fine and stay inert; capability sets are compared as
/// string subsets, never by exhaustive equality.
public struct LinkCapability: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public static let independentMatches = Self(rawValue: "independentMatches")
    public static let correlatedRequests = Self(rawValue: "correlatedRequests")
    public static let durableTerminalQueue = Self(rawValue: "durableTerminalQueue")
    public static let latestSnapshotContext = Self(rawValue: "latestSnapshotContext")
    public static let compressedFinish = Self(rawValue: "compressedFinish")
    public static let deltaActions = Self(rawValue: "deltaActions")
    public static let fileTransfer = Self(rawValue: "fileTransfer")
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

public struct LinkSharedEditTracker: Sendable {
    private struct Edit: Sendable {
        let handle: LinkedMatchHandle
        let revision: UInt64
        let baseRevision: UInt64
        let sentAt: Int64
    }

    private var localEdit: Edit?
    private var lastNoticedRevision: UInt64?

    public init() {}

    public mutating func recordLocalEdit(
        handle: LinkedMatchHandle,
        revision: UInt64,
        baseRevision: UInt64,
        sentAt: Int64
    ) {
        localEdit = Edit(handle: handle, revision: revision, baseRevision: baseRevision, sentAt: sentAt)
        lastNoticedRevision = nil
    }

    public mutating func shouldShowNotice(
        for envelope: LinkEnvelope<LinkedScoreboardSetup>,
        now: Int64
    ) -> Bool {
        guard let localEdit, let baseRevision = envelope.baseSnapshotRevision,
              localEdit.handle == envelope.handle,
              envelope.sessionRevision > localEdit.baseRevision,
              baseRevision < localEdit.revision,
              lastNoticedRevision != localEdit.revision,
              abs(Double(envelope.sentAtEpochMilliseconds) - Double(localEdit.sentAt)) <= 2_000,
              abs(Double(now) - Double(envelope.sentAtEpochMilliseconds)) <= 2_000 else { return false }
        lastNoticedRevision = localEdit.revision
        return true
    }
}

public enum LinkSharedRevision {
    public static func writer(of revision: UInt64) -> LinkPeer? {
        guard revision > 0 else { return nil }
        return revision.isMultiple(of: 2) ? .watch : .phone
    }
}

/// Manual score resync is bidirectional in a shared session: either device may
/// ask the peer for a fresh full snapshot, and either device answers.
public enum LinkManualResyncPolicy {
    public static func canRequest(hasActiveSession: Bool) -> Bool {
        hasActiveSession
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
    case matchFinished
    case recordAcknowledgement
    case scoreboardExitedToHome
    case sessionLeft
    case commonNamesSyncRequest
    case connectivityProbe
    case connectivityProbeResponse
}

/// Why a setup request was refused. The phone surfaces the reason so the
/// start dialog can tell a version mismatch from a user decline.
public enum LinkSetupRejectionReason: String, Codable, Equatable, Sendable {
    case userDeclined = "user_declined"
    case unsupportedSport = "unsupported_sport"
    case incompatibleProtocol = "incompatible_protocol"
    case malformedSetup = "malformed_setup"
}

public struct LinkSetupRejectedPayload: Codable, Equatable, Sendable {
    public let reason: LinkSetupRejectionReason
    public let detail: String?

    public init(reason: LinkSetupRejectionReason = .userDeclined, detail: String? = nil) {
        self.reason = reason
        self.detail = detail
    }
}

/// Metadata for files queued through `transferFile` on the reliable channel.
public enum WatchTransferFileKind: String, Codable, Sendable {
    case watchRecord = "watch_record"
    case matchFinished = "match_finished"
}

/// Linked snapshots carry the reducer state itself. Football therefore travels
/// as the complete `FootballMatchState`: goal counts, half/stage, the wall-clock
/// anchor (`timer.savedWallClockMilliseconds`), the carried minute/second
/// remainder (`elapsedSubsecondMilliseconds`), regulation/extra lengths,
/// stoppage history, kick-off, side swap and finish flags. Anything less cannot
/// rebuild the same clock on the other device.
public enum LinkedScoreboardSnapshot: Codable, Equatable, Sendable {
    case rally(RallyMatchState)
    case tennis(TennisMatchState)
    case archery(ArcheryMatchState)
    case eightBall(EightBallState)
    case nineBall(NineBallChaseState)
    case snooker(SnookerState)
    case football(FootballMatchState)
    case basketballTraining(ShotTrainingState)

    private enum CodingKeys: String, CodingKey {
        case kind
        case rally
        case tennis
        case archery
        case eightBall
        case nineBall
        case snooker
        case football
        case basketballTraining
    }

    private enum Kind: String, Codable {
        case rally
        case tennis
        case archery
        case eightBall
        case nineBall
        case snooker
        case football
        case basketballTraining
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .rally:
            self = .rally(try container.decode(RallyMatchState.self, forKey: .rally))
        case .tennis:
            self = .tennis(try container.decode(TennisMatchState.self, forKey: .tennis))
        case .archery:
            self = .archery(try container.decode(ArcheryMatchState.self, forKey: .archery))
        case .eightBall:
            self = .eightBall(try container.decode(EightBallState.self, forKey: .eightBall))
        case .nineBall:
            self = .nineBall(try container.decode(NineBallChaseState.self, forKey: .nineBall))
        case .snooker:
            self = .snooker(try container.decode(SnookerState.self, forKey: .snooker))
        case .football:
            self = .football(try container.decode(FootballMatchState.self, forKey: .football))
        case .basketballTraining:
            self = .basketballTraining(try container.decode(ShotTrainingState.self, forKey: .basketballTraining))
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
        case .football(let state):
            try container.encode(Kind.football, forKey: .kind)
            try container.encode(state, forKey: .football)
        case .basketballTraining(let state):
            try container.encode(Kind.basketballTraining, forKey: .kind)
            try container.encode(state, forKey: .basketballTraining)
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

    public var archeryState: ArcheryMatchState? {
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

    public var footballState: FootballMatchState? {
        guard case .football(let state) = self else { return nil }
        return state
    }

    public var basketballTrainingState: ShotTrainingState? {
        guard case .basketballTraining(let state) = self else { return nil }
        return state
    }

    /// Whether the carried match state is finished. The finish flag is part of
    /// every synced state, so the phone can mirror the HarmonyOS behavior of
    /// treating any received finished snapshot as authoritative for the finish
    /// dialog regardless of delivery order or revision.
    public func matches(gameType: GameType) -> Bool {
        WatchSportRegistry.matchesSnapshot(self, for: gameType)
    }

    public var isFinished: Bool {
        switch self {
        case .rally(let state): return state.finished
        case .tennis(let state): return state.finished
        case .archery(let state): return state.finished
        case .eightBall(let state): return state.finished
        case .nineBall(let state): return state.finished
        case .snooker(let state): return state.finished
        case .football(let state): return state.finished
        case .basketballTraining(let state): return state.finished
        }
    }
}


public struct EmptyLinkPayload: Codable, Equatable, Sendable {
    public init() {}
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
    public var revision: UInt64
    public var reachable: Bool
    public var capabilities: Set<LinkCapability>

    public init(
        revision: UInt64,
        reachable: Bool = true,
        capabilities: Set<LinkCapability> = LinkProtocol.capabilities
    ) {
        self.revision = revision
        self.reachable = reachable
        self.capabilities = capabilities
    }
}

public struct PhoneLinkResumeContext: Codable, Equatable, Sendable {
    public var handle: LinkedMatchHandle
    public var setup: LinkedScoreboardSetup
    public var revision: UInt64
    public var latestAuthoritativeSnapshot: LinkedScoreboardSnapshot?
    public var detailedActions: [DetailedScoreAction]
    public var completedMatchIds: Set<UUID>
    public var pendingTerminalMessageIds: Set<UUID>
    public var peerSupportsCompressedFinish: Bool?
    public var finishedRecordId: String?
    /// Capability intersection agreed at handshake, persisted so restored
    /// sessions keep routing to the same channels.
    public var negotiatedPeerCapabilities: Set<LinkCapability>?
    public var actionHistory: LinkSnapshotHistory?

    public init(
        handle: LinkedMatchHandle,
        setup: LinkedScoreboardSetup,
        revision: UInt64,
        latestAuthoritativeSnapshot: LinkedScoreboardSnapshot?,
        detailedActions: [DetailedScoreAction],
        completedMatchIds: Set<UUID>,
        pendingTerminalMessageIds: Set<UUID>,
        finishedRecordId: String? = nil,
        peerSupportsCompressedFinish: Bool? = nil,
        negotiatedPeerCapabilities: Set<LinkCapability>? = nil,
        actionHistory: LinkSnapshotHistory? = nil
    ) {
        self.handle = handle
        self.setup = setup
        self.revision = revision
        self.latestAuthoritativeSnapshot = latestAuthoritativeSnapshot
        self.detailedActions = detailedActions
        self.completedMatchIds = completedMatchIds
        self.pendingTerminalMessageIds = pendingTerminalMessageIds
        self.peerSupportsCompressedFinish = peerSupportsCompressedFinish
        self.finishedRecordId = finishedRecordId
        self.negotiatedPeerCapabilities = negotiatedPeerCapabilities
        self.actionHistory = actionHistory
    }
}

public struct WatchLinkResumeContext: Codable, Equatable, Sendable {
    public var handle: LinkedMatchHandle
    public var setup: LinkedScoreboardSetup
    public var revision: UInt64
    public var latestAuthoritativeSnapshot: LinkedScoreboardSnapshot?
    public var detailedActions: [DetailedScoreAction]
    public var completedMatchIds: Set<UUID>
    public var pendingTerminalMessageIds: Set<UUID>
    public var peerSupportsCompressedFinish: Bool?
    /// Capability intersection agreed at handshake, persisted so restored
    /// sessions keep routing to the same channels.
    public var negotiatedPeerCapabilities: Set<LinkCapability>?
    public var actionHistory: LinkSnapshotHistory?

    public init(
        handle: LinkedMatchHandle,
        setup: LinkedScoreboardSetup,
        revision: UInt64,
        latestAuthoritativeSnapshot: LinkedScoreboardSnapshot?,
        detailedActions: [DetailedScoreAction],
        completedMatchIds: Set<UUID>,
        pendingTerminalMessageIds: Set<UUID>,
        peerSupportsCompressedFinish: Bool? = nil,
        negotiatedPeerCapabilities: Set<LinkCapability>? = nil,
        actionHistory: LinkSnapshotHistory? = nil
    ) {
        self.handle = handle
        self.setup = setup
        self.revision = revision
        self.latestAuthoritativeSnapshot = latestAuthoritativeSnapshot
        self.detailedActions = detailedActions
        self.completedMatchIds = completedMatchIds
        self.pendingTerminalMessageIds = pendingTerminalMessageIds
        self.peerSupportsCompressedFinish = peerSupportsCompressedFinish
        self.negotiatedPeerCapabilities = negotiatedPeerCapabilities
        self.actionHistory = actionHistory
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
        retainAfterExhaustion: Bool = false,
        sendImmediately: Bool = false
    ) -> Data? {
        guard var item = pending else { return nil }
        guard sendImmediately || nowEpochMilliseconds - item.lastSentAtEpochMilliseconds >= Self.retryIntervalMilliseconds else {
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
    public struct LocalRecord: Codable, Equatable, Sendable {
        public let gameType: GameType
        public let payload: LinkMatchFinishedPayload

        public init(gameType: GameType, payload: LinkMatchFinishedPayload) {
            self.gameType = gameType
            self.payload = payload
        }
    }

    public struct Item: Codable, Equatable, Sendable {
        public let messageId: UUID
        public let handle: LinkedMatchHandle
        public var data: Data
        public var attempts: Int
        public var lastSentAtEpochMilliseconds: Int64
        public var pendingLocalRecord: LocalRecord?
        /// Negotiated file-transfer snapshot captured at enqueue time. Retries
        /// after a next-match transition or app restart route by this value —
        /// never by whichever session happens to be active now.
        public var peerSupportsFileTransfer: Bool?

        public init(
            messageId: UUID,
            handle: LinkedMatchHandle,
            data: Data,
            attempts: Int = 0,
            lastSentAtEpochMilliseconds: Int64,
            pendingLocalRecord: LocalRecord? = nil,
            peerSupportsFileTransfer: Bool? = nil
        ) {
            self.messageId = messageId
            self.handle = handle
            self.data = data
            self.attempts = attempts
            self.lastSentAtEpochMilliseconds = lastSentAtEpochMilliseconds
            self.pendingLocalRecord = pendingLocalRecord
            self.peerSupportsFileTransfer = peerSupportsFileTransfer
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

    public mutating func markLocalRecordSaved(messageId: UUID) {
        guard let index = items.firstIndex(where: { $0.messageId == messageId }) else { return }
        items[index].pendingLocalRecord = nil
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

    /// Same retry bookkeeping as `retryDue`, returning the full items so the
    /// caller can route each frame by its own negotiated-capability snapshot.
    public mutating func retryDueItems(nowEpochMilliseconds: Int64) -> [Item] {
        var due: [Item] = []
        for index in items.indices {
            guard nowEpochMilliseconds - items[index].lastSentAtEpochMilliseconds
                    >= Self.retryIntervalMilliseconds else { continue }
            items[index].attempts += 1
            items[index].lastSentAtEpochMilliseconds = nowEpochMilliseconds
            due.append(items[index])
        }
        return due
    }

    public mutating func removeAll(sessionId: UUID) {
        items.removeAll { $0.handle.sessionId == sessionId }
    }
}

/// The record metadata needed after the live session has been replaced.
public struct LinkRecordSession: Codable, Sendable {
    public let handle: LinkedMatchHandle
    public let gameType: GameType
    public fileprivate(set) var completedMatchIds: Set<UUID>
    public let allowsPeerNextMatch: Bool?

    public init(
        handle: LinkedMatchHandle,
        gameType: GameType,
        completedMatchIds: Set<UUID>,
        allowsPeerNextMatch: Bool? = nil
    ) {
        self.handle = handle
        self.gameType = gameType
        self.completedMatchIds = completedMatchIds
        self.allowsPeerNextMatch = allowsPeerNextMatch
    }

    public func accepts(handle incoming: LinkedMatchHandle) -> Bool {
        guard incoming.sessionId == handle.sessionId else { return false }
        if incoming.matchGeneration < handle.matchGeneration { return true }
        if incoming.matchGeneration > handle.matchGeneration {
            return allowsPeerNextMatch == true
        }
        return incoming == handle
    }
}

/// Terminal retries can outlive both the live session and the app process.
public struct LinkRetiredRecordSessions: Sendable {
    private static let key = "link_retired_record_sessions"
    private let store: any LinkDataStore
    private var sessions: [UUID: LinkRecordSession]

    public init(store: any LinkDataStore) {
        self.store = store
        sessions = store.data(forKey: Self.key).flatMap {
            try? JSONDecoder().decode([UUID: LinkRecordSession].self, from: $0)
        } ?? [:]
    }

    public subscript(sessionId: UUID) -> LinkRecordSession? { sessions[sessionId] }

    public mutating func retire(_ session: LinkRecordSession) {
        let id = session.handle.sessionId
        var retained = session
        if let existing = sessions[id] {
            if existing.handle.matchGeneration > session.handle.matchGeneration {
                retained = existing
            }
            retained.completedMatchIds.formUnion(existing.completedMatchIds)
            retained.completedMatchIds.formUnion(session.completedMatchIds)
        }
        sessions[id] = retained
        persist()
    }

    public mutating func markFinished(_ handle: LinkedMatchHandle) {
        guard var session = sessions[handle.sessionId] else { return }
        session.completedMatchIds.insert(handle.matchId)
        if handle.matchGeneration > session.handle.matchGeneration {
            session = LinkRecordSession(
                handle: handle, gameType: session.gameType,
                completedMatchIds: session.completedMatchIds, allowsPeerNextMatch: session.allowsPeerNextMatch
            )
        }
        sessions[handle.sessionId] = session
        persist()
    }

    public mutating func removeConfirmedSession(handle: LinkedMatchHandle) {
        guard let session = sessions[handle.sessionId], session.handle == handle else { return }
        sessions.removeValue(forKey: handle.sessionId)
        persist()
    }

    public mutating func clear() {
        sessions.removeAll()
        store.removeObject(forKey: Self.key)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sessions) {
            store.set(data, forKey: Self.key)
        }
    }
}

/// A user-requested linked-session end that waits until every terminal message
/// for the same session has been acknowledged.
public struct LinkPendingSessionEnd: Codable, Equatable, Sendable {
    public let handle: LinkedMatchHandle
    public let revision: UInt64

    public init(
        handle: LinkedMatchHandle,
        revision: UInt64
    ) {
        self.handle = handle
        self.revision = revision
    }
}

public struct LinkedScoreboardSetup: Codable, Equatable, Sendable {
    public let gameType: GameType
    public let maxSets: Int?
    public let initialSnapshot: LinkedScoreboardSnapshot?
    /// `var` so send sites can trim the tail below the WCSession payload limit
    /// before encoding (receivers merge actions by id and never shrink their
    /// local union, so dropping the oldest tail is safe for live sync).
    public var detailedActions: [DetailedScoreAction]
    public let participantNames: [String]
    public let capabilities: Set<LinkCapability>
    /// `true` marks append-only actions. `false` marks a history correction.
    /// Only explicitly removed IDs are deleted, even if history spans several frames.
    public var isDeltaActions: Bool?
    public var removedActionIDs: [UUID]?

    public var carriesHistory: Bool {
        !detailedActions.isEmpty || removedActionIDs?.isEmpty == false
    }

    public init(
        gameType: GameType,
        maxSets: Int? = nil,
        initialSnapshot: LinkedScoreboardSnapshot? = nil,
        detailedActions: [DetailedScoreAction] = [],
        participantNames: [String] = [],
        capabilities: Set<LinkCapability> = LinkProtocol.capabilities,
        isDeltaActions: Bool? = nil,
        removedActionIDs: [UUID]? = nil
    ) {
        self.gameType = gameType
        self.maxSets = maxSets
        self.initialSnapshot = initialSnapshot
        self.detailedActions = detailedActions
        self.participantNames = participantNames
        self.capabilities = capabilities
        self.isDeltaActions = isDeltaActions
        self.removedActionIDs = removedActionIDs
    }
}

public struct LinkEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public let protocolVersion: Int
    public let capabilities: Set<LinkCapability>
    public let supportsCompressedFinish: Bool?
    public let baseSnapshotRevision: UInt64?
    public let messageId: UUID
    public let correlationId: UUID?
    public let sessionId: UUID
    public let matchId: UUID
    public let matchGeneration: UInt64
    public let kind: LinkMessageKind
    public let sender: LinkPeer
    public let senderSequence: UInt64
    public let sessionRevision: UInt64
    public let sentAtEpochMilliseconds: Int64
    public var payload: Payload

    public init(
        protocolVersion: Int = LinkProtocol.currentVersion,
        capabilities: Set<LinkCapability> = LinkProtocol.capabilities,
        supportsCompressedFinish: Bool? = nil,
        baseSnapshotRevision: UInt64? = nil,
        messageId: UUID = UUID(),
        correlationId: UUID? = nil,
        sessionId: UUID,
        matchId: UUID? = nil,
        matchGeneration: UInt64 = 1,
        kind: LinkMessageKind,
        sender: LinkPeer,
        senderSequence: UInt64,
        sessionRevision: UInt64,
        sentAtEpochMilliseconds: Int64,
        payload: Payload
    ) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.supportsCompressedFinish = supportsCompressedFinish
        self.baseSnapshotRevision = baseSnapshotRevision
        self.messageId = messageId
        self.correlationId = correlationId
        self.sessionId = sessionId
        self.matchId = matchId ?? sessionId
        self.matchGeneration = max(1, matchGeneration)
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

public struct LinkEnvelopeHead: Decodable, Sendable {
    public let protocolVersion: Int
    public let messageId: UUID
    public let correlationId: UUID?
    public let sessionId: UUID
    public let matchId: UUID
    public let matchGeneration: UInt64
    public let kind: LinkMessageKind
    public let sender: LinkPeer
    public let sessionRevision: UInt64
}

/// WCSession raises an Objective-C exception for payloads above 65,536 bytes
/// (it does not surface a Swift error), so every send site must stay well below
/// the limit before handing data to the transport. This helper encodes an
/// envelope and, when it would exceed `byteLimit`, drops the oldest detailed
/// actions by halving until it fits. Receivers merge actions by id and never
/// shrink their local union, so trimming the oldest tail never loses state;
/// full history still travels with the terminal matchFinished payload, which
/// is trimmed only as a last resort so delivery always wins over fidelity.
public enum LinkEnvelopeEncoding {
    public static let defaultByteLimit = 60_000

    /// 泛型分派入口：已知携带 detailedActions 的 payload 类型按各自字段裁剪，
    /// 其余直接编码。发送层统一走这里，避免逐调用点遗漏新增信封类型。
    public static func encodedData<Payload: Codable & Sendable>(
        _ envelope: LinkEnvelope<Payload>
    ) -> Data {
        if let setupEnvelope = envelope as? LinkEnvelope<LinkedScoreboardSetup> {
            return data(setupEnvelope, actionsKeyPath: \.detailedActions)
        }
        if let finishedEnvelope = envelope as? LinkEnvelope<LinkMatchFinishedPayload> {
            return data(finishedEnvelope, actionsKeyPath: \.detailedActions)
        }
        if let ackEnvelope = envelope as? LinkEnvelope<LinkAcknowledgementPayload> {
            return data(ackEnvelope, actionsKeyPath: \.detailedActions)
        }
        return data(envelope)
    }

    /// `WCSession.applicationContext` 与常用名称表共享 65,536 字节上限：
    /// 兜底快照只保留最新比分/规则状态，剥离 `detailedActions`（完整动作历史由
    /// `sendMessageData` 实时通道和 `matchFinished` 完赛通道传递，接收端按 id 并集合并）。
    /// applicationContext 分区的轻量快照：剥离动作历史，并**重写 messageId**。
    /// 轻量帧与实时帧必须使用不同 id：对端对轻量帧的回执不得清空实时帧的
    /// pendingAck 与增量动作台账（轻量帧不含动作，从未把它们送达对端）。
    public static func applicationContextData(
        _ envelope: LinkEnvelope<LinkedScoreboardSetup>
    ) -> Data {
        var stripped = envelope
        stripped.payload.detailedActions = []
        // checkpoint 不是权威替换帧：清除 delta 标记，接收端绝不会把
        // 空检查点误当替换处理（替换帧随后同 revision 到达时才做替换）。
        stripped.payload.isDeltaActions = nil
        stripped.payload.removedActionIDs = nil
        return data(Self.checkpointEnvelope(stripped))
    }

    /// 复制信封并分配全新 messageId（其余字段原样，供 context 帧独立回执）。
    public static func checkpointEnvelope<Payload: Codable & Sendable>(
        _ envelope: LinkEnvelope<Payload>
    ) -> LinkEnvelope<Payload> {
        LinkEnvelope(
            protocolVersion: envelope.protocolVersion,
            capabilities: envelope.capabilities,
            supportsCompressedFinish: envelope.supportsCompressedFinish,
            baseSnapshotRevision: envelope.baseSnapshotRevision,
            messageId: UUID(),
            correlationId: envelope.correlationId,
            sessionId: envelope.sessionId,
            matchId: envelope.matchId,
            matchGeneration: envelope.matchGeneration,
            kind: envelope.kind,
            sender: envelope.sender,
            senderSequence: envelope.senderSequence,
            sessionRevision: envelope.sessionRevision,
            sentAtEpochMilliseconds: envelope.sentAtEpochMilliseconds,
            payload: envelope.payload
        )
    }

    public static func applicationContextData<Payload: Codable & Sendable>(
        _ envelope: LinkEnvelope<Payload>
    ) -> Data {
        if let setupEnvelope = envelope as? LinkEnvelope<LinkedScoreboardSetup> {
            return applicationContextData(setupEnvelope)
        }
        if var finishedEnvelope = envelope as? LinkEnvelope<LinkMatchFinishedPayload> {
            finishedEnvelope.payload.detailedActions = []
            return data(Self.checkpointEnvelope(finishedEnvelope))
        }
        if var ackEnvelope = envelope as? LinkEnvelope<LinkAcknowledgementPayload> {
            ackEnvelope.payload.detailedActions = []
            return data(ackEnvelope)
        }
        return data(envelope)
    }

    public static func data<Payload: Codable & Sendable>(
        _ envelope: LinkEnvelope<Payload>,
        actionsKeyPath: WritableKeyPath<Payload, [DetailedScoreAction]>? = nil,
        byteLimit: Int = defaultByteLimit
    ) -> Data {
        guard let full = try? JSONEncoder().encode(envelope) else { return Data() }
        guard let keyPath = actionsKeyPath, full.count > byteLimit else { return full }
        var candidate = envelope
        var actions = candidate.payload[keyPath: keyPath]
        while !actions.isEmpty {
            actions.removeFirst(max(1, actions.count / 2))
            candidate.payload[keyPath: keyPath] = actions
            if let data = try? JSONEncoder().encode(candidate), data.count <= byteLimit {
                return data
            }
        }
        candidate.payload[keyPath: keyPath] = []
        return (try? JSONEncoder().encode(candidate)) ?? full
    }

    /// 与 `data(_:actionsKeyPath:byteLimit:)` 相同的编码与裁剪，返回最终 Data 与
    /// **严格从最终 Data 解码得到**的实际上线动作（不按字节长度推断）。被预算
    /// 裁剪掉的动作不进入发送台账，回执无法误清欠账；后续帧继续补发。
    public struct SnapshotFrame {
        public let data: Data
        public let actions: [DetailedScoreAction]
        public let removedActionIDs: [UUID]

        public var carriesHistory: Bool { !actions.isEmpty || !removedActionIDs.isEmpty }
    }

    public static func snapshotFrame(
        _ envelope: LinkEnvelope<LinkedScoreboardSetup>,
        byteLimit: Int = defaultByteLimit
    ) -> SnapshotFrame {
        var candidate = envelope
        let encoder = JSONEncoder()
        var encoded = data(candidate, actionsKeyPath: \.detailedActions, byteLimit: byteLimit)
        // A correction can contain more removals than will fit even without
        // additions. The ACK records exactly the removals carried in this batch.
        if encoded.count > byteLimit {
            candidate.payload.detailedActions = []
            while let removals = candidate.payload.removedActionIDs, !removals.isEmpty {
                let remaining = removals.prefix(removals.count / 2)
                candidate.payload.removedActionIDs = remaining.isEmpty ? nil : Array(remaining)
                encoded = (try? encoder.encode(candidate)) ?? Data()
                if encoded.count <= byteLimit { break }
            }
        }
        guard !encoded.isEmpty, encoded.count <= byteLimit,
              let wire = try? JSONDecoder().decode(LinkEnvelope<LinkedScoreboardSetup>.self, from: encoded)
        else { return SnapshotFrame(data: Data(), actions: [], removedActionIDs: []) }
        return SnapshotFrame(data: encoded, actions: wire.payload.detailedActions, removedActionIDs: wire.payload.removedActionIDs ?? [])
    }

    public static func dataWithSentActions(
        _ envelope: LinkEnvelope<LinkedScoreboardSetup>,
        byteLimit: Int = defaultByteLimit
    ) -> (data: Data, sentActions: [DetailedScoreAction]) {
        let frame = snapshotFrame(envelope, byteLimit: byteLimit)
        return (frame.data, frame.actions)
    }
}

/// Groups queued record payloads into batches whose total size stays below the
/// WCSession per-message limit, so flushing many queued finished records never
/// exceeds 65,536 bytes in one `sendMessage`. A single oversized item becomes
/// its own batch; the caller decides whether that item can be delivered at all.
public enum LinkPendingRecordChunking {
    public static let defaultBatchBytes = 55_000

    public static func chunk(
        _ datas: [Data],
        maxBytes: Int = defaultBatchBytes
    ) -> [[Data]] {
        var batches: [[Data]] = []
        var current: [Data] = []
        var currentBytes = 0
        for data in datas {
            if !current.isEmpty, currentBytes + data.count > maxBytes {
                batches.append(current)
                current = []
                currentBytes = 0
            }
            current.append(data)
            currentBytes += data.count
        }
        if !current.isEmpty { batches.append(current) }
        return batches
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

    public enum Validation: Equatable, Sendable {
        case current
        case duplicateOrOlder
        case wrongSession
        case wrongMatch
        case endedSession
    }

    public private(set) var handle: LinkedMatchHandle
    public private(set) var revision: UInt64
    public private(set) var completedMatchIds: Set<UUID>
    public private(set) var lifecycle: Lifecycle
    public private(set) var setupCorrelationId: UUID?
    public private(set) var pendingAcknowledgementIds: Set<UUID>

    public init(
        handle: LinkedMatchHandle,
        revision: UInt64 = 0,
        completedMatchIds: Set<UUID> = [],
        lifecycle: Lifecycle = .active,
        pendingAcknowledgementIds: Set<UUID> = []
    ) {
        self.handle = handle
        self.revision = revision
        self.completedMatchIds = completedMatchIds
        self.lifecycle = lifecycle
        setupCorrelationId = nil
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
        accepted: Bool
    ) -> Bool {
        guard lifecycle == .starting,
              setupCorrelationId == correlationId else { return false }
        setupCorrelationId = nil
        guard accepted else {
            lifecycle = .ended
            return true
        }
        lifecycle = .active
        return true
    }

    @discardableResult
    public mutating func beginNextMatch(matchId: UUID = UUID()) -> LinkedMatchHandle {
        handle = handle.nextMatch(matchId: matchId)
        revision = 0
        lifecycle = .active
        setupCorrelationId = nil
        // 新一场比赛的 ACK 属于旧 matchId，不再等待。
        pendingAcknowledgementIds = []
        return handle
    }

    @discardableResult
    public mutating func advanceRevision(sender: LinkPeer? = nil) -> UInt64 {
        if let sender {
            // Each edit advances the logical round. Same-round edits have a
            // stable order on both peers without relying on device clocks.
            let round = revision / 2 + revision % 2
            revision = round * 2 + (sender == .phone ? 1 : 2)
        } else {
            revision += 1
        }
        return revision
    }

    public mutating func accept(
        handle incoming: LinkedMatchHandle,
        revision incomingRevision: UInt64
    ) -> Validation {
        guard lifecycle != .ended else { return .endedSession }
        guard incoming.sessionId == handle.sessionId else { return .wrongSession }
        if incoming.matchGeneration < handle.matchGeneration {
            return .wrongMatch
        }
        if incoming.matchGeneration == handle.matchGeneration,
           incoming.matchId != handle.matchId {
            return .wrongMatch
        }
        if incoming.matchGeneration > handle.matchGeneration {
            handle = incoming
            revision = incomingRevision
            lifecycle = .active
            setupCorrelationId = nil
            return .current
        }
        guard incomingRevision > revision else { return .duplicateOrOlder }
        revision = incomingRevision
        return .current
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
        pendingAcknowledgementIds = []
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
    /// Throwing variants are real requirements (NOT extension defaults): every
    /// call through `any LinkDataStore` must surface the concrete store's write
    /// failure, so terminal-queue persistence gates on the real disk result.
    func setOrThrow(_ data: Data, forKey key: String) throws
    @discardableResult
    func removeOrThrow(forKey key: String) throws -> Bool
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

    public func setOrThrow(_ data: Data, forKey key: String) throws {
        defaults.set(data, forKey: key)
    }

    @discardableResult
    public func removeOrThrow(forKey key: String) throws -> Bool {
        let existed = defaults.data(forKey: key) != nil
        defaults.removeObject(forKey: key)
        return existed
    }
}

#if canImport(WatchConnectivity)
public enum WatchConnectivityTransportError: Error, Equatable, Sendable {
    case sessionNotActivated
    case peerNotReachable
    /// WCSession raises a native exception for payloads above 65,536 bytes;
    /// transports throw this Swift error instead so callers degrade gracefully.
    case payloadTooLarge(Int)
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
    var onCommonNameMutationsData: (@Sendable (Data) -> Void)? { get set }
    var onCommonNameMutationAckData: (@Sendable (Data) -> Void)? { get set }
    /// Reliable-channel file arrived. Implementations must read the incoming
    /// file synchronously inside the delegate callback and hand the bytes over.
    var onReceivedFile: (@Sendable (Data, [String: Any]) -> Void)? { get set }
    /// Pairing-level file-transfer capability. The first-release link protocol
    /// only pairs same-version apps, so the production transport always reports
    /// true; standalone (never-handshaked) transfers rely on this instead of an
    /// active session's negotiated capabilities.
    var supportsFileTransfer: Bool { get }

    func activate()
    func refreshStatus()
    func sendInteractive(_ data: Data) throws
    func updateApplicationContext(_ context: [String: Any]) throws
    func transferWatchRecord(_ data: Data) throws
    /// Reliable large-payload channel: queues a file whose metadata carries
    /// the `WatchTransferFileKind` discriminator.
    func transferFileData(_ data: Data, metadata: [String: Any]) throws
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
    /// Hard WCSession payload ceiling: larger payloads raise a native exception.
    public static let maxPayloadBytes = 65_536

    private static func ensurePayloadFits(_ data: Data) throws {
        guard data.count <= maxPayloadBytes else {
            throw WatchConnectivityTransportError.payloadTooLarge(data.count)
        }
    }
    public static let commonNamesContextKey = "jifen.common_names.v1"
    public static let watchRecordUserInfoKey = "jifen.watch_record.v1"
    public static let commonNameMutationsUserInfoKey = "jifen.common_name_mutations.v1"
    /// `transferFile` metadata key holding the `WatchTransferFileKind` raw value.
    public static let transferFileKindKey = "jifen.transfer_file.kind"
    /// Context budget for the common-names partition inside `applicationContext`.
    public static let commonNamesContextBudgetBytes = 24_000
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
    /// Reliable-channel file payloads (records, terminal frames).
    public var onReceivedFile: (@Sendable (Data, [String: Any]) -> Void)?
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

    /// Same-version pairing is a first-release invariant: the link protocol
    /// never shipped to users before this build, so any paired peer that can
    /// receive our messages can also receive our files.
    public var supportsFileTransfer: Bool { true }

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
        let isSupported = WCSession.isSupported()
        guard isSupported, session.activationState == .activated else {
            return WatchConnectivityStatus(
                isSupported: isSupported,
                isActivated: false,
                isPaired: false,
                isWatchAppInstalled: false,
                isReachable: false
            )
        }
        #if os(iOS)
        let isPaired = session.isPaired
        let isWatchAppInstalled = session.isWatchAppInstalled
        #else
        let isPaired = true
        let isWatchAppInstalled = true
        #endif
        return WatchConnectivityStatus(
            isSupported: isSupported,
            isActivated: true,
            isPaired: isPaired,
            isWatchAppInstalled: isWatchAppInstalled,
            isReachable: session.isReachable
        )
    }

    /// Current application context received from the peer (may be empty).
    public var receivedApplicationContext: [String: Any] {
        guard session.activationState == .activated else { return [:] }
        return session.receivedApplicationContext
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
        try Self.ensurePayloadFits(data)
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
        try Self.ensurePayloadFits(data)
        var context = session.applicationContext
        context[Self.latestLinkSnapshotContextKey] = data
        try session.updateApplicationContext(context)
    }

    public func enqueueDurable(_ data: Data) throws {
        guard session.activationState == .activated else {
            throw WatchConnectivityTransportError.sessionNotActivated
        }
        try Self.ensurePayloadFits(data)
        guard !session.outstandingUserInfoTransfers.contains(where: {
            $0.userInfo[Self.durableLinkPayloadKey] as? Data == data
        }) else { return }
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
        try Self.ensurePayloadFits(data)
        session.sendMessageData(data, replyHandler: nil, errorHandler: nil)
    }

    /// Push a small always-latest dictionary to the peer (used for common-names auto sync).
    /// The merged dictionary is serialized to measure the real byte size before
    /// hitting WCSession, which raises a native exception above 65,536 bytes.
    public func updateApplicationContext(_ context: [String: Any]) throws {
        guard session.activationState == .activated else {
            throw WatchConnectivityTransportError.sessionNotActivated
        }
        var merged = session.applicationContext
        for (key, value) in context {
            merged[key] = value
        }
        guard Self.contextDictionaryFits(merged) else {
            throw WatchConnectivityTransportError.payloadTooLarge(Self.maxPayloadBytes + 1)
        }
        try session.updateApplicationContext(merged)
    }

    /// Serializes the merged context dictionary the same way WCSession would,
    /// and rejects it when the total would exceed the 65,536-byte ceiling.
    static func contextDictionaryFits(_ context: [String: Any]) -> Bool {
        guard JSONSerialization.isValidJSONObject(context) else { return false }
        guard let data = try? JSONSerialization.data(withJSONObject: context, options: [.sortedKeys]) else {
            return false
        }
        return data.count <= maxPayloadBytes
    }

    /// Queue a finished watch record for delivery even when the peer is not reachable.
    public func transferWatchRecord(_ data: Data) throws {
        guard session.activationState == .activated else {
            throw WatchConnectivityTransportError.sessionNotActivated
        }
        try Self.ensurePayloadFits(data)
        session.transferUserInfo([Self.watchRecordUserInfoKey: data])
    }

    /// Queue a large payload as a background file transfer. The bytes land on
    /// disk first so `WCSession` never sees them as a dictionary payload; the
    /// sender keeps the full payload until the receiver ACKs ingest.
    public func transferFileData(_ data: Data, metadata: [String: Any]) throws {
        guard session.activationState == .activated else {
            throw WatchConnectivityTransportError.sessionNotActivated
        }
        guard !data.isEmpty else {
            throw WatchConnectivityTransportError.payloadTooLarge(0)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jifen-link-\(UUID().uuidString).jifenlink")
        try data.write(to: url, options: .atomic)
        pendingOutgoingFileURLs[url.path] = url
        session.transferFile(url, metadata: metadata)
    }

    /// Temp files awaiting `didFinish` cleanup, keyed by path.
    private var pendingOutgoingFileURLs: [String: URL] = [:]

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
            print("[LinkCore] requestPendingWatchRecords skipped: peer unavailable, state=\(session.activationState.rawValue)")
            #endif
            return
        }
        session.sendMessage([Self.catchUpRequestMessageKey: true], replyHandler: nil) { error in
            #if DEBUG
            print("[LinkCore] requestPendingWatchRecords send failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Watch side: respond with the queued pending record datas, split into
    /// per-message batches so a large queue never exceeds the WCSession limit.
    public func sendPendingWatchRecords(_ datas: [Data]) {
        #if DEBUG
        print("[LinkCore] sendPendingWatchRecords count=\(datas.count) (watch → phone)")
        #endif
        guard session.activationState == .activated, session.isReachable else {
            #if DEBUG
            print("[LinkCore] sendPendingWatchRecords skipped: peer unavailable, state=\(session.activationState.rawValue)")
            #endif
            return
        }
        // 单条记录超限时无法经消息通道投递（会触发原生异常）；调用方负责
        // 先裁剪，这里作为最后防线丢弃并报错，不让整个 flush 崩溃。
        let deliverable = datas.filter { data in
            guard data.count <= Self.maxPayloadBytes else {
                #if DEBUG
                print("[LinkCore] sendPendingWatchRecords dropped oversized record: \(data.count) bytes")
                #endif
                onSendError?(WatchConnectivityTransportError.payloadTooLarge(data.count))
                return false
            }
            return true
        }
        for batch in LinkPendingRecordChunking.chunk(deliverable) {
            session.sendMessage(
                [Self.pendingRecordsMessageKey: batch],
                replyHandler: nil
            ) { error in
                #if DEBUG
                print("[LinkCore] sendPendingWatchRecords send failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Phone side: tell the watch to drop the given pending ids after the phone ingested them.
    public func clearPendingWatchRecords(ids: [String]) {
        guard !ids.isEmpty, session.activationState == .activated else { return }
        let acknowledgement = [Self.clearPendingMessageKey: ids]
        guard session.isReachable else {
            session.transferUserInfo(acknowledgement)
            return
        }
        session.sendMessage(acknowledgement, replyHandler: nil) { [weak self] error in
            #if DEBUG
            print("[LinkCore] clearPendingWatchRecords send failed: \(error.localizedDescription)")
            #endif
            guard let self, self.session.activationState == .activated else { return }
            self.session.transferUserInfo(acknowledgement)
        }
    }

    private func reportStatus() {
        onStatusChange?(status)
    }

    private func deliverApplicationContextIfNeeded() {
        let context = receivedApplicationContext
        guard !context.isEmpty else { return }
        if let data = context[Self.latestLinkSnapshotContextKey] as? Data {
            onReceive?(data)
        }
        onApplicationContext?(context)
    }
}

extension WatchConnectivityTransport: WCSessionDelegate {
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let currentStatus = status
        #if DEBUG
        print("[LinkCore] activationDidComplete state=\(activationState.rawValue) paired=\(currentStatus.isPaired) reachable=\(currentStatus.isReachable) installed=\(currentStatus.isWatchAppInstalled) error=\(error?.localizedDescription ?? "nil")")
        #endif
        onStatusChange?(currentStatus)
        deliverApplicationContextIfNeeded()
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        let currentStatus = status
        #if DEBUG
        print("[LinkCore] reachabilityDidChange reachable=\(currentStatus.isReachable)")
        #endif
        onStatusChange?(currentStatus)
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
        if let ids = userInfo[Self.clearPendingMessageKey] as? [String] {
            onClearPendingRequest?(ids)
            return
        }
        if let mutationsData = userInfo[Self.commonNameMutationsUserInfoKey] as? Data {
            onCommonNameMutationsData?(mutationsData)
            return
        }
        if let acknowledgementData = userInfo[Self.commonNameMutationAckUserInfoKey] as? Data {
            onCommonNameMutationAckData?(acknowledgementData)
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

    /// watchOS/iOS delete the incoming temp file as soon as this delegate call
    /// returns, so the bytes must be captured synchronously right here.
    public func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let data = (try? Data(contentsOf: file.fileURL)) ?? Data()
        if data.isEmpty {
            #if DEBUG
            print("[LinkCore] didReceiveFile: empty or unreadable file at", file.fileURL.lastPathComponent)
            #endif
            return
        }
        onReceivedFile?(data, file.metadata ?? [:])
    }

    public func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let url = fileTransfer.file.fileURL
        pendingOutgoingFileURLs.removeValue(forKey: url.path)
        if url.path.contains("jifen-link-") {
            try? FileManager.default.removeItem(at: url)
        }
        if let error {
            #if DEBUG
            print("[LinkCore] didFinishFileTransfer error:", error.localizedDescription)
            #endif
        }
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

    public func sessionDidBecomeInactive(_ session: WCSession) {
        reportStatus()
    }

    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
#endif
}
#endif
