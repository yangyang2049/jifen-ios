import Combine
import Foundation
import Observation

nonisolated enum CommonDataSyncPhase: String, Codable, Sendable {
    case signedOut
    case idle
    case queued
    case syncing
    case synced
    case failed
}

nonisolated struct CommonDataLimits: Codable, Equatable, Sendable {
    var TEAM: Int = 50
    var PLAYER: Int = 150
    var PLACE: Int = 50
}

nonisolated private struct CloudNameRecord: Codable, Hashable, Sendable {
    var type: String
    var name: String
    var useCount: Int
    var lastUsed: Int64
    var createTime: Int64
    var updatedAt: Int64
}

nonisolated private struct CloudPlaceRecord: Codable, Hashable, Sendable {
    var name: String
    var useCount: Int
    var lastUsed: Int64
    var createTime: Int64
    var updatedAt: Int64
}

nonisolated private struct DeletedCloudName: Codable, Hashable, Sendable {
    var type: String
    var name: String
    var deletedAt: Int64
}

nonisolated private struct DeletedCloudPlace: Codable, Hashable, Sendable {
    var name: String
    var deletedAt: Int64
}

nonisolated private struct CommonDataSnapshot: Codable, Sendable {
    var names: [CloudNameRecord]
    var places: [CloudPlaceRecord]
    var limits: CommonDataLimits?
    var trimmed: Trimmed?
    var serverTime: Int64?

    struct Trimmed: Codable, Sendable {
        var total: Int
    }
}

nonisolated private struct CommonDataSyncRequest: Encodable, Sendable {
    var names: [CloudNameRecord]
    var places: [CloudPlaceRecord]
    var deletedNames: [DeletedCloudName]
    var deletedPlaces: [DeletedCloudPlace]
}

nonisolated private struct PersistedCommonDataState: Codable {
    var ownerUserId: String?
    var names: [CloudNameRecord] = []
    var places: [CloudPlaceRecord] = []
    var deletedNames: [DeletedCloudName] = []
    var deletedPlaces: [DeletedCloudPlace] = []
    var lastSyncAt: Int64 = 0
    var limits = CommonDataLimits()
}

nonisolated struct CommonDataSyncEpoch: Equatable, Sendable {
    let userId: String
    let sessionRevision: UInt64
    let mutationRevision: UInt64

    func belongsTo(userId: String?, sessionRevision: UInt64) -> Bool {
        self.userId == userId && self.sessionRevision == sessionRevision
    }

    func canApply(userId: String?, sessionRevision: UInt64, mutationRevision: UInt64) -> Bool {
        belongsTo(userId: userId, sessionRevision: sessionRevision)
            && self.mutationRevision == mutationRevision
    }
}

@MainActor
@Observable
final class CommonDataCloudSyncManager {
    static let shared = CommonDataCloudSyncManager()

    private(set) var phase: CommonDataSyncPhase = .signedOut
    private(set) var lastSyncAt: Date?
    private(set) var lastError: String?
    private(set) var limits = CommonDataLimits()
    private(set) var lastTrimmedTotal = 0

    private let client: APIClient
    private let defaults: UserDefaults
    private let storageKey = "jifen-v3.commonDataCloudState"
    private var state: PersistedCommonDataState
    private var activeUserId: String?
    private var inFlight = false
    private var pendingAfterFlight = false
    private var applyingRemote = false
    private var retryIndex = 0
    private var sessionRevision: UInt64 = 0
    private var localMutationRevision: UInt64 = 0
    private var scheduledTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let retryDelays: [UInt64] = [15, 60, 300]

    init(client: APIClient = .shared, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(PersistedCommonDataState.self, from: data) {
            state = decoded
            limits = decoded.limits
            lastSyncAt = decoded.lastSyncAt > 0 ? Date(timeIntervalSince1970: Double(decoded.lastSyncAt) / 1000) : nil
        } else {
            state = PersistedCommonDataState()
        }
        NotificationCenter.default.publisher(for: .commonNamesDidChange)
            .merge(with: NotificationCenter.default.publisher(for: .commonPlacesDidChange))
            .sink { [weak self] _ in self?.localDataChanged() }
            .store(in: &cancellables)
    }

    func sessionDidChange(userId: String?) async {
        scheduledTask?.cancel()
        sessionRevision &+= 1
        activeUserId = userId
        guard let userId else {
            phase = .signedOut
            return
        }
        if let owner = state.ownerUserId, owner != userId {
            replaceLocalDataForAccount(userId)
            await pullAndReplace(for: userId)
            return
        }
        if state.ownerUserId == nil {
            state.ownerUserId = userId
            persist()
        }
        await syncNow(reason: "session", force: true)
    }

    func forceSync() async {
        await syncNow(reason: "manual", force: true)
    }

