import Foundation

struct WatchPingPongRules: WatchGameRules {
    let gameType: WatchGameType = .pingpong
    let maxSets: Int
    let pointsToWin: Int = 11
    var displayTitle: String { NSLocalizedString("game_pingpong", comment: "Ping Pong") }
    var setOptionsText: String {
        switch maxSets {
        case 3:
            return NSLocalizedString("best_of_3_sets", comment: "Best of 3")
        case 5:
            return NSLocalizedString("best_of_5_sets", comment: "Best of 5")
        case 7:
            return NSLocalizedString("best_of_7_sets", comment: "Best of 7")
        default:
            return String(format: NSLocalizedString("watch_sets_generic", value: "%d sets", comment: "Generic sets"), maxSets)
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
