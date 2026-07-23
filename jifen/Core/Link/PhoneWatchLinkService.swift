import Foundation
import LinkCore
import Observation
import ScoreCore

@MainActor
@Observable
final class PhoneWatchLinkService {
    private struct ActiveSession {
        let sessionId: UUID
        let gameType: ScoreCore.GameType
        var revision: UInt64
        var role: LinkControlRole
        var setup: LinkedScoreboardSetup
    }

    private let transport = WatchConnectivityTransport()
    private var sequence: UInt64 = 0
    private var activeSession: ActiveSession?
    private var pendingAck = LinkPendingAckQueue()
    private var setupContinuation: CheckedContinuation<UUID, Error>?
    private var setupTimeoutTask: Task<Void, Never>?
    private var ackRetryTask: Task<Void, Never>?
    private var revisionGate = LinkRevisionGate()
    private var pendingTakeoverMessageId: UUID?

    private(set) var connectivityStatus: WatchConnectivityStatus
    private(set) var controlRole: LinkControlRole?
    private(set) var latestRemoteSnapshot: LinkedSnapshotUpdate?
    private(set) var finishedRecordId: String?
    private(set) var lastErrorMessage: String?
    /// Last watch record id auto-synced into phone records (for toast / UI).
    private(set) var lastSyncedWatchRecordId: String?

    static let setupTimeoutSeconds: TimeInterval = 20

    enum InteractiveStartError: LocalizedError {
        case watchUnavailable
        case setupRejected
        case setupTimedOut
        case notController

        var errorDescription: String? {
            switch self {
            case .watchUnavailable:
                return NSLocalizedString(
                    "linked_score_watch_unavailable",
                    value: "Apple Watch 未连接，请打开手表端全能计分器后重试。",
                    comment: ""
                )
            case .setupRejected:
                return NSLocalizedString(
                    "linked_score_watch_rejected",
                    value: "手表拒绝了联动开局。",
                    comment: ""
                )
            case .setupTimedOut:
                return NSLocalizedString(
                    "linked_score_watch_timeout",
                    value: "等待手表确认超时，请重试。",
                    comment: ""
                )
            case .notController:
                return NSLocalizedString(
                    "linked_score_not_controller",
                    value: "当前不是主控端，无法执行该操作。",
                    comment: ""
                )
            }
        }
    }

    struct LinkedSnapshotUpdate: Equatable {
        let sessionId: UUID
        let revision: UInt64
        let snapshot: LinkedScoreboardSnapshot
    }

    init() {
        connectivityStatus = transport.status
        transport.onStatusChange = { [weak self] status in
            DispatchQueue.main.async {
                self?.handleConnectivityStatusChange(status)
            }
        }
        transport.onReceive = { [weak self] data in
            DispatchQueue.main.async {
                self?.handleIncoming(data)
            }
        }
        transport.onWatchRecordData = { [weak self] data in
            DispatchQueue.main.async {
                self?.handleWatchRecordTransfer(data)
            }
        }
        transport.onCommonNameUsageData = { [weak self] data in
            DispatchQueue.main.async {
                self?.handleCommonNameUsage(data)
            }
        }
        transport.activate()
        startAckRetryLoop()
        NotificationCenter.default.addObserver(
            forName: .commonNamesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let service = self else { return }
            Task { @MainActor in
                service.pushCommonNamesToWatch()
            }
        }
        pushCommonNamesToWatch()
    }

    var canStartInteractiveSession: Bool {
        connectivityStatus.canStartInteractiveSession
    }

    /// Force a connectivity status refresh for the Watch Link settings page.
    func refreshConnectivity() {
        transport.refreshStatus()
        connectivityStatus = transport.status
        pushCommonNamesToWatch()
    }