    func appBecameActive() {
        guard activeUserId != nil else { return }
        if let lastSyncAt, Date().timeIntervalSince(lastSyncAt) < 5 * 60 { return }
        schedule(reason: "foreground", delaySeconds: 0)
    }

    func noteNameUsed(_ name: String, type: NameType) {
        localMutationRevision &+= 1
        captureLocalChanges()
        let key = normalized(name)
        if let index = state.names.firstIndex(where: { $0.type == cloudType(type) && normalized($0.name) == key }) {
            state.names[index].useCount = min(Int.max, state.names[index].useCount + 1)
            state.names[index].lastUsed = nowMillis
            state.names[index].updatedAt = nowMillis
            persist()
            schedule(reason: "name_used")
        }
    }

    func notePlaceUsed(_ name: String) {
        localMutationRevision &+= 1
        captureLocalChanges()
        let key = normalized(name)
        if let index = state.places.firstIndex(where: { normalized($0.name) == key }) {
            state.places[index].useCount = min(Int.max, state.places[index].useCount + 1)
            state.places[index].lastUsed = nowMillis
            state.places[index].updatedAt = nowMillis
            persist()
            schedule(reason: "place_used")
        }
    }

    private func localDataChanged() {
        guard !applyingRemote, activeUserId != nil else { return }
        localMutationRevision &+= 1
        captureLocalChanges()
        schedule(reason: "local_change")
    }

