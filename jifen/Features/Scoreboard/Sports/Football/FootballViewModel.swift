//
//  FootballViewModel.swift
//  jifen
//
//  Football scoreboard view model
//

import Foundation

@Observable
class FootballViewModel: BaseScoreViewModel {
    override init(controller: BaseScoreboardController? = nil) {
        super.init(controller: controller)
        self.leftTeam = TeamData(name: "红队", score: 0)
        self.rightTeam = TeamData(name: "蓝队", score: 0)
    }

    override func addScore(isLeft: Bool, points: Int) {
        guard !gameFinished else { return }

        // Save history before change
        controller?.pushHistory(
            left: leftTeam.score,
            right: rightTeam.score,
            leftSets: leftTeam.sets,
            rightSets: rightTeam.sets,
            leftGames: leftTeam.games,
            rightGames: rightTeam.games
        )

        if isLeft {
            leftTeam.score += points
        } else {
            rightTeam.score += points
        }

        // Record football-specific action
        controller?.recordScoreAction(action: "\(isLeft ? leftTeam.name : rightTeam.name) 进球 +\(points)分")

        controller?.performVibration(type: .light)
    }

    func adjustScore(isLeft: Bool, delta: Int) {
        // Save history before change
        controller?.pushHistory(
            left: leftTeam.score,
            right: rightTeam.score,
            leftSets: leftTeam.sets,
            rightSets: rightTeam.sets,
            leftGames: leftTeam.games,
            rightGames: rightTeam.games
        )

        // Adjust score
        if isLeft {
            leftTeam.score = max(0, leftTeam.score + delta)
        } else {
            rightTeam.score = max(0, rightTeam.score + delta)
        }

        controller?.performVibration(type: .light)
    }

    func getScoringOptions() -> [Int] {
        return [1] // Football: typically just +1 for goals
    }
}
