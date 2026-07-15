import ScoreCore
import SwiftUI

struct WatchBadmintonScoreView: View {
    let maxSets: Int
    let initialState: RallyMatchState?

    init(maxSets: Int, initialState: RallyMatchState? = nil) {
        self.maxSets = maxSets
        self.initialState = initialState
    }

    var body: some View {
        WatchRallyScoreView(gameType: .badminton, rules: .badminton(maxSets: maxSets), initialState: initialState)
    }
}
