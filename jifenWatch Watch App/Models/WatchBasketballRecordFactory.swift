import Foundation
import ScoreCore

enum WatchBasketballRecordFactory {
    static func make(
        id: String,
        state: BasketballMatchState,
        startTime: Date,
        endTime: Date,
        actionLog: WatchScoreActionLog,
        manualEnd: Bool
    ) -> WatchScoreboardRecord {
        let winner: String? = if state.leftScore == state.rightScore {
            nil
        } else {
            state.leftScore > state.rightScore ? state.leftName : state.rightName
        }
        return WatchScoreboardRecord(
            id: id,
            gameType: state.gameMode == .threeXThree ? .threeBasketball : .basketball,
            startTime: startTime,
            endTime: endTime,
            duration: max(0, endTime.timeIntervalSince(startTime)),
            team1Name: state.leftName,
            team2Name: state.rightName,
            team1FinalScore: state.leftScore,
            team2FinalScore: state.rightScore,
            team1SetScore: 0,
            team2SetScore: 0,
            winner: winner,
            actions: actionLog.actions,
            totalScoreChanges: actionLog.scoreChangeCount,
            participants: [
                WatchRecordParticipant(name: state.leftName, score: state.leftScore),
                WatchRecordParticipant(name: state.rightName, score: state.rightScore)
            ],
            projectConfiguration: [
                "gameMode": state.gameMode.rawValue,
                "ruleSet": state.ruleSet.rawValue,
                "manualEnd": String(manualEnd)
            ]
        )
    }
}
