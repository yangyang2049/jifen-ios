import Foundation

/// Shared transport boundary for both linked-scoreboard peers.
///
/// The engine owns exactly the parts that are duplicated verbatim today in
/// `WatchLinkService` / `PhoneWatchLinkService`:
///
/// 1. **Safe receive** (`route(_:)`) — probe the `[0x4A, 0x46, 0x01]` LZFSE
///    terminal prefix before any JSON decoding, decode `LinkEnvelopeHead`
///    exactly once, and drop frames from the local peer or above the
///    framed-payload budget. Typed payload decoding stays with the app: each
///    peer decodes only the kinds it accepts, and no `LinkSync` type ever
///    enters this file.
/// 2. **Send fallback** (`send(_:peerSupportsCompressedFinish:peerSupportsFileTransfer:)`
///    and `sendReplayableFrame(_:kind:peerSupportsFileTransfer:)`) — live
///    channel, latest-snapshot context partition, bounded `transferUserInfo`,
///    negotiated `transferFile`, or hold-in-outbox.
/// 3. **Bounded retry** (`nextRetryDeadlineEpochMilliseconds(...)`,
///    `nextRetryDelayNanoseconds(...)`, `retryDue(...)`) — interactive control
///    frames retry `LinkControlRetryQueue.maxRetries` times and then expire,
///    durable terminal frames never expire, and delta-history frames are
///    retained until the peer acknowledges them.
///
/// Persistence and the ACK that follows a successful persist stay in the app:
/// `terminalOutbox` is a value the app loads before init and re-encodes after
/// every retry that mutates it, and the business ACK is sent by the handler
/// that owns the store. Nothing here is WatchConnectivity-specific, so the
/// whole boundary runs in `swift test` on macOS.
///
/// Adoption (both ends keep their existing typed handlers):
/// ```
/// // Watch: WatchLinkMessageHandling.receive(_:)
/// switch engine.route(data) {
/// case .terminalFrame(let frame): handled = handleMatchFinishedFromPhone(frame)
/// case .envelope(let head, let body): handled = route(head, body)   // existing kind switch
/// case .oversize, .wrongSender, .undecodable: handled = false
/// }
/// if handled { markCommunication() } else { handleMalformedSetupRequest(data) }
///
/// // Phone: PhoneWatchLinkMessageHandling.handleIncoming(_:)
/// switch engine.route(data) {
/// case .terminalFrame(let frame): _ = handleMatchFinishedFromWatch(frame)
/// case .envelope(let head, let body): route(head, body)             // existing kind switch
/// case .oversize, .wrongSender, .undecodable: break
/// }
///
/// // Send: replaces send(_:)/sendEnvelope(_:)
/// let outcome = await engine.send(
///     envelope,
///     peerSupportsCompressedFinish: peerSupportsCompressedFinish,
///     peerSupportsFileTransfer: peerSupportsFileTransfer
/// )
/// if let error = outcome.firstErrorDescription { lastErrorMessage = error }
/// // Replayed frames (intentSubmit/intentCommit/ACK/terminal) use one entry:
/// let outcome = await engine.sendReplayableFrame(
///     data,
///     kind: .intentFrame,
///     peerSupportsFileTransfer: peerSupportsFileTransfer
/// )
/// // Outbox retries re-deliver the exact stored frame by its own snapshot:
/// _ = await engine.sendReplayableFrame(
///     item.data, kind: .matchFinished,
///     peerSupportsFileTransfer: item.peerSupportsFileTransfer ?? false
/// )
///
/// // Retry: replaces performRetryWork()/nextRetryDelayNanoseconds()
/// for action in engine.retryDue(retainsControlFrame: tracksHistory) {
///     switch action {
///     case .resendControl(let data): try? await transport.sendRealtime(data)
///     case .controlExpired(let messageId): /* session machine + timeout notice */
///     case .resendTerminal(let item): await engine.sendReplayableFrame(
///         item.data, kind: .matchFinished,
///         peerSupportsFileTransfer: item.peerSupportsFileTransfer ?? false
///     )
///     }
/// }
/// ```
public struct LinkSessionEngine: Sendable {
    /// Framed-payload budget for one inbound frame. It matches the terminal
    /// decoder's own budget (`LinkFinishedEncoding`): anything larger is
    /// dropped without parsing instead of being handed to a JSON decoder.
    public static let defaultMaximumFrameBytes = 2 * 1024 * 1024
    /// A pending session end has no acknowledgement queue of its own; keep the
    /// shared one-second backoff only while one is actually pending.
    public static let pendingSessionEndRetryMilliseconds: Int64 = 1_000

