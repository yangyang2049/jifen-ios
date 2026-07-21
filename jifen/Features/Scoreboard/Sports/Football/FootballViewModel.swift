//
//  FootballViewModel.swift
//  jifen
//
//  Football scoreboard view model
//

import Foundation
import ScoreCore

@Observable
class FootballViewModel: LineScoreViewModel {
    init(controller: BaseScoreboardController? = nil) {
        super.init(controller: controller, rules: .nonNegative)
        self.leftTeam = TeamData(name: NSLocalizedString("team_home", comment: "Home Team"), score: 0)
        self.rightTeam = TeamData(name: NSLocalizedString("team_away", comment: "Away Team"), score: 0)
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
