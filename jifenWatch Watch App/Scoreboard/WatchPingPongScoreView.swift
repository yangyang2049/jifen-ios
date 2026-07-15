import ScoreCore
import SwiftUI

struct WatchPingPongScoreView: View {
    let maxSets: Int
    let initialState: RallyMatchState?

    init(maxSets: Int, initialState: RallyMatchState? = nil) {
        self.maxSets = maxSets
        self.initialState = initialState
    }

    var body: some View {
        WatchRallyScoreView(gameType: .pingpong, rules: .pingPong(maxSets: maxSets), initialState: initialState)
    }
}
