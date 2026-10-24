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

nonisolated enum CommonDataAccountLinkError: Error { case quota }

nonisolated private struct CommonDataAccountLinkPause: Equatable {
    let context: WechatBindingSessionContext
    let sessionRevision: UInt64
    let paused: Bool
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
    private var accountLinkPause: CommonDataAccountLinkPause?
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
        accountLinkPause = nil
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

    /// Flush before the server takes its preview, then freeze local deltas.
    /// The checkpoint also preserves unsynced/tombstone state for manual recovery.
    func pauseForAccountLink(context: WechatBindingSessionContext) async throws {
        if accountLinkPause?.context == context, accountLinkPause?.paused == true {
            try await validateAccountLinkPause(context)
            return
        }
        guard activeUserId == context.accountID, accountLinkPause == nil else { throw CancellationError() }
        // Register ownership before the first suspension so closing the sheet
        // can invalidate a pause that is still waiting for an in-flight sync.
        accountLinkPause = .init(context: context, sessionRevision: sessionRevision, paused: false)
        do {
            try await validateAccountLinkPause(context)
            let deadline = Date().addingTimeInterval(25)
            while inFlight {
                guard Date() < deadline else { throw URLError(.timedOut) }
                try await Task.sleep(for: .milliseconds(100))
                try await validateAccountLinkPause(context)
            }
            captureLocalChanges()
            let original = state
            if let checkpoint = try? JSONEncoder().encode(original) {
                defaults.set(checkpoint, forKey: "jifen-v3.commonDataLinkArchive." + context.accountID)
            }
            guard original.names.filter({ $0.type == "TEAM" }).count <= limits.TEAM,
                  original.names.filter({ $0.type == "PLAYER" }).count <= limits.PLAYER,
                  original.places.count <= limits.PLACE else { throw CommonDataAccountLinkError.quota }
            await syncNow(reason: "account_link", force: true)
            try await validateAccountLinkPause(context)
            guard phase == .synced else { throw URLError(.cannotConnectToHost) }
            if lastTrimmedTotal > 0 {
                // Only the still-current source session may restore its checkpoint.
                applyingRemote = true
                CommonNamesManager.shared.replaceNamesFromCloud(original.names.filter { $0.type == "TEAM" }.map(\.name), type: .team)
                CommonNamesManager.shared.replaceNamesFromCloud(original.names.filter { $0.type == "PLAYER" }.map(\.name), type: .player)
                CommonPlacesManager.shared.replacePlacesFromCloud(original.places.map(\.name))
                applyingRemote = false
                state = original
                persist()
                throw CommonDataAccountLinkError.quota
            }
            scheduledTask?.cancel()
            scheduledTask = nil
            sessionRevision &+= 1
            accountLinkPause = .init(context: context, sessionRevision: sessionRevision, paused: true)
            pendingAfterFlight = false
            activeUserId = nil
        } catch {
            if accountLinkPause?.context == context { accountLinkPause = nil }
            throw error
        }
    }

    private func validateAccountLinkPause(_ context: WechatBindingSessionContext) async throws {
        try Task.checkCancellation()
        guard let pause = accountLinkPause, pause.context == context,
              pause.sessionRevision == sessionRevision else { throw CancellationError() }
        let authRevision = await client.authSessionRevision()
        guard accountLinkPause == pause, sessionRevision == pause.sessionRevision,
              authRevision == context.authRevision,
              pause.paused ? (activeUserId == nil && state.ownerUserId == context.accountID)
                           : activeUserId == context.accountID else { throw CancellationError() }
        try Task.checkCancellation()
    }

    func cancelAccountLink(context: WechatBindingSessionContext) async {
        guard let pause = accountLinkPause, pause.context == context else { return }
        accountLinkPause = nil
        guard pause.paused, pause.sessionRevision == sessionRevision,
              activeUserId == nil, state.ownerUserId == context.accountID else { return }
        let authRevision = await client.authSessionRevision()
        guard accountLinkPause == nil, sessionRevision == pause.sessionRevision,
              authRevision == context.authRevision, activeUserId == nil else { return }
        await sessionDidChange(userId: context.accountID)
    }

    /// Pull the committed cloud baseline before allowing any old local deletion
    /// delta to run, including when the selected master has the same ID.
    func completeAccountLink(userID: String, context: WechatBindingSessionContext) async throws {
        guard let pause = accountLinkPause, pause.context == context, pause.paused,
              pause.sessionRevision == sessionRevision, activeUserId == nil,
              state.ownerUserId == context.accountID else { throw CancellationError() }
        accountLinkPause = nil
        scheduledTask?.cancel()
        sessionRevision &+= 1
        activeUserId = userID
        pendingAfterFlight = false
        replaceLocalDataForAccount(userID)
        await pullAndReplace(for: userID)
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

