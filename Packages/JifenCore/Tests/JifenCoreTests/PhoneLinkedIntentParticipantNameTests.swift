import Foundation
@testable import LinkCore
import LinkSync
import ScoreCore
import Testing

/// Participant names are durable per full handle so a linked record created
/// after a rematch, after a restart, or for a match that finished late still
/// carries the eight-ball/snooker names instead of localized defaults.
@MainActor
struct PhoneLinkedIntentParticipantNameTests {
    private let adapter = LinkedReducerAdapter()

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private var rally: RallyMatchState {
        RallyMatchEngine.initial(leftName: "L", rightName: "R", rules: .pingPong())
    }

    @Test func activatePersistsNamesForTheFullHandleAcrossRestarts() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let handle = LinkedMatchHandle(sessionId: UUID(), matchId: UUID())

        do {
            let host = PhoneLinkedIntentCoordinator(directoryURL: directory, adapter: adapter) { _ in }
            try host.activate(
                handle: handle, gameType: .pingpong, initialSnapshot: .rally(rally),
                initialEpochMilliseconds: 1_000, participantNames: ["甲", "乙"]
            )
        }

        var projections = [PhoneLinkedIntentCoordinator.Projection]()
        let restarted = PhoneLinkedIntentCoordinator(directoryURL: directory, adapter: adapter) {
            projections.append($0)
        }
        try restarted.recoverActiveMatch(handle: handle)
        #expect(restarted.participantNames(for: handle) == ["甲", "乙"])
        // The durable projection cursor is already current, so nothing is
        // re-projected until the next operation carries the names.
        #expect(projections.isEmpty)
        _ = try restarted.submitLocal(
            .rally(.pointWon(.left)), handle: handle, opId: UUID(),
            createdAtEpochMilliseconds: 1_100, phoneClockReferenceEpochMilliseconds: 1_100
        )
        #expect(projections.last?.participantNames == ["甲", "乙"])
    }

    @Test func lateFinishAfterRematchStillCarriesThePreviousMatchesNames() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let handle = LinkedMatchHandle(sessionId: UUID(), matchId: UUID())
        let successor = handle.nextMatch(matchId: UUID())
        var projections = [PhoneLinkedIntentCoordinator.Projection]()
        let host = PhoneLinkedIntentCoordinator(directoryURL: directory, adapter: adapter) {
            projections.append($0)
        }

        try host.activate(
            handle: handle, gameType: .pingpong, initialSnapshot: .rally(rally),
            initialEpochMilliseconds: 1_000, participantNames: ["甲", "乙"]
        )
        _ = try host.submitLocal(
            .rally(.pointWon(.left)), handle: handle, opId: UUID(),
            createdAtEpochMilliseconds: 1_100, phoneClockReferenceEpochMilliseconds: 1_100
        )
        _ = try host.submitLocal(
            .finish, handle: handle, opId: UUID(),
            createdAtEpochMilliseconds: 1_200, phoneClockReferenceEpochMilliseconds: 1_200
        )
        _ = try host.submitLocal(
            .nextMatch(matchId: successor.matchId, matchGeneration: successor.matchGeneration),
            handle: handle, opId: UUID(),
            createdAtEpochMilliseconds: 1_250, phoneClockReferenceEpochMilliseconds: 1_250
        )
        try host.activate(
            handle: successor, gameType: .pingpong, initialSnapshot: .rally(rally),
            initialEpochMilliseconds: 2_000, participantNames: ["甲", "乙"]
        )

        // The Watch's late operation for the previous match repairs that
        // match's projection while the successor is active.
        let late = LinkOperation(
            opId: UUID(), handle: handle, origin: .watch, clientSeq: 1, baseRevision: 3,
            createdAtEpochMilliseconds: 1_300, intent: .rally(.pointWon(.right))
        )
        _ = try host.receiveWatchOperation(late, phoneClockReferenceEpochMilliseconds: 2_100)

        let retiredProjection = try #require(projections.last { $0.checkpoint.handle == handle })
        #expect(retiredProjection.isActiveMatch == false)
        #expect(retiredProjection.participantNames == ["甲", "乙"])
    }

    @Test func anOldActiveSeedBackfillsNamesOnceFromThePersistedSession() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let handle = LinkedMatchHandle(sessionId: UUID(), matchId: UUID())

        do {
            // Simulates a build before names metadata existed: seed only.
            let legacy = PhoneLinkedIntentCoordinator(directoryURL: directory, adapter: adapter) { _ in }
            try legacy.activate(
                handle: handle, gameType: .pingpong, initialSnapshot: .rally(rally),
                initialEpochMilliseconds: 1_000
            )
            #expect(legacy.participantNames(for: handle).isEmpty)
        }

        var projections = [PhoneLinkedIntentCoordinator.Projection]()
        let restarted = PhoneLinkedIntentCoordinator(directoryURL: directory, adapter: adapter) {
            projections.append($0)
        }
        try restarted.recoverActiveMatch(handle: handle, participantNames: ["旧甲", "旧乙"])
        #expect(restarted.participantNames(for: handle) == ["旧甲", "旧乙"])
        _ = try restarted.submitLocal(
            .rally(.pointWon(.left)), handle: handle, opId: UUID(),
            createdAtEpochMilliseconds: 1_100, phoneClockReferenceEpochMilliseconds: 1_100
        )
        #expect(projections.last?.participantNames == ["旧甲", "旧乙"])

        // A second restore reads the durable copy; an explicit different set
        // never overwrites names that were already stored.
        let again = PhoneLinkedIntentCoordinator(directoryURL: directory, adapter: adapter) { _ in }
        try again.recoverActiveMatch(handle: handle, participantNames: ["不应覆盖"])
        #expect(again.participantNames(for: handle) == ["旧甲", "旧乙"])
    }

    @Test func aRetiredLegacySeedWithoutNamesKeepsTheDefault() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = LinkedMatchHandle(sessionId: UUID(), matchId: UUID())
        let active = LinkedMatchHandle(sessionId: UUID(), matchId: UUID())
        let host = PhoneLinkedIntentCoordinator(directoryURL: directory, adapter: adapter) { _ in }
        try host.activate(
            handle: legacy, gameType: .pingpong, initialSnapshot: .rally(rally),
            initialEpochMilliseconds: 1_000
        )
        host.deactivate(handle: legacy)
        try host.activate(
            handle: active, gameType: .pingpong, initialSnapshot: .rally(rally),
            initialEpochMilliseconds: 2_000, participantNames: ["甲", "乙"]
        )
        #expect(host.participantNames(for: legacy).isEmpty)
        #expect(host.participantNames(for: active) == ["甲", "乙"])
    }

    @Test func projectionsReuseTheInMemoryNamesInsteadOfReadingPerScore() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let handle = LinkedMatchHandle(sessionId: UUID(), matchId: UUID())
        var projections = [PhoneLinkedIntentCoordinator.Projection]()
        let host = PhoneLinkedIntentCoordinator(directoryURL: directory, adapter: adapter) {
            projections.append($0)
        }
        try host.activate(
            handle: handle, gameType: .pingpong, initialSnapshot: .rally(rally),
            initialEpochMilliseconds: 1_000, participantNames: ["甲", "乙"]
        )

        // Remove the durable copy: an implementation that re-reads it per
        // projection loses the names here, the in-memory Match must not.
        let key = "names-\(handle.sessionId.uuidString)-\(handle.matchId.uuidString)-\(handle.matchGeneration)"
        let metadataFile = directory
            .appendingPathComponent("phone-match-metadata", isDirectory: true)
            .appendingPathComponent(FileLinkDataStore.safeFileName(for: key) + ".json")
        #expect(FileManager.default.fileExists(atPath: metadataFile.path))
        try FileManager.default.removeItem(at: metadataFile)

        _ = try host.submitLocal(
            .rally(.pointWon(.left)), handle: handle, opId: UUID(),
            createdAtEpochMilliseconds: 1_100, phoneClockReferenceEpochMilliseconds: 1_100
        )
        #expect(projections.last?.participantNames == ["甲", "乙"])
    }
}
