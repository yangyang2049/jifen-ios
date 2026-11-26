import Foundation
import RecordCore
import ScoreCore

/// Tracks which detailed actions the peer has already acknowledged so live
/// snapshots only carry the unacknowledged delta. Kept per linked session;
/// reset on manual resync and next-match transitions.
public struct LinkDeltaActionTracker: Equatable, Sendable {

    public private(set) var acknowledgedActionIDs: Set<UUID> = []
    public private(set) var inFlightMessageActions: [UUID: [UUID]] = [:]

    private var acknowledgedRemovalIDs: Set<UUID> = []
    private var inFlightRemovalIDs: [UUID] = []

    public init() {}

    /// Actions that still need to reach the peer, in chronological order.
    public func pendingDeltaActions(of actions: [DetailedScoreAction]) -> [DetailedScoreAction] {
        actions.filter { !acknowledgedActionIDs.contains($0.id) }
    }

    /// Record ONLY the actions that actually reached the wire. Callers pass the
    /// post-trim action list returned by `LinkEnvelopeEncoding.dataWithSentActions`
    /// (decoded from the final frame, never inferred), so actions dropped by the
    /// byte budget stay pending: their ACK never exists, and later frames
    /// re-send them until the peer consumes them.
    public mutating func noteSent(messageId: UUID, actions: [DetailedScoreAction]) {
        inFlightMessageActions[messageId] = actions.map(\.id)
    }

    /// The live retry queue only keeps the latest snapshot. Its replacement
    /// still includes every unacknowledged action, so older receipts can be ignored.
    public mutating func noteLatestSnapshot(messageId: UUID, frame: LinkEnvelopeEncoding.SnapshotFrame) {
        inFlightMessageActions.removeAll(keepingCapacity: true)
        inFlightRemovalIDs = frame.removedActionIDs
        noteSent(messageId: messageId, actions: frame.actions)
    }

    public func pendingRemovalIDs(_ removed: Set<UUID>) -> [UUID] {
        removed.subtracting(acknowledgedRemovalIDs).sorted { $0.uuidString < $1.uuidString }
    }

    /// Merge the acknowledged frame's actions into the acknowledged set.
    /// **无溢出重建**：绝不用其他 in-flight 帧的 ID 冒充已确认（那会把尚未
    /// ACK 的动作从欠账里删掉）。台账只在整场生命周期内增长，换场/重置/
    /// 手动同步统一 `reset()` 清理；单场动作量远小于内存与编码上限。
    public mutating func noteAcknowledged(messageId: UUID) {
        guard let ids = inFlightMessageActions.removeValue(forKey: messageId) else { return }
        acknowledgedActionIDs.formUnion(ids)
        acknowledgedRemovalIDs.formUnion(inFlightRemovalIDs)
        inFlightRemovalIDs = []
    }

    /// Return the exact state frame acknowledged by the peer on the realtime channel.
    public func acknowledgedSnapshot(
        by ack: LinkEnvelope<LinkAcknowledgementPayload>,
        pending: LinkControlRetryQueue.PendingItem?
    ) -> LinkEnvelope<LinkedScoreboardSetup>? {
        guard ack.kind == .acknowledgement,
              let pending, pending.messageId == ack.payload.acknowledgedMessageId,
              carriesHistory(messageId: pending.messageId),
              let frame = try? JSONDecoder().decode(LinkEnvelope<LinkedScoreboardSetup>.self, from: pending.data),
              frame.kind == .stateSnapshot, frame.handle == ack.handle,
              frame.authorityEpoch == ack.authorityEpoch,
              frame.sessionRevision == ack.payload.acknowledgedRevision else { return nil }
        return frame
    }

    public func carriesHistory(messageId: UUID) -> Bool {
        guard let actions = inFlightMessageActions[messageId] else { return false }
        return !actions.isEmpty || !inFlightRemovalIDs.isEmpty
    }

    /// Keep the same score and revision while delivering the remaining history.
    public func continuation(
        of frame: LinkEnvelope<LinkedScoreboardSetup>,
        actions: [DetailedScoreAction],
        removedActionIDs: Set<UUID>,
        sequence: UInt64,
        now: Int64
    ) -> LinkEnvelope<LinkedScoreboardSetup>? {
        let remaining = pendingDeltaActions(of: actions)
        let removals = pendingRemovalIDs(removedActionIDs)
        guard !remaining.isEmpty || !removals.isEmpty else { return nil }
        var payload = frame.payload
        payload.detailedActions = remaining
        payload.removedActionIDs = removals.isEmpty ? nil : removals
        payload.isDeltaActions = removals.isEmpty
        return LinkEnvelope(
            sessionId: frame.sessionId,
            matchId: frame.matchId,
            matchGeneration: frame.matchGeneration,
            authorityEpoch: frame.authorityEpoch,
            kind: .stateSnapshot,
            sender: frame.sender,
            senderSequence: sequence,
            sessionRevision: frame.sessionRevision,
            sentAtEpochMilliseconds: now,
            payload: payload
        )
    }

    /// Manual resync and next-match start from a clean action ledger.
    public mutating func reset() {
        acknowledgedActionIDs = []
        inFlightMessageActions = [:]
        acknowledgedRemovalIDs = []
        inFlightRemovalIDs = []
    }
}
/// Linked matches synchronize additions and explicit removals by action ID.
public struct LinkSnapshotHistory: Codable, Equatable, Sendable {
    private var lastLocalActionIDs: Set<UUID> = []
    public private(set) var removedActionIDs: Set<UUID> = []

