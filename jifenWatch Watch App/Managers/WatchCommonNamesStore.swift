import Foundation
import LinkCore
import Observation

enum WatchCommonNamesError: Error, Equatable {
    case emptyName
    case duplicateName
    case nameNotFound
    case presetName
}

/// `common-names/store.json` 单一原子文件的持久化状态。
private struct WatchCommonNamesPersistedState: Codable {
    var canonicalTeams: [String] = []
    var canonicalPlayers: [String] = []
    var updatedAtEpochMilliseconds: Int64 = 0
    var revision: UInt64 = 0
    var pendingMutations: [CommonNameMutation] = []
    var lastSyncAtEpochMilliseconds: Int64 = 0
    var hasUnresolvedConflict: Bool = false
}

/// Phone-canonical common names plus an optimistic, persistent watch mutation overlay.
/// 7 个 UserDefaults key 收敛为 common-names/store.json 单一原子文件；
/// 首发格式直接起算，store.json 缺失或损坏时重新起算干净状态。
@MainActor
@Observable
final class WatchCommonNamesStore {
    static let shared = WatchCommonNamesStore()

    private var canonicalTeams: [String]
    private var canonicalPlayers: [String]
    private(set) var teams: [String] = []
    private(set) var players: [String] = []
    private(set) var updatedAtEpochMilliseconds: Int64
    private(set) var revision: UInt64
    private(set) var pendingMutations: [CommonNameMutation]
    private(set) var lastSyncAtEpochMilliseconds: Int64
    private(set) var hasUnresolvedConflict: Bool

    static let maxNameLength = 24
    static let maxNamesPerType = 50
    static let maxMutationsPerBatch = 50

    private let storeFileURL: URL

    /// - Parameter directoryURL: 存储目录；nil 使用 WatchStorageContainer.shared
    ///   的 common-names/ 子目录（测试传临时目录隔离）。
    init(directoryURL: URL? = nil) {
        let directory = directoryURL ?? WatchStorageContainer.shared.commonNamesDirectory
        storeFileURL = directory.appendingPathComponent("store.json", isDirectory: false)
        if let data = try? Data(contentsOf: storeFileURL), !data.isEmpty,
           let state = try? JSONDecoder().decode(WatchCommonNamesPersistedState.self, from: data) {
            canonicalTeams = state.canonicalTeams
            canonicalPlayers = state.canonicalPlayers
            updatedAtEpochMilliseconds = state.updatedAtEpochMilliseconds
            revision = state.revision
            pendingMutations = state.pendingMutations
            lastSyncAtEpochMilliseconds = state.lastSyncAtEpochMilliseconds
            hasUnresolvedConflict = state.hasUnresolvedConflict
        } else {
            // 缺失或损坏：重新起算干净状态（覆盖写回干净文件）。
            let clean = WatchCommonNamesPersistedState()
            canonicalTeams = clean.canonicalTeams
            canonicalPlayers = clean.canonicalPlayers
            updatedAtEpochMilliseconds = clean.updatedAtEpochMilliseconds
            revision = clean.revision
            pendingMutations = clean.pendingMutations
            lastSyncAtEpochMilliseconds = clean.lastSyncAtEpochMilliseconds
            hasUnresolvedConflict = clean.hasUnresolvedConflict
            persistState(clean)
        }
        recomputeEffectiveNames()
    }

