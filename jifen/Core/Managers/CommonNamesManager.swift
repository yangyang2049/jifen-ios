import Foundation

enum CommonNamesError: Error {
    case emptyName
    case duplicateName
    case nameNotFound
}

class CommonNamesManager {
    static let shared = CommonNamesManager()

    private let userDefaults = UserDefaults.standard
    private let teamsKey = "commonTeamNames"
    private let playersKey = "commonPlayerNames"

    // Limits the number of common names stored
    private let maxNames = 50

    private init() {}

    // Record usage of a name, moving it to the top of the list.
    func recordUsage(_ name: String, _ type: NameType) async {
        let normalized = normalizeName(name)
        guard !normalized.isEmpty else { return }

        var names = getNames(type: type)
        let key = normalizedKey(normalized)

        // Remove existing entry to move it to the top.
        names.removeAll { normalizedKey($0) == key }
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

    private func saveNames(_ names: [String], type: NameType) {
        let key = (type == .team) ? teamsKey : playersKey
        userDefaults.set(names, forKey: key)
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
