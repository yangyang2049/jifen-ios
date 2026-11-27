//
//  FootballViewModel.swift
//  jifen
//
//  Football scoreboard view model
//

import Foundation
import LinkSync
import RecordCore
import ScoreCore

struct FootballResumeStateV2: Codable {
    static let currentSchemaVersion = 2
    var schemaVersion = currentSchemaVersion
    let lineScore: LineScoreResumeState
    var timer: FootballTimerStateV2
}

@Observable
class FootballViewModel: LineScoreViewModel {
    let gameType: ScoreCore.GameType
    private var standaloneState: FootballMatchState
    private let clockAnchorWall: Int64
    private let clockAnchorUptime: UInt64
    private(set) var clockRevision = 0
    @ObservationIgnored var submitLinkedIntent: (@MainActor (LinkedScoreboardIntent) -> Bool)?
    private var confirmedLinkedState: FootballMatchState?
    private var linkedDisplayEpochMilliseconds: Int64 = 0
    private var finishedViaLink = false

    init(
        controller: BaseScoreboardController? = nil,
        gameType: ScoreCore.GameType = .football,
        halfLengthSeconds: Int = 45 * 60
    ) {
        self.gameType = gameType
        let now = Self.wallClockMilliseconds()
        clockAnchorWall = now
        clockAnchorUptime = DispatchTime.now().uptimeNanoseconds
        let left = NSLocalizedString("team_home", comment: "Home Team")
        let right = NSLocalizedString("team_away", comment: "Away Team")
        standaloneState = FootballMatchReducer.initial(
            leftName: left, rightName: right, isFiveAside: gameType == .football5v5,
            halfLengthSeconds: halfLengthSeconds, at: now
        )
        super.init(controller: controller, rules: .nonNegative)
        leftTeam = TeamData(name: left, score: 0)
        rightTeam = TeamData(name: right, score: 0)
    }

    func getScoringOptions() -> [Int] {
        return [1] // Football: typically just +1 for goals
    }

    func getWinnerName() -> String {
        guard gameFinished else { return "" }
        if leftTeam.score > rightTeam.score { return leftTeam.name }
        if rightTeam.score > leftTeam.score { return rightTeam.name }
        return ""
    }