    /// 全量状态原子落盘（替代此前 7 个零散 UserDefaults key 的多次写入）。
    private func persistState(_ state: WatchCommonNamesPersistedState? = nil) {
        let state = state ?? WatchCommonNamesPersistedState(
            canonicalTeams: canonicalTeams,
            canonicalPlayers: canonicalPlayers,
            updatedAtEpochMilliseconds: updatedAtEpochMilliseconds,
            revision: revision,
            pendingMutations: pendingMutations,
            lastSyncAtEpochMilliseconds: lastSyncAtEpochMilliseconds,
            hasUnresolvedConflict: hasUnresolvedConflict
        )
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: storeFileURL, options: .atomic)
        }
    }

    var pendingCount: Int { pendingMutations.count }

    func names(for type: CommonNameSyncType) -> [String] {
        type == .team ? teams : players
    }

    @discardableResult
    func apply(_ snapshot: CommonNamesSyncSnapshot) -> Bool {
        guard snapshot.schemaVersion <= CommonNamesSyncSnapshot.currentSchemaVersion else {
            return false
        }
        guard shouldAccept(snapshot) else { return false }
        applyCanonical(snapshot)
        persistState()
        recomputeEffectiveNames()
        return true
    }

    func apply(_ acknowledgement: CommonNameMutationAcknowledgement) {
        let pendingIDs = Set(pendingMutations.map(\.id))
        let relevantResults = acknowledgement.results.filter { pendingIDs.contains($0.mutationId) }
        let acknowledgedIDs = Set(acknowledgement.results.map(\.mutationId))
        pendingMutations.removeAll { acknowledgedIDs.contains($0.id) }
        if !relevantResults.isEmpty {
            hasUnresolvedConflict = relevantResults.contains {
                $0.status == .conflict || $0.status == .invalid
            }
        }
        if shouldAccept(acknowledgement.snapshot) {
            applyCanonical(acknowledgement.snapshot)
        }
        lastSyncAtEpochMilliseconds = nowMilliseconds()
        persistState()
        recomputeEffectiveNames()
    }

    @discardableResult
    func addName(_ raw: String, type: CommonNameSyncType) throws -> String {
        let name = try validatedName(raw)
        guard !contains(name, in: names(for: type)) else {
            throw WatchCommonNamesError.duplicateName
        }
        appendMutation(.init(kind: .add, nameType: type, newName: name))
        return name
    }

    /// Remembers a name entered while starting a game, matching the HarmonyOS
    /// watch behavior. Existing and preset names are intentionally ignored.
    @discardableResult
    func recordUsage(_ raw: String, type: CommonNameSyncType) -> Bool {
        do {
            _ = try addName(raw, type: type)
            return true
        } catch WatchCommonNamesError.emptyName,
                WatchCommonNamesError.duplicateName,
                WatchCommonNamesError.presetName {
            return false
        } catch {
            return false
        }
    }

    @discardableResult
    func updateName(_ originalName: String, newName raw: String, type: CommonNameSyncType) throws -> String {
        let currentNames = names(for: type)
        guard currentNames.contains(where: { normalizedKey($0) == normalizedKey(originalName) }) else {
            throw WatchCommonNamesError.nameNotFound
        }
        let name = try validatedName(raw)
        guard !currentNames.contains(where: {
            normalizedKey($0) == normalizedKey(name) && normalizedKey($0) != normalizedKey(originalName)
        }) else {
            throw WatchCommonNamesError.duplicateName
        }
        appendMutation(.init(
            kind: .rename,
            nameType: type,
            originalName: originalName,
            newName: name
        ))
        return name
    }

    func deleteName(_ name: String, type: CommonNameSyncType) throws {
        guard contains(name, in: names(for: type)) else {
            throw WatchCommonNamesError.nameNotFound
        }
        appendMutation(.init(kind: .delete, nameType: type, originalName: name))
    }

    func pendingBatch() -> CommonNameMutationBatch? {
        pendingMutations.isEmpty
            ? nil
            : CommonNameMutationBatch(mutations: Array(pendingMutations.prefix(Self.maxMutationsPerBatch)))
    }

    private func appendMutation(_ mutation: CommonNameMutation) {
        pendingMutations.append(mutation)
        persistState()
        recomputeEffectiveNames()
    }

    private func applyCanonical(_ snapshot: CommonNamesSyncSnapshot) {
        canonicalTeams = Array(snapshot.teams.prefix(Self.maxNamesPerType))
        canonicalPlayers = Array(snapshot.players.prefix(Self.maxNamesPerType))
        updatedAtEpochMilliseconds = snapshot.updatedAtEpochMilliseconds
        revision = max(revision, snapshot.revision)
        if pendingMutations.isEmpty {
            lastSyncAtEpochMilliseconds = nowMilliseconds()
        }
    }

    private func shouldAccept(_ snapshot: CommonNamesSyncSnapshot) -> Bool {
        if snapshot.revision > 0 {
            return snapshot.revision > revision
        }
        guard revision == 0 else { return false }
        guard snapshot.updatedAtEpochMilliseconds >= updatedAtEpochMilliseconds else {
            return false
        }
        let incomingTeams = Array(snapshot.teams.prefix(Self.maxNamesPerType))
        let incomingPlayers = Array(snapshot.players.prefix(Self.maxNamesPerType))
        let isDuplicate = snapshot.updatedAtEpochMilliseconds == updatedAtEpochMilliseconds
            && incomingTeams == canonicalTeams
            && incomingPlayers == canonicalPlayers
        return !isDuplicate
    }

    private func recomputeEffectiveNames() {
        var effectiveTeams = canonicalTeams
        var effectivePlayers = canonicalPlayers
        for mutation in pendingMutations {
            switch mutation.nameType {
            case .team:
                applyLocally(mutation, to: &effectiveTeams)
            case .player:
                applyLocally(mutation, to: &effectivePlayers)
            }
        }
        teams = Array(effectiveTeams.prefix(Self.maxNamesPerType))
        players = Array(effectivePlayers.prefix(Self.maxNamesPerType))
    }

    private func applyLocally(_ mutation: CommonNameMutation, to names: inout [String]) {
        switch mutation.kind {
        case .add:
            guard let value = mutation.newName,
                  !contains(value, in: names) else { return }
            names.insert(value, at: 0)
        case .delete:
            guard let value = mutation.originalName else { return }
            let key = normalizedKey(value)
            names.removeAll { normalizedKey($0) == key }
        case .rename:
            guard let oldValue = mutation.originalName,
                  let newValue = mutation.newName,
                  let index = names.firstIndex(where: { normalizedKey($0) == normalizedKey(oldValue) }) else { return }
            names[index] = newValue
        }
        if names.count > Self.maxNamesPerType {
            names = Array(names.prefix(Self.maxNamesPerType))
        }
    }

    private func validatedName(_ raw: String) throws -> String {
        let normalized = normalize(raw)
        guard !normalized.isEmpty else { throw WatchCommonNamesError.emptyName }
        guard !PresetCommonNames.isPreset(normalized) else {
            throw WatchCommonNamesError.presetName
        }
        return String(normalized.prefix(Self.maxNameLength))
    }

    private func normalize(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedKey(_ raw: String) -> String {
        normalize(raw).lowercased()
    }

    private func contains(_ name: String, in names: [String]) -> Bool {
        let key = normalizedKey(name)
        return names.contains { normalizedKey($0) == key }
    }

    private func nowMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }
}
