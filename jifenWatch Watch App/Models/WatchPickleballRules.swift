//
//  WatchPickleballRules.swift
//  jifenWatch Watch App
//
//  Pickleball rules for Watch: target 11, win by 2, rally scoring (simplified).
//

import Foundation

struct WatchPickleballRules: WatchGameRules {
    let gameType: WatchGameType = .pickleball
    let maxSets: Int
    let pointsToWin: Int = 11
    var displayTitle: String { NSLocalizedString("game_pickleball", comment: "Pickleball") }
    var setOptionsText: String {
        switch maxSets {
        case 3:
            return NSLocalizedString("best_of_3_sets", comment: "Best of 3")
        case 5:
            return NSLocalizedString("best_of_5_sets", comment: "Best of 5")
        default:
            return String(format: NSLocalizedString("watch_sets_generic", value: "%d sets", comment: "Generic sets"), maxSets)
        }
    }
    let midGameRestAt: Int? = nil
    let restBetweenSets: Int = 60
    let decidingSetSwapAt: Int? = nil

    func shouldEndSet(redScore: Int, blueScore: Int, redGames: Int, blueGames: Int, isTiebreak: Bool) -> Bool {
        let diff = abs(redScore - blueScore)
        let maxScore = max(redScore, blueScore)
        return maxScore >= pointsToWin && diff >= 2
    }
}