    public let localPeer: LinkPeer
    public let transport: any LinkTransport
    public let clock: any LinkClock
    public let maximumFrameBytes: Int
    /// Reliable large-frame channel (`WCSession.transferFile`). Nil on a
    /// platform without a file channel: durable frames that exceed the
    /// dictionary budget then stay in `terminalOutbox` and retry later.
    public let fileTransfer: (@Sendable (Data, WatchTransferFileKind) throws -> Void)?

    /// Latest interactive control frame waiting for its acknowledgement. The
    /// app reads this for the delta-action ledger, exactly as it read
    /// `pendingAck` before.
    public var pendingControl: LinkControlRetryQueue
    /// Durable terminal frames awaiting an acknowledgement. The app owns the
    /// store: it restores this value before init and re-encodes it after every
    /// mutation (`retryDue` included).
    public var terminalOutbox: LinkDurableOutbox

    public init(
        localPeer: LinkPeer,
        transport: any LinkTransport,
        clock: any LinkClock = SystemLinkClock(),
        maximumFrameBytes: Int = LinkSessionEngine.defaultMaximumFrameBytes,
        pendingControl: LinkControlRetryQueue = LinkControlRetryQueue(),
        terminalOutbox: LinkDurableOutbox = LinkDurableOutbox(),
        fileTransfer: (@Sendable (Data, WatchTransferFileKind) throws -> Void)? = nil
    ) {
        self.localPeer = localPeer
        self.transport = transport
        self.clock = clock
        self.maximumFrameBytes = max(1, maximumFrameBytes)
        self.pendingControl = pendingControl
        self.terminalOutbox = terminalOutbox
        self.fileTransfer = fileTransfer
    }

    // MARK: - Receive

    /// Classifies one received frame without decoding its payload.
    ///
    /// Ordering is contractual: a compressed terminal frame is not JSON, so the
    /// magic prefix must win before `LinkEnvelopeHead` is attempted. Regular
    /// envelopes are supported by the same call, which is why both peers can
    /// keep a single receive entry point.
    public func route(_ data: Data) -> LinkInboundRoute {
        guard data.count <= maximumFrameBytes else { return .oversize(data.count) }
        if LinkFinishedEncoding.isCompressedFrame(data) { return .terminalFrame(data) }
        guard let head = try? JSONDecoder().decode(LinkEnvelopeHead.self, from: data) else {
            return .undecodable
        }
        guard head.sender != localPeer else { return .wrongSender(head) }
        return .envelope(head, data)
    }

    // MARK: - Send

