import ScoreCore
import SwiftUI

struct WatchBadmintonScoreView: View {
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
            gameType: doublesGameType ?? (initialState?.doubles == nil ? .badminton : .badmintonDoubles),
            rules: .badminton(maxSets: maxSets),
            initialState: initialState,
            linkedSessionId: linkedSessionId
        )
    }
}
