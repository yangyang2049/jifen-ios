//
//  PointsTableModels.swift
//  jifen
//
//  积分表数据模型：记录名 + 多队伍（赛/胜/平/负/积分），与鸿蒙 PointsTable 对齐。
//

import Foundation

struct PointsTableTeam: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var played: Int
    var win: Int
    var draw: Int
    var loss: Int

    var points: Int { win * 3 + draw }

    init(name: String, played: Int = 0, win: Int = 0, draw: Int = 0, loss: Int = 0) {
        self.name = name
        self.win = min(9999, max(0, win))
        self.draw = min(9999, max(0, draw))
        self.loss = min(9999, max(0, loss))
        // Prefer derived 赛 from 胜/平/负 (aligned with Harmony/Android).
        let derived = self.win + self.draw + self.loss
        self.played = derived > 0 ? derived : max(0, played)
    }

    mutating func syncPlayed() {
        played = win + draw + loss
    }

    mutating func setWin(_ value: Int) {
        win = min(9999, max(0, value))
        syncPlayed()
    }

    mutating func setDraw(_ value: Int) {
        draw = min(9999, max(0, value))
        syncPlayed()
    }

    mutating func setLoss(_ value: Int) {
        loss = min(9999, max(0, value))
        syncPlayed()
    }
}

struct PointsTableRecord: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var teams: [PointsTableTeam]
    var createdAt: Date

    init(id: String? = nil, name: String, teams: [PointsTableTeam] = [], createdAt: Date = Date()) {
        self.id = id ?? UUID().uuidString
        self.name = name
        self.teams = teams
        self.createdAt = createdAt
    }

    /// 按积分 → 胜场 → 队名排序后的队伍（含排名）
    func standings() -> [(rank: Int, team: PointsTableTeam)] {
        let sorted = teams.sorted { t1, t2 in
            if t1.points != t2.points { return t1.points > t2.points }
            if t1.win != t2.win { return t1.win > t2.win }
            return t1.name.localizedStandardCompare(t2.name) == .orderedAscending
        }
        return sorted.enumerated().map { (index, team) in (rank: index + 1, team: team) }
    }
}
