import Foundation
import ScoreCore

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

public enum LinkProtocol {
    public static let currentVersion = 1
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

public enum LinkedScoreboardSnapshot: Codable, Equatable, Sendable {
    case basketball(BasketballMatchState)
    case rally(RallyMatchState)
    case tennis(TennisMatchState)
    case archery(LinkedArcheryState)
    case eightBall(EightBallState)
    case nineBall(NineBallChaseState)
    case snooker(SnookerState)

    private enum CodingKeys: String, CodingKey {
        case kind
        case basketball
        case rally
        case tennis
        case archery
        case eightBall
        case nineBall
        case snooker
    }

    private enum Kind: String, Codable {
        case basketball
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
        case .basketball:
            self = .basketball(try container.decode(BasketballMatchState.self, forKey: .basketball))
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
        case .basketball(let state):
            try container.encode(Kind.basketball, forKey: .kind)
            try container.encode(state, forKey: .basketball)
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

    public var basketballState: BasketballMatchState? {
        guard case .basketball(let state) = self else { return nil }
        return state
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
        sidesSwapped: Bool = false
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
            sidesSwapped: match.sidesSwapped
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
        if finished {
            match.pendingSetNumber = 0
            match.closestToCenterPending = false
        }
    }
}

public struct EmptyLinkPayload: Codable, Equatable, Sendable {
    public init() {}
}

public struct LinkAcknowledgementPayload: Codable, Equatable, Sendable {
    public var acknowledgedMessageId: UUID
    public var acknowledgedRevision: UInt64

    public init(acknowledgedMessageId: UUID, acknowledgedRevision: UInt64) {
        self.acknowledgedMessageId = acknowledgedMessageId
        self.acknowledgedRevision = acknowledgedRevision
    }
}

public struct LinkMatchFinishedPayload: Codable, Equatable, Sendable {
    public var snapshot: LinkedScoreboardSnapshot
    public var recordId: String
    public var winnerSide: MatchSide?
    public var manualEnd: Bool
    /// Match wall-clock start (ms since epoch). Optional for backward compatibility.
    public var startTimeEpochMilliseconds: Int64?
    /// Match wall-clock end (ms since epoch). Optional for backward compatibility.
    public var endTimeEpochMilliseconds: Int64?
    /// Duration in seconds. Optional for backward compatibility.
    public var durationSeconds: Double?
    /// Approximate score-change count for record summaries.
    public var totalScoreChanges: Int?

    public init(
        snapshot: LinkedScoreboardSnapshot,
        recordId: String,
        winnerSide: MatchSide? = nil,
        manualEnd: Bool = false,
        startTimeEpochMilliseconds: Int64? = nil,
        endTimeEpochMilliseconds: Int64? = nil,
        durationSeconds: Double? = nil,
        totalScoreChanges: Int? = nil
    ) {
        self.snapshot = snapshot
        self.recordId = recordId
        self.winnerSide = winnerSide
        self.manualEnd = manualEnd
        self.startTimeEpochMilliseconds = startTimeEpochMilliseconds
        self.endTimeEpochMilliseconds = endTimeEpochMilliseconds
        self.durationSeconds = durationSeconds
        self.totalScoreChanges = totalScoreChanges
    }
}

public struct LinkStatusPayload: Codable, Equatable, Sendable {
    public var role: LinkControlRole
    public var revision: UInt64
    public var reachable: Bool

    public init(role: LinkControlRole, revision: UInt64, reachable: Bool = true) {
        self.role = role
        self.revision = revision
        self.reachable = reachable
    }
}

/// Single-pending ACK queue: Harmony-aligned ~3s retry, max 2 retries.
public struct LinkPendingAckQueue: Equatable, Sendable {
    public struct PendingItem: Equatable, Sendable {
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
    public mutating func retryIfDue(nowEpochMilliseconds: Int64) -> Data? {
        guard var item = pending else { return nil }
        guard nowEpochMilliseconds - item.lastSentAtEpochMilliseconds >= Self.retryIntervalMilliseconds else {
            return nil
        }
        guard item.attempts < Self.maxRetries else {
            pending = nil
            return nil
        }
        item.attempts += 1
        item.lastSentAtEpochMilliseconds = nowEpochMilliseconds
        pending = item
        return item.data
    }
}

public struct LinkedScoreboardSetup: Codable, Equatable, Sendable {
    public let gameType: GameType
    public let maxSets: Int?
    public let basketballThreeXThree: Bool
    public let initialSnapshot: LinkedScoreboardSnapshot?

