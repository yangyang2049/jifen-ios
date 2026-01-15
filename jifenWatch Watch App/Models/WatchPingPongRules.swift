import Foundation

struct WatchPingPongRules: WatchGameRules {
    let gameType: WatchGameType = .pingpong
    let maxSets: Int
    let pointsToWin: Int = 11
    let displayTitle: String = "乒乓球"
    var setOptionsText: String {
        switch maxSets {
        case 3:
            return "三局两胜"
        case 5:
            return "五局三胜"
        case 7:
            return "七局四胜"
        default:
            return "\(maxSets)局"
        }
    }
    let midGameRestAt: Int? = nil
    let restBetweenSets: Int = 60
    let decidingSetSwapAt: Int? = 5
    
    func shouldEndSet(redScore: Int, blueScore: Int, redGames: Int, blueGames: Int, isTiebreak: Bool) -> Bool {
        let diff = abs(redScore - blueScore)
        let maxScore = max(redScore, blueScore)
        return maxScore >= pointsToWin && diff >= 2
    }
}
