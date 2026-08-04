import Foundation
import LinkCore
import Observation

enum WatchCommonNamesError: Error, Equatable {
    case emptyName
    case duplicateName
    case nameNotFound
    case presetName
}

/// Phone-canonical common names plus an optimistic, persistent watch mutation overlay.
@MainActor
@Observable
final class WatchCommonNamesStore {
    static let shared = WatchCommonNamesStore()

    private let teamsKey = "watch_common_team_names"
    private let playersKey = "watch_common_player_names"
    private let updatedAtKey = "watch_common_names_updated_at"
    private let revisionKey = "watch_common_names_revision_v2"
    private let pendingMutationsKey = "watch_common_names_pending_mutations_v1"
    private let lastSyncAtKey = "watch_common_names_last_sync_at_v1"
    private let unresolvedConflictKey = "watch_common_names_unresolved_conflict_v1"
    private let defaults: UserDefaults

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

    private static let presetNameKeys: Set<String> = {
        let names = [
            "红队", "蓝队", "红方", "蓝方", "主队", "客队", "左队", "右队", "A队", "B队",
            "选手A", "选手B", "射手A", "射手B", "选手1", "选手2", "玩家1", "玩家2", "玩家3",
            "红A", "红B", "蓝A", "蓝B", "红A / 红B", "蓝A / 蓝B", "红A/红B", "蓝A/蓝B",
            "red team", "blue team", "red", "blue", "home", "away", "team a", "team b",
            "player a", "player b", "archer a", "archer b", "player 1", "player 2", "player 3",
            "red a", "red b", "blue a", "blue b",
            "red a / red b", "blue a / blue b", "red a/red b", "blue a/blue b"
        ]
        return Set(names.map { $0.lowercased() })
    }()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        canonicalTeams = defaults.stringArray(forKey: teamsKey) ?? []
        canonicalPlayers = defaults.stringArray(forKey: playersKey) ?? []
        updatedAtEpochMilliseconds = Int64(defaults.integer(forKey: updatedAtKey))
        if let number = defaults.object(forKey: revisionKey) as? NSNumber {
            revision = number.uint64Value
        } else {
            revision = 0
        }
        if let data = defaults.data(forKey: pendingMutationsKey),
           let mutations = try? JSONDecoder().decode([CommonNameMutation].self, from: data) {
            pendingMutations = mutations
        } else {
            pendingMutations = []
        }
        lastSyncAtEpochMilliseconds = Int64(defaults.integer(forKey: lastSyncAtKey))
        hasUnresolvedConflict = defaults.bool(forKey: unresolvedConflictKey)
        recomputeEffectiveNames()
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
        persistCanonical()
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
            defaults.set(hasUnresolvedConflict, forKey: unresolvedConflictKey)
        }
        if shouldAccept(acknowledgement.snapshot) {
            applyCanonical(acknowledgement.snapshot)
            persistCanonical()
        }
        lastSyncAtEpochMilliseconds = nowMilliseconds()
        persistPendingMutations()
        defaults.set(Int(lastSyncAtEpochMilliseconds), forKey: lastSyncAtKey)
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
        persistPendingMutations()
        recomputeEffectiveNames()
    }

    private func applyCanonical(_ snapshot: CommonNamesSyncSnapshot) {
        canonicalTeams = Array(snapshot.teams.prefix(Self.maxNamesPerType))
        canonicalPlayers = Array(snapshot.players.prefix(Self.maxNamesPerType))
        updatedAtEpochMilliseconds = snapshot.updatedAtEpochMilliseconds
        revision = max(revision, snapshot.revision)
        if pendingMutations.isEmpty {
            lastSyncAtEpochMilliseconds = nowMilliseconds()
            defaults.set(Int(lastSyncAtEpochMilliseconds), forKey: lastSyncAtKey)
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
        guard !Self.presetNameKeys.contains(normalized.lowercased()) else {
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

    private func persistCanonical() {
        defaults.set(canonicalTeams, forKey: teamsKey)
        defaults.set(canonicalPlayers, forKey: playersKey)
        defaults.set(Int(updatedAtEpochMilliseconds), forKey: updatedAtKey)
        defaults.set(NSNumber(value: revision), forKey: revisionKey)
    }

    private func persistPendingMutations() {
        if pendingMutations.isEmpty {
            defaults.removeObject(forKey: pendingMutationsKey)
        } else if let data = try? JSONEncoder().encode(pendingMutations) {
            defaults.set(data, forKey: pendingMutationsKey)
        }
    }

    private func nowMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }
}