    public init(
        gameType: GameType,
        maxSets: Int? = nil,
        basketballThreeXThree: Bool = false,
        initialSnapshot: LinkedScoreboardSnapshot? = nil
    ) {
        self.gameType = gameType
        self.maxSets = maxSets
        self.basketballThreeXThree = basketballThreeXThree
        self.initialSnapshot = initialSnapshot
    }
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
        protocolVersion: Int = LinkProtocol.currentVersion,
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

public struct LinkRevisionGate: Equatable, Sendable {
    public enum Disposition: Equatable, Sendable {
        case newer
        case duplicateOrOlder
        case wrongSession
    }

    public private(set) var activeSessionId: UUID?
    public private(set) var latestRevision: UInt64?

    public init() {}

    @discardableResult
    public mutating func beginSession(_ sessionId: UUID, initialRevision: UInt64 = 0) -> Bool {
        guard activeSessionId != sessionId else { return false }
        activeSessionId = sessionId
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
        guard activeSessionId == sessionId else { return .wrongSession }
        guard revision > (latestRevision ?? 0) else { return .duplicateOrOlder }
        latestRevision = revision
        return .newer
    }

    public mutating func endSession(_ sessionId: UUID) {
        guard activeSessionId == sessionId else { return }
        activeSessionId = nil
        latestRevision = nil
    }
}

public protocol LinkTransport: Sendable {
    func send(_ data: Data) async throws
}

#if canImport(WatchConnectivity)
public enum WatchConnectivityTransportError: Error, Equatable, Sendable {
    case sessionNotActivated
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

/// A binary transport shared by the phone and Watch targets.
public final class WatchConnectivityTransport: NSObject, @unchecked Sendable, LinkTransport {
    public typealias ReceiveHandler = @Sendable (Data) -> Void
    public typealias DictionaryHandler = @Sendable ([String: Any]) -> Void

    private static let userInfoPayloadKey = "jifen.link.payload"
    public static let commonNamesContextKey = "jifen.common_names.v1"
    public static let watchRecordUserInfoKey = "jifen.watch_record.v1"
    public static let commonNameUsageUserInfoKey = "jifen.common_name_usage.v1"

    private let session: WCSession
    public var onReceive: ReceiveHandler?
    public var onStatusChange: (@Sendable (WatchConnectivityStatus) -> Void)?
    /// Latest application context from the peer (phone→watch common names, etc.).
    public var onApplicationContext: DictionaryHandler?
    /// Queued watch→phone finished-record payloads.
    public var onWatchRecordData: ReceiveHandler?
    /// Queued watch→phone common-name usage events.
    public var onCommonNameUsageData: ReceiveHandler?

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

    /// Push a small always-latest dictionary to the peer (used for common-names auto sync).
    public func updateApplicationContext(_ context: [String: Any]) throws {
        guard session.activationState == .activated else {
            throw WatchConnectivityTransportError.sessionNotActivated
        }
        try session.updateApplicationContext(context)
    }

    /// Queue a finished watch record for delivery even when the peer is not reachable.
    public func transferWatchRecord(_ data: Data) throws {
        guard session.activationState == .activated else {
            throw WatchConnectivityTransportError.sessionNotActivated
        }
        session.transferUserInfo([Self.watchRecordUserInfoKey: data])
    }

    /// Queue a name-usage event even if the phone is currently unreachable.
    public func transferCommonNameUsage(_ data: Data) throws {
        guard session.activationState == .activated else {
            throw WatchConnectivityTransportError.sessionNotActivated
        }
        session.transferUserInfo([Self.commonNameUsageUserInfoKey: data])
    }

    private func reportStatus() {
        onStatusChange?(status)
    }

    private func deliverApplicationContextIfNeeded() {
        let context = session.receivedApplicationContext
        guard !context.isEmpty else { return }
        onApplicationContext?(context)
    }
}

extension WatchConnectivityTransport: WCSessionDelegate {
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        reportStatus()
        deliverApplicationContextIfNeeded()
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        reportStatus()
    }

    public func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        onReceive?(messageData)
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let usageData = userInfo[Self.commonNameUsageUserInfoKey] as? Data {
            onCommonNameUsageData?(usageData)
            return
        }
        if let recordData = userInfo[Self.watchRecordUserInfoKey] as? Data {
            onWatchRecordData?(recordData)
            return
        }
        guard let data = userInfo[Self.userInfoPayloadKey] as? Data else { return }
        onReceive?(data)
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
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
