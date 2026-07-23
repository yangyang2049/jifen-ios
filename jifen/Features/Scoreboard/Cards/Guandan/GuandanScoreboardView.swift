import ScoreCore
import SwiftUI
import UIKit

struct GuandanScoreboardView: View {
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var state: GuandanMatchState
    @State private var history: [GuandanMatchState] = []
    @State private var actionLog: [String] = []
    @State private var actionCount = 0
    @State private var gameStartAt: Date
    @State private var recordID: String
    @State private var showGameOverDialog = false
    @State private var showFinishedRecordDetail = false

    private let reducer = GuandanSessionReducer()

    init(
        initialSetup: SportsSetupResult? = nil,
        initialRecordId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        onNavigationBack: (() -> Void)? = nil
    ) {
        self.initialSetup = initialSetup
        self.initialRecordId = initialRecordId
        self.onSetupConsumed = onSetupConsumed
        self.onNavigationBack = onNavigationBack

        let red = initialSetup?.team1Name.nonEmpty
            ?? NSLocalizedString("watch_team_red", value: "红方", comment: "")
        let blue = initialSetup?.team2Name.nonEmpty
            ?? NSLocalizedString("watch_team_blue", value: "蓝方", comment: "")
        let tripleA = initialSetup?.guandanTripleA ?? PreferencesManager.shared.guandanSetupTripleA
        let passRaw = initialSetup?.guandanPassACondition ?? PreferencesManager.shared.guandanSetupPassACondition
        let pass: GuandanPassACondition = passRaw == "double_up" ? .doubleUp : .notLast
        let fallback = initialSetup?.guandanTripleAFallbackRank
            ?? PreferencesManager.shared.guandanSetupTripleAFallbackRank

        var initial = GuandanMatchState.initial(
            redName: red,
            blueName: blue,
            aStageMode: tripleA ? .tripleA : .singleA,
            passACondition: pass,
            tripleAFallbackRank: fallback
        )
        var start = Date()
        var id = "guandan_\(Int(start.timeIntervalSince1970))"
        var actions = 0
        var showFinished = false
        var restoredActions: [String] = []

        if let initialRecordId,
           let record = ScoreboardRecordManager.shared.getRecordById(initialRecordId),
           record.status == .draft,
           let data = record.stateSnapshot,
           let restored = try? JSONDecoder().decode(GuandanMatchState.self, from: data) {
            initial = restored
            start = record.startTime
            id = record.id
            actions = max(record.totalScoreChanges, 1)
            restoredActions = record.actions
            showFinished = restored.phase == .finished
        }

        _state = State(initialValue: initial)
        _gameStartAt = State(initialValue: start)
        _recordID = State(initialValue: id)
        _actionCount = State(initialValue: actions)
        _showGameOverDialog = State(initialValue: showFinished)
        _actionLog = State(initialValue: restoredActions)
    }