    /// Push current phone common names to the watch via application context (always-latest).
    func pushCommonNamesToWatch() {
        guard connectivityStatus.isSupported,
              connectivityStatus.isActivated,
              connectivityStatus.isPaired,
              connectivityStatus.isWatchAppInstalled else { return }
        let snapshot = CommonNamesSyncSnapshot(
            teams: CommonNamesManager.shared.getNames(type: .team),
            players: CommonNamesManager.shared.getNames(type: .player)
        )
        let context: [String: Any] = [
            WatchConnectivityTransport.commonNamesContextKey: snapshot.applicationContextValue()
        ]
        do {
            try transport.updateApplicationContext(context)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func handleWatchRecordTransfer(_ data: Data) {
        guard let payload = try? JSONDecoder().decode(WatchRecordTransferPayload.self, from: data) else {
            return
        }
        do {
            lastSyncedWatchRecordId = try WatchStandaloneRecordIngestor.ingest(payload)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func handleCommonNameUsage(_ data: Data) {
        guard let payload = try? JSONDecoder().decode(CommonNameUsagePayload.self, from: data),
              payload.nameType == "player" else { return }
        Task { @MainActor [weak self] in
            for name in payload.names {
                await CommonNamesManager.shared.recordUsage(name, .player)
            }
            self?.pushCommonNamesToWatch()
        }
    }

    /// Cancel an in-flight setup handshake (user left Setup while waiting).
    func cancelPendingSetupHandshake() {
        setupTimeoutTask?.cancel()
        setupTimeoutTask = nil
        let continuation = setupContinuation
        setupContinuation = nil
        if let sessionId = activeSession?.sessionId {
            leaveSession(sessionId)
        } else {
            clearSession()
        }
        continuation?.resume(throwing: InteractiveStartError.setupRejected)
    }

    var isFollower: Bool {
        controlRole == .phoneFollower
    }

    var isController: Bool {
        controlRole == .phoneController
    }

    var activeSessionId: UUID? {
        activeSession?.sessionId
    }

    func startInteractiveOnWatch(state: BasketballMatchState) async throws -> UUID {
        try await startInteractiveSession(
            gameType: state.gameMode == .threeXThree ? .threeBasketball : .basketball,
            basketballThreeXThree: state.gameMode == .threeXThree,
            initialSnapshot: .basketball(state)
        )
    }

    func startInteractiveOnWatch(gameType: ScoreCore.GameType, state: RallyMatchState) async throws -> UUID {
        try await startInteractiveSession(
            gameType: gameType,
            maxSets: state.rules.maxSets,
            initialSnapshot: .rally(state)
        )
    }

    func startInteractiveOnWatch(gameType: ScoreCore.GameType, state: TennisMatchState) async throws -> UUID {
        try await startInteractiveSession(
            gameType: gameType,
            maxSets: state.rules.maxSets,
            initialSnapshot: .tennis(state)
        )
    }

    func startInteractiveOnWatch(snapshot: LinkedScoreboardSnapshot, gameType: ScoreCore.GameType) async throws -> UUID {
        try await startInteractiveSession(
            gameType: gameType,
            maxSets: maxSets(for: snapshot),
            basketballThreeXThree: isThreeXThree(snapshot),
            initialSnapshot: snapshot
        )
    }

    func syncWatch(sessionId: UUID, state: BasketballMatchState) {
        let gameType: ScoreCore.GameType = state.gameMode == .threeXThree ? .threeBasketball : .basketball
        sendSnapshotIfController(sessionId: sessionId, gameType: gameType, snapshot: .basketball(state))
    }

    func syncWatch(sessionId: UUID, gameType: ScoreCore.GameType, state: RallyMatchState) {
        sendSnapshotIfController(sessionId: sessionId, gameType: gameType, snapshot: .rally(state))
    }

    func syncWatch(sessionId: UUID, gameType: ScoreCore.GameType, state: TennisMatchState) {
        sendSnapshotIfController(sessionId: sessionId, gameType: gameType, snapshot: .tennis(state))
    }

    func syncWatch(sessionId: UUID, gameType: ScoreCore.GameType, snapshot: LinkedScoreboardSnapshot) {
        sendSnapshotIfController(sessionId: sessionId, gameType: gameType, snapshot: snapshot)
    }

    func takeover(sessionId: UUID) async throws {
        guard let session = activeSession,
              session.sessionId == sessionId,
              connectivityStatus.canStartInteractiveSession else {
            throw InteractiveStartError.watchUnavailable
        }
        sequence += 1
        let messageId = UUID()
        let envelope = LinkEnvelope(
            messageId: messageId,
            sessionId: sessionId,
            kind: .takeoverByPhone,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: session.revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: EmptyLinkPayload()
        )
        let data = try JSONEncoder().encode(envelope)
        pendingTakeoverMessageId = messageId
        pendingAck.enqueue(.init(
            messageId: messageId,
            sessionId: sessionId,
            revision: session.revision,
            data: data,
            lastSentAtEpochMilliseconds: nowMs()
        ))
        do {
            try await transport.send(data)
        } catch {
            _ = pendingAck.acknowledge(messageId: messageId)
            pendingTakeoverMessageId = nil
            throw error
        }
    }

    func leaveSession(_ sessionId: UUID) {
        guard activeSession?.sessionId == sessionId else { return }
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: sessionId,
            kind: .sessionLeft,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: activeSession?.revision ?? 0,
            sentAtEpochMilliseconds: nowMs(),
            payload: EmptyLinkPayload()
        )
        Task { try? await sendEnvelope(envelope) }
        clearSession()
    }

    func endWatchSession(_ sessionId: UUID) {
        leaveSession(sessionId)
    }

    func notifyMatchFinished(
        sessionId: UUID,
        snapshot: LinkedScoreboardSnapshot,
        recordId: String,
        winnerSide: MatchSide?,
        manualEnd: Bool,
        startTime: Date? = nil,
        endTime: Date? = nil,
        totalScoreChanges: Int? = nil
    ) {
        guard var session = activeSession, session.sessionId == sessionId else { return }
        session.revision += 1
        activeSession = session
        sequence += 1
        let messageId = UUID()
        let end = endTime ?? Date()
        let start = startTime ?? end.addingTimeInterval(-60)
        let duration = max(1, end.timeIntervalSince(start))
        let envelope = LinkEnvelope(
            messageId: messageId,
            sessionId: sessionId,
            kind: .matchFinished,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: session.revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkMatchFinishedPayload(
                snapshot: snapshot,
                recordId: recordId,
                winnerSide: winnerSide,
                manualEnd: manualEnd,
                startTimeEpochMilliseconds: Int64(start.timeIntervalSince1970 * 1000),
                endTimeEpochMilliseconds: Int64(end.timeIntervalSince1970 * 1000),
                durationSeconds: duration,
                totalScoreChanges: totalScoreChanges
            )
        )
        Task {
            guard let data = try? JSONEncoder().encode(envelope) else { return }
            pendingAck.enqueue(.init(
                messageId: messageId,
                sessionId: sessionId,
                revision: session.revision,
                data: data,
                lastSentAtEpochMilliseconds: nowMs()
            ))
            try? await transport.send(data)
        }
    }

    // MARK: - Private

    private func startInteractiveSession(
        gameType: ScoreCore.GameType,
        maxSets: Int? = nil,
        basketballThreeXThree: Bool = false,
        initialSnapshot: LinkedScoreboardSnapshot
    ) async throws -> UUID {
        guard canStartInteractiveSession else {
            throw InteractiveStartError.watchUnavailable
        }
        if setupContinuation != nil {
            let continuation = setupContinuation
            setupContinuation = nil
            if let existing = activeSession?.sessionId {
                leaveSession(existing)
            } else {
                clearSession()
            }
            continuation?.resume(throwing: InteractiveStartError.setupTimedOut)
        }
        setupTimeoutTask?.cancel()

        let sessionId = UUID()
        let setup = LinkedScoreboardSetup(
            gameType: gameType,
            maxSets: maxSets,
            basketballThreeXThree: basketballThreeXThree,
            initialSnapshot: initialSnapshot
        )
        if let existing = activeSession?.sessionId {
            leaveSession(existing)
        }
        activeSession = ActiveSession(
            sessionId: sessionId,
            gameType: gameType,
            revision: 0,
            role: .phoneFollower,
            setup: setup
        )
        controlRole = .phoneFollower
        latestRemoteSnapshot = nil
        finishedRecordId = nil
        lastErrorMessage = nil
        _ = revisionGate.beginSession(sessionId, initialRevision: 0)
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: sessionId,
            kind: .setupRequest,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: 0,
            sentAtEpochMilliseconds: nowMs(),
            payload: setup
        )
        return try await withCheckedThrowingContinuation { continuation in
            setupContinuation = continuation
            setupTimeoutTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(Self.setupTimeoutSeconds * 1_000_000_000))
                } catch {
                    return
                }
                await MainActor.run {
                    guard let self,
                          self.activeSession?.sessionId == sessionId,
                          let cont = self.setupContinuation else { return }
                    self.setupContinuation = nil
                    self.setupTimeoutTask = nil
                    self.leaveSession(sessionId)
                    cont.resume(throwing: InteractiveStartError.setupTimedOut)
                }
            }
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.sendEnvelope(envelope)
                } catch {
                    guard self.activeSession?.sessionId == sessionId,
                          let cont = self.setupContinuation else { return }
                    self.setupContinuation = nil
                    self.setupTimeoutTask?.cancel()
                    self.setupTimeoutTask = nil
                    self.clearSession()
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func sendSnapshotIfController(
        sessionId: UUID,
        gameType: ScoreCore.GameType,
        snapshot: LinkedScoreboardSnapshot
    ) {
        guard var session = activeSession,
              session.sessionId == sessionId,
              session.gameType == gameType,
              session.role == .phoneController else { return }
        session.revision += 1
        activeSession = session
        sequence += 1
        let messageId = UUID()
        let envelope = LinkEnvelope(
            messageId: messageId,
            sessionId: sessionId,
            kind: .stateSnapshot,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: session.revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkedScoreboardSetup(
                gameType: gameType,
                maxSets: maxSets(for: snapshot),
                basketballThreeXThree: isThreeXThree(snapshot),
                initialSnapshot: snapshot
            )
        )
        Task {
            guard let data = try? JSONEncoder().encode(envelope) else { return }
            pendingAck.enqueue(.init(
                messageId: messageId,
                sessionId: sessionId,
                revision: session.revision,
                data: data,
                lastSentAtEpochMilliseconds: nowMs()
            ))
            try? await transport.send(data)
        }
    }

    private func handleIncoming(_ data: Data) {
        if handleSetupResponse(data) { return }
        if handleAck(data) { return }
        if handleSnapshotFromWatch(data) { return }
        if handleTakeoverRelated(data) { return }
        if handleMatchFinishedFromWatch(data) { return }
        if handleSessionLeft(data) { return }
        _ = handleStatus(data)
    }

    private func handleSetupResponse(_ data: Data) -> Bool {
        if let accepted = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data),
           accepted.kind == .setupAccepted,
           accepted.sender == .watch,
           accepted.sessionId == activeSession?.sessionId {
            setupTimeoutTask?.cancel()
            setupTimeoutTask = nil
            if var session = activeSession {
                session.role = .phoneFollower
                activeSession = session
            }
            controlRole = .phoneFollower
            setupContinuation?.resume(returning: accepted.sessionId)
            setupContinuation = nil
            return true
        }
        if let rejected = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data),
           rejected.kind == .setupRejected,
           rejected.sender == .watch,
           rejected.sessionId == activeSession?.sessionId {
            setupTimeoutTask?.cancel()
            setupTimeoutTask = nil
            clearSession()
            setupContinuation?.resume(throwing: InteractiveStartError.setupRejected)
            setupContinuation = nil
            return true
        }
        return false
    }

    private func handleAck(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkAcknowledgementPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .acknowledgement || envelope.kind == .recordAcknowledgement else {
            return false
        }
        let acknowledgedMessageId = envelope.payload.acknowledgedMessageId
        _ = pendingAck.acknowledge(messageId: acknowledgedMessageId)
        if acknowledgedMessageId == pendingTakeoverMessageId,
           var session = activeSession,
           session.sessionId == envelope.sessionId {
            pendingTakeoverMessageId = nil
            session.role = .phoneController
            activeSession = session
            controlRole = .phoneController
        }
        return true
    }

    private func handleSnapshotFromWatch(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkedScoreboardSetup>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .stateSnapshot,
              let snapshot = envelope.payload.initialSnapshot,
              activeSession?.sessionId == envelope.sessionId else {
            return false
        }

        let disposition = revisionGate.classify(
            sessionId: envelope.sessionId,
            revision: envelope.sessionRevision
        )
        guard disposition != .wrongSession else { return false }
        if disposition == .newer, var session = activeSession {
            session.revision = max(session.revision, envelope.sessionRevision)
            activeSession = session
            latestRemoteSnapshot = LinkedSnapshotUpdate(
                sessionId: envelope.sessionId,
                revision: envelope.sessionRevision,
                snapshot: snapshot
            )
        }
        // ACK valid duplicates too: a retry usually means our prior ACK was lost.
        sendAck(
            sessionId: envelope.sessionId,
            messageId: envelope.messageId,
            revision: envelope.sessionRevision
        )
        return true
    }

    private func handleTakeoverRelated(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.sessionId == activeSession?.sessionId else { return false }
        switch envelope.kind {
        case .reclaimAccepted:
            if var session = activeSession {
                session.role = .phoneFollower
                activeSession = session
            }
            controlRole = .phoneFollower
            return true
        case .reclaimDenied:
            lastErrorMessage = NSLocalizedString(
                "linked_score_reclaim_denied",
                value: "手表拒绝交还控制权。",
                comment: ""
            )
            return true
        default:
            return false
        }
    }

    private func handleMatchFinishedFromWatch(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkMatchFinishedPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .matchFinished,
              envelope.sessionId == activeSession?.sessionId else { return false }

        latestRemoteSnapshot = LinkedSnapshotUpdate(
            sessionId: envelope.sessionId,
            revision: envelope.sessionRevision,
            snapshot: envelope.payload.snapshot
        )

        // Once this session has been durably committed, acknowledge any retry
        // without replacing the accepted record.
        if finishedRecordId != nil {
            sendAck(
                sessionId: envelope.sessionId,
                messageId: envelope.messageId,
                revision: envelope.sessionRevision,
                recordAck: true
            )
            return true
        }

        guard let gameType = activeSession?.gameType else { return false }
        do {
            finishedRecordId = try LinkedMatchRecordIngestor.ingest(
                payload: envelope.payload,
                gameType: gameType,
                sessionId: envelope.sessionId
            )
        } catch {
            // Do not ACK a record that was not saved. The watch retains the
            // stable message and retries instead of silently losing the match.
            lastErrorMessage = error.localizedDescription
            return true
        }
        sendAck(
            sessionId: envelope.sessionId,
            messageId: envelope.messageId,
            revision: envelope.sessionRevision,
            recordAck: true
        )
        return true
    }

    private func handleSessionLeft(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .sessionLeft,
              envelope.sessionId == activeSession?.sessionId else { return false }
        clearSession()
        return true
    }

    private func handleStatus(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkStatusPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .statusResponse else { return false }
        if var session = activeSession, session.sessionId == envelope.sessionId {
            session.revision = max(session.revision, envelope.payload.revision)
            switch envelope.payload.role {
            case .watchController:
                session.role = .phoneFollower
            case .watchFollower:
                session.role = .phoneController
            case .phoneController, .phoneFollower:
                break
            }
            activeSession = session
            controlRole = session.role
        }
        return true
    }

    private func handleConnectivityStatusChange(_ status: WatchConnectivityStatus) {
        connectivityStatus = status
        pushCommonNamesToWatch()
        guard status.isReachable else { return }
        requestStatusForActiveSession()
    }

    private func requestStatusForActiveSession() {
        guard let session = activeSession else { return }
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: session.sessionId,
            kind: .statusQuery,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: session.revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: EmptyLinkPayload()
        )
        Task { try? await sendEnvelope(envelope) }
    }

    private func sendAck(
        sessionId: UUID,
        messageId: UUID,
        revision: UInt64,
        recordAck: Bool = false
    ) {
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: sessionId,
            kind: recordAck ? .recordAcknowledgement : .acknowledgement,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkAcknowledgementPayload(
                acknowledgedMessageId: messageId,
                acknowledgedRevision: revision
            )
        )
        Task { try? await sendEnvelope(envelope) }
    }

    private func sendEnvelope<Payload: Codable & Sendable>(_ envelope: LinkEnvelope<Payload>) async throws {
        let data = try JSONEncoder().encode(envelope)
        try await transport.send(data)
    }

    private func startAckRetryLoop() {
        ackRetryTask?.cancel()
        ackRetryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    guard let self else { return }
                    if let data = self.pendingAck.retryIfDue(nowEpochMilliseconds: self.nowMs()) {
                        Task { try? await self.transport.send(data) }
                    }
                }
            }
        }
    }

    private func clearSession() {
        if let id = activeSession?.sessionId {
            revisionGate.endSession(id)
        }
        activeSession = nil
        controlRole = nil
        pendingTakeoverMessageId = nil
        pendingAck.clear()
        latestRemoteSnapshot = nil
    }

    private func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }

    private func maxSets(for snapshot: LinkedScoreboardSnapshot) -> Int? {
        switch snapshot {
        case .rally(let state): return state.rules.maxSets
        case .tennis(let state): return state.rules.maxSets
        default: return nil
        }
    }

    private func isThreeXThree(_ snapshot: LinkedScoreboardSnapshot) -> Bool {
        guard case .basketball(let state) = snapshot else { return false }
        return state.gameMode == .threeXThree
    }
}
