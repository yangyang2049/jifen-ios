import Foundation

struct CommonPlace: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var useCount: Int
    var lastUsedAt: Date?

    init(id: UUID = UUID(), name: String, useCount: Int = 0, lastUsedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
    }
}

enum CommonPlacesError: Error {
    case emptyName
    case duplicateName
    case placeNotFound
}

final class CommonPlacesManager {
    static let shared = CommonPlacesManager()

    private let defaults = UserDefaults.standard
    private let storageKey = "jifen-v2.commonPlaces"
    private let maxPlaces = 50

    private init() {}

    func getAllPlaces() -> [CommonPlace] {
        guard let data = defaults.data(forKey: storageKey),
              let places = try? JSONDecoder().decode([CommonPlace].self, from: data) else {
            return []
        }
        return sorted(places)
    }

    func recordUsage(_ rawName: String) {
        let name = normalize(rawName)
        guard !name.isEmpty else { return }
        var places = getAllPlaces()
        if let index = places.firstIndex(where: { normalizedKey($0.name) == normalizedKey(name) }) {
            places[index].name = name
            places[index].useCount += 1
            places[index].lastUsedAt = Date()
        } else {
            places.append(CommonPlace(name: name, useCount: 1, lastUsedAt: Date()))
        }
        save(Array(sorted(places).prefix(maxPlaces)))
    }

    @discardableResult
    func addPlace(_ rawName: String) throws -> CommonPlace {
        let name = normalize(rawName)
        guard !name.isEmpty else { throw CommonPlacesError.emptyName }
        var places = getAllPlaces()
        guard !places.contains(where: { normalizedKey($0.name) == normalizedKey(name) }) else {
            throw CommonPlacesError.duplicateName
        }
        let place = CommonPlace(name: name)
        places.insert(place, at: 0)
        save(Array(places.prefix(maxPlaces)))
        return place
    }

    func addPlacesBatch(_ rawNames: [String]) -> (added: Int, skipped: Int) {
        var places = getAllPlaces()
        var known = Set(places.map { normalizedKey($0.name) })
        var accepted: [CommonPlace] = []
        var skipped = 0
        for rawName in rawNames {
            let name = normalize(rawName)
            let key = normalizedKey(name)
            guard !name.isEmpty, !known.contains(key) else {
                skipped += 1
                continue
            }
            known.insert(key)
            accepted.append(CommonPlace(name: name))
        }
        places = accepted + places
        save(Array(places.prefix(maxPlaces)))
        return (accepted.count, skipped)
    }

    func updatePlace(id: UUID, name rawName: String) throws {
        let name = normalize(rawName)
        guard !name.isEmpty else { throw CommonPlacesError.emptyName }
        var places = getAllPlaces()
        guard let index = places.firstIndex(where: { $0.id == id }) else {
            throw CommonPlacesError.placeNotFound
        }
        guard !places.enumerated().contains(where: { offset, place in
            offset != index && normalizedKey(place.name) == normalizedKey(name)
        }) else {
            throw CommonPlacesError.duplicateName
        }
        places[index].name = name
        save(places)
    }

    func deletePlace(id: UUID) {
        save(getAllPlaces().filter { $0.id != id })
    }

    func clearAll() {
        defaults.removeObject(forKey: storageKey)
    }

    private func save(_ places: [CommonPlace]) {
        guard let data = try? JSONEncoder().encode(places) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func normalize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedKey(_ raw: String) -> String {
        normalize(raw).lowercased()
    }

    private func sorted(_ places: [CommonPlace]) -> [CommonPlace] {
        places.sorted {
            if $0.useCount != $1.useCount { return $0.useCount > $1.useCount }
            return ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast)
        }
    }
}
