import Foundation

/// Every native entry point uses the same owner and cloud-overlay checks.
/// The native file can remain as an offline backup after a cloud choice or deletion.
@MainActor enum PersonalRecordAccessPolicy {
    static func allowsNativeRecord(_ recordKey: String,
                                   identity: ParticipantIdentityStore = .shared,
                                   cloud: PersonalRecordsCloudSync = .shared) -> Bool {
        identity.canRead(recordKey: recordKey)
            && !cloud.usesCloudVersion(recordKey: recordKey)
            && !cloud.isLocallyDeleted(libraryId: identity.libraryId(for: recordKey), recordKey: recordKey)
    }

    static func resumeRecordKey(_ sessionId: UUID) -> String {
        ManualResumeSessionStore.recordID(for: sessionId) ?? sessionId.uuidString
    }
}