    private static func wallClockMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }

    private var localClockMilliseconds: Int64 {
        clockAnchorWall + Int64((DispatchTime.now().uptimeNanoseconds - clockAnchorUptime) / 1_000_000)
    }

    private var activeFootballState: FootballMatchState { confirmedLinkedState ?? standaloneState }
    var clockStage: Int { activeFootballState.timer.stage }
    var clockPeriodLengthSeconds: Int { activeFootballState.currentPeriodLengthSeconds }
    var clockStoppageSeconds: Int { activeFootballState.currentStoppageSeconds }
    var clockIsRunning: Bool {
        activeFootballState.timer.isRunning && (confirmedLinkedState == nil || !clockPeriodCompleted)
    }
    var clockIsTimeUp: Bool { clockElapsedSeconds >= activeFootballState.targetSeconds }
    var clockElapsedSeconds: Int {
        activeFootballState.displayElapsedSeconds(
            at: confirmedLinkedState == nil ? localClockMilliseconds : linkedDisplayEpochMilliseconds
        )
    }
    var clockMainDisplaySeconds: Int { min(clockElapsedSeconds, clockPeriodLengthSeconds) }
    var clockStoppageElapsedSeconds: Int { max(0, clockElapsedSeconds - clockPeriodLengthSeconds) }
    var clockPeriodCompleted: Bool { clockIsTimeUp }
    var allowsManualClockPause: Bool { activeFootballState.allowsManualClockPause }
    var allowsStoppageTime: Bool { activeFootballState.allowsStoppageTime }

    func formattedClock() -> String {
        let seconds = max(0, clockMainDisplaySeconds)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func formattedStoppageClock() -> String {
        let seconds = max(0, clockStoppageElapsedSeconds)
        return String(format: "+%02d:%02d", seconds / 60, seconds % 60)
    }

    func toggleClock() {
        guard allowsManualClockPause else { return }
        sendClockIntent(.toggleClock)
    }

    func addStoppage(_ seconds: Int) {
        sendClockIntent(.addStoppage(seconds: seconds))
    }

    var canUndoLastStoppage: Bool { !activeFootballState.stoppageHistory.isEmpty }

    func undoLastStoppage() {
        sendClockIntent(.undoLastStoppage)
    }

    @discardableResult
    func advanceClockStage() -> Bool {
        sendClockIntent(.advanceStage)
    }

    @discardableResult
    private func sendClockIntent(_ intent: FootballMatchIntent) -> Bool {
        if let submitLinkedIntent { return submitLinkedIntent(.football(intent)) }
        let result = FootballMatchReducer().reduce(
            state: localState(with: sessionState), intent: intent, at: localClockMilliseconds
        )
        guard result.accepted else { return false }
        standaloneState = result.state
        clockRevision &+= 1
        return true
    }

    func checkClockExpiry() -> Bool {
        let wasRunning = clockIsRunning
        if confirmedLinkedState != nil {
            linkedDisplayEpochMilliseconds = Self.wallClockMilliseconds()
            return wasRunning && clockPeriodCompleted
        }
        guard wasRunning, clockIsTimeUp else { return false }
        standaloneState = FootballMatchReducer.settleClock(state: standaloneState, at: localClockMilliseconds)
        clockRevision &+= 1
        return true
    }

    func restoreFootballSession(_ resumeState: FootballResumeStateV2) {
        restoreSession(resumeState.lineScore)
        // Read the shipped V2 timer with its original upgrade semantics.
        var restored = FootballMatchClockSession(state: resumeState.timer, gameType: gameType)
        restored.reconcileAfterRestore()
        var timer = restored.state
        timer.savedWallClockMilliseconds = localClockMilliseconds
        standaloneState = makeStandaloneState(timer: timer)
        clockRevision &+= 1
    }

    /// Earlier sessions had no clock. Keep their score at a paused first period.
    func restoreLegacyFootballSession(_ resumeState: LineScoreResumeState? = nil) {
        if let resumeState { restoreSession(resumeState) }
        standaloneState = makeStandaloneState(timer: .init(
            halfLengthSeconds: standaloneState.timer.halfLengthSeconds,
            savedWallClockMilliseconds: localClockMilliseconds
        ))
        clockRevision &+= 1
    }

    func resetClock(halfLengthSeconds: Int? = nil) {
        finishedViaLink = false
        standaloneState = FootballMatchReducer.initial(
            leftName: leftTeam.name, rightName: rightTeam.name, isFiveAside: gameType == .football5v5,
            halfLengthSeconds: halfLengthSeconds ?? standaloneState.timer.halfLengthSeconds,
            at: localClockMilliseconds
        )
        clockRevision &+= 1
    }

    private func makeStandaloneState(timer: FootballTimerStateV2) -> FootballMatchState {
        FootballMatchState(
            leftName: leftTeam.name, rightName: rightTeam.name, leftScore: leftTeam.score,
            rightScore: rightTeam.score, timer: timer, isFiveAside: gameType == .football5v5,
            sidesSwapped: sidesSwapped, finished: gameFinished
        )
    }

    private func localState(with score: LineScoreState) -> FootballMatchState {
        var state = standaloneState
        state.leftName = score.leftName
        state.rightName = score.rightName
        state.leftScore = score.leftScore
        state.rightScore = score.rightScore
        state.sidesSwapped = score.sidesSwapped
        state.finished = score.finished
        return state
    }

    override func stateAfterApplying(_ intent: LineScoreIntent, to score: LineScoreState) -> LineScoreState? {
        let current = localState(with: score)
        let footballIntent: FootballMatchIntent
        var repetitions = 1
        switch intent {
        case .pointWon(let side):
            footballIntent = .goal(side: side)
        case .adjust(let side, let delta):
            let previous = side == .left ? score.leftScore : score.rightScore
            let (sum, overflow) = previous.addingReportingOverflow(delta)
            let target = score.rules.clamp(overflow ? (delta > 0 ? Int.max : Int.min) : sum)
            guard target != previous else { return nil }
            footballIntent = target > previous ? .goal(side: side) : .subtractGoal(side: side)
            repetitions = abs(target - previous)
        case .exchangeSides:
            footballIntent = .exchangeSides
        case .setNames(let left, let right):
            footballIntent = .setNames(left: left, right: right)
        case .finish:
            footballIntent = .finish
        case .reset:
            footballIntent = .reset()
        }
        var next = current
        let now = localClockMilliseconds
        for _ in 0..<repetitions {
            let result = FootballMatchReducer().reduce(state: next, intent: footballIntent, at: now)
            guard result.accepted else { return nil }
            next = result.state
        }
        standaloneState = next
        return LineScoreState(
            leftName: next.leftName, rightName: next.rightName, rules: score.rules,
            leftScore: next.leftScore, rightScore: next.rightScore,
            sidesSwapped: next.sidesSwapped, finished: next.finished
        )
    }

    override func snapshotAnnotation(for intent: LineScoreIntent) -> String? {
        switch intent {
        case .pointWon, .adjust(_, delta: 1...):
            return FootballClockAnnotation.encode(
                period: standaloneState.timer.stage, elapsedSeconds: standaloneState.timer.elapsedSeconds
            )
        default:
            return nil
        }
    }

    // MARK: - Linked session

    func applyLinkedState(_ state: FootballMatchState) {
        // Retain the exact anchor and fractional carry from the sequencer. Ticks update display time only.
        confirmedLinkedState = state
        linkedDisplayEpochMilliseconds = Int64(Date().timeIntervalSince1970 * 1_000)
        leftTeam.name = state.leftName
        rightTeam.name = state.rightName
        leftTeam.score = state.leftScore
        rightTeam.score = state.rightScore
        sidesSwapped = state.sidesSwapped
        finishedViaLink = state.finished
        gameFinished = state.finished
        clockRevision &+= 1
    }

    func continueStandaloneFromLink(actions: [DetailedScoreAction]) {
        submitLinkedIntent = nil
        guard let state = confirmedLinkedState else { return }
        standaloneState = FootballMatchReducer.settleClock(state: state, at: Self.wallClockMilliseconds())
        standaloneState.timer.savedWallClockMilliseconds = localClockMilliseconds
        confirmedLinkedState = nil
        if !state.finished {
            controller?.gameActions = actions.compactMap(Self.standaloneAction)
        }
        restoreSession(state: sessionState, history: [])
        clockRevision &+= 1
    }

    /// Only score and administrative actions belonged to the published line-score timeline.
    private static func standaloneAction(_ action: DetailedScoreAction) -> String? {
        guard let timestamp = action.epochMilliseconds, let operationCode = action.operationCode,
              action.scores.count == 2 else { return nil }
        let code: String
        switch operationCode {
        case "goal", "goal_subtracted", "score_adjust": code = "score_adjust"
        case "undo": code = "undo"
        case "edit_name", "edit_names": code = "edit_names"
        case "exchange_sides", "exchange_side": code = "exchange_side"
        default: return nil
        }
        let snapshot = "\(timestamp)|snapshot|\(code)|\(action.scores[0]),\(action.scores[1])"
        guard let period = action.footballPeriod,
              let elapsed = action.footballElapsedSeconds,
              let annotation = FootballClockAnnotation.encode(period: period, elapsedSeconds: elapsed) else { return snapshot }
        return "\(snapshot)||\(annotation)"
    }

    override func addScore(isLeft: Bool, points: Int) {
        guard submitLinkedIntent != nil else {
            super.addScore(isLeft: isLeft, points: points)
            return
        }
        adjustScore(isLeft: isLeft, delta: points)
    }

    override func subtractScore(isLeft: Bool, points: Int) {
        guard submitLinkedIntent != nil else {
            super.subtractScore(isLeft: isLeft, points: points)
            return
        }
        if points == 1 { adjustScore(isLeft: isLeft, delta: -1) }
    }

    override func adjustScore(isLeft: Bool, delta: Int) {
        guard let submitLinkedIntent else {
            super.adjustScore(isLeft: isLeft, delta: delta)
            return
        }
        let side: MatchSide = isLeft ? .left : .right
        switch delta {
        case 1: _ = submitLinkedIntent(.football(.goal(side: side)))
        case -1: _ = submitLinkedIntent(.football(.subtractGoal(side: side)))
        default: break
        }
    }

    override func exchangeSides() {
        guard let submitLinkedIntent else {
            super.exchangeSides()
            return
        }
        _ = submitLinkedIntent(.football(.exchangeSides))
    }

    override func confirmEditName(isLeft: Bool) {
        guard let submitLinkedIntent else {
            super.confirmEditName(isLeft: isLeft)
            return
        }
        guard editState.editingSide == (isLeft ? .left : .right) else { return }
        let input = editState.currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaults = DefaultParticipantNames.resolve(for: .simpleScore)
        let name = input.isEmpty ? (isLeft ? defaults.left : defaults.right) : input
        let accepted = submitLinkedIntent(.football(.setNames(
            left: isLeft ? name : leftTeam.name,
            right: isLeft ? rightTeam.name : name
        )))
        if accepted {
            editState.editingSide = nil
            editState.currentInput = ""
        }
    }

    override func reset() {
        guard submitLinkedIntent == nil else { return }
        super.reset()
    }

    override func endGame() {
        if let submitLinkedIntent {
            _ = submitLinkedIntent(.finish)
            return
        }
        super.endGame()
        clockRevision &+= 1
    }

    override func undo() -> Bool {
        if let submitLinkedIntent { return submitLinkedIntent(.undo(targetOpId: nil)) }
        // Android 3.1 keeps score undo and injury-time undo as separate
        // commands. The scoreboard's generic Undo must therefore only consume
        // the line-score reducer history; `undoLastStoppage()` owns stoppage
        // rollback and clock/stage operations never enter the score undo stack.
        guard super.undo() else { return false }
        standaloneState = localState(with: sessionState)
        return true
    }

    // MARK: - Real-time Record Saving

    func saveGameRecordInRealTime(recordID: String, isGameFinished: Bool = false) {
        guard submitLinkedIntent == nil, !finishedViaLink else { return }
        #if DEBUG
        print("[FootballViewModel] 💾 Saving football record in real-time (isGameFinished: \(isGameFinished))")
        #endif
        let finished = isGameFinished || gameFinished
        let hasProgress = !(controller?.getGameActions().isEmpty ?? true)
            || leftTeam.score != 0
            || rightTeam.score != 0
            || standaloneState.timer.stage != 1
            || clockElapsedSeconds > 0
            || standaloneState.timer.stoppageSeconds.contains(where: { $0 > 0 })
            || finished
        guard hasProgress else { return }

        let resumeState = LineScoreResumeState(
            state: sessionState,
            undoHistory: resumeHistory,
            intentTimeline: controller?.getGameActions() ?? []
        )
        var persistedTimer = FootballMatchReducer.settleClock(
            state: standaloneState, at: localClockMilliseconds
        ).timer
        persistedTimer.savedWallClockMilliseconds = Self.wallClockMilliseconds()
        if finished {
            persistedTimer.isRunning = false
        }
        let footballResume = FootballResumeStateV2(lineScore: resumeState, timer: persistedTimer)

        controller?.saveRealtimeRecord(
            id: recordID,
            hasProgress: true,
            isFinished: finished,
            team1Name: leftTeam.name,
            team2Name: rightTeam.name,
            team1FinalScore: leftTeam.score,
            team2FinalScore: rightTeam.score,
            // Football has periods but no independent set score. Persisting a
            // synthetic 1:1 made a genuine 2:0 result render and share as 1:1.
            team1SetScore: nil,
            team2SetScore: nil,
            extraData: [:],
            projectConfiguration: [
                ScoreboardRecordConfiguration.Key.scoreCoreGameType: gameType.rawValue,
                "minimumScore": LineScoreRuleSet.nonNegative.minimum,
                "maximumScore": LineScoreRuleSet.nonNegative.maximum,
                "ruleProfileVersion": 1,
                "footballHalfLengthSeconds": standaloneState.timer.halfLengthSeconds,
                "showMatchTime": true
            ],
            snapshot: footballResume,
            snapshotErrorLabel: "football"
        )
        #if DEBUG
        print("[FootballViewModel] ✅ Football record saved successfully")
        #endif
    }
}
