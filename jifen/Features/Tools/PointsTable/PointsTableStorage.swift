//
//  PointsTableStorage.swift
//  jifen
//
//  积分表本地持久化，UserDefaults key points_table_records。
//

import Foundation

enum PointsTableStorage {
    private static let key = "points_table_records"

    static func load() -> [PointsTableRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PointsTableRecord].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(_ records: [PointsTableRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
