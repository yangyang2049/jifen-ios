#if !os(watchOS)
import Foundation
import ScoreCore

public enum RealtimeSyncProtocol {
    public static let currentVersion = 1
    public static let maximumParticipants = 8
}

public struct SyncIdentity: Codable, Equatable, Sendable {
    public let localID: UUID
    public var displayName: String
    public var accountID: String?

    public init(localID: UUID, displayName: String, accountID: String? = nil) {
        self.localID = localID
        self.displayName = displayName
        self.accountID = accountID
    }
}

public protocol IdentityProvider: Sendable {
    func currentIdentity() async throws -> SyncIdentity
    func updateDisplayName(_ displayName: String) async throws -> SyncIdentity
}

public enum SyncParticipantRole: String, Codable, CaseIterable, Sendable {
    case hostController = "host_controller"
    case remoteController = "remote_controller"
    case display

    public var canSendIntents: Bool {
        self == .hostController || self == .remoteController
    }
}

public struct SyncParticipant: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var displayName: String
    public var role: SyncParticipantRole
    public var connected: Bool

    public init(id: UUID, displayName: String, role: SyncParticipantRole, connected: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.connected = connected
    }
}

public struct SyncRoomDescriptor: Codable, Equatable, Sendable {
    public let roomID: UUID
    public let shortCode: String
    public let hostIdentityID: UUID
    public let roomSecret: String
    public let expiresAt: Date

    public init(
        roomID: UUID,
        shortCode: String,
        hostIdentityID: UUID,
        roomSecret: String,
        expiresAt: Date
    ) {
        self.roomID = roomID
        self.shortCode = shortCode
        self.hostIdentityID = hostIdentityID
        self.roomSecret = roomSecret
        self.expiresAt = expiresAt
    }
}

public protocol RoomService: Sendable {
    func createRoom(identity: SyncIdentity) async throws -> SyncRoomDescriptor
    func joinRoom(code: String, role: SyncParticipantRole, identity: SyncIdentity) async throws -> SyncRoomDescriptor
    func leaveRoom(_ roomID: UUID, identity: SyncIdentity) async
}

public enum RealtimeSyncMessageKind: String, Codable, Sendable {
    case hello
    case joinRequest = "join_request"
    case joinAccepted = "join_accepted"
    case joinRejected = "join_rejected"
    case participantUpdate = "participant_update"
    case setup
    case intent
    case snapshot
    case acknowledgement
    case negativeAcknowledgement = "negative_acknowledgement"
    case resyncRequest = "resync_request"
    case phaseChanged = "phase_changed"
    case controllerPaused = "controller_paused"
    case controllerResumed = "controller_resumed"
    case matchFinished = "match_finished"
    case participantRemoved = "participant_removed"
    case roomEnded = "room_ended"
}

public struct RealtimeSyncEnvelope: Codable, Equatable, Identifiable, Sendable {
    public let protocolVersion: Int
    public let id: UUID
    public let roomID: UUID
    public let sessionID: UUID?
    public let gameType: GameType?
    public let stateSchemaVersion: Int
    public let senderID: UUID
    public let senderRole: SyncParticipantRole
    public let senderSequence: UInt64
    public let sessionRevision: UInt64
    public let sentAtEpochMilliseconds: Int64
    public let kind: RealtimeSyncMessageKind
    public let correlationID: UUID?
    public let payload: Data

    public init(
        protocolVersion: Int = RealtimeSyncProtocol.currentVersion,
        id: UUID = UUID(),
        roomID: UUID,
        sessionID: UUID? = nil,
        gameType: GameType? = nil,
        stateSchemaVersion: Int = 1,
        senderID: UUID,
        senderRole: SyncParticipantRole,
        senderSequence: UInt64,
        sessionRevision: UInt64,
        sentAtEpochMilliseconds: Int64,
        kind: RealtimeSyncMessageKind,
        correlationID: UUID? = nil,
        payload: Data = Data()
    ) {
        self.protocolVersion = protocolVersion
        self.id = id
        self.roomID = roomID
        self.sessionID = sessionID
        self.gameType = gameType
        self.stateSchemaVersion = stateSchemaVersion
        self.senderID = senderID
        self.senderRole = senderRole
        self.senderSequence = senderSequence
        self.sessionRevision = sessionRevision
        self.sentAtEpochMilliseconds = sentAtEpochMilliseconds
        self.kind = kind
        self.correlationID = correlationID
        self.payload = payload
    }

