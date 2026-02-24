import Foundation

struct WatchBadmintonRules: WatchGameRules {
    let gameType: WatchGameType = .badminton
    let maxSets: Int
    let pointsToWin: Int = 21
    var displayTitle: String { NSLocalizedString("game_badminton", comment: "Badminton") }
    var setOptionsText: String { NSLocalizedString("best_of_3_sets", comment: "Best of 3") }
    let midGameRestAt: Int? = 11
    let restBetweenSets: Int = 60
    let decidingSetSwapAt: Int? = 11

    func shouldEndSet(redScore: Int, blueScore: Int, redGames: Int, blueGames: Int, isTiebreak: Bool) -> Bool {
        let diff = abs(redScore - blueScore)
        let maxScore = max(redScore, blueScore)
        if maxScore >= 30 { return true }
        return maxScore >= pointsToWin && diff >= 2
    }
}
