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
        self.played = played
        self.win = win
        self.draw = draw
        self.loss = loss
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

    /// 按积分排序后的队伍（含排名）
    func standings() -> [(rank: Int, team: PointsTableTeam)] {
        let sorted = teams.sorted { t1, t2 in
            if t1.points != t2.points { return t1.points > t2.points }
            return t1.name < t2.name
        }
        return sorted.enumerated().map { (index, team) in (rank: index + 1, team: team) }
    }
}
