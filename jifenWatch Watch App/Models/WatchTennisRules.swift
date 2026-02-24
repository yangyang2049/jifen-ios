import Foundation

struct WatchTennisRules: WatchGameRules {
    let gameType: WatchGameType = .tennis
    let maxSets: Int
    let pointsToWin: Int = 4 // Points to win a game
    var displayTitle: String { NSLocalizedString("game_tennis", comment: "Tennis") }
    var setOptionsText: String {
        switch maxSets {
        case 1:
            return NSLocalizedString("sets_1", comment: "1 set")
        case 3:
            return NSLocalizedString("sets_3_best_of_2", comment: "Best of 3")
        case 5:
            return NSLocalizedString("sets_5_best_of_3", comment: "Best of 5")
        default:
            return String(format: NSLocalizedString("sets_generic_tennis", value: "%d盘", comment: "Generic tennis sets"), maxSets)
        }
    }
    let midGameRestAt: Int? = nil
    let restBetweenSets: Int = 120
    let decidingSetSwapAt: Int? = nil // Tennis swap logic is more complex

    func displayScore(for score: Int, isTiebreak: Bool) -> String {
        if isTiebreak {
            return "\(score)"
        }
        switch score {
        case 0: return "0"
        case 1: return "15"
        case 2: return "30"
        case 3: return "40"
        default: return "AD"
        }
    }
    
    func shouldEndGame(redScore: Int, blueScore: Int, redGames: Int, blueGames: Int, isTiebreak: Bool) -> Bool {
        if isTiebreak {
            return (redScore >= 7 || blueScore >= 7) && abs(redScore - blueScore) >= 2
        }
        return (redScore >= 4 || blueScore >= 4) && abs(redScore - blueScore) >= 2
    }

    func shouldEndSet(redScore: Int, blueScore: Int, redGames: Int, blueGames: Int, isTiebreak: Bool) -> Bool {
        if redGames >= 6 || blueGames >= 6 {
            if abs(redGames - blueGames) >= 2 {
                return true
            }
            if redGames == 7 || blueGames == 7 {
                return true
            }
        }
        return false
    }

    func shouldStartTiebreak(redGames: Int, blueGames: Int) -> Bool {
        return redGames == 6 && blueGames == 6
    }
    
    func onScoreChange(redScore: inout Int, blueScore: inout Int, redGames: inout Int, blueGames: inout Int, redSets: inout Int, blueSets: inout Int, isTiebreak: inout Bool) {
        if !isTiebreak {
            // Handle deuce: if both scores are >= 3 (40-40) and equal, reset to 3-3 to avoid AD-AD
            if redScore >= 3 && blueScore >= 3 && redScore == blueScore && redScore > 3 {
                redScore = 3
                blueScore = 3
            }
        }
    }
}
