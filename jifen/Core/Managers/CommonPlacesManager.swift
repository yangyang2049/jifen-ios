import Foundation

extension Notification.Name {
    static let commonPlacesDidChange = Notification.Name("jifen.commonPlacesDidChange")
}

struct CommonPlace: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

enum CommonPlacesError: Error {
    case emptyName
    case duplicateName
    case placeNotFound
}

final class CommonPlacesManager {
    static let shared = CommonPlacesManager()

    /// 常用地点容量上限（支持批量导入，2026-08 从 50 上调至 200）。
    static let maxPlaces = 200

    private let defaults: UserDefaults
    private let storageKey = "jifen-v2.commonPlaces"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func getAllPlaces() -> [CommonPlace] {
        guard let data = defaults.data(forKey: storageKey),
              let places = try? JSONDecoder().decode([CommonPlace].self, from: data) else {
            return []
        }
        return places
    }

    /// Automatically save a newly entered place without tracking usage or reordering existing places.
    func savePlaceIfNeeded(_ rawName: String) {
        let name = normalize(rawName)
        guard !name.isEmpty else { return }
        var places = getAllPlaces()
        guard !places.contains(where: { normalizedKey($0.name) == normalizedKey(name) }) else { return }
        places.insert(CommonPlace(name: name), at: 0)
        save(Array(places.prefix(Self.maxPlaces)))
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
        save(Array(places.prefix(Self.maxPlaces)))
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
        save(Array(places.prefix(Self.maxPlaces)))
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
        NotificationCenter.default.post(name: .commonPlacesDidChange, object: nil)
    }

    /// Applies the backend canonical snapshot while preserving stable UUIDs
    /// for unchanged local places.
    func replacePlacesFromCloud(_ names: [String]) {
        let existing = Dictionary(uniqueKeysWithValues: getAllPlaces().map {
            (normalizedKey($0.name), $0.id)
        })
        var seen = Set<String>()
        let places = names.compactMap { raw -> CommonPlace? in
            let name = normalize(raw)
            let key = normalizedKey(name)
            guard !name.isEmpty, seen.insert(key).inserted else { return nil }
            return CommonPlace(id: existing[key] ?? UUID(), name: name)
        }
        save(Array(places.prefix(Self.maxPlaces)))
    }

    private func save(_ places: [CommonPlace]) {
        guard let data = try? JSONEncoder().encode(places) else { return }
        defaults.set(data, forKey: storageKey)
        NotificationCenter.default.post(name: .commonPlacesDidChange, object: nil)
    }

    private func normalize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedKey(_ raw: String) -> String {
        normalize(raw).lowercased()
    }

}
