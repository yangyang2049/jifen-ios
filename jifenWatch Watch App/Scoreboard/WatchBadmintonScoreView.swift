import ScoreCore
import SessionCore
import SwiftUI

struct WatchBadmintonScoreView: View {
    let maxSets: Int
    let initialState: RallyMatchState?
    let linkedSessionId: UUID?
    let doublesGameType: GameType?
    let resumeBundle: ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>?
    let resumedStartTime: Date?
    let resumedRestState: WatchRestState?

    init(
        maxSets: Int,
        initialState: RallyMatchState? = nil,
        linkedSessionId: UUID? = nil,
        doublesGameType: GameType? = nil,
        resumeBundle: ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>? = nil,
        resumedStartTime: Date? = nil,
        resumedRestState: WatchRestState? = nil
    ) {
        self.maxSets = maxSets
        self.initialState = initialState
        self.linkedSessionId = linkedSessionId
        self.doublesGameType = doublesGameType
        self.resumeBundle = resumeBundle
        self.resumedStartTime = resumedStartTime
        self.resumedRestState = resumedRestState
    }

    var body: some View {
        WatchRallyScoreView(
            gameType: doublesGameType ?? (initialState?.doubles == nil ? .badminton : .badmintonDoubles),
            rules: .badminton(maxSets: maxSets),
            initialState: initialState,
            linkedSessionId: linkedSessionId,
            resumeBundle: resumeBundle,
            resumedStartTime: resumedStartTime,
            resumedRestState: resumedRestState
        )
    }
}
