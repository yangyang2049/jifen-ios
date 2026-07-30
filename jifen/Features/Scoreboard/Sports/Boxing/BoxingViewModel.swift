//
//  BoxingViewModel.swift
//  jifen
//
//  拳击计分：总分 + 胜回合数，addRoundScore(leftPoints, rightPoints) 与鸿蒙对齐。
//

import Foundation
import ScoreCore

struct BoxingHistoryEntry: Codable, Equatable {
    let state: BoxingMatchState
    let restoresNames: Bool
}

struct BoxingSessionArchive: Codable, Equatable {
    var schemaVersion = 1
    let state: BoxingMatchState
    let undoHistory: [BoxingHistoryEntry]
    let intentTimeline: [String]
}

@Observable
class BoxingViewModel: BaseScoreViewModel, ScoreEditGuarding {
    private let reducer = BoxingMatchReducer()
    var currentRound: Int = 1
    var maxRounds: Int = 3
    private var fullStateHistory: [BoxingHistoryEntry] = []
    private var sidesSwapped = false

    override init(controller: BaseScoreboardController? = nil) {
        super.init(controller: controller)
        leftTeam.sets = 0
        rightTeam.sets = 0
    }

    /// 结束一回合：累加双方本回合分数，胜方回合数 +1
    func addRoundScore(leftPoints: Int, rightPoints: Int) {
        guard !gameFinished, currentRound <= maxRounds else { return }
        saveFullStateToHistory()
        let result = reduce(.submitRound(left: leftPoints, right: rightPoints))
        guard result.accepted else { _ = fullStateHistory.popLast(); return }
        apply(result.state)

        controller?.recordScoreAction(action: "round \(max(0, leftPoints))-\(max(0, rightPoints))")
        controller?.performVibration(type: .medium)
    }

    func setMaxRounds(_ rounds: Int) {
        maxRounds = max(1, min(rounds, 99))
    }

    func getWinnerName() -> String {
        guard gameFinished else { return "" }
        let leftSets = leftTeam.sets ?? 0
        let rightSets = rightTeam.sets ?? 0
        if leftSets > rightSets { return leftTeam.name }
        if rightSets > leftSets { return rightTeam.name }
        return ""
    }

    func saveGameRecordInRealTime(recordID: String, isGameFinished: Bool = false) {
        let hasProgress = !(controller?.getGameActions().isEmpty ?? true)
            || leftTeam.score != 0
            || rightTeam.score != 0
            || (leftTeam.sets ?? 0) != 0
            || (rightTeam.sets ?? 0) != 0
            || isGameFinished
            || gameFinished
        guard hasProgress else { return }

        let finished = isGameFinished || gameFinished
        let start = controller?.getGameStartTime() ?? Date()
        let end = Date()

        var winner: String?
        if finished {
            let leftSets = leftTeam.sets ?? 0
            let rightSets = rightTeam.sets ?? 0
            if leftSets > rightSets {
                winner = "left"
            } else if rightSets > leftSets {
                winner = "right"
            }
        }

        let archive = BoxingSessionArchive(
            state: coreState,
            undoHistory: fullStateHistory,
            intentTimeline: controller?.getGameActions() ?? []
        )
        let snapshotData: Data
        do {
            snapshotData = try JSONEncoder().encode(archive)
        } catch {
            ScoreboardPersistenceFailureReporter.report(
                error,
                context: "Failed to encode boxing record \(recordID)"
            )
            return
        }

        controller?.saveScoreboardRecord(
            id: recordID,
            endTime: end,
            duration: end.timeIntervalSince(start),
            team1Name: leftTeam.name,
            team2Name: rightTeam.name,
            team1FinalScore: leftTeam.score,
            team2FinalScore: rightTeam.score,
            team1SetScore: leftTeam.sets,
            team2SetScore: rightTeam.sets,
            winner: winner,
            totalScoreChanges: controller?.getGameActions().count ?? 0,
            extraData: [
                "currentRound": currentRound,
                "maxRounds": maxRounds,
                "leftSets": leftTeam.sets ?? 0,
                "rightSets": rightTeam.sets ?? 0
            ],
            projectConfiguration: [
                ScoreboardRecordConfiguration.Key.scoreCoreGameType: ScoreCore.GameType.boxing.rawValue,
                "maxRounds": maxRounds
            ],
            stateSnapshot: snapshotData,
            status: finished ? .finished : .draft
        )
    }

    func restoreSession(_ archive: BoxingSessionArchive) {
        fullStateHistory = Array(archive.undoHistory.suffix(50))
        apply(archive.state)
        controller?.clearHistory()
        for entry in fullStateHistory {
            controller?.pushHistory(
                left: entry.state.leftTotal,
                right: entry.state.rightTotal,
                leftSets: entry.state.leftRoundsWon,
                rightSets: entry.state.rightRoundsWon
            )
        }
    }

    func restoreLegacyMatch(
        leftName: String,
        rightName: String,
        leftScore: Int,
        rightScore: Int,
        leftSets: Int,
        rightSets: Int,
        currentRound: Int,
        maxRounds: Int
    ) {
        fullStateHistory.removeAll()
        apply(BoxingMatchState(
            leftName: leftName,
            rightName: rightName,
            maxRounds: maxRounds,
            leftTotal: leftScore,
            rightTotal: rightScore,
            leftRoundsWon: leftSets,
            rightRoundsWon: rightSets,
            currentRound: currentRound
        ))
        controller?.clearHistory()
    }

