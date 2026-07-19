import CryptoKit
import Foundation
import LinkCore

@MainActor
final class RecordSyncOutbox {
    static let shared = RecordSyncOutbox()
    private let store: LocalRecordSyncStore

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jifen-v3/sync", isDirectory: true)
        store = LocalRecordSyncStore(fileURL: directory.appendingPathComponent("record-outbox.json"))
    }

    func enqueueUpsert(_ record: ScoreboardRecord) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let payload = try? encoder.encode(record) else { return }
        enqueue(recordID: record.id, kind: .upsert, payload: payload)
    }

    func enqueueDelete(recordID: String) {
        let deletedAt = Int64(Date().timeIntervalSince1970 * 1_000)
        let payload = try? JSONEncoder().encode(RecordTombstone(recordID: recordID, deletedAtEpochMilliseconds: deletedAt))
        enqueue(recordID: recordID, kind: .delete, payload: payload, updatedAt: deletedAt)
    }

    private func enqueue(recordID: String, kind: RecordSyncMutationKind, payload: Data?, updatedAt: Int64? = nil) {
        let stableID = Self.stableUUID(for: recordID)
        let timestamp = updatedAt ?? Int64(Date().timeIntervalSince1970 * 1_000)
        Task {
            guard let identity = try? await AnonymousIdentityProvider.shared.currentIdentity() else { return }
            let mutation = RecordSyncMutation(
                recordID: stableID,
                actorID: identity.localID,
                revision: UInt64(max(0, timestamp)),
                updatedAtEpochMilliseconds: timestamp,
                kind: kind,
                payload: payload
            )
            try? await store.enqueue(mutation)
        }
    }

    private static func stableUUID(for value: String) -> UUID {
        let digest = SHA256.hash(data: Data(value.utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

private struct RecordTombstone: Codable {
    let recordID: String
    let deletedAtEpochMilliseconds: Int64
}
