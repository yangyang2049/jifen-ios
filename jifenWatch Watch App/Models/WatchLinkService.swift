import Foundation
import LinkCore
import Observation
import RecordCore
import ScoreCore

struct LinkedSetupRequest: Equatable {
    let handle: LinkedMatchHandle
    let messageId: UUID
    let authorityEpoch: UInt64
    let setup: LinkedScoreboardSetup
    var peerSupportsCompressedFinish = false
    var peerSupportsSharedEditing = false

    var sessionId: UUID { handle.sessionId }
}
struct LinkedSnapshotUpdate: Equatable {
    let sessionId: UUID
    let revision: UInt64
    var matchGeneration: UInt64 = 1
    let snapshot: LinkedScoreboardSnapshot
    let detailedActions: [DetailedScoreAction]

    func beginsMatch(after previous: Self?) -> Bool {
        guard let previous, previous.sessionId == sessionId else { return false }
        return previous.matchGeneration < matchGeneration
    }
}

struct PendingWatchReclaimAcceptance: Equatable {
    let messageId: UUID
    let correlationId: UUID
    let sessionId: UUID
    let revision: UInt64
    let snapshot: LinkedScoreboardSnapshot
    let detailedActions: [DetailedScoreAction]
}

enum WatchPhoneLinkTestState: Equatable {
    case idle
    case testing
    case success
    case failed
}

enum WatchPhoneLinkTestFailure: Equatable {
    case inactive
    case unreachable
    case sendFailed
    case timedOut
}

enum WatchCommonNamesSyncRequestResult: Equatable {
    case requested
    case queuedUntilPhoneAvailable
    case connectionInactive
    case failed
}

struct WatchPhoneLinkProbeTracker: Equatable {
    static let timeoutSeconds: TimeInterval = 8
    private(set) var activeProbeID: UUID?

    mutating func start(_ probeID: UUID) {
        activeProbeID = probeID
    }

    mutating func accept(_ probeID: UUID) -> Bool {
        guard activeProbeID == probeID else { return false }
        activeProbeID = nil
        return true
    }

    mutating func accept(sessionID: UUID, probeID: UUID) -> Bool {
        guard sessionID == probeID else { return false }
        return accept(probeID)
    }

    mutating func timeout(_ probeID: UUID) -> Bool {
        accept(probeID)
    }

    mutating func cancel() {
        activeProbeID = nil
    }

    static func canStart(with status: WatchConnectivityStatus) -> Bool {
        status.isActivated && status.isReachable
    }
}

@MainActor
@Observable
final class WatchLinkService {
    /// Pending setup awaiting user confirm (does not auto-open).
    var pendingConfirmRequest: LinkedSetupRequest?
    /// After accept, active linked setup for scoreboard routing.
    var acceptedSetup: LinkedSetupRequest?
    var latestSnapshot: LinkedSnapshotUpdate?
    var sharedEditTracker = LinkSharedEditTracker()
    var simultaneousEditNotice: UUID?
    var controlRole: LinkControlRole?
    var phoneTookOver: Bool = false
    var pendingReclaimAcceptance: PendingWatchReclaimAcceptance?
    internal(set) var connectivityStatus: WatchConnectivityStatus
    internal(set) var phoneLinkTestState: WatchPhoneLinkTestState = .idle
    internal(set) var phoneLinkTestFailure: WatchPhoneLinkTestFailure?
    internal(set) var lastCommunicationAtEpochMilliseconds: Int64
    internal(set) var commonNamesSyncFailed = false
    internal(set) var lastLinkErrorMessage: String?

    let transport: any WatchLinkTransport
    let contextStore: any LinkDataStore
    let outboxStore: any LinkDataStore
    let clock: any LinkClock
    let recordSink: any WatchLinkRecordSink
    var revisionGate = LinkRevisionGate()
    var sequence: UInt64 = 0
    /// Authoritative linked-match and control lifecycle. The scalar fields
    /// below are projections used by existing Watch views and persistence.
    var sessionMachine: LinkSessionStateMachine?
    var pendingAck = LinkControlRetryQueue()
    var terminalOutbox = LinkDurableOutbox()
    var peerSupportsCompressedFinish = false
    @ObservationIgnored var retiredRecordSessions: LinkRetiredRecordSessions

