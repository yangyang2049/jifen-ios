import Foundation
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

public struct SessionArchiveEntry: Codable, Equatable, Identifiable, Sendable {
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

public actor SessionArchiveIndex {
    private let store: AtomicJSONFileStore<[SessionArchiveEntry]>

    public init(fileURL: URL) {
        store = AtomicJSONFileStore(fileURL: fileURL)
    }

    public func entries() async throws -> [SessionArchiveEntry] {
        try await store.load()?.sorted { $0.updatedAtEpochMilliseconds > $1.updatedAtEpochMilliseconds } ?? []
    }

    public func upsert(_ entry: SessionArchiveEntry) async throws {
        var allEntries = try await store.load() ?? []
        allEntries.removeAll { $0.sessionId == entry.sessionId }
        allEntries.append(entry)
        try await store.save(allEntries)
    }

    public func remove(sessionId: UUID) async throws {
        var allEntries = try await store.load() ?? []
        allEntries.removeAll { $0.sessionId == sessionId }
        try await store.save(allEntries)
    }
}

/// Single persistence gateway for v2 score sessions. New sessions write only
/// through this repository; legacy v1 records remain a read-only migration source.
public actor SessionArchiveRepository {
    public let rootURL: URL
    private let index: SessionArchiveIndex

    public init(rootURL: URL = SessionArchiveRepository.defaultRootURL()) {
        self.rootURL = rootURL
        index = SessionArchiveIndex(fileURL: rootURL.appendingPathComponent("session-index.json"))
    }

    public static func defaultRootURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jifen-v2", isDirectory: true)
    }

    public static func snapshotURL(sessionId: UUID, rootURL: URL = defaultRootURL()) -> URL {
        rootURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("\(sessionId.uuidString).json")
    }

    public func save<State: Codable & Sendable, Event: Codable & Sendable>(
        _ session: ScoreSession<State, Event>,
        source: RecordSource = .phoneLocal,
        updatedAtEpochMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    ) async throws {
        let snapshotPath = "sessions/\(session.sessionId.uuidString).json"
        let store = AtomicJSONFileStore<ScoreSession<State, Event>>(
            fileURL: rootURL.appendingPathComponent(snapshotPath)
        )
        try await store.save(session)
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

    public func load<State: Codable & Sendable, Event: Codable & Sendable>(
        sessionId: UUID,
        as type: ScoreSession<State, Event>.Type = ScoreSession<State, Event>.self
    ) async throws -> ScoreSession<State, Event>? {
        try await AtomicJSONFileStore<ScoreSession<State, Event>>(
            fileURL: Self.snapshotURL(sessionId: sessionId, rootURL: rootURL)
        ).load()
    }

    public func entries() async throws -> [SessionArchiveEntry] {
        try await index.entries()
    }

    public func liveEntries() async throws -> [SessionArchiveEntry] {
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

    /// Prunes stacked live sessions (legacy data) down to the newest one.
    @discardableResult
    public func retainNewestLiveSession() async throws -> SessionArchiveEntry? {
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
            try FileManager.default.removeItem(at: url)
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
