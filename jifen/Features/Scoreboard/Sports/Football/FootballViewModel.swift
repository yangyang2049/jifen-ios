//
//  FootballViewModel.swift
//  jifen
//
//  Football scoreboard view model
//

import Foundation
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

    var clockStage: Int { clockSession.state.stage }
    var clockIsRunning: Bool { clockSession.state.isRunning }
    var clockIsTimeUp: Bool { clockSession.isTimeUp() }
    var clockElapsedSeconds: Int { clockSession.elapsedSecondsNow() }
    var clockMainDisplaySeconds: Int { clockSession.mainDisplaySeconds }
    var clockStoppageElapsedSeconds: Int { clockSession.elapsedStoppageSeconds }
    var clockPeriodCompleted: Bool { clockSession.periodCompleted }
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
        clockSession.toggleRunning()
        clockRevision &+= 1
    }

    func addStoppage(_ seconds: Int) {
        guard clockSession.addStoppageSeconds(seconds) else { return }
        stoppageAdditionHistory.append(seconds)
        clockRevision &+= 1
    }

    var canUndoLastStoppage: Bool { !stoppageAdditionHistory.isEmpty }

    func undoLastStoppage() {
        guard let seconds = stoppageAdditionHistory.last else { return }
        guard clockSession.undoStoppageSeconds(seconds) else { return }
        stoppageAdditionHistory.removeLast()
        clockRevision &+= 1
    }

    @discardableResult
    func advanceClockStage() -> Bool {
        guard clockSession.advanceStage() else { return false }
        clockRevision &+= 1
        return true
    }

    func checkClockExpiry() -> Bool {
        let wasRunning = clockIsRunning
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
        let length = halfLengthSeconds ?? clockSession.state.halfLengthSeconds
        clockSession = FootballMatchClockSession(
            state: .init(halfLengthSeconds: length),
            gameType: gameType
        )
        clockSession.resetForNewGame()
        stoppageAdditionHistory.removeAll()
        clockRevision &+= 1
    }

    override func undo() -> Bool {
        // Android 3.1 keeps score undo and injury-time undo as separate
        // commands. The scoreboard's generic Undo must therefore only consume
        // the line-score reducer history; `undoLastStoppage()` owns stoppage
        // rollback and clock/stage operations never enter the score undo stack.
        super.undo()
    }

    // MARK: - Real-time Record Saving

    func saveGameRecordInRealTime(recordID: String, isGameFinished: Bool = false) {
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
