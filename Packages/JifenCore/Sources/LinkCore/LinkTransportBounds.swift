import Foundation

/// Byte ceilings shared by the WatchConnectivity transport and the pure
/// helpers the transports build on.
public enum LinkPayloadBudget {
    /// Maximum data message and application context size used by the transport.
    public static let maxBytes = 65_536

    /// Background `transferUserInfo` body budget shared by terminal frames and
    /// the common-name control channel. The dictionary channel wraps the body
    /// with its key and property-list envelope, so this stays well below the
    /// 65,536-byte ceiling; `applicationContext` is measured as the complete
    /// merged dictionary instead and only needs `maxBytes`.
    public static let userInfoBodyBudgetBytes = 32_000
}

public enum LinkApplicationContextError: Error, Equatable, Sendable {
    /// The merged dictionary cannot be encoded as a binary property list, or
    /// its encoded size exceeds the transport ceiling.
    case invalidContext
    case tooLarge(Int)
}

/// Binary property-list codec for `WCSession.applicationContext`.
///
/// The context carries raw `Data` values (the latest-snapshot partition), so a
/// JSON-based size probe rejects every realistic context. Binary property lists
/// accept `Data`, `NSNumber`, arrays and dictionaries, and measure the same
/// merged dictionary the transport hands to WatchConnectivity.
public enum LinkApplicationContextCodec {
    public static func merged(base: [String: Any], update: [String: Any]) -> [String: Any] {
        var merged = base
        for (key, value) in update {
            merged[key] = value
        }
        return merged
    }

    /// Encoded binary property-list size, or nil when the dictionary contains a
    /// value WatchConnectivity cannot carry.
    public static func encodedSize(_ context: [String: Any]) -> Int? {
        guard PropertyListSerialization.propertyList(context, isValidFor: .binary) else { return nil }
        return try? PropertyListSerialization.data(
            fromPropertyList: context, format: .binary, options: 0
        ).count
    }

    public static func fits(
        _ context: [String: Any],
        maxBytes: Int = LinkPayloadBudget.maxBytes
    ) -> Bool {
        guard let size = encodedSize(context) else { return false }
        return size <= maxBytes
    }
}

/// Serializes the read/modify/write sequence of `updateApplicationContext`.
///
/// `WCSession.applicationContext` holds the dictionary this process set most
/// recently (Apple documents it as "the most recent dictionary of app-specific
/// data you set"), so each call re-reads it instead of keeping a copy: a paired
/// device change then cannot re-publish the previous device's dictionary. The
/// shared lock is what keeps two write entry points from interleaving their
/// read and write and losing each other's keys.
public final class LinkApplicationContextWriter: @unchecked Sendable {
    public typealias Read = () -> [String: Any]
    public typealias Write = ([String: Any]) throws -> Void

    private let lock = NSLock()
    private let maxBytes: Int
    private let read: Read
    private let write: Write

    public init(
        maxBytes: Int = LinkPayloadBudget.maxBytes,
        read: @escaping Read,
        write: @escaping Write
    ) {
        self.maxBytes = maxBytes
        self.read = read
        self.write = write
    }

    /// Merges `update` into the context currently published by the session,
    /// validates the complete merged dictionary and sends it. The read happens
    /// inside the lock, so concurrent writers always compose on the previous
    /// call's dictionary. A rejected dictionary is never sent and leaves the
    /// session's context untouched.
    public func merge(_ update: [String: Any]) throws {
        try lock.withLock {
            let merged = LinkApplicationContextCodec.merged(base: read(), update: update)
            guard let size = LinkApplicationContextCodec.encodedSize(merged) else {
                throw LinkApplicationContextError.invalidContext
            }
            guard size <= maxBytes else {
                throw LinkApplicationContextError.tooLarge(size)
            }
            try write(merged)
        }
    }
}

/// Bounds for the common-name mutation and acknowledgement side channel.
///
/// Both travel through `transferUserInfo`, a dictionary channel rather than the
/// 64 KB `sendMessageData` ceiling used for intent frames. A batch is
/// independently applicable per mutation, so an oversized batch is trimmed to a
/// deliverable prefix instead of being dropped: the watch keeps the remainder
/// queued and the phone's acknowledgement dequeues only what it received.
public enum LinkCommonNameControlBudget {
    public static var bodyBudgetBytes: Int {
        LinkPayloadBudget.userInfoBodyBudgetBytes
    }

    public static func fits(_ data: Data, maxBytes: Int = bodyBudgetBytes) -> Bool {
        data.count <= maxBytes
    }
}

public enum LinkCommonNameControlError: Error, Equatable, Sendable {
    /// Even the results-only acknowledgement exceeds the control budget.
    case tooLarge(Int)
}

public extension CommonNameMutationAcknowledgement {
    /// Encoded acknowledgement that fits the common-name control budget.
    ///
    /// The Watch dequeues pending mutations by mutationId, so every result must
    /// survive. When the complete acknowledgement is too large, only the
    /// canonical snapshot is trimmed with `budgetConstrainedData` and the
    /// acknowledgement is re-encoded; falling back to a bare snapshot push would
    /// never dequeue the Watch's queue and it would retry the same batch forever.
    func encodedWithinControlBudget(
        maxBytes: Int = LinkCommonNameControlBudget.bodyBudgetBytes
    ) throws -> Data {
        let encoder = JSONEncoder()
        let complete = try encoder.encode(self)
        guard complete.count > maxBytes else { return complete }
        let resultsData = try encoder.encode(results)
        let snapshotBudget = max(1_024, maxBytes - resultsData.count - 512)
        let constrained = CommonNameMutationAcknowledgement(
            snapshot: snapshot.budgetConstrainedData(maxBytes: snapshotBudget),
            results: results
        )
        let data = try encoder.encode(constrained)
        guard data.count <= maxBytes else {
            throw LinkCommonNameControlError.tooLarge(data.count)
        }
        return data
    }
}

public extension CommonNameMutationBatch {
    /// Largest leading run of mutations whose encoded body fits the budget, or
    /// nil when the batch is empty or even its first mutation is too large.
    func fittingPrefix(maxBytes: Int = LinkCommonNameControlBudget.bodyBudgetBytes) -> CommonNameMutationBatch? {
        guard !mutations.isEmpty else { return nil }
        let encoder = JSONEncoder()
        for count in stride(from: mutations.count, through: 1, by: -1) {
            let candidate = CommonNameMutationBatch(mutations: Array(mutations.prefix(count)))
            guard let data = try? encoder.encode(candidate), data.count <= maxBytes else { continue }
            return candidate
        }
        return nil
    }
}
