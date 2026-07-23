import ScoreCore
import SwiftUI

struct WatchPingPongScoreView: View {
    let maxSets: Int
    let initialState: RallyMatchState?
    let linkedSessionId: UUID?
    let doublesGameType: GameType?

    init(
        maxSets: Int,
        initialState: RallyMatchState? = nil,
        linkedSessionId: UUID? = nil,
        doublesGameType: GameType? = nil
    ) {
        self.maxSets = maxSets
        self.initialState = initialState
        self.linkedSessionId = linkedSessionId
        self.doublesGameType = doublesGameType
    }

    var body: some View {
        WatchRallyScoreView(
            gameType: doublesGameType ?? (initialState?.doubles == nil ? .pingpong : .pingpongDoubles),
            rules: .pingPong(maxSets: maxSets),
            initialState: initialState,
            linkedSessionId: linkedSessionId
        )
    }
}
