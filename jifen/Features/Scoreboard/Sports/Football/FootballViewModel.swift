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
    private(set) var clockSession: FootballMatchClockSession
    private var stoppageAdditionHistory: [Int] = []
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
        self.clockSession = FootballMatchClockSession(
            state: .init(halfLengthSeconds: halfLengthSeconds),
            gameType: gameType
        )
        super.init(controller: controller, rules: .nonNegative)
        self.leftTeam = TeamData(name: NSLocalizedString("team_home", comment: "Home Team"), score: 0)
        self.rightTeam = TeamData(name: NSLocalizedString("team_away", comment: "Away Team"), score: 0)
        self.clockSession.resetForNewGame()
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

    var clockStage: Int { confirmedLinkedState?.timer.stage ?? clockSession.state.stage }
    var clockPeriodLengthSeconds: Int { confirmedLinkedState?.currentPeriodLengthSeconds ?? clockSession.currentPeriodLengthSeconds }
    var clockStoppageSeconds: Int { confirmedLinkedState?.currentStoppageSeconds ?? clockSession.currentStoppageSeconds }
    var clockIsRunning: Bool {
        guard let confirmedLinkedState else { return clockSession.state.isRunning }
        return confirmedLinkedState.timer.isRunning && !clockPeriodCompleted
    }
    var clockIsTimeUp: Bool {
        guard let confirmedLinkedState else { return clockSession.isTimeUp() }
        return clockElapsedSeconds >= confirmedLinkedState.targetSeconds
    }
    var clockElapsedSeconds: Int {
        guard let confirmedLinkedState else { return clockSession.elapsedSecondsNow() }
        return FootballMatchReducer.displayElapsedSeconds(state: confirmedLinkedState, at: linkedDisplayEpochMilliseconds)
    }
    var clockMainDisplaySeconds: Int {
        confirmedLinkedState == nil ? clockSession.mainDisplaySeconds : min(clockElapsedSeconds, clockPeriodLengthSeconds)
    }
    var clockStoppageElapsedSeconds: Int {
        confirmedLinkedState == nil ? clockSession.elapsedStoppageSeconds : max(0, clockElapsedSeconds - clockPeriodLengthSeconds)
    }
    var clockPeriodCompleted: Bool { confirmedLinkedState == nil ? clockSession.periodCompleted : clockIsTimeUp }
    var allowsManualClockPause: Bool { clockSession.allowsManualPause }
    var allowsStoppageTime: Bool { clockSession.allowsStoppageTime }

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
        if let submitLinkedIntent {
            _ = submitLinkedIntent(.football(.toggleClock))
            return
        }
        clockSession.toggleRunning()
        clockRevision &+= 1
    }

    func addStoppage(_ seconds: Int) {
        if let submitLinkedIntent {
            _ = submitLinkedIntent(.football(.addStoppage(seconds: seconds)))
            return
        }
        guard clockSession.addStoppageSeconds(seconds) else { return }
        stoppageAdditionHistory.append(seconds)
        clockRevision &+= 1
    }

    var canUndoLastStoppage: Bool { !(confirmedLinkedState?.stoppageHistory ?? stoppageAdditionHistory).isEmpty }

    func undoLastStoppage() {
        if let submitLinkedIntent {
            _ = submitLinkedIntent(.football(.undoLastStoppage))
            return
        }
        guard let seconds = stoppageAdditionHistory.last else { return }
        guard clockSession.undoStoppageSeconds(seconds) else { return }
        stoppageAdditionHistory.removeLast()
        clockRevision &+= 1
    }

    @discardableResult
    func advanceClockStage() -> Bool {
        if let submitLinkedIntent { return submitLinkedIntent(.football(.advanceStage)) }
        guard clockSession.advanceStage() else { return false }
        clockRevision &+= 1
        return true
    }

    func checkClockExpiry() -> Bool {
        let wasRunning = clockIsRunning
        if confirmedLinkedState != nil {
            linkedDisplayEpochMilliseconds = Int64(Date().timeIntervalSince1970 * 1_000)
            return wasRunning && clockPeriodCompleted
        }
        let completed = clockSession.refresh()
        if wasRunning && completed { clockRevision &+= 1 }
        return wasRunning && completed
    }

    func restoreFootballSession(_ resumeState: FootballResumeStateV2) {
        restoreSession(resumeState.lineScore)
        clockSession = FootballMatchClockSession(state: resumeState.timer, gameType: gameType)
        clockSession.reconcileAfterRestore()
        stoppageAdditionHistory.removeAll()
        clockRevision &+= 1
    }

    /// Android 3.0 records did not contain a football clock. Preserve their
    /// score while restoring a paused first period at the configured default.
    func restoreLegacyFootballSession(_ resumeState: LineScoreResumeState? = nil) {
        if let resumeState { restoreSession(resumeState) }
        clockSession = FootballMatchClockSession(
            state: .init(halfLengthSeconds: clockSession.state.halfLengthSeconds),
            gameType: gameType
        )
        stoppageAdditionHistory.removeAll()
        clockRevision &+= 1
    }

    func resetClock(halfLengthSeconds: Int? = nil) {
        finishedViaLink = false
        let length = halfLengthSeconds ?? clockSession.state.halfLengthSeconds
        clockSession = FootballMatchClockSession(
            state: .init(halfLengthSeconds: length),
            gameType: gameType
        )
        clockSession.resetForNewGame()
        stoppageAdditionHistory.removeAll()
        clockRevision &+= 1
    }

    /// Goals carry the match-clock snapshot so records can render `53′` /
    /// `45+2′` (same fields Android and Harmony write).
    override func snapshotAnnotation(for intent: LineScoreIntent) -> String? {
        guard case .pointWon = intent else { return nil }
        return FootballClockAnnotation.encode(
            period: clockSession.state.stage,
            elapsedSeconds: clockSession.elapsedSecondsNow()
        )
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
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        var timer = state.timer
        timer.elapsedSeconds = FootballMatchReducer.displayElapsedSeconds(state: state, at: now)
        timer.savedWallClockMilliseconds = now
        timer.isRunning = timer.isRunning && !state.finished && timer.elapsedSeconds < state.targetSeconds
        clockSession = FootballMatchClockSession(state: timer, gameType: gameType)
        stoppageAdditionHistory = state.stoppageHistory
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
        // Freeze the match clock at the final whistle. The board keeps a 1s
        // tick that refreshes the clock session, so without this every later
        // save (background/exit) persisted a longer elapsed time than the
        // moment the match actually ended.
        clockSession.pause()
        clockRevision &+= 1
    }

    override func undo() -> Bool {
        if let submitLinkedIntent { return submitLinkedIntent(.undo(targetOpId: nil)) }
        // Android 3.1 keeps score undo and injury-time undo as separate
        // commands. The scoreboard's generic Undo must therefore only consume
        // the line-score reducer history; `undoLastStoppage()` owns stoppage
        // rollback and clock/stage operations never enter the score undo stack.
        return super.undo()
    }

    // MARK: - Real-time Record Saving

    func saveGameRecordInRealTime(recordID: String, isGameFinished: Bool = false) {
        guard submitLinkedIntent == nil, !finishedViaLink else { return }
        #if DEBUG
        print("[FootballViewModel] 💾 Saving football record in real-time (isGameFinished: \(isGameFinished))")
        #endif
        let hasProgress = !(controller?.getGameActions().isEmpty ?? true)
            || leftTeam.score != 0
            || rightTeam.score != 0
            || clockSession.state.stage != 1
            || clockSession.elapsedSecondsNow() > 0
            || clockSession.state.stoppageSeconds.contains(where: { $0 > 0 })
            || isGameFinished
            || gameFinished
        guard hasProgress else { return }

        let endTime = Date()
        let duration = endTime.timeIntervalSince(controller?.getGameStartTime() ?? Date())

        var winner: String? = nil
        if isGameFinished || gameFinished {
            if leftTeam.score > rightTeam.score {
                winner = TeamID.team0.rawValue
            } else if rightTeam.score > leftTeam.score {
                winner = TeamID.team1.rawValue
            }
        }

        let resumeState = LineScoreResumeState(
            state: sessionState,
            undoHistory: resumeHistory,
            intentTimeline: controller?.getGameActions() ?? []
        )
        var persistedTimer = clockSession.snapshot()
        if isGameFinished || gameFinished {
            persistedTimer.isRunning = false
        }
        let footballResume = FootballResumeStateV2(lineScore: resumeState, timer: persistedTimer)
        let snapshotData: Data
        do {
            snapshotData = try JSONEncoder().encode(footballResume)
        } catch {
            ScoreboardPersistenceFailureReporter.report(
                error,
                context: "Failed to encode football record \(recordID)"
            )
            return
        }

        controller?.saveScoreboardRecord(
            id: recordID,
            endTime: endTime,
            duration: duration,
            team1Name: leftTeam.name,
            team2Name: rightTeam.name,
            team1FinalScore: leftTeam.score,
            team2FinalScore: rightTeam.score,
            // Football has periods but no independent set score. Persisting a
            // synthetic 1:1 made a genuine 2:0 result render and share as 1:1.
            team1SetScore: nil,
            team2SetScore: nil,
            winner: winner,
            totalScoreChanges: controller?.getGameActions().count ?? 0,
            extraData: [:],
            projectConfiguration: [
                ScoreboardRecordConfiguration.Key.scoreCoreGameType: gameType.rawValue,
                "minimumScore": LineScoreRuleSet.nonNegative.minimum,
                "maximumScore": LineScoreRuleSet.nonNegative.maximum,
                "ruleProfileVersion": 1,
                "footballHalfLengthSeconds": clockSession.state.halfLengthSeconds,
                "showMatchTime": true
            ],
            stateSnapshot: snapshotData,
            isFinished: isGameFinished || gameFinished
        )
        #if DEBUG
        print("[FootballViewModel] ✅ Football record saved successfully")
        #endif
    }
}
