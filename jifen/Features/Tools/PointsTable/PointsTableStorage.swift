//
//  PointsTableStorage.swift
//  jifen
//
//  积分表本地持久化，UserDefaults key points_table_records。
//

import Foundation

enum PointsTableStorage {
    static let key = "points_table_records"

    static func load(defaults: UserDefaults = .standard) -> [PointsTableRecord] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PointsTableRecord].self, from: data) else {
            return []
        }
        return decoded.map { $0.localizingLegacyDefaults() }
    }

    static func save(_ records: [PointsTableRecord], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