    var activeRecordSession: LinkRecordSession? {
        guard let handle = activeHandle, let gameType = activeGameType,
              sessionMachine?.lifecycle != .starting else { return nil }
        return LinkRecordSession(
            handle: handle, gameType: gameType,
            authorityEpoch: authorityEpoch, completedMatchIds: publishedFinishedMatchIds,
            allowsPeerNextMatch: controlRole == .watchFollower || controlRole == .shared
        )
    }
    var publishedFinishedMatchIds: Set<UUID> = []
    var pendingReclaimRequestMessageId: UUID?
    var reclaimRequestTimeoutTask: Task<Void, Never>?
    var activeSessionId: UUID?
    var activeHandle: LinkedMatchHandle?
    var activeRevision: UInt64 = 0
    var authorityEpoch: UInt64 = 0
    var activeGameType: GameType?
    var activeSetup: LinkedScoreboardSetup?
    var mergedDetailedActions: [DetailedScoreAction] = []
    var ackRetryTask: Task<Void, Never>?
    let pendingWatchRecordsKey = "watch_pending_record_transfers_v1"
    var pendingWatchRecords: [WatchRecordTransferPayload] = []
    let pendingCommonNameUsageKey = "watch_pending_common_name_usage_v1"
    var pendingCommonNameUsage: [CommonNameUsagePayload] = []
    var lastQueuedCommonNameMutationIDs: [UUID] = []
    var probeTracker = WatchPhoneLinkProbeTracker()
    var probeTimeoutTask: Task<Void, Never>?
    let lastCommunicationAtKey = "watch_phone_link_last_communication_at_v1"
    let contextKey = "watch_link_context"
    let terminalOutboxKey = "watch_link_terminal_outbox"
    let pendingSessionEndsKey = "watch_link_pending_session_ends"
    let legacyCleanupMarkerKey = "watch_link_legacy_cleanup_v1"
    var pendingSessionEnds: [LinkPendingSessionEnd] = []
    var pendingSessionEndInFlight: Set<UUID> = []

    init(
        transport: any WatchLinkTransport = WatchConnectivityTransport(),
        contextStore: any LinkDataStore = UserDefaultsLinkDataStore.standard,
        outboxStore: any LinkDataStore = UserDefaultsLinkDataStore.standard,
        clock: any LinkClock = SystemLinkClock(),
        recordSink: (any WatchLinkRecordSink)? = nil
    ) {
        self.transport = transport
        self.contextStore = contextStore
        retiredRecordSessions = LinkRetiredRecordSessions(store: contextStore)
        self.outboxStore = outboxStore
        self.clock = clock
        self.recordSink = recordSink ?? DefaultWatchLinkRecordSink()
        connectivityStatus = transport.status
        lastCommunicationAtEpochMilliseconds = Int64(
            WatchPreferences.shared.int(forKey: lastCommunicationAtKey)
        )
        if contextStore.data(forKey: legacyCleanupMarkerKey) == nil {
            contextStore.removeObject(forKey: "watch_link_context_v1")
            outboxStore.removeObject(forKey: "watch_link_terminal_outbox_v1")
            outboxStore.removeObject(forKey: "watch_link_pending_ack_v1")
            contextStore.set(Data([1]), forKey: legacyCleanupMarkerKey)
        }
        if let data = outboxStore.data(forKey: terminalOutboxKey),
           let outbox = try? JSONDecoder().decode(LinkDurableOutbox.self, from: data) {
            terminalOutbox = outbox
        }
        if let data = outboxStore.data(forKey: pendingSessionEndsKey),
           let requests = try? JSONDecoder().decode([LinkPendingSessionEnd].self, from: data) {
            pendingSessionEnds = requests
        }
        restoreContext()
        if let data = WatchPreferences.shared.data(forKey: pendingWatchRecordsKey),
           let payloads = try? JSONDecoder().decode([WatchRecordTransferPayload].self, from: data) {
            pendingWatchRecords = payloads
        }
        if let data = WatchPreferences.shared.data(forKey: pendingCommonNameUsageKey),
           let payloads = try? JSONDecoder().decode([CommonNameUsagePayload].self, from: data) {
            pendingCommonNameUsage = payloads
        }
        transport.onReceive = { [weak self] data in
            DispatchQueue.main.async {
                self?.receive(data)
            }
        }
        transport.onSendError = { [weak self] error in
            DispatchQueue.main.async {
                self?.lastLinkErrorMessage = error.localizedDescription
            }
        }
        transport.onApplicationContext = { [weak self] context in
            DispatchQueue.main.async {
                self?.handleApplicationContext(context)
            }
        }
        transport.onCommonNameMutationAckData = { [weak self] data in
            DispatchQueue.main.async {
                self?.handleCommonNameMutationAcknowledgement(data)
            }
        }
        transport.onStatusChange = { [weak self] status in
            DispatchQueue.main.async {
                self?.connectivityStatus = status
                guard status.isActivated else { return }
                self?.flushPendingWatchRecords()
                self?.flushPendingCommonNameUsage()
                self?.flushPendingCommonNameMutations(force: false)
                if status.isReachable {
                    self?.requestCommonNamesSnapshot()
                }
            }
        }
        WatchRecordManager.shared.recordTransferHandler = { [weak self] payload in
            #if DEBUG
            print("[WatchLink] recordTransferHandler fired for \(payload.id)")
            #endif
            self?.transferFinishedRecord(payload)
        }
        transport.onCatchUpRequest = { [weak self] in
            DispatchQueue.main.async {
                self?.respondToCatchUpRequest()
            }
        }
        transport.onClearPendingRequest = { [weak self] ids in
            DispatchQueue.main.async {
                self?.clearPendingWatchRecords(ids: ids)
            }
        }
        transport.activate()
        connectivityStatus = transport.status
        scheduleRetryIfNeeded()
        if connectivityStatus.isActivated {
            handleApplicationContext(transport.receivedApplicationContext)
            flushPendingCommonNameMutations(force: false)
        }
        #if DEBUG
        print("[WatchLink] recordTransferHandler registered at WatchLinkService init")
        #endif
    }

