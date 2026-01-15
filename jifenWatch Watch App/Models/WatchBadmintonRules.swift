import Foundation

struct WatchBadmintonRules: WatchGameRules {
    let gameType: WatchGameType = .badminton
    let maxSets: Int
    let pointsToWin: Int = 21
    let displayTitle: String = "羽毛球"
    let setOptionsText: String = "三局两胜"
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
