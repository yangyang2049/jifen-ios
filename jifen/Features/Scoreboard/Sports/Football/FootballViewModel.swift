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

    func getWinnerName() -> String {
        guard gameFinished else { return "" }
        if leftTeam.score > rightTeam.score { return leftTeam.name }
        if rightTeam.score > leftTeam.score { return rightTeam.name }
        return ""
    }

    // MARK: - Real-time Record Saving

    func saveGameRecordInRealTime(isGameFinished: Bool = false) {
        print("[FootballViewModel] 💾 Saving football record in real-time (isGameFinished: \(isGameFinished))")
        let endTime = Date()
        let duration = endTime.timeIntervalSince(controller?.getGameStartTime() ?? Date())

        var winner: String? = nil
        if isGameFinished || gameFinished {
            if leftTeam.score > rightTeam.score {
                winner = "left"
            } else if rightTeam.score > leftTeam.score {
                winner = "right"
            }
        }

        controller?.saveScoreboardRecord(
            id: "football_\(Int(controller?.getGameStartTime().timeIntervalSince1970 ?? 0))_\(Int(endTime.timeIntervalSince1970))",
            endTime: endTime,
            duration: duration,
            team1Name: leftTeam.name,
            team2Name: rightTeam.name,
            team1FinalScore: leftTeam.score,
            team2FinalScore: rightTeam.score,
            team1SetScore: 1, // Football is typically 1 "set" (half/game)
            team2SetScore: 1,
            winner: winner,
            totalScoreChanges: controller?.getGameActions().count ?? 0,
            extraData: [:]
        )
        print("[FootballViewModel] ✅ Football record saved successfully")
    }
}