    var isController: Bool {
        controlRole == .watchController
    }

    var canEditLinkedMatch: Bool {
        isController || controlRole == .shared
    }

    var incomingSnapshot: LinkedSnapshotUpdate? {
        guard let update = latestSnapshot,
              isFollower || (controlRole == .shared && LinkSharedRevision.writer(of: update.revision) == .phone)
        else { return nil }
        return update
    }

    var peerFinishedSharedMatch: Bool {
        controlRole == .shared && incomingSnapshot?.snapshot.isFinished == true
    }

    #if DEBUG
    var hasScheduledRetryForTesting: Bool { ackRetryTask != nil }
    #endif

    func clearLinkError() {
        lastLinkErrorMessage = nil
    }

    /// Watch side of the catch-up handshake: gather queued finished records and push them to the phone.
    func respondToCatchUpRequest() {
        let datas = pendingWatchRecords
            .map { sizedPendingRecordData($0) }
            .filter { !$0.isEmpty }
        #if DEBUG
        print("[WatchLink] respondToCatchUpRequest pending=\(pendingWatchRecords.count) encoded=\(datas.count)")
        #endif
        guard !datas.isEmpty else { return }
        transport.sendPendingWatchRecords(datas)
    }

    /// Phone confirmed it ingested these ids; drop them from the local queue.
    func clearPendingWatchRecords(ids: [String]) {
        WatchRecordManager.shared.markSynced(ids: ids)
        #if DEBUG
        print("[WatchLink] clearPendingWatchRecords ids=\(ids)")
        #endif
        let set = Set(ids)
        let before = pendingWatchRecords.count
        pendingWatchRecords.removeAll { set.contains($0.id) }
        guard pendingWatchRecords.count != before else { return }
        persistPendingWatchRecords()
    }

}

@MainActor
protocol WatchLinkRecordSink {
    @discardableResult
    func ingest(
        payload: LinkMatchFinishedPayload,
        gameType: ScoreCore.GameType,
        matchId: UUID,
        syncState: WatchRecordSyncState
    ) -> String?

    func markSynced(recordId: String)
}

struct DefaultWatchLinkRecordSink: WatchLinkRecordSink {
    nonisolated init() {}

    @discardableResult
    func ingest(
        payload: LinkMatchFinishedPayload,
        gameType: ScoreCore.GameType,
        matchId: UUID,
        syncState: WatchRecordSyncState
    ) -> String? {
        WatchLinkedRecordIngestor.ingest(
            payload: payload,
            gameType: gameType,
            matchId: matchId,
            syncState: syncState
        )
    }

    func markSynced(recordId: String) {
        guard !recordId.isEmpty else { return }
        WatchRecordManager.shared.markSynced(ids: [recordId])
    }
}