    public func decodePayload<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = JSONDecoder()) throws -> T {
        try decoder.decode(type, from: payload)
    }

    public static func encodePayload<T: Encodable>(_ value: T, encoder: JSONEncoder = JSONEncoder()) throws -> Data {
        try encoder.encode(value)
    }
}

public protocol RealtimeTransport: Sendable {
    var incomingEnvelopes: AsyncStream<RealtimeSyncEnvelope> { get }
    func connect(room: SyncRoomDescriptor, identity: SyncIdentity, role: SyncParticipantRole) async throws
    func send(_ envelope: RealtimeSyncEnvelope) async throws
    func disconnect(reason: String) async
}

public struct RealtimeRevisionGate: Equatable, Sendable {
    public private(set) var roomID: UUID?
    public private(set) var sessionID: UUID?
    public private(set) var latestRevision: UInt64 = 0
    private var seenMessageIDs: Set<UUID> = []

    public init() {}

    public mutating func begin(roomID: UUID, sessionID: UUID?, revision: UInt64 = 0) {
        self.roomID = roomID
        self.sessionID = sessionID
        latestRevision = revision
        seenMessageIDs.removeAll(keepingCapacity: true)
    }

    public mutating func accept(_ envelope: RealtimeSyncEnvelope) -> Bool {
        guard envelope.roomID == roomID,
              envelope.sessionID == sessionID,
              !seenMessageIDs.contains(envelope.id),
              envelope.sessionRevision > latestRevision else { return false }
        seenMessageIDs.insert(envelope.id)
        latestRevision = envelope.sessionRevision
        if seenMessageIDs.count > 1_024 {
            seenMessageIDs.removeAll(keepingCapacity: true)
            seenMessageIDs.insert(envelope.id)
        }
        return true
    }

    public func requiresResync(for envelope: RealtimeSyncEnvelope) -> Bool {
        envelope.roomID == roomID && envelope.sessionID == sessionID && envelope.sessionRevision > latestRevision + 1
    }
}

public enum RecordSyncMutationKind: String, Codable, Sendable {
    case upsert
    case delete
}

public struct RecordSyncMutation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let recordID: UUID
    public let actorID: UUID
    public let revision: UInt64
    public let updatedAtEpochMilliseconds: Int64
    public let kind: RecordSyncMutationKind
    public let payload: Data?

    public init(
        id: UUID = UUID(),
        recordID: UUID,
        actorID: UUID,
        revision: UInt64,
        updatedAtEpochMilliseconds: Int64,
        kind: RecordSyncMutationKind,
        payload: Data?
    ) {
        self.id = id
        self.recordID = recordID
        self.actorID = actorID
        self.revision = revision
        self.updatedAtEpochMilliseconds = updatedAtEpochMilliseconds
        self.kind = kind
        self.payload = payload
    }
}

public protocol RecordSyncStore: Sendable {
    func enqueue(_ mutation: RecordSyncMutation) async throws
    func pendingMutations(limit: Int) async throws -> [RecordSyncMutation]
    func acknowledge(ids: Set<UUID>, cursor: String?) async throws
    func syncCursor() async throws -> String?
}

public actor LocalRecordSyncStore: RecordSyncStore {
    private struct State: Codable {
        var mutations: [RecordSyncMutation] = []
        var cursor: String?
    }

    private let fileURL: URL
    private var state: State

    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(State.self, from: data) {
            state = decoded
        } else {
            state = State()
        }
    }

    public func enqueue(_ mutation: RecordSyncMutation) async throws {
        if let index = state.mutations.firstIndex(where: { $0.id == mutation.id }) {
            state.mutations[index] = mutation
        } else {
            state.mutations.append(mutation)
        }
        try persist()
    }

    public func pendingMutations(limit: Int) async throws -> [RecordSyncMutation] {
        Array(state.mutations.prefix(max(0, limit)))
    }

    public func acknowledge(ids: Set<UUID>, cursor: String?) async throws {
        state.mutations.removeAll { ids.contains($0.id) }
        if let cursor { state.cursor = cursor }
        try persist()
    }

    public func syncCursor() async throws -> String? {
        state.cursor
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}
#endif
