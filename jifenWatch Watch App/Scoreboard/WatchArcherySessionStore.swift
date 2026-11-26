import Foundation
import ScoreCore
import SessionCore

typealias WatchArcherySessionStore = WatchReducerSessionStore<ArcheryMatchReducer>

extension WatchReducerSessionStore where R == ArcheryMatchReducer {
    convenience init(
        initialState: ArcheryMatchState? = nil,
        resumeBundle: ResumeBundle? = nil,
        resumedStartTime: Date? = nil,
        resumedActionLog: WatchScoreActionLog? = nil
    ) {
        let startedAt = resumedStartTime ?? Date()
        let actionLog = resumedActionLog ?? WatchScoreActionLog(startedAt: startedAt)
        let binding = WatchBoardBindings.archery()
        let reducer = ArcheryMatchReducer()
        if let resumeBundle {
            self.init(
                resumeBundle: resumeBundle, reducer: reducer, binding: binding,
                actionLog: actionLog, startedAt: startedAt
            )
            return
        }

        let defaults = WatchDefaultTeamNames.resolve(for: .archeryDual)
        let state = initialState ?? ArcheryMatchState(leftName: defaults.left, rightName: defaults.right)
        let descriptor = ScoreboardKernelRegistry.descriptor(for: .archeryDual)
        let session = ScoreSession<ArcheryMatchState, ArcheryMatchEvent>(
            gameType: .archeryDual,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: state,
            status: state.finished ? .finished : .live,
            participants: [
                .init(id: TeamID.team0.rawValue, name: state.leftName, role: "team"),
                .init(id: TeamID.team1.rawValue, name: state.rightName, role: "team")
            ]
        )
        self.init(seedSession: session, reducer: reducer, binding: binding, actionLog: actionLog, startedAt: startedAt)
    }
}
