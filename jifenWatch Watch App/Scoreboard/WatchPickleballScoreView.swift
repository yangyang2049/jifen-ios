//
//  WatchPickleballScoreView.swift
//  jifenWatch Watch App
//

import ScoreCore
import SwiftUI

struct WatchPickleballScoreView: View {
    let maxSets: Int
    let initialState: RallyMatchState?

    init(maxSets: Int, initialState: RallyMatchState? = nil) {
        self.maxSets = maxSets
        self.initialState = initialState
    }

    var body: some View {
        WatchRallyScoreView(gameType: .pickleball, rules: .pickleball(maxSets: maxSets), initialState: initialState)
    }
}
