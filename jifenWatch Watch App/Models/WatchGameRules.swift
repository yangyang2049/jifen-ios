import Foundation

protocol WatchGameRules {
    var gameType: WatchGameType { get }
    var maxSets: Int { get }
    var pointsToWin: Int { get }
    var displayTitle: String { get }
    var setOptionsText: String { get }
    var midGameRestAt: Int? { get }
    var restBetweenSets: Int { get }
    var decidingSetSwapAt: Int? { get }

    func displayScore(for score: Int, isTiebreak: Bool) -> String
    func shouldEndSet(redScore: Int, blueScore: Int, redGames: Int, blueGames: Int, isTiebreak: Bool) -> Bool
    func shouldEndGame(redScore: Int, blueScore: Int, redGames: Int, blueGames: Int, isTiebreak: Bool) -> Bool
    func shouldStartTiebreak(redGames: Int, blueGames: Int) -> Bool
    func onScoreChange(redScore: inout Int, blueScore: inout Int, redGames: inout Int, blueGames: inout Int, redSets: inout Int, blueSets: inout Int, isTiebreak: inout Bool)
}

// Default implementations for set-based games like Ping-Pong and Badminton
extension WatchGameRules {
    func displayScore(for score: Int, isTiebreak: Bool) -> String {
        return "\(score)"
    }

    func shouldEndGame(redScore: Int, blueScore: Int, redGames: Int, blueGames: Int, isTiebreak: Bool) -> Bool {
        return false // Not applicable for simple set-based games
    }

    func shouldStartTiebreak(redGames: Int, blueGames: Int) -> Bool {
        return false
    }
    
    func onScoreChange(redScore: inout Int, blueScore: inout Int, redGames: inout Int, blueGames: inout Int, redSets: inout Int, blueSets: inout Int, isTiebreak: inout Bool) {
        // Default is no-op
    }
}