    /// Encodes an envelope once and routes it by kind, mirroring the two
    /// hand-written `switch envelope.kind` blocks this replaces:
    ///
    /// - `.stateSnapshot`: publish the action-stripped checkpoint on
    ///   `applicationContext`, then the full frame on the live channel when the
    ///   peer is reachable.
    /// - `.matchFinished`: built by `LinkFinishedFrameBuilder` — which never
    ///   trims history — and then delivered through the durable channels. A
    ///   terminal frame is therefore never sized by `LinkEnvelopeEncoding`'s
    ///   action-trimming fallback before channel selection.
    /// - everything else (handshake, ACK, intent submit/commit, resync, status,
    ///   side channels): the live channel.
    ///
    /// A failing channel never suppresses the other one and never throws;
    /// inspect `LinkSendOutcome.failures`.
    @discardableResult
    public func send<Payload: Codable & Sendable>(
        _ envelope: LinkEnvelope<Payload>,
        peerSupportsCompressedFinish: Bool = false,
        peerSupportsFileTransfer: Bool = false
    ) async -> LinkSendOutcome {
        let data = LinkEnvelopeEncoding.encodedData(envelope)
        switch envelope.kind {
        case .matchFinished:
            guard let terminal = envelope as? LinkEnvelope<LinkMatchFinishedPayload> else {
                return await deliver([.realtime(data)])
            }
            let built = LinkFinishedFrameBuilder.buildFrame(
                terminal,
                peerSupportsCompressedFinish: peerSupportsCompressedFinish
            )
            let frame = built.isEmpty ? data : built
            return await sendReplayableFrame(
                frame,
                kind: .matchFinished,
                peerSupportsFileTransfer: peerSupportsFileTransfer
            )
        case .stateSnapshot:
            var frames: [OutboundFrame] = [
                .latestSnapshot(LinkEnvelopeEncoding.applicationContextData(envelope))
            ]
            if transport.isReachable { frames.append(.realtime(data)) }
            return await deliver(frames)
        default:
            return await deliver([.realtime(data)])
        }
    }

    /// Live-first delivery for an already-encoded frame that the sender must
    /// keep replaying until the peer confirms it: `intentSubmit`,
    /// `intentCommit`, `matchFinished`, acknowledgements and checkpoints.
    ///
    /// Within the realtime budget a reachable peer gets the frame immediately
    /// and a successful send returns at once, with no duplicate on the durable
    /// channels. Only a failure or an unreachable peer falls through to the
    /// bounded durable choice: `transferUserInfo` (≤32 KB), the negotiated file
    /// channel, or `.hold` when neither is admissible — the caller then keeps
    /// its pending operation and replays it, which is what an unsendable intent
    /// must do. The frame is never trimmed here, so its full history survives.
    ///
    /// `peerSupportsFileTransfer` is the capability captured with the pending
    /// item, not whichever session happens to be active at replay time.
    @discardableResult
    public func sendReplayableFrame(
        _ data: Data,
        kind: WatchTransferFileKind,
        peerSupportsFileTransfer: Bool
    ) async -> LinkSendOutcome {
        if data.count <= LinkFinishedRouting.realtimeBudgetBytes, transport.isReachable {
            do {
                try await transport.sendRealtime(data)
                return LinkSendOutcome(steps: [.realtime])
            } catch {
                // The live attempt just failed, so fall back to the durable
                // channels only and keep the live failure for diagnostics.
                let fallback = await deliver(durableFrames(data, kind: kind, peerSupportsFileTransfer: peerSupportsFileTransfer))
                return LinkSendOutcome(
                    steps: [.realtime] + fallback.steps,
                    failures: fallback.failures.merging([.realtime: error.localizedDescription]) { current, _ in current }
                )
            }
        }
        return await deliver(durableFrames(data, kind: kind, peerSupportsFileTransfer: peerSupportsFileTransfer))
    }

    /// The bounded durable ladder for a frame that cannot use the live channel.
    private func durableFrames(
        _ data: Data,
        kind: WatchTransferFileKind,
        peerSupportsFileTransfer: Bool
    ) -> [OutboundFrame] {
        switch LinkFinishedRouting.chooseDurableChannel(
            frameByteCount: data.count,
            peerSupportsFileTransfer: peerSupportsFileTransfer
        ) {
        case .userInfo: [.durableUserInfo(data)]
        case .file: [.durableFile(data, kind)]
        case .hold: [.hold(data)]
        }
    }