/// Persists finished Watch↔Phone linked matches into the Watch local history store
/// without re-triggering standalone `transferToPhone` delivery.
enum WatchLinkedRecordIngestor {
    @MainActor
    @discardableResult
    static func ingest(
        payload: LinkMatchFinishedPayload,
        gameType: ScoreCore.GameType,
        matchId: UUID,
        syncState: WatchRecordSyncState
    ) -> String? {
        guard let record = makeRecord(payload: payload, gameType: gameType, matchId: matchId) else {
            return nil
        }
        guard WatchRecordManager.shared.saveRecord(record, transferToPhone: false) else { return nil }
        switch syncState {
        case .sent:
            WatchRecordManager.shared.markSynced(ids: [record.id])
        case .pending:
            WatchRecordManager.shared.setSyncState(.pending, for: record.id)
        }
        return record.id
    }

    @MainActor
    static func makeRecord(
        payload: LinkMatchFinishedPayload,
        gameType: ScoreCore.GameType,
        matchId: UUID
    ) -> WatchScoreboardRecord? {
        guard let watchGameType = WatchGameType(scoreCoreGameType: gameType) else { return nil }
        let recordId = payload.recordId.isEmpty ? "w_\(matchId.uuidString)" : payload.recordId
        let start = Date(timeIntervalSince1970: Double(payload.startTimeEpochMilliseconds) / 1000)
        let end = Date(timeIntervalSince1970: Double(payload.endTimeEpochMilliseconds) / 1000)
        let duration = max(0, payload.durationSeconds)
        let training = payload.snapshot.basketballTrainingState
        let details = training?.detailedActions(endingAt: end) ?? payload.detailedActions
        let actions = details.map(WatchScoreAction.init(detailedAction:))
        let scoreChanges = training?.counts.attempts ?? max(0, payload.totalScoreChanges)
        let projected = project(
            snapshot: payload.snapshot,
            gameType: gameType,
            winnerSide: payload.winnerSide,
            participantNames: payload.participantNames
        )
        return WatchScoreboardRecord(
            id: recordId,
            gameType: watchGameType,
            startTime: start,
            endTime: end,
            duration: duration,
            team1Name: projected.team1Name,
            team2Name: projected.team2Name,
            team1FinalScore: projected.team1FinalScore,
            team2FinalScore: projected.team2FinalScore,
            team1SetScore: projected.team1SetScore,
            team2SetScore: projected.team2SetScore,
            winner: projected.winner,
            actions: actions,
            totalScoreChanges: scoreChanges,
            participants: projected.participants,
            projectConfiguration: projected.projectConfiguration,
            basketballTrainingDetails: projected.basketballTrainingDetails
        )
    }

    private struct Projection {
        let team1Name: String
        let team2Name: String
        let team1FinalScore: Int
        let team2FinalScore: Int
        let team1SetScore: Int
        let team2SetScore: Int
        let winner: String?
        let participants: [WatchRecordParticipant]?
        let projectConfiguration: [String: String]
        let basketballTrainingDetails: WatchBasketballTrainingDetails?

        init(
            team1Name: String,
            team2Name: String,
            team1FinalScore: Int,
            team2FinalScore: Int,
            team1SetScore: Int,
            team2SetScore: Int,
            winner: String?,
            participants: [WatchRecordParticipant]?,
            projectConfiguration: [String: String],
            basketballTrainingDetails: WatchBasketballTrainingDetails? = nil
        ) {
            self.team1Name = team1Name
            self.team2Name = team2Name
            self.team1FinalScore = team1FinalScore
            self.team2FinalScore = team2FinalScore
            self.team1SetScore = team1SetScore
            self.team2SetScore = team2SetScore
            self.winner = winner
            self.participants = participants
            self.projectConfiguration = projectConfiguration
            self.basketballTrainingDetails = basketballTrainingDetails
        }
    }

