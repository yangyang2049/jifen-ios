import Foundation
import ScoreCore

public enum ScoreboardSessionFactory {
    public static func rally(
        gameType: GameType,
        leftName: String,
        rightName: String,
        rules: RallyRuleSet? = nil,
        openingServer: MatchSide = .left
    ) -> ScoreSessionCore<RallyMatchReducer>? {
        guard let resolvedRules = rules ?? ScoreboardKernelRegistry.defaultRallyRules(for: gameType) else { return nil }
        let descriptor = ScoreboardKernelRegistry.descriptor(for: gameType)
        let state = RallyMatchEngine.initial(leftName: leftName, rightName: rightName, rules: resolvedRules, openingServer: openingServer)
        let session = ScoreSession<RallyMatchState, RallyMatchEvent>(
            gameType: gameType,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: state,
            participants: participants(leftName, rightName)
        )
        return ScoreSessionCore(seedSession: session, reducer: RallyMatchReducer(), shouldFinish: { _, state in state.finished })
    }

    public static func tennis(
        gameType: GameType,
        leftName: String,
        rightName: String,
        rules: TennisRuleSet = .init(),
        openingServer: MatchSide = .left
    ) -> ScoreSessionCore<TennisMatchReducer>? {
        guard gameType == .tennis || gameType == .tennisDoubles else { return nil }
        let descriptor = ScoreboardKernelRegistry.descriptor(for: gameType)
        let state = TennisMatchState(leftName: leftName, rightName: rightName, rules: rules, openingServer: openingServer)
        let session = ScoreSession<TennisMatchState, TennisMatchEvent>(
            gameType: gameType,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: state,
            participants: participants(leftName, rightName)
        )
        return ScoreSessionCore(seedSession: session, reducer: TennisMatchReducer(), shouldFinish: { _, state in state.finished })
    }

    public static func line(
        gameType: GameType,
        leftName: String,
        rightName: String,
        rules: LineScoreRuleSet? = nil
    ) -> ScoreSessionCore<LineScoreReducer>? {
        guard let resolvedRules = rules ?? ScoreboardKernelRegistry.defaultLineRules(for: gameType) else { return nil }
        let descriptor = ScoreboardKernelRegistry.descriptor(for: gameType)
        let state = LineScoreState(leftName: leftName, rightName: rightName, rules: resolvedRules)
        let session = ScoreSession<LineScoreState, LineScoreEvent>(
            gameType: gameType,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: state,
            participants: participants(leftName, rightName)
        )
        return ScoreSessionCore(seedSession: session, reducer: LineScoreReducer(), shouldFinish: { _, state in state.finished })
    }

    public static func boxing(
        leftName: String,
        rightName: String,
        maxRounds: Int = 3
    ) -> ScoreSessionCore<BoxingMatchReducer> {
        let descriptor = ScoreboardKernelRegistry.descriptor(for: .boxing)
        let state = BoxingMatchState(leftName: leftName, rightName: rightName, maxRounds: maxRounds)
        let session = ScoreSession<BoxingMatchState, BoxingMatchEvent>(
            gameType: .boxing,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: state,
            participants: participants(leftName, rightName)
        )
        return ScoreSessionCore(seedSession: session, reducer: BoxingMatchReducer(), shouldFinish: { _, state in state.finished })
    }

    public static func archery(
        leftName: String,
        rightName: String,
        openingShooterIsLeft: Bool = true,
        rules: ArcheryMatchRules = .default
    ) -> ScoreSessionCore<ArcheryMatchReducer> {
        let descriptor = ScoreboardKernelRegistry.descriptor(for: .archeryDual)
        let state = ArcheryMatchState(
            leftName: leftName,
            rightName: rightName,
            currentShooterIsLeft: openingShooterIsLeft,
            openingShooterIsLeft: openingShooterIsLeft,
            rules: rules
        )
        let session = ScoreSession<ArcheryMatchState, ArcheryMatchEvent>(
            gameType: .archeryDual,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: state,
            participants: participants(leftName, rightName)
        )
        return ScoreSessionCore(seedSession: session, reducer: ArcheryMatchReducer(), shouldFinish: { _, state in state.finished })
    }

    private static func participants(_ left: String, _ right: String) -> [SessionParticipant] {
        [.init(id: "left", name: left, role: "team"), .init(id: "right", name: right, role: "team")]
    }
}