    private enum OutboundFrame {
        case latestSnapshot(Data)
        case realtime(Data)
        case durableUserInfo(Data)
        case durableFile(Data, WatchTransferFileKind)
        case hold(Data)

        var channel: LinkSendChannel {
            switch self {
            case .latestSnapshot: .latestSnapshot
            case .realtime: .realtime
            case .durableUserInfo: .durableUserInfo
            case .durableFile: .durableFile
            case .hold: .hold
            }
        }
    }

    private func deliver(_ frames: [OutboundFrame]) async -> LinkSendOutcome {
        var failures: [LinkSendChannel: String] = [:]
        for frame in frames {
            do {
                switch frame {
                case .latestSnapshot(let data):
                    try transport.publishLatestSnapshot(data)
                case .realtime(let data):
                    try await transport.sendRealtime(data)
                case .durableUserInfo(let data):
                    try transport.enqueueDurable(data)
                case .durableFile(let data, let kind):
                    guard let fileTransfer else { throw LinkSessionEngineError.fileChannelUnavailable }
                    try fileTransfer(data, kind)
                case .hold:
                    break
                }
            } catch {
                failures[frame.channel] = error.localizedDescription
            }
        }
        return LinkSendOutcome(steps: frames.map(\.channel), failures: failures)
    }

    // MARK: - Bounded retry

    /// Next instant at which `retryDue(...)` has work, or nil when both queues
    /// are settled. `retainsControlFrame` means the pending control frame still
    /// carries unacknowledged action history (`peerSupportsDeltaActions &&
    /// deltaActionTracker.carriesHistory`): that frame is only retried while the
    /// peer is reachable and is never dropped on attempt exhaustion.
    public func nextRetryDeadlineEpochMilliseconds(
        retainsControlFrame: Bool = false,
        hasPendingSessionEnd: Bool = false
    ) -> Int64? {
        let now = clock.nowEpochMilliseconds()
        var deadlines: [Int64] = []
        if let pending = pendingControl.pending, transport.isReachable || !retainsControlFrame {
            deadlines.append(
                pending.lastSentAtEpochMilliseconds + LinkControlRetryQueue.retryIntervalMilliseconds
            )
        }
        deadlines.append(contentsOf: terminalOutbox.items.map {
            $0.lastSentAtEpochMilliseconds + LinkDurableOutbox.retryIntervalMilliseconds
        })
        if hasPendingSessionEnd {
            deadlines.append(now + Self.pendingSessionEndRetryMilliseconds)
        }
        return deadlines.min()
    }

    /// Convenience for `Task.sleep(nanoseconds:)`; nil means nothing is queued
    /// and the retry task can stop rescheduling itself.
    public func nextRetryDelayNanoseconds(
        retainsControlFrame: Bool = false,
        hasPendingSessionEnd: Bool = false
    ) -> UInt64? {
        guard let deadline = nextRetryDeadlineEpochMilliseconds(
            retainsControlFrame: retainsControlFrame,
            hasPendingSessionEnd: hasPendingSessionEnd
        ) else { return nil }
        let delay = max(0, deadline - clock.nowEpochMilliseconds())
        return UInt64(delay) * 1_000_000
    }

    /// Returns the work that is due now, in the order both peers already used:
    /// the interactive frame first, then every due durable terminal frame.
    ///
    /// Bounded by construction — `LinkControlRetryQueue` stops after
    /// `maxRetries` and reports `.controlExpired` (unless the frame carries
    /// history, in which case it is retained), while `LinkDurableOutbox` items
    /// never expire and only an explicit acknowledgement removes them.
    /// `sendImmediately` is the reconnect path: it resends a retained history
    /// frame without waiting for the retry interval.
    @discardableResult
    public mutating func retryDue(
        retainsControlFrame: Bool = false,
        sendImmediately: Bool = false
    ) -> [LinkRetryAction] {
        let now = clock.nowEpochMilliseconds()
        var actions: [LinkRetryAction] = []
        let pendingControlMessageId = pendingControl.pending?.messageId
        if !retainsControlFrame || transport.isReachable,
           let data = pendingControl.retryIfDue(
               nowEpochMilliseconds: now,
               retainAfterExhaustion: retainsControlFrame,
               sendImmediately: retainsControlFrame && sendImmediately
           ) {
            actions.append(.resendControl(data))
        } else if let pendingControlMessageId, pendingControl.pending == nil {
            actions.append(.controlExpired(messageId: pendingControlMessageId))
        }
        for item in terminalOutbox.retryDueItems(nowEpochMilliseconds: now) {
            actions.append(.resendTerminal(item))
        }
        return actions
    }
}

