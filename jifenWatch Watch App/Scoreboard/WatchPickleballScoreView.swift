//
//  WatchPickleballScoreView.swift
//  jifenWatch Watch App
//

import ScoreCore
import SwiftUI

struct WatchPickleballScoreView: View {
    let maxSets: Int
    let initialState: RallyMatchState?
    let linkedSessionId: UUID?

    init(maxSets: Int, initialState: RallyMatchState? = nil, linkedSessionId: UUID? = nil) {
        self.maxSets = maxSets
        self.initialState = initialState
        self.linkedSessionId = linkedSessionId
    }

    var body: some View {
        WatchRallyScoreView(
            gameType: .pickleball,
            rules: .pickleball(maxSets: maxSets),
            initialState: initialState,
            linkedSessionId: linkedSessionId
        )
    }
}
