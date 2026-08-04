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

    public init(
        sessionId: UUID,
        gameType: GameType,
        startedAtEpochMilliseconds: Int64,
        updatedAtEpochMilliseconds: Int64,
        participants: [SessionParticipant],
        scoreSummary: String,
        payloadKind: ResumePayloadKind,
        payload: Data
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
    }
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
    public let rootURL: URL
    private let index: ResumeSessionIndex

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
        let fileManager = FileManager.default
        let sessionsURL = rootURL.appendingPathComponent("sessions", isDirectory: true)
        try fileManager.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
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
        try JSONEncoder().encode(envelope).write(
            to: snapshotURL(sessionId: sessionId, rootURL: rootURL),
            options: .atomic
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

        // Route index updates through the actor to avoid clobbering concurrent
        // saves from `ResumeSessionRepository.save`. The semaphore bridges the
        // sync call site (MainActor) to the async actor method without changing
        // the public signature. This is safe because `saveManualPayload` is
        // never called from the `ResumeSessionRepository` actor itself.
        let semaphore = DispatchSemaphore(value: 0)
        let errorBox = OSAllocatedUnfairLock(initialState: nil as NSError?)
        Task {
            do {
                let repository = ResumeSessionRepository(rootURL: rootURL)
                try await repository.saveManualSession(summary)
            } catch {
                errorBox.withLock { $0 = error as NSError }
            }
            semaphore.signal()
        }
        semaphore.wait()
        if let error = errorBox.withLock({ $0 }) { throw error }
    }

    /// Index-only update for manual (non-ScoreCore) sessions. Uses `index.upsert`
    /// instead of replacing the entire index array, and delegates session cleanup
    /// to `discardOtherLiveSessions` to stay consistent with actor-managed saves.
    public func saveManualSession(_ summary: ResumeSessionSummary) async throws {
        try await index.upsert(summary)
        if summary.status == .live {
            try await discardOtherLiveSessions(except: summary.sessionId)
        }
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
        let store = AtomicJSONFileStore<ResumeSessionEnvelope>(
            fileURL: rootURL.appendingPathComponent(snapshotPath)
        )
        try await store.save(envelope)
        try await index.upsert(.init(
            sessionId: session.sessionId,
            gameType: session.gameType,
            source: source,
            snapshotPath: snapshotPath,
            participants: session.participants,
            status: session.status,
            updatedAtEpochMilliseconds: updatedAtEpochMilliseconds
        ))
        // Resume GameBar allows at most one live session (aligned with HarmonyOS).
        if session.status == .live {
            try await discardOtherLiveSessions(except: session.sessionId)
        }
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
        let store = AtomicJSONFileStore<ResumeSessionEnvelope>(
            fileURL: rootURL.appendingPathComponent(snapshotPath)
        )
        try await store.save(envelope)
        try await index.upsert(.init(
            sessionId: session.sessionId,
            gameType: session.gameType,
            source: source,
            snapshotPath: snapshotPath,
            participants: session.participants,
            status: session.status,
            updatedAtEpochMilliseconds: updatedAtEpochMilliseconds
        ))
        if session.status == .live {
            try await discardOtherLiveSessions(except: session.sessionId)
        }
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
        try await entries().filter { $0.status == .live }
    }

    /// Keeps at most one live resume target: discards every live session except `sessionId`.
    public func discardOtherLiveSessions(except sessionId: UUID) async throws {
        for entry in try await liveEntries() where entry.sessionId != sessionId {
            try await remove(sessionId: entry.sessionId)
        }
    }

    public func discardAllLiveSessions() async throws {
        for entry in try await liveEntries() {
            try await remove(sessionId: entry.sessionId)
        }
    }

    /// Prunes accidentally stacked live sessions down to the newest one.
    @discardableResult
    public func retainNewestLiveSession() async throws -> ResumeSessionSummary? {
        let live = try await liveEntries()
        guard let newest = live.first else { return nil }
        for entry in live.dropFirst() {
            try await remove(sessionId: entry.sessionId)
        }
        return newest
    }

    public func remove(sessionId: UUID) async throws {
        let url = Self.snapshotURL(sessionId: sessionId, rootURL: rootURL)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                // Another finished-record cleanup won the race. Removal is
                // intentionally idempotent, so there is nothing left to do.
            }
        }
        try await index.remove(sessionId: sessionId)
    }

    public func clear() async throws {
        let allEntries = try await entries()
        for entry in allEntries {
            try await remove(sessionId: entry.sessionId)
        }
    }
}