    private func schedule(reason: String, delaySeconds: UInt64 = 1) {
        phase = .queued
        scheduledTask?.cancel()
        scheduledTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(delaySeconds) + (delaySeconds == 1 ? 0.5 : 0)))
            guard !Task.isCancelled else { return }
            await self?.syncNow(reason: reason)
        }
    }

    private func syncNow(reason: String, force: Bool = false) async {
        guard let userId = activeUserId else { phase = .signedOut; return }
        if inFlight {
            pendingAfterFlight = true
            return
        }
        if !force, state.ownerUserId != userId {
            await pullAndReplace(for: userId)
            return
        }
        inFlight = true
        phase = .syncing
        lastError = nil
        captureLocalChanges()
        let requestEpoch = CommonDataSyncEpoch(
            userId: userId,
            sessionRevision: sessionRevision,
            mutationRevision: localMutationRevision
        )
        let request = CommonDataSyncRequest(
            names: Array(state.names.prefix(500)),
            places: Array(state.places.prefix(500)),
            deletedNames: Array(state.deletedNames.prefix(500)),
            deletedPlaces: Array(state.deletedPlaces.prefix(500))
        )
        do {
            let snapshot: CommonDataSnapshot = try await client.request(
                "/api/common-data/sync",
                method: .post,
                body: request,
                requiresAuth: true
            )
            // An A-account response may arrive after the user has switched to
            // B. Never apply it, and never let it seed B's follow-up request.
            if requestEpoch.canApply(
                userId: activeUserId,
                sessionRevision: sessionRevision,
                mutationRevision: localMutationRevision
            ) {
                apply(snapshot, ownerUserId: userId)
                retryIndex = 0
                phase = .synced
            } else if requestEpoch.belongsTo(userId: activeUserId, sessionRevision: sessionRevision) {
                // Local edits made during the request stay authoritative until
                // the immediate follow-up round merges them with the cloud.
                pendingAfterFlight = true
            }
        } catch {
            if requestEpoch.belongsTo(userId: activeUserId, sessionRevision: sessionRevision) {
                lastError = error.localizedDescription
                phase = .failed
                let delay = retryDelays[min(retryIndex, retryDelays.count - 1)]
                retryIndex = min(retryIndex + 1, retryDelays.count - 1)
                schedule(reason: "retry_\(reason)", delaySeconds: delay)
            }
        }
        inFlight = false
        if pendingAfterFlight {
            pendingAfterFlight = false
            await syncNow(reason: "followup", force: true)
        }
    }

    private func pullAndReplace(for userId: String) async {
        guard !inFlight else { pendingAfterFlight = true; return }
        inFlight = true
        phase = .syncing
        let requestEpoch = CommonDataSyncEpoch(
            userId: userId,
            sessionRevision: sessionRevision,
            mutationRevision: localMutationRevision
        )
        do {
            let snapshot: CommonDataSnapshot = try await client.request(
                "/api/common-data",
                requiresAuth: true
            )
            if requestEpoch.canApply(
                userId: activeUserId,
                sessionRevision: sessionRevision,
                mutationRevision: localMutationRevision
            ) {
                apply(snapshot, ownerUserId: userId)
                retryIndex = 0
                phase = .synced
                lastError = nil
            } else if requestEpoch.belongsTo(userId: activeUserId, sessionRevision: sessionRevision) {
                pendingAfterFlight = true
            }
        } catch {
            if requestEpoch.belongsTo(userId: activeUserId, sessionRevision: sessionRevision) {
                phase = .failed
                lastError = error.localizedDescription
                let delay = retryDelays[min(retryIndex, retryDelays.count - 1)]
                retryIndex = min(retryIndex + 1, retryDelays.count - 1)
                schedule(reason: "account_switch_retry", delaySeconds: delay)
            }
        }
        inFlight = false
        if pendingAfterFlight {
            pendingAfterFlight = false
            await syncNow(reason: "pull_followup", force: true)
        }
    }

    /// Account-scoped common data must never remain visible after switching
    /// users, including while the new account's first pull is offline.
    private func replaceLocalDataForAccount(_ userId: String) {
        applyingRemote = true
        CommonNamesManager.shared.replaceNamesFromCloud([], type: .team)
        CommonNamesManager.shared.replaceNamesFromCloud([], type: .player)
        CommonPlacesManager.shared.replacePlacesFromCloud([])
        applyingRemote = false
        state = PersistedCommonDataState(ownerUserId: userId)
        limits = state.limits
        lastSyncAt = nil
        lastTrimmedTotal = 0
        retryIndex = 0
        lastError = nil
        persist()
    }

    private func apply(_ snapshot: CommonDataSnapshot, ownerUserId: String) {
        applyingRemote = true
        CommonNamesManager.shared.replaceNamesFromCloud(
            snapshot.names.filter { $0.type == "TEAM" }.map(\.name),
            type: .team
        )
        CommonNamesManager.shared.replaceNamesFromCloud(
            snapshot.names.filter { $0.type == "PLAYER" }.map(\.name),
            type: .player
        )
        CommonPlacesManager.shared.replacePlacesFromCloud(snapshot.places.map(\.name))
        applyingRemote = false
        let now = snapshot.serverTime ?? nowMillis
        state = PersistedCommonDataState(
            ownerUserId: ownerUserId,
            names: snapshot.names,
            places: snapshot.places,
            deletedNames: [],
            deletedPlaces: [],
            lastSyncAt: now,
            limits: snapshot.limits ?? state.limits
        )
        limits = state.limits
        lastTrimmedTotal = snapshot.trimmed?.total ?? 0
        lastSyncAt = Date(timeIntervalSince1970: Double(now) / 1000)
        persist()
    }

    private func captureLocalChanges() {
        let now = nowMillis
        let localNames: [(String, String)] =
            CommonNamesManager.shared.getNames(type: .team).map { ("TEAM", $0) } +
            CommonNamesManager.shared.getNames(type: .player).map { ("PLAYER", $0) }
        let localNameKeys = Set(localNames.map { "\($0.0)::\(normalized($0.1))" })
        let oldNames = state.names
        for (type, name) in localNames {
            let key = "\(type)::\(normalized(name))"
            if let index = state.names.firstIndex(where: { "\($0.type)::\(normalized($0.name))" == key }) {
                if state.names[index].name != name {
                    state.names[index].name = name
                    state.names[index].updatedAt = now
                }
            } else {
                state.names.append(.init(type: type, name: name, useCount: 0, lastUsed: 0, createTime: now, updatedAt: now))
            }
            state.deletedNames.removeAll { $0.type == type && normalized($0.name) == normalized(name) }
        }
        for old in oldNames where !localNameKeys.contains("\(old.type)::\(normalized(old.name))") {
            if !state.deletedNames.contains(where: { $0.type == old.type && normalized($0.name) == normalized(old.name) }) {
                state.deletedNames.append(.init(type: old.type, name: old.name, deletedAt: now))
            }
        }
        state.names.removeAll { !localNameKeys.contains("\($0.type)::\(normalized($0.name))") }

        let localPlaces = CommonPlacesManager.shared.getAllPlaces().map(\.name)
        let localPlaceKeys = Set(localPlaces.map(normalized))
        let oldPlaces = state.places
        for name in localPlaces {
            if let index = state.places.firstIndex(where: { normalized($0.name) == normalized(name) }) {
                if state.places[index].name != name {
                    state.places[index].name = name
                    state.places[index].updatedAt = now
                }
            } else {
                state.places.append(.init(name: name, useCount: 0, lastUsed: 0, createTime: now, updatedAt: now))
            }
            state.deletedPlaces.removeAll { normalized($0.name) == normalized(name) }
        }
        for old in oldPlaces where !localPlaceKeys.contains(normalized(old.name)) {
            if !state.deletedPlaces.contains(where: { normalized($0.name) == normalized(old.name) }) {
                state.deletedPlaces.append(.init(name: old.name, deletedAt: now))
            }
        }
        state.places.removeAll { !localPlaceKeys.contains(normalized($0.name)) }
        persist()
    }

    private var nowMillis: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    private func cloudType(_ type: NameType) -> String { type == .team ? "TEAM" : "PLAYER" }
    private func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: storageKey) }
    }
}