/// Result of the shared receive boundary.
///
/// Not `Equatable`: `LinkEnvelopeHead` carries no equality conformance, so
/// callers pattern-match instead.
public enum LinkInboundRoute: Sendable {
    /// `[0x4A, 0x46, 0x01]` LZFSE terminal frame. Decode it with
    /// `LinkFinishedEncoding.decode(_:)`, never with a JSON decoder.
    case terminalFrame(Data)
    /// Regular JSON envelope, decoded only as far as its head. The typed
    /// payload is still undecoded: that is the app's `LinkSync`-facing step.
    case envelope(LinkEnvelopeHead, Data)
    /// Larger than `maximumFrameBytes`; dropped without parsing.
    case oversize(Int)
    /// The envelope claims this peer as its sender.
    case wrongSender(LinkEnvelopeHead)
    /// No terminal prefix and no decodable head.
    case undecodable
}

/// One channel a frame was handed to, in execution order.
public enum LinkSendChannel: String, CaseIterable, Hashable, Sendable {
    /// `updateApplicationContext` checkpoint partition (actions stripped).
    case latestSnapshot
    /// `sendMessageData` live channel.
    case realtime
    /// `transferUserInfo` durable channel (≤32 KB).
    case durableUserInfo
    /// `transferFile` durable channel, peer-negotiated.
    case durableFile
    /// No admissible channel: the frame stays in `terminalOutbox`.
    case hold
}

/// What a send actually did. A failed channel is recorded, not thrown: the
/// peer-facing behaviour is "best effort per channel, retry loop covers the
/// rest", which is what both services already implemented by hand.
public struct LinkSendOutcome: Equatable, Sendable {
    public let steps: [LinkSendChannel]
    public let failures: [LinkSendChannel: String]

    public init(steps: [LinkSendChannel], failures: [LinkSendChannel: String] = [:]) {
        self.steps = steps
        self.failures = failures
    }

    public var isFullyDelivered: Bool { failures.isEmpty }

    /// True when the frame was only held for the outbox to retry.
    public var isHeld: Bool { steps.contains(.hold) }

    /// First channel error, in the same shape the services' `lastErrorMessage`
    /// already expects.
    public var firstErrorDescription: String? { failures.values.first }
}

/// Work produced by `LinkSessionEngine.retryDue(...)`.
public enum LinkRetryAction: Equatable, Sendable {
    /// The due interactive control frame; resend it on the live channel.
    case resendControl(Data)
    /// Bounded control attempts are exhausted and the frame carried no action
    /// history: acknowledge the pending id and report a sync timeout, exactly
    /// as the hand-written retry loops did.
    case controlExpired(messageId: UUID)
    /// A durable frame is due. Replay it through
    /// `sendReplayableFrame(_:kind:peerSupportsFileTransfer:)` with the item's
    /// own negotiated capability snapshot, and persist `terminalOutbox` first
    /// when the app also had to save a local record.
    case resendTerminal(LinkDurableOutbox.Item)
}

public enum LinkSessionEngineError: Error, Equatable, Sendable {
    /// The peer negotiated `fileTransfer` but no file sink was injected.
    case fileChannelUnavailable
}
