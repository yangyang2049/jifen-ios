import Foundation
import os
import RecordCore
import ScoreCore
import SessionCore

public actor AtomicJSONFileStore<Value: Codable & Sendable> {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func load() throws -> Value? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try decoder.decode(Value.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ value: Value) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory.appendingPathComponent(".\(fileURL.lastPathComponent).tmp")
        try encoder.encode(value).write(to: temporaryURL, options: .atomic)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: fileURL)
        }
    }

    public func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: fileURL)
    }
}

public enum ResumePayloadKind: String, Codable, Sendable {
    case scoreSession
    case scoreSessionBundle
    case manualState
}

public struct ResumeSessionEnvelope: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let sessionId: UUID
    public let gameType: GameType
    public let startedAtEpochMilliseconds: Int64
    public let updatedAtEpochMilliseconds: Int64
    public let participants: [SessionParticipant]
    public let scoreSummary: String
    public let payloadKind: ResumePayloadKind
    public let payload: Data
    /// Unique identity for one durable snapshot write. Timestamps and payloads
    /// can repeat (for example a terminal undo completed in the same
    /// millisecond and restored byte-identical state), so cleanup must not use
    /// either as an optimistic-concurrency token.
    public let snapshotGenerationID: UUID?

    public init(
        sessionId: UUID,
        gameType: GameType,
        startedAtEpochMilliseconds: Int64,
        updatedAtEpochMilliseconds: Int64,
        participants: [SessionParticipant],
        scoreSummary: String,
        payloadKind: ResumePayloadKind,
        payload: Data,
        snapshotGenerationID: UUID? = UUID()
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.sessionId = sessionId
        self.gameType = gameType
        self.startedAtEpochMilliseconds = startedAtEpochMilliseconds
        self.updatedAtEpochMilliseconds = updatedAtEpochMilliseconds
        self.participants = participants
        self.scoreSummary = scoreSummary
        self.payloadKind = payloadKind
        self.payload = payload
        self.snapshotGenerationID = snapshotGenerationID
    }
}

/// Opaque compare-and-delete token for a specific durable resume snapshot.
/// A later live save always receives a different envelope generation, even if
/// it restores exactly the same reducer state.
public struct ResumeSessionCleanupToken: Equatable, Sendable {
    fileprivate let envelope: ResumeSessionEnvelope
}

public struct ResumeSessionSummary: Codable, Equatable, Identifiable, Sendable {
    public let sessionId: UUID
    public let gameType: GameType
    public let source: RecordSource
    public let snapshotPath: String
    public let participants: [SessionParticipant]
    public let status: SessionStatus
    public let updatedAtEpochMilliseconds: Int64

    public var id: UUID { sessionId }

    public init(
        sessionId: UUID,
        gameType: GameType,
        source: RecordSource,
        snapshotPath: String,
        participants: [SessionParticipant],
        status: SessionStatus,
        updatedAtEpochMilliseconds: Int64
    ) {
        self.sessionId = sessionId
        self.gameType = gameType
        self.source = source
        self.snapshotPath = snapshotPath
        self.participants = participants
        self.status = status
        self.updatedAtEpochMilliseconds = updatedAtEpochMilliseconds
    }
}

/// Determines how long a live scoreboard remains resumable. The lifetime is
/// measured from the match start rather than the last autosave so background
/// persistence cannot keep an abandoned match alive indefinitely.
public struct ResumeSessionRetentionPolicy: Equatable, Sendable {
    public static let fortyEightHours = Self(retentionInterval: 48 * 60 * 60)

    public let retentionInterval: TimeInterval

    public init(retentionInterval: TimeInterval = 48 * 60 * 60) {
        self.retentionInterval = max(0, retentionInterval)
    }

    public func isExpired(
        startedAtEpochMilliseconds: Int64,
        nowEpochMilliseconds: Int64
    ) -> Bool {
        let retentionMilliseconds = Int64(retentionInterval * 1_000)
        let age = nowEpochMilliseconds.subtractingReportingOverflow(
            startedAtEpochMilliseconds
        )
        guard !age.overflow else { return nowEpochMilliseconds > startedAtEpochMilliseconds }
        return age.partialValue > retentionMilliseconds
    }

