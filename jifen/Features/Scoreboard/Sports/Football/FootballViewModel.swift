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

    func saveGameRecordInRealTime(recordID: String, isGameFinished: Bool = false) {
        #if DEBUG
        print("[FootballViewModel] 💾 Saving football record in real-time (isGameFinished: \(isGameFinished))")
        #endif
        let hasProgress = !(controller?.getGameActions().isEmpty ?? true)
            || leftTeam.score != 0
            || rightTeam.score != 0
            || isGameFinished
            || gameFinished
        guard hasProgress else { return }

        let endTime = Date()
        let duration = endTime.timeIntervalSince(controller?.getGameStartTime() ?? Date())

        var winner: String? = nil
        if isGameFinished || gameFinished {
            if leftTeam.score > rightTeam.score {
                winner = TeamID.team0.rawValue
            } else if rightTeam.score > leftTeam.score {
                winner = TeamID.team1.rawValue
            }
        }

        let resumeState = LineScoreResumeState(
            state: sessionState,
            undoHistory: resumeHistory,
            intentTimeline: controller?.getGameActions() ?? []
        )
        let snapshotData: Data
        do {
            snapshotData = try JSONEncoder().encode(resumeState)
        } catch {
            ScoreboardPersistenceFailureReporter.report(
                error,
                context: "Failed to encode football record \(recordID)"
            )
            return
        }

        controller?.saveScoreboardRecord(
            id: recordID,
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
            projectConfiguration: [
                ScoreboardRecordConfiguration.Key.scoreCoreGameType: ScoreCore.GameType.football.rawValue,
                "minimumScore": LineScoreRuleSet.nonNegative.minimum,
                "maximumScore": LineScoreRuleSet.nonNegative.maximum
            ],
            stateSnapshot: snapshotData,
            isFinished: isGameFinished || gameFinished
        )
        #if DEBUG
        print("[FootballViewModel] ✅ Football record saved successfully")
        #endif
    }
}
