import ScoreCore
import SwiftUI

struct WatchBadmintonScoreView: View {
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
            gameType: initialState?.doubles == nil ? .badminton : .badmintonDoubles,
            rules: .badminton(maxSets: maxSets),
            initialState: initialState,
            linkedSessionId: linkedSessionId
        )
    }
}
