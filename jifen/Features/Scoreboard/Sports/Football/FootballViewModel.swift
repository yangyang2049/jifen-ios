//
//  FootballViewModel.swift
//  jifen
//
//  Football scoreboard view model
//

import Foundation

@Observable
class FootballViewModel: BaseScoreViewModel {
    private static let scoreRange = 0 ... 9999

    override init(controller: BaseScoreboardController? = nil) {
        super.init(controller: controller, scoreRange: Self.scoreRange)
        self.leftTeam = TeamData(name: NSLocalizedString("team_home", comment: "Home Team"), score: 0)
        self.rightTeam = TeamData(name: NSLocalizedString("team_away", comment: "Away Team"), score: 0)
    }

    override func endGame() {
        gameFinished = true
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
            leftTeam.score = min(Self.scoreRange.upperBound, leftTeam.score + points)
        } else {
            rightTeam.score = min(Self.scoreRange.upperBound, rightTeam.score + points)
        }

        // Record football-specific action
        controller?.recordScoreAction(action: "\(isLeft ? leftTeam.name : rightTeam.name) 进球 +\(points)分")

        controller?.performVibration(type: .light)
    }

    override func adjustScore(isLeft: Bool, delta: Int) {
        guard delta != 0 else { return }
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
            leftTeam.score = min(Self.scoreRange.upperBound, max(Self.scoreRange.lowerBound, leftTeam.score + delta))
        } else {
            rightTeam.score = min(Self.scoreRange.upperBound, max(Self.scoreRange.lowerBound, rightTeam.score + delta))
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
        #if DEBUG
        print("[FootballViewModel] 💾 Saving football record in real-time (isGameFinished: \(isGameFinished))")
        #endif
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
            id: "football_\(Int(controller?.getGameStartTime().timeIntervalSince1970 ?? 0))",
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
            extraData: [:],
            status: (isGameFinished || gameFinished) ? .finished : .draft
        )
        #if DEBUG
        print("[FootballViewModel] ✅ Football record saved successfully")
        #endif
    }
}