    @MainActor
    private static func project(
        snapshot: LinkedScoreboardSnapshot,
        gameType: ScoreCore.GameType,
        winnerSide: MatchSide?,
        participantNames: [String]
    ) -> Projection {
        func resolvedWinner(leftName: String, rightName: String, fallbackLeft: Int, fallbackRight: Int) -> String? {
            switch winnerSide {
            case .left: return leftName
            case .right: return rightName
            case nil:
                if fallbackLeft == fallbackRight { return nil }
                return fallbackLeft > fallbackRight ? leftName : rightName
            }
        }

        switch snapshot {
        case .rally(let state):
            return Projection(
                team1Name: state.leftName,
                team2Name: state.rightName,
                team1FinalScore: state.leftPoints,
                team2FinalScore: state.rightPoints,
                team1SetScore: state.leftSets,
                team2SetScore: state.rightSets,
                winner: resolvedWinner(
                    leftName: state.leftName,
                    rightName: state.rightName,
                    fallbackLeft: state.leftSets,
                    fallbackRight: state.rightSets
                ),
                participants: state.doubles?.playerNames.map {
                    WatchRecordParticipant(name: $0, score: 0)
                },
                projectConfiguration: [
                    "scoreCoreGameType": gameType.rawValue,
                    "isSingles": String(state.doubles == nil),
                    "maxSets": String(state.rules.maxSets),
                    "pointsPerSet": String(state.rules.pointsToWinSet),
                    "useRallyScoring": String(state.rules.useRallyScoring),
                    "rallyScoring": String(state.rules.useRallyScoring),
                    "isDoubles": String(state.doubles != nil)
                ]
            )
        case .tennis(let state):
            let isTiebreakOnly = state.rules.setScoringMode == .tiebreakOnly
            let fallbackLeft = isTiebreakOnly ? state.leftPoints : state.leftSets
            let fallbackRight = isTiebreakOnly ? state.rightPoints : state.rightSets
            return Projection(
                team1Name: state.leftName,
                team2Name: state.rightName,
                team1FinalScore: isTiebreakOnly ? state.leftPoints : state.leftGames,
                team2FinalScore: isTiebreakOnly ? state.rightPoints : state.rightGames,
                team1SetScore: state.leftSets,
                team2SetScore: state.rightSets,
                winner: resolvedWinner(
                    leftName: state.leftName,
                    rightName: state.rightName,
                    fallbackLeft: fallbackLeft,
                    fallbackRight: fallbackRight
                ),
                participants: state.doublesPlayerNames?.map {
                    WatchRecordParticipant(name: $0, score: 0)
                },
                projectConfiguration: [
                    "scoreCoreGameType": gameType.rawValue,
                    "isSingles": String(state.doublesPlayerNames == nil),
                    "maxSets": String(state.rules.maxSets),
                    "tieBreakPoints": String(state.rules.tieBreakPoints),
                    "setScoringMode": state.rules.setScoringMode.rawValue,
                    "usesNoAdScoring": String(state.rules.usesNoAdScoring),
                    "isDoubles": String(state.doublesPlayerNames != nil)
                ]
            )
        case .archery(let state):
            return Projection(
                team1Name: state.leftName,
                team2Name: state.rightName,
                team1FinalScore: state.leftArrowSum,
                team2FinalScore: state.rightArrowSum,
                team1SetScore: state.leftSetPoints,
                team2SetScore: state.rightSetPoints,
                winner: resolvedWinner(
                    leftName: state.leftName,
                    rightName: state.rightName,
                    fallbackLeft: state.leftSetPoints,
                    fallbackRight: state.rightSetPoints
                ),
                participants: [
                    WatchRecordParticipant(name: state.leftName, score: state.leftSetPoints),
                    WatchRecordParticipant(name: state.rightName, score: state.rightSetPoints)
                ],
                projectConfiguration: [
                    "scoreCoreGameType": gameType.rawValue
                ]
            )
        case .eightBall(let state):
            let defaults = WatchDefaultTeamNames.resolve(for: .eightBall)
            let leftName = resolvedParticipantName(participantNames, index: 0, fallback: defaults.left)
            let rightName = resolvedParticipantName(participantNames, index: 1, fallback: defaults.right)
            return Projection(
                team1Name: leftName,
                team2Name: rightName,
                team1FinalScore: state.leftPoints,
                team2FinalScore: state.rightPoints,
                team1SetScore: state.leftPoints,
                team2SetScore: state.rightPoints,
                winner: resolvedWinner(
                    leftName: leftName,
                    rightName: rightName,
                    fallbackLeft: state.leftPoints,
                    fallbackRight: state.rightPoints
                ),
                participants: nil,
                projectConfiguration: [
                    "scoreCoreGameType": gameType.rawValue,
                    "targetRacks": String(state.targetPoints),
                    "handicapRacks": String(state.handicapRacks),
                    "handicapBeneficiary": state.handicapBeneficiary?.rawValue ?? "none"
                ]
            )
        case .nineBall(let state):
            let count = max(2, state.playerCount)
            let names: [String] = (0..<count).map { index in
                let fallback = resolvedParticipantName(
                    participantNames,
                    index: index,
                    fallback: String(
                        format: NSLocalizedString(
                            "multi_score_player_default_format",
                            value: "选手 %d",
                            comment: ""
                        ),
                        index + 1
                    )
                )
                return state.resolvedName(at: index, fallback: fallback)
            }
            let points: [Int] = (0..<count).map { index in
                state.playerPoints.indices.contains(index) ? state.playerPoints[index] : 0
            }
            let winner: String? = {
                if count > 2 {
                    guard let best = points.max() else { return nil }
                    let leaders = points.indices.filter { points[$0] == best }
                    return leaders.count == 1 ? names[leaders[0]] : nil
                }
                return resolvedWinner(
                    leftName: names[0],
                    rightName: names[1],
                    fallbackLeft: points[0],
                    fallbackRight: points[1]
                )
            }()
            return Projection(
                team1Name: names[0],
                team2Name: names[1],
                team1FinalScore: points[0],
                team2FinalScore: points[1],
                team1SetScore: points[0],
                team2SetScore: points[1],
                winner: winner,
                participants: (0..<count).map {
                    WatchRecordParticipant(name: names[$0], score: points[$0])
                },
                projectConfiguration: [
                    "scoreCoreGameType": gameType.rawValue,
                    "playerCount": String(count)
                ]
            )
        case .snooker(let state):
            let defaults = WatchDefaultTeamNames.resolve(for: .snooker)
            let leftName = resolvedParticipantName(participantNames, index: 0, fallback: defaults.left)
            let rightName = resolvedParticipantName(participantNames, index: 1, fallback: defaults.right)
            let fallbackLeft = state.leftFrames != state.rightFrames ? state.leftFrames : state.leftScore
            let fallbackRight = state.leftFrames != state.rightFrames ? state.rightFrames : state.rightScore
            return Projection(
                team1Name: leftName,
                team2Name: rightName,
                team1FinalScore: state.leftScore,
                team2FinalScore: state.rightScore,
                team1SetScore: state.leftFrames,
                team2SetScore: state.rightFrames,
                winner: resolvedWinner(
                    leftName: leftName,
                    rightName: rightName,
                    fallbackLeft: fallbackLeft,
                    fallbackRight: fallbackRight
                ),
                participants: nil,
                projectConfiguration: [
                    "scoreCoreGameType": gameType.rawValue,
                    "maxFrames": String(state.maxFrames)
                ]
            )
        case .football(let state):
            return Projection(
                team1Name: state.leftName,
                team2Name: state.rightName,
                team1FinalScore: state.leftScore,
                team2FinalScore: state.rightScore,
                team1SetScore: 0,
                team2SetScore: 0,
                winner: resolvedWinner(
                    leftName: state.leftName,
                    rightName: state.rightName,
                    fallbackLeft: state.leftScore,
                    fallbackRight: state.rightScore
                ),
                participants: nil,
                projectConfiguration: [
                    "scoreCoreGameType": gameType.rawValue,
                    "footballHalfLengthSeconds": String(state.timer.halfLengthSeconds),
                    "showMatchTime": "true"
                ]
            )
        case .basketballTraining(let state):
            let mode = WatchBasketballTrainingMode(linkedMode: state.mode)
            let counts = state.counts
            let shots = state.shots.map {
                WatchBasketballTrainingShot(points: $0.points, made: $0.made, timestamp: $0.timestamp)
            }
            var configuration: [String: String] = [
                "scoreCoreGameType": gameType.rawValue,
                "type": "basketball_training",
                "gameMode": mode.fixedPoints.map { "\($0)pt" } ?? "free",
                "basketballTrainingMode": mode.fixedPoints == nil ? "mixed" : "fixed",
                "basketballTrainingScoringMode": mode.fixedPoints.map { "fixed_\($0)" } ?? "free"
            ]
            if let fixedPoints = mode.fixedPoints {
                configuration["targetScore"] = String(fixedPoints)
            }
            return Projection(
                team1Name: NSLocalizedString("watch_training_miss", value: "未中", comment: ""),
                team2Name: NSLocalizedString("watch_training_made", value: "命中", comment: ""),
                team1FinalScore: counts.missed,
                team2FinalScore: counts.made,
                team1SetScore: 0,
                team2SetScore: 0,
                winner: nil,
                participants: nil,
                projectConfiguration: configuration,
                basketballTrainingDetails: WatchBasketballTrainingDetails(mode: mode, shots: shots, totals: counts)
            )
        }
    }

    private static func resolvedParticipantName(
        _ names: [String],
        index: Int,
        fallback: String
    ) -> String {
        guard names.indices.contains(index) else { return fallback }
        let trimmed = names[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
