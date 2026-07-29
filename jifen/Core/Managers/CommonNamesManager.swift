import Foundation
import LinkCore

extension Notification.Name {
    static let commonNamesDidChange = Notification.Name("jifen.commonNamesDidChange")
}

enum CommonNamesError: Error {
    case emptyName
    case duplicateName
    case nameNotFound
}

class CommonNamesManager {
    static let shared = CommonNamesManager()

    private let userDefaults: UserDefaults
    private let teamsKey = "commonTeamNames"
    private let playersKey = "commonPlayerNames"
    private let revisionKey = "commonNamesSyncRevisionV2"
    private let processedWatchMutationIDsKey = "processedWatchCommonNameMutationIDsV1"
    private let processedWatchMutationResultsKey = "processedWatchCommonNameMutationResultsV1"

    // Limits the number of common names stored
    private let maxNames = 50

    /// 预制名称（红队/蓝队、选手1/2、主队/客队、红方/蓝方、左队/右队等），不写入常用名称，与鸿蒙一致。
    private static let presetNameKeys: Set<String> = {
        let list = [
            "红队", "蓝队", "主队", "客队", "选手1", "选手2", "红方", "蓝方", "左队", "右队",
            "red team", "blue team", "home", "away", "player 1", "player 2"
        ]
        return Set(list.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
    }()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var currentRevision: UInt64 {
        if let number = userDefaults.object(forKey: revisionKey) as? NSNumber {
            return number.uint64Value
        }
        return 0
    }

    func currentSyncSnapshot() -> CommonNamesSyncSnapshot {
        CommonNamesSyncSnapshot(
            teams: getNames(type: .team),
            players: getNames(type: .player),
            revision: currentRevision
        )
    }

    private func isPresetName(_ normalized: String) -> Bool {
        Self.presetNameKeys.contains(normalized.lowercased())
    }

    /// Automatically save a newly entered name without tracking usage or reordering existing names.
    func saveNameIfNeeded(_ name: String, _ type: NameType) async {
        let normalized = normalizeName(name)
        guard !normalized.isEmpty else { return }
        if isPresetName(normalized) { return }

        var names = getNames(type: type)
        let key = normalizedKey(normalized)
        guard !names.contains(where: { normalizedKey($0) == key }) else { return }
        names.insert(normalized, at: 0)

        if names.count > maxNames {
            names = Array(names.prefix(maxNames))
        }

        saveNames(names, type: type)
    }

    // Get a list of common names for a given type.
    func getNames(type: NameType) -> [String] {
        let key = (type == .team) ? teamsKey : playersKey
        return userDefaults.stringArray(forKey: key) ?? []
    }

    @discardableResult
    func addName(_ name: String, type: NameType) throws -> String {
        let normalized = normalizeName(name)
        guard !normalized.isEmpty else {
            throw CommonNamesError.emptyName
        }
        if isPresetName(normalized) {
            throw CommonNamesError.duplicateName
        }

        var names = getNames(type: type)
        let key = normalizedKey(normalized)
        guard !names.contains(where: { normalizedKey($0) == key }) else {
            throw CommonNamesError.duplicateName
        }

        names.insert(normalized, at: 0)
        if names.count > maxNames {
            names = Array(names.prefix(maxNames))
        }

        saveNames(names, type: type)
        return normalized
    }

    func updateName(oldName: String, newName: String, type: NameType) throws {
        let oldKey = normalizedKey(normalizeName(oldName))
        let normalizedNew = normalizeName(newName)

        guard !normalizedNew.isEmpty else {
            throw CommonNamesError.emptyName
        }

        var names = getNames(type: type)
        guard let index = names.firstIndex(where: { normalizedKey($0) == oldKey }) else {
            throw CommonNamesError.nameNotFound
        }

        let newKey = normalizedKey(normalizedNew)
        let hasDuplicate = names.enumerated().contains { idx, value in
            idx != index && normalizedKey(value) == newKey
        }
        guard !hasDuplicate else {
            throw CommonNamesError.duplicateName
        }

        names[index] = normalizedNew
        saveNames(names, type: type)
    }

    func addNamesBatch(_ namesInput: [String], type: NameType) -> (added: Int, skipped: Int) {
        var names = getNames(type: type)
        var existingKeys = Set(names.map { normalizedKey($0) })
        var batchKeys = Set<String>()
        var accepted: [String] = []
        var skipped = 0

        for raw in namesInput {
            let normalized = normalizeName(raw)
            if normalized.isEmpty {
                skipped += 1
                continue
            }
            if isPresetName(normalized) {
                skipped += 1
                continue
            }

            let key = normalizedKey(normalized)
            if batchKeys.contains(key) || existingKeys.contains(key) {
                skipped += 1
                continue
            }

            batchKeys.insert(key)
            existingKeys.insert(key)
            accepted.append(normalized)
        }

        if accepted.isEmpty {
            return (0, skipped)
        }

        names = accepted + names
        if names.count > maxNames {
            names = Array(names.prefix(maxNames))
        }

        saveNames(names, type: type)
        return (accepted.count, skipped)
    }

    func removeName(_ name: String, type: NameType) {
        var names = getNames(type: type)
        let key = normalizedKey(name)
        names.removeAll { normalizedKey($0) == key }
        saveNames(names, type: type)
    }

    func clearNames(type: NameType) {
        saveNames([], type: type)
    }

    func applyWatchMutations(_ mutations: [CommonNameMutation]) -> CommonNameMutationAcknowledgement {
        var teams = getNames(type: .team)
        var players = getNames(type: .player)
        var processed = Set(userDefaults.stringArray(forKey: processedWatchMutationIDsKey) ?? [])
        var processedOrder = userDefaults.stringArray(forKey: processedWatchMutationIDsKey) ?? []
        var processedResults = userDefaults.dictionary(forKey: processedWatchMutationResultsKey) as? [String: String] ?? [:]
        var results: [CommonNameMutationResult] = []
        var didChange = false

        for mutation in mutations {
            let id = mutation.id.uuidString
            if processed.contains(id) {
                let previousStatus = processedResults[id].flatMap(CommonNameMutationResultStatus.init(rawValue:))
                    ?? .noChange
                results.append(.init(mutationId: mutation.id, status: previousStatus))
                continue
            }

            let status: CommonNameMutationResultStatus
            switch mutation.nameType {
            case .team:
                status = apply(mutation, to: &teams)
            case .player:
                status = apply(mutation, to: &players)
            }
            if status == .applied {
                didChange = true
            }
            results.append(.init(mutationId: mutation.id, status: status))
            processed.insert(id)
            processedOrder.append(id)
            processedResults[id] = status.rawValue
        }

        if processedOrder.count > 500 {
            processedOrder = Array(processedOrder.suffix(500))
        }
        let retainedIDs = Set(processedOrder)
        processedResults = processedResults.filter { retainedIDs.contains($0.key) }
        userDefaults.set(processedOrder, forKey: processedWatchMutationIDsKey)
        userDefaults.set(processedResults, forKey: processedWatchMutationResultsKey)

        if didChange {
            userDefaults.set(Array(teams.prefix(maxNames)), forKey: teamsKey)
            userDefaults.set(Array(players.prefix(maxNames)), forKey: playersKey)
            incrementRevisionAndNotify()
        }

        return CommonNameMutationAcknowledgement(
            snapshot: currentSyncSnapshot(),
            results: results
        )
    }

    private func apply(
        _ mutation: CommonNameMutation,
        to names: inout [String]
    ) -> CommonNameMutationResultStatus {
        switch mutation.kind {
        case .add:
            guard let raw = mutation.newName else { return .invalid }
            let value = normalizeWatchMutationName(raw)
            guard !value.isEmpty, !isPresetName(value) else { return .invalid }
            if names.contains(where: { normalizedKey($0) == normalizedKey(value) }) {
                return .noChange
            }
            names.insert(value, at: 0)
            names = Array(names.prefix(maxNames))
            return .applied

        case .delete:
            guard let raw = mutation.originalName else { return .invalid }
            let key = normalizedKey(raw)
            guard !key.isEmpty else { return .invalid }
            let before = names.count
            names.removeAll { normalizedKey($0) == key }
            return names.count == before ? .noChange : .applied

        case .rename:
            guard let oldRaw = mutation.originalName,
                  let newRaw = mutation.newName else { return .invalid }
            let oldKey = normalizedKey(oldRaw)
            guard !oldKey.isEmpty else { return .invalid }
            let newValue = normalizeWatchMutationName(newRaw)
            guard !newValue.isEmpty, !isPresetName(newValue) else { return .invalid }
            let newKey = normalizedKey(newValue)
            guard let oldIndex = names.firstIndex(where: { normalizedKey($0) == oldKey }) else {
                return names.contains(where: { normalizedKey($0) == newKey }) ? .noChange : .conflict
            }
            if let duplicateIndex = names.firstIndex(where: { normalizedKey($0) == newKey }),
               duplicateIndex != oldIndex {
                return .conflict
            }
            if normalizedKey(names[oldIndex]) == newKey, names[oldIndex] == newValue {
                return .noChange
            }
            names[oldIndex] = newValue
            return .applied
        }
    }

    private func saveNames(_ names: [String], type: NameType) {
        let key = (type == .team) ? teamsKey : playersKey
        userDefaults.set(names, forKey: key)
        incrementRevisionAndNotify()
    }

    private func incrementRevisionAndNotify() {
        let nextRevision = currentRevision == .max ? UInt64.max : currentRevision + 1
        userDefaults.set(NSNumber(value: nextRevision), forKey: revisionKey)
        NotificationCenter.default.post(name: .commonNamesDidChange, object: nil)
    }

    private func normalizeWatchMutationName(_ raw: String) -> String {
        String(normalizeName(raw).prefix(24))
    }

    private func normalizeName(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedKey(_ raw: String) -> String {
        normalizeName(raw).lowercased()
    }
}