    var body: some View {
        ZStack {
            SpecializedScoreboardScaffold(
                gameType: .guandan,
                leftName: state.redTeam.name,
                rightName: state.blueTeam.name,
                leftScore: state.displayRank(for: .red),
                rightScore: state.displayRank(for: .blue),
                leftDetail: leftDetail,
                rightDetail: rightDetail,
                finished: state.phase == .finished,
                onLeftTap: { handleSideTap(.red) },
                onRightTap: { handleSideTap(.blue) },
                onUndo: undo,
                onReset: resetMatch,
                onExchange: nil,
                onBack: {
                    saveRecord()
                    onNavigationBack?()
                    dismiss()
                },
                showEndGame: true,
                onEndGame: finishMatch,
                onEditCommit: applyEdit,
                bottomBar: state.phase == .roundResult ? { AnyView(stepButtonsBar) } : nil,
                topCenter: {
                    AnyView(statusPill)
                },
                center: {
                    EmptyView()
                }
            )

            if showGameOverDialog, let winner = state.finalWinner {
                GameOverDialog(
                    winnerName: winner == .red ? state.redTeam.name : state.blueTeam.name,
                    leftName: state.redTeam.name,
                    rightName: state.blueTeam.name,
                    leftScore: GuandanMatchState.rankDisplayScore(state.redTeam.currentRank),
                    rightScore: GuandanMatchState.rankDisplayScore(state.blueTeam.currentRank),
                    onNewGame: {
                        resetMatch()
                    },
                    onRecords: {
                        saveRecord()
                        showFinishedRecordDetail = true
                    },
                    onShare: {
                        ScoreboardShareSupport.present(
                            text: "\(state.redTeam.name) \(state.displayRank(for: .red)) - \(state.displayRank(for: .blue)) \(state.blueTeam.name)"
                        )
                    },
                    onExit: {
                        saveRecord()
                        onNavigationBack?()
                        dismiss()
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showFinishedRecordDetail) {
            NavigationStack {
                ScoreboardRecordDetailPage(recordId: recordID)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(NSLocalizedString("done", value: "完成", comment: "")) {
                                showFinishedRecordDetail = false
                            }
                        }
                    }
            }
        }
        .onAppear {
            if state.phase == .notStarted {
                send(.startMatch)
            }
            onSetupConsumed?()
        }
        .onChange(of: state.phase) { _, phase in
            if phase == .finished {
                showGameOverDialog = true
            }
        }
        .onDisappear {
            saveRecord()
        }
    }

    private var leftDetail: String? {
        guard state.isInAStage, state.aStageTeam == .red else { return nil }
        if state.aStageMode == .tripleA {
            return String(format: NSLocalizedString("guandan_a_fail_format", value: "闯A失败 %d/3", comment: ""), state.redAFailCount)
        }
        return NSLocalizedString("guandan_a_stage", value: "闯A中", comment: "")
    }

    private var rightDetail: String? {
        guard state.isInAStage, state.aStageTeam == .blue else { return nil }
        if state.aStageMode == .tripleA {
            return String(format: NSLocalizedString("guandan_a_fail_format", value: "闯A失败 %d/3", comment: ""), state.blueAFailCount)
        }
        return NSLocalizedString("guandan_a_stage", value: "闯A中", comment: "")
    }

    private var statusPill: some View {
        Group {
            if state.phase == .roundResult {
                Text(NSLocalizedString("guandan_select_upgrade", value: "选择升几级", comment: ""))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Capsule())
            } else if state.isInAStage, let side = state.aStageTeam {
                Text(String(
                    format: NSLocalizedString("guandan_a_stage_team_format", value: "%@ 闯A", comment: ""),
                    side == .red ? state.redTeam.name : state.blueTeam.name
                ))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.85))
                .clipShape(Capsule())
            }
        }
    }

    private var stepButtonsBar: some View {
        HStack(spacing: 10) {
            ForEach([1, 2, 3], id: \.self) { step in
                Button {
                    send(.applyRoundSettlement(step: step))
                } label: {
                    Text(String(format: NSLocalizedString("guandan_upgrade_step_format", value: "升%d", comment: ""), step))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 72, height: 44)
                        .background(Theme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Button {
                send(.cancelRoundResult)
            } label: {
                Text(NSLocalizedString("cancel", value: "取消", comment: ""))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Color.black.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 18)
    }

    private func handleSideTap(_ side: GuandanSide) {
        guard state.phase == .playing else { return }
        send(.beginRoundResult(winner: side))
    }

    private func send(_ intent: GuandanSessionIntent) {
        let result = reducer.reduce(state: state, intent: intent, at: Int64(Date().timeIntervalSince1970 * 1000))
        guard result.accepted else { return }
        history.append(state)
        if history.count > 80 { history.removeFirst() }
        state = result.state
        actionCount += 1
        appendSnapshot(String(describing: intent))
        VibrationManager.shared.vibrateMedium()
        if state.phase == .finished {
            showGameOverDialog = true
        }
    }

    private func undo() -> Bool {
        guard let previous = history.popLast() else { return false }
        state = previous
        actionCount = max(0, actionCount - 1)
        appendSnapshot("undo")
        showGameOverDialog = state.phase == .finished
        return true
    }

    private func resetMatch() {
        history.append(state)
        state = .initial(
            redName: state.redTeam.name,
            blueName: state.blueTeam.name,
            aStageMode: state.aStageMode,
            passACondition: state.passACondition,
            tripleAFallbackRank: state.tripleAFallbackRank
        )
        state.phase = .playing
        actionCount += 1
        appendSnapshot("reset")
        showGameOverDialog = false
    }

    private func finishMatch() {
        guard state.phase != .finished else { return }
        history.append(state)
        let redScore = GuandanMatchState.rankDisplayScore(state.redTeam.currentRank)
        let blueScore = GuandanMatchState.rankDisplayScore(state.blueTeam.currentRank)
        state.finalWinner = redScore == blueScore ? nil : (redScore > blueScore ? .red : .blue)
        state.phase = .finished
        actionCount += 1
        appendSnapshot("finish")
        showGameOverDialog = true
    }

    private func applyEdit(left: String, right: String, leftScore: String, rightScore: String) {
        history.append(state)
        if !left.isEmpty { state.redTeam.name = left }
        if !right.isEmpty { state.blueTeam.name = right }
        let redRank = leftScore.uppercased().replacingOccurrences(of: "A1", with: "A")
            .replacingOccurrences(of: "A2", with: "A")
            .replacingOccurrences(of: "A3", with: "A")
        let blueRank = rightScore.uppercased().replacingOccurrences(of: "A1", with: "A")
            .replacingOccurrences(of: "A2", with: "A")
            .replacingOccurrences(of: "A3", with: "A")
        if guandanRankOrder.contains(redRank) { state.redTeam.currentRank = redRank }
        if guandanRankOrder.contains(blueRank) { state.blueTeam.currentRank = blueRank }
        state.phase = .playing
        state.finalWinner = nil
        actionCount += 1
        showGameOverDialog = false
    }

    private func saveRecord() {
        guard actionCount > 0 || state.phase != .notStarted else { return }
        let end = Date()
        let winnerName: String? = {
            guard let winner = state.finalWinner else { return nil }
            return winner == .red ? state.redTeam.name : state.blueTeam.name
        }()
        let snapshotData = try? JSONEncoder().encode(state)
        let finished = state.phase == .finished
        let record = ScoreboardRecord(
            id: recordID,
            gameType: .guandan,
            startTime: gameStartAt,
            endTime: end,
            duration: end.timeIntervalSince(gameStartAt),
            team1Name: state.redTeam.name,
            team2Name: state.blueTeam.name,
            team1FinalScore: GuandanMatchState.rankDisplayScore(state.redTeam.currentRank),
            team2FinalScore: GuandanMatchState.rankDisplayScore(state.blueTeam.currentRank),
            winner: winnerName,
            actions: actionLog,
            totalScoreChanges: max(actionCount, history.count),
            extraData: [
                "schemaVersion": AnyCodable(3),
                "guandanTripleA": AnyCodable(state.aStageMode == .tripleA),
                "guandanPassACondition": AnyCodable(state.passACondition.rawValue),
                "guandanTripleAFallbackRank": AnyCodable(state.tripleAFallbackRank)
            ],
            stateSnapshot: snapshotData,
            status: finished ? .finished : .draft
        )
        try? ScoreboardRecordManager.shared.saveScoreboardRecord(record)
    }

    private func appendSnapshot(_ code: String) {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
        let scores = [
            GuandanMatchState.rankDisplayScore(state.redTeam.currentRank),
            GuandanMatchState.rankDisplayScore(state.blueTeam.currentRank)
        ]
        let safeCode = code.replacingOccurrences(of: "|", with: "_").replacingOccurrences(of: " ", with: "_")
        actionLog.append("\(timestamp)|snapshot|\(safeCode)|\(scores.map(String.init).joined(separator: ","))|")
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    GuandanScoreboardView()
}