    public func isExpired(
        _ envelope: ResumeSessionEnvelope,
        now: Date = Date()
    ) -> Bool {
        isExpired(
            startedAtEpochMilliseconds: envelope.startedAtEpochMilliseconds,
            nowEpochMilliseconds: Int64(now.timeIntervalSince1970 * 1_000)
        )
    }
}

public actor ResumeSessionIndex {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.sortedKeys]
    }

    public func entries() async throws -> [ResumeSessionSummary] {
        try load().sorted { $0.updatedAtEpochMilliseconds > $1.updatedAtEpochMilliseconds }
    }

    public func upsert(_ entry: ResumeSessionSummary) async throws {
        var allEntries = try load()
        allEntries.removeAll { $0.sessionId == entry.sessionId }
        allEntries.append(entry)
        try save(allEntries)
    }

    public func remove(sessionId: UUID) async throws {
        var allEntries = try load()
        guard allEntries.contains(where: { $0.sessionId == sessionId }) else { return }
        allEntries.removeAll { $0.sessionId == sessionId }
        try save(allEntries)
    }

    /// Snapshot and catalog mutations share this actor across repository
    /// instances. A save can no longer reinsert an index entry after a
    /// concurrent discard has already deleted its snapshot.
    public func saveEnvelope(
        _ envelope: ResumeSessionEnvelope,
        summary: ResumeSessionSummary
    ) throws {
        let snapshotURL = snapshotURL(sessionId: envelope.sessionId)
        try FileManager.default.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(envelope).write(to: snapshotURL, options: .atomic)
        var allEntries = try load()
        allEntries.removeAll { $0.sessionId == summary.sessionId }
        allEntries.append(summary)
        try save(allEntries)
    }

    /// Remove the catalog entry first. If file cleanup fails, an unindexed
    /// snapshot is recoverable storage residue rather than an unreadable Home
    /// resume entry that repeatedly presents a corruption alert.
    public func removeSnapshot(sessionId: UUID) throws {
        var allEntries = try load()
        if allEntries.contains(where: { $0.sessionId == sessionId }) {
            allEntries.removeAll { $0.sessionId == sessionId }
            try save(allEntries)
        }
        let url = snapshotURL(sessionId: sessionId)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // A second idempotent cleanup won the race.
        }
    }

    public func removeSnapshot(
        sessionId: UUID,
        ifUnchanged token: ResumeSessionCleanupToken
    ) throws -> Bool {
        guard token.envelope.sessionId == sessionId else { return false }
        let url = snapshotURL(sessionId: sessionId)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let current = try decoder.decode(
            ResumeSessionEnvelope.self,
            from: Data(contentsOf: url)
        )
        guard current == token.envelope else { return false }
        try removeSnapshot(sessionId: sessionId)
        return true
    }

    /// Previous versions could leave a live index entry after its snapshot
    /// disappeared. Prune only entries whose file is actually absent, while
    /// serialized with every new snapshot write and removal.
    public func liveEntriesWithExistingSnapshots() throws -> [ResumeSessionSummary] {
        let allEntries = try load()
        let retained = allEntries.filter { entry in
            entry.status != .live
                || FileManager.default.fileExists(
                    atPath: fileURL.deletingLastPathComponent()
                        .appendingPathComponent(entry.snapshotPath).path
                )
        }
        if retained.count != allEntries.count {
            try save(retained)
        }
        return retained.filter { $0.status == .live }
            .sorted { $0.updatedAtEpochMilliseconds > $1.updatedAtEpochMilliseconds }
    }

    private func snapshotURL(sessionId: UUID) -> URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("\(sessionId.uuidString).json")
    }

    private func load() throws -> [ResumeSessionSummary] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode([ResumeSessionSummary].self, from: Data(contentsOf: fileURL))
    }

    private func save(_ entries: [ResumeSessionSummary]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(entries).write(to: fileURL, options: .atomic)
    }
}

