import Foundation

struct WatchTennisRules: WatchGameRules {
    let gameType: WatchGameType = .tennis
    let maxSets: Int
    let pointsToWin: Int = 4 // Points to win a game
    let displayTitle: String = "网球"
    var setOptionsText: String {
        switch maxSets {
        case 1:
            return "一盘"
        case 3:
            return "三盘两胜"
        case 5:
            return "五盘三胜"
        default:
            return "\(maxSets)盘"
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
        if isTiebreak {
            if (redScore + blueScore) % 2 != 0 {
                // show swap reminder
            }
        }
    }
}