    public init() {}

    /// Only a previous local publication can establish that an action is now
    /// missing. Locally unseen actions received from the peer stay in history.
    @discardableResult
    public mutating func noteLocalPublication(_ actions: [DetailedScoreAction]) -> Bool {
        let current = Set(actions.map(\.id))
        let removed = lastLocalActionIDs.subtracting(current).subtracting(removedActionIDs)
        lastLocalActionIDs = current
        removedActionIDs.formUnion(removed)
        return !removed.isEmpty
    }

    public mutating func noteRemoteRemovals(_ ids: [UUID]) {
        removedActionIDs.formUnion(ids)
    }

    public func merging(
        _ incoming: [DetailedScoreAction],
        into current: [DetailedScoreAction]
    ) -> [DetailedScoreAction] {
        var byID = [UUID: DetailedScoreAction]()
        for action in current + incoming where !removedActionIDs.contains(action.id) && byID[action.id] == nil {
            byID[action.id] = action
        }
        return byID.values.sorted {
            ($0.epochMilliseconds ?? 0, $0.id.uuidString) < ($1.epochMilliseconds ?? 0, $1.id.uuidString)
        }
    }
}

/// Channel choice for durable (terminal) frames, per the three-channel layout:
/// `transferUserInfo` carries the background dictionary up to 32KB; larger
/// frames go through `transferFile` when the peer negotiated the capability;
/// otherwise the full payload is held in the outbox until a capable channel
/// appears — trimming before channel selection is forbidden.
public enum LinkDurableChannel: Equatable, Sendable {
    case userInfo
    case file
    /// No admissible channel right now: keep the full payload queued.
    case hold
}

public enum LinkFinishedRouting {
    /// Background `transferUserInfo` budget for terminal frames.
    public static let userInfoBudgetBytes = 32_000
    /// Realtime (`sendMessageData`) budget — enforced by the transport too.
    public static let realtimeBudgetBytes = 60_000

    public static func chooseDurableChannel(
        frameByteCount: Int,
        peerSupportsFileTransfer: Bool
    ) -> LinkDurableChannel {
        if frameByteCount <= userInfoBudgetBytes { return .userInfo }
        if peerSupportsFileTransfer { return .file }
        return .hold
    }
}

/// Builds the wire frame for a terminal payload without ever trimming actions.
/// Compression only applies when the peer negotiated the capability; oversize
/// payloads travel whole on the file channel.
public enum LinkFinishedFrameBuilder {
    public static func buildFrame(
        _ envelope: LinkEnvelope<LinkMatchFinishedPayload>,
        peerSupportsCompressedFinish: Bool
    ) -> Data {
        let compressed = peerSupportsCompressedFinish
            ? LinkFinishedEncoding.compressedFrameIfPossible(envelope)
            : nil
        if let json = LinkFinishedEncoding.fullJSONData(envelope) {
            if json.count <= LinkFinishedRouting.realtimeBudgetBytes {
                // Within the realtime budget: encode() picks the smaller of the
                // raw JSON and the compressed frame and never trims.
                return LinkFinishedEncoding.encode(envelope, compress: peerSupportsCompressedFinish)
            }
            if let compressed { return compressed }
            return json
        }
        return compressed ?? Data()
    }
}

public extension LinkDeltaActionTracker {
    /// Builds the setup-style snapshot payload. When delta actions were
    /// negotiated, only unacknowledged actions ride along and the frame is
    /// marked `isDeltaActions`; receivers merge by id so the union never shrinks.
    ///
    /// 撤销/重置等**替换权威历史**的帧（已确认动作在当前历史中缺席）必须走
    /// 非增量全量帧，并清除该场旧的增量确认状态——否则被撤销的动作永远
    /// 不会再出现在增量里，对端无法按全量重放替换语义。
    /// 返回值附带 `historyReplaced`，调用方据此维护台账（本方法已 reset）。
    mutating func snapshotSetup(
        snapshot: LinkedScoreboardSnapshot,
        gameType: ScoreCore.GameType,
        maxSets: Int?,
        participantNames: [String],
        fullActions: [DetailedScoreAction],
        deltaEnabled: Bool
    ) -> (setup: LinkedScoreboardSetup, historyReplaced: Bool) {
        let currentIDs = Set(fullActions.map(\.id))
        let historyReplaced = !acknowledgedActionIDs.isSubset(of: currentIDs)
        if historyReplaced { reset() }
        guard deltaEnabled, !historyReplaced else {
            return (
                LinkedScoreboardSetup(
                    gameType: gameType,
                    maxSets: maxSets,
                    initialSnapshot: snapshot,
                    detailedActions: fullActions,
                    participantNames: participantNames
                ),
                historyReplaced
            )
        }
        let delta = pendingDeltaActions(of: fullActions)
        return (
            LinkedScoreboardSetup(
                gameType: gameType,
                maxSets: maxSets,
                initialSnapshot: snapshot,
                detailedActions: delta,
                participantNames: participantNames,
                isDeltaActions: true
            ),
            false
        )
    }
}