    func startNewMatch() {
        let result = reduce(.reset)
        apply(result.state)
        fullStateHistory.removeAll()
        controller?.clearHistory()
    }

    func adjustSets(isLeft: Bool, delta: Int) {
        let result = reduce(.adjust(
            leftTotal: leftTeam.score,
            rightTotal: rightTeam.score,
            currentRound: currentRound,
            leftRoundsWon: max(0, (leftTeam.sets ?? 0) + (isLeft ? delta : 0)),
            rightRoundsWon: max(0, (rightTeam.sets ?? 0) + (isLeft ? 0 : delta))
        ))
        guard result.accepted else { return }
        saveFullStateToHistory()
        apply(result.state)
        controller?.recordScoreAction(action: (isLeft ? "left" : "right") + " sets \(delta > 0 ? "+" : "")\(delta)")
    }

    func canAdjustSetScore(isLeft: Bool, delta: Int) -> Bool {
        let state = coreState
        let left = state.leftRoundsWon + (isLeft ? delta : 0)
        let right = state.rightRoundsWon + (isLeft ? 0 : delta)
        return state.allowsRoundsWon(left: left, right: right)
    }

    override func addScore(isLeft: Bool, points: Int) {
        guard !gameFinished else { return }
        saveFullStateToHistory()
        let result = reduce(.addPoints(side: isLeft ? .left : .right, points: points))
        guard result.accepted else { _ = fullStateHistory.popLast(); return }
        apply(result.state)
        controller?.recordScoreAction(action: "\(isLeft ? "left" : "right") +\(points)")
        controller?.performVibration(type: .medium)
    }

    override func subtractScore(isLeft: Bool, points: Int) {
        guard !gameFinished else { return }
        saveFullStateToHistory()
        let result = reduce(.adjust(
            leftTotal: max(0, leftTeam.score - (isLeft ? points : 0)),
            rightTotal: max(0, rightTeam.score - (isLeft ? 0 : points)),
            currentRound: currentRound,
            leftRoundsWon: leftTeam.sets ?? 0,
            rightRoundsWon: rightTeam.sets ?? 0
        ))
        apply(result.state)
        controller?.recordScoreAction(action: "\(isLeft ? "left" : "right") -\(points)")
        controller?.performVibration(type: .light)
    }

    override func exchangeSides() {
        saveFullStateToHistory(restoresNames: true)
        apply(reduce(.exchangeSides).state)
        controller?.performVibration(type: .medium)
    }

    override func undo() -> Bool {
        guard controller?.undoEnabled ?? true else { return false }
        guard let entry = fullStateHistory.popLast() else { return false }
        let state = entry.state

        _ = controller?.popHistory()
        if entry.restoresNames {
            leftTeam.name = state.leftName
            rightTeam.name = state.rightName
        }
        leftTeam.score = state.leftTotal
        rightTeam.score = state.rightTotal
        leftTeam.sets = state.leftRoundsWon
        rightTeam.sets = state.rightRoundsWon
        currentRound = state.currentRound
        maxRounds = state.maxRounds
        sidesSwapped = state.sidesSwapped
        gameFinished = state.finished

        controller?.performVibration(type: .light)
        return true
    }

    override func reset() {
        saveFullStateToHistory()
        apply(reduce(.reset).state)
        controller?.clearHistory()
        fullStateHistory.removeAll()
    }

    override func endGame() {
        apply(reduce(.finish).state)
    }

    private func saveFullStateToHistory(restoresNames: Bool = false) {
        fullStateHistory.append(
            BoxingHistoryEntry(
                state: coreState,
                restoresNames: restoresNames
            )
        )
        if fullStateHistory.count > 50 {
            fullStateHistory.removeFirst()
        }

        controller?.pushHistory(
            left: leftTeam.score,
            right: rightTeam.score,
            leftSets: leftTeam.sets,
            rightSets: rightTeam.sets
        )
    }

    private func reduce(_ intent: BoxingMatchIntent) -> ReduceResult<BoxingMatchState, BoxingMatchEvent> {
        reducer.reduce(state: coreState, intent: intent, at: Int64(Date().timeIntervalSince1970 * 1_000))
    }

    private var coreState: BoxingMatchState {
        .init(
            leftName: leftTeam.name,
            rightName: rightTeam.name,
            maxRounds: maxRounds,
            leftTotal: leftTeam.score,
            rightTotal: rightTeam.score,
            leftRoundsWon: leftTeam.sets ?? 0,
            rightRoundsWon: rightTeam.sets ?? 0,
            currentRound: currentRound,
            sidesSwapped: sidesSwapped,
            finished: gameFinished
        )
    }

    private func apply(_ state: BoxingMatchState) {
        leftTeam.name = state.leftName
        rightTeam.name = state.rightName
        leftTeam.score = state.leftTotal
        rightTeam.score = state.rightTotal
        leftTeam.sets = state.leftRoundsWon
        rightTeam.sets = state.rightRoundsWon
        currentRound = state.currentRound
        maxRounds = state.maxRounds
        sidesSwapped = state.sidesSwapped
        gameFinished = state.finished
    }
}
