import Foundation
import XCTest
import ScoreCore
@testable import jifen

@MainActor final class PersonalRecordAccessPolicyTests: XCTestCase {
    func testNativeEntryPointsRejectOtherAccountAndRetainedGuestScopes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = ParticipantIdentityStore(fileURL: root.appendingPathComponent("identity.json"))
        let library = identity.ledger.libraryId
        try identity.registerRecord("private-a")
        try identity.adopt(libraryId: library, accountId: "A", person: .init(id: "person-a", kind: .account))
        let cloud = PersonalRecordsCloudSync(fileURL: root.appendingPathComponent("cloud.json"), identity: identity,
            currentAccountID: { nil }, scoreRecords: { [] }, timerRecords: { [] })
        XCTAssertTrue(PersonalRecordAccessPolicy.allowsNativeRecord("private-a", identity: identity, cloud: cloud))
        try identity.beginAccount("B")
        XCTAssertFalse(PersonalRecordAccessPolicy.allowsNativeRecord("private-a", identity: identity, cloud: cloud))
        try identity.beginNewGuest()
        XCTAssertFalse(PersonalRecordAccessPolicy.allowsNativeRecord("private-a", identity: identity, cloud: cloud))
    }

    func testExplicitLogoutHidesPrivateRecordsEvenWhenIdentityPersistenceFails() throws {
        for explicit in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let file = root.appendingPathComponent("identity.json")
            let identity = ParticipantIdentityStore(fileURL: file)
            let oldLibrary = identity.ledger.libraryId
            try identity.registerRecord("private-a")
            try identity.adopt(libraryId: oldLibrary, accountId: "A", person: .init(id: "person-a", kind: .account))
            let cloud = PersonalRecordsCloudSync(fileURL: root.appendingPathComponent("cloud.json"), identity: identity,
                currentAccountID: { nil }, scoreRecords: { [] }, timerRecords: { [] })
            XCTAssertTrue(identity.canRead(recordKey: "not-yet-indexed-legacy-a"))
            // A directory at the JSON file path deterministically rejects atomic
            // writes, without touching any shared or installed-user storage.
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            cloud.signedOut(explicit: explicit)
            XCTAssertEqual(PersonalRecordAccessPolicy.allowsNativeRecord("private-a", identity: identity, cloud: cloud), !explicit)
            XCTAssertEqual(identity.canRead(recordKey: "not-yet-indexed-legacy-a"), !explicit)
            XCTAssertEqual(identity.isGuest, explicit)
            if explicit {
                XCTAssertNotEqual(identity.ledger.libraryId, oldLibrary)
                XCTAssertNotNil(identity.lastError)
                XCTAssertTrue(cloud.remoteRecords.isEmpty)
            } else { XCTAssertNil(identity.lastError) }
        }
    }

    func testNativeEntryPointsHideTombstoneEvenWhileNativeFileIsRetained() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = ParticipantIdentityStore(fileURL: root.appendingPathComponent("identity.json"))
        try identity.adopt(libraryId: identity.ledger.libraryId, accountId: "A", person: .init(id: "person-a", kind: .account))
        try identity.registerRecord("native-file-still-present")
        let cloud = PersonalRecordsCloudSync(fileURL: root.appendingPathComponent("cloud.json"), identity: identity,
            currentAccountID: { "A" }, scoreRecords: { [] }, timerRecords: { [] })
        await cloud.sessionDidAuthenticate(userId: "A")
        XCTAssertTrue(PersonalRecordAccessPolicy.allowsNativeRecord("native-file-still-present", identity: identity, cloud: cloud))
        cloud.markDeleted(recordKey: "native-file-still-present")
        XCTAssertFalse(PersonalRecordAccessPolicy.allowsNativeRecord("native-file-still-present", identity: identity, cloud: cloud))
        cloud.signedOut(explicit: false)
    }

    func testUnknownLegacyResumeKeepsOriginalLibraryAfterSwitchingAccounts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = ParticipantIdentityStore(fileURL: root.appendingPathComponent("identity.json"))
        let legacyLibrary = identity.ledger.libraryId
        try identity.registerLegacyResumeIfNeeded(recordKey: "first-legacy-resume", expectedLibraryId: legacyLibrary)
        try identity.adopt(libraryId: legacyLibrary, accountId: "A", person: .init(id: "person-a", kind: .account))
        try identity.beginAccount("B")
        try identity.registerLegacyResumeIfNeeded(recordKey: "another-legacy-resume", expectedLibraryId: identity.ledger.libraryId)
        XCTAssertEqual(identity.libraryId(for: "another-legacy-resume"), legacyLibrary)
        XCTAssertFalse(identity.canRead(recordKey: "another-legacy-resume"))
        XCTAssertEqual(identity.libraryId(for: "first-legacy-resume"), legacyLibrary)
    }
}