/// Repository instances are intentionally lightweight, but every instance
/// targeting the same root must mutate one shared index actor. Otherwise two
/// scoreboards finishing close together can both load and replace the same
/// index file through independent actors.
private final class ResumeSessionIndexRegistry: @unchecked Sendable {
    static let shared = ResumeSessionIndexRegistry()

    private let lock = NSLock()
    private var indexes: [String: ResumeSessionIndex] = [:]

    func index(for fileURL: URL) -> ResumeSessionIndex {
        let key = fileURL.standardizedFileURL.path
        lock.lock()
        defer { lock.unlock() }
        if let existing = indexes[key] { return existing }
        let index = ResumeSessionIndex(fileURL: fileURL)
        indexes[key] = index
        return index
    }
}

/// The single store for every resumable match. Its schema starts at 1 because
/// the previous archive and unfinished-record implementations were never released.
public actor ResumeSessionRepository {
    /// Posted on the main queue after the durable resume-session catalog changes.
    /// The notification object is the repository root URL that changed.
    public nonisolated static let didChangeNotification = Notification.Name(
        "com.douhua.jifen.resumeSessionRepositoryDidChange"
    )

    public nonisolated let rootURL: URL
    private let index: ResumeSessionIndex
    private var activeSnapshotWriteCounts: [UUID: Int] = [:]

    public init(rootURL: URL = ResumeSessionRepository.defaultRootURL()) {
        self.rootURL = rootURL
        index = ResumeSessionIndexRegistry.shared.index(
            for: rootURL.appendingPathComponent("resume-index.json")
        )
        if rootURL == Self.defaultRootURL() {
            let oldRoot = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0].appendingPathComponent("jifen-v2", isDirectory: true)
            try? FileManager.default.removeItem(at: oldRoot)
        }
    }

    public static func defaultRootURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jifen", isDirectory: true)
            .appendingPathComponent("resume", isDirectory: true)
    }

    public static func snapshotURL(sessionId: UUID, rootURL: URL = defaultRootURL()) -> URL {
        rootURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("\(sessionId.uuidString).json")
    }

    public static func saveManualPayload(
        sessionId: UUID,
        gameType: GameType,
        startedAtEpochMilliseconds: Int64,
        participants: [SessionParticipant],
        scoreSummary: String,
        payload: Data,
        rootURL: URL = defaultRootURL(),
        updatedAtEpochMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    ) throws {
        let envelope = ResumeSessionEnvelope(
            sessionId: sessionId,
            gameType: gameType,
            startedAtEpochMilliseconds: startedAtEpochMilliseconds,
            updatedAtEpochMilliseconds: updatedAtEpochMilliseconds,
            participants: participants,
            scoreSummary: scoreSummary,
            payloadKind: .manualState,
            payload: payload
        )
        let summary = ResumeSessionSummary(
            sessionId: sessionId,
            gameType: gameType,
            source: .phoneLocal,
            snapshotPath: "sessions/\(sessionId.uuidString).json",
            participants: participants,
            status: .live,
            updatedAtEpochMilliseconds: updatedAtEpochMilliseconds
        )

        // Bridge the synchronous manual call site to the shared index actor.
        // Both the snapshot and catalog update must run in one actor turn.
        let semaphore = DispatchSemaphore(value: 0)
        let errorBox = OSAllocatedUnfairLock(initialState: nil as NSError?)
        Task {
            do {
                let repository = ResumeSessionRepository(rootURL: rootURL)
                try await repository.saveManualEnvelope(envelope, summary: summary)
            } catch {
                errorBox.withLock { $0 = error as NSError }
            }
            semaphore.signal()
        }
        semaphore.wait()
        if let error = errorBox.withLock({ $0 }) { throw error }
    }

    private func saveManualEnvelope(
        _ envelope: ResumeSessionEnvelope,
        summary: ResumeSessionSummary
    ) async throws {
        try await index.saveEnvelope(envelope, summary: summary)
        postDidChangeNotification()
    }

    public static func loadEnvelope(
        sessionId: UUID,
        rootURL: URL = defaultRootURL()
    ) throws -> ResumeSessionEnvelope? {
        let url = snapshotURL(sessionId: sessionId, rootURL: rootURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let envelope = try JSONDecoder().decode(
            ResumeSessionEnvelope.self,
            from: Data(contentsOf: url)
        )
        guard envelope.schemaVersion == ResumeSessionEnvelope.currentSchemaVersion,
              envelope.sessionId == sessionId else {
            return nil
        }
        return envelope
    }

    public static func cleanupToken(
        sessionId: UUID,
        rootURL: URL = defaultRootURL()
    ) throws -> ResumeSessionCleanupToken? {
        try loadEnvelope(sessionId: sessionId, rootURL: rootURL).map {
            ResumeSessionCleanupToken(envelope: $0)
        }
    }

    public static func loadPayload(
        sessionId: UUID,
        expectedKind: ResumePayloadKind,
        rootURL: URL = defaultRootURL()
    ) throws -> Data? {
        guard let envelope = try loadEnvelope(sessionId: sessionId, rootURL: rootURL),
              envelope.payloadKind == expectedKind else {
            return nil
        }
        return envelope.payload
    }

    public static func loadManualPayload(
        sessionId: UUID,
        rootURL: URL = defaultRootURL()
    ) throws -> Data? {
        try loadPayload(
            sessionId: sessionId,
            expectedKind: .manualState,
            rootURL: rootURL
        )
    }

    public func save<State: Codable & Sendable, Event: Codable & Sendable>(
        _ session: ScoreSession<State, Event>,
        source: RecordSource = .phoneLocal,
        updatedAtEpochMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    ) async throws {
        if session.status == .finished {
            try await remove(sessionId: session.sessionId)
            return
        }
        beginSnapshotWrite(sessionId: session.sessionId)
        defer { endSnapshotWrite(sessionId: session.sessionId) }
        let snapshotPath = "sessions/\(session.sessionId.uuidString).json"
        let payload = try JSONEncoder().encode(session)
        let envelope = ResumeSessionEnvelope(
            sessionId: session.sessionId,
            gameType: session.gameType,
            startedAtEpochMilliseconds: Int64(
                session.metadata.extras["startedAtEpochMilliseconds"] ?? ""
            ) ?? updatedAtEpochMilliseconds,
            updatedAtEpochMilliseconds: updatedAtEpochMilliseconds,
            participants: session.participants,
            scoreSummary: "",
            payloadKind: .scoreSession,
            payload: payload
        )
        try await index.saveEnvelope(envelope, summary: .init(
            sessionId: session.sessionId,
            gameType: session.gameType,
            source: source,
            snapshotPath: snapshotPath,
            participants: session.participants,
            status: session.status,
            updatedAtEpochMilliseconds: updatedAtEpochMilliseconds
        ))
        postDidChangeNotification()
    }

    /// Persists the complete resumable session, including reducer intent
    /// timeline and undo frames. Specialized scoreboards use this instead of
    /// maintaining a second UI-owned history stack.
    public func saveResumeBundle<
        State: Codable & Sendable,
        Event: Codable & Sendable,
        Intent: Codable & Sendable
    >(
        _ bundle: ScoreSessionResumeBundle<State, Event, Intent>,
        source: RecordSource = .phoneLocal,
        updatedAtEpochMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    ) async throws {
        let session = bundle.currentSession
        if session.status == .finished {
            try await remove(sessionId: session.sessionId)
            return
        }
        beginSnapshotWrite(sessionId: session.sessionId)
        defer { endSnapshotWrite(sessionId: session.sessionId) }
        let snapshotPath = "sessions/\(session.sessionId.uuidString).json"
        let payload = try JSONEncoder().encode(bundle)
        let envelope = ResumeSessionEnvelope(
            sessionId: session.sessionId,
            gameType: session.gameType,
            startedAtEpochMilliseconds: Int64(
                session.metadata.extras["startedAtEpochMilliseconds"] ?? ""
            ) ?? updatedAtEpochMilliseconds,
            updatedAtEpochMilliseconds: updatedAtEpochMilliseconds,
            participants: session.participants,
            scoreSummary: "",
            payloadKind: .scoreSessionBundle,
            payload: payload
        )
        try await index.saveEnvelope(envelope, summary: .init(
            sessionId: session.sessionId,
            gameType: session.gameType,
            source: source,
            snapshotPath: snapshotPath,
            participants: session.participants,
            status: session.status,
            updatedAtEpochMilliseconds: updatedAtEpochMilliseconds
        ))
        postDidChangeNotification()
    }

    public func load<State: Codable & Sendable, Event: Codable & Sendable>(
        sessionId: UUID,
        as type: ScoreSession<State, Event>.Type = ScoreSession<State, Event>.self
    ) async throws -> ScoreSession<State, Event>? {
        guard let envelope = try await AtomicJSONFileStore<ResumeSessionEnvelope>(
            fileURL: Self.snapshotURL(sessionId: sessionId, rootURL: rootURL)
        ).load(), envelope.schemaVersion == ResumeSessionEnvelope.currentSchemaVersion,
              envelope.payloadKind == .scoreSession else { return nil }
        return try JSONDecoder().decode(type, from: envelope.payload)
    }

    public func loadResumeBundle<
        State: Codable & Sendable,
        Event: Codable & Sendable,
        Intent: Codable & Sendable
    >(
        sessionId: UUID,
        as type: ScoreSessionResumeBundle<State, Event, Intent>.Type
    ) async throws -> ScoreSessionResumeBundle<State, Event, Intent>? {
        guard let envelope = try await AtomicJSONFileStore<ResumeSessionEnvelope>(
            fileURL: Self.snapshotURL(sessionId: sessionId, rootURL: rootURL)
        ).load(), envelope.schemaVersion == ResumeSessionEnvelope.currentSchemaVersion,
              envelope.payloadKind == .scoreSessionBundle else { return nil }
        return try JSONDecoder().decode(type, from: envelope.payload)
    }

    public func entries() async throws -> [ResumeSessionSummary] {
        try await index.entries()
    }

    public func liveEntries() async throws -> [ResumeSessionSummary] {
        try await index.liveEntriesWithExistingSnapshots()
    }

    public func remove(sessionId: UUID) async throws {
        try await index.removeSnapshot(sessionId: sessionId)
        postDidChangeNotification()
    }

    /// Deletes only the exact snapshot observed by the finished-record commit.
    /// If a live save has started or completed since then, cleanup becomes a
    /// successful no-op and must never remove that newer recovery point.
    @discardableResult
    public func remove(
        sessionId: UUID,
        ifUnchanged token: ResumeSessionCleanupToken
    ) async throws -> Bool {
        guard token.envelope.sessionId == sessionId,
              activeSnapshotWriteCounts[sessionId, default: 0] == 0 else {
            return false
        }
        guard try await index.removeSnapshot(sessionId: sessionId, ifUnchanged: token) else {
            return false
        }
        postDidChangeNotification()
        return true
    }

    public func clear() async throws {
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return }
        do {
            // The index is only a catalog, not the complete storage inventory.
            // Removing the dedicated root also clears orphan/corrupted snapshots,
            // temporary files, and an unreadable index in one retry-safe step.
            try FileManager.default.removeItem(at: rootURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // Another idempotent cleanup already removed the directory.
        }
        postDidChangeNotification()
    }

    private nonisolated func postDidChangeNotification() {
        let changedRootURL = rootURL
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.didChangeNotification,
                object: changedRootURL
            )
        }
    }


    private func beginSnapshotWrite(sessionId: UUID) {
        activeSnapshotWriteCounts[sessionId, default: 0] += 1
    }

    private func endSnapshotWrite(sessionId: UUID) {
        let remaining = activeSnapshotWriteCounts[sessionId, default: 0] - 1
        if remaining > 0 {
            activeSnapshotWriteCounts[sessionId] = remaining
        } else {
            activeSnapshotWriteCounts[sessionId] = nil
        }
    }
}
