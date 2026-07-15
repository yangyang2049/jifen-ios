import ScoreCore
import SwiftUI

struct WatchPingPongScoreView: View {
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
            gameType: .pingpong,
            rules: .pingPong(maxSets: maxSets),
            initialState: initialState,
            linkedSessionId: linkedSessionId
        )
    }
}
