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
