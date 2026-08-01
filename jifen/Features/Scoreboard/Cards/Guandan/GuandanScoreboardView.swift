import ScoreCore
import SwiftUI
import UIKit

struct GuandanScoreboardView: View {
    var initialSetup: SportsSetupResult? = nil
    var initialResumeSessionId: String? = nil
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
    @State private var pendingEditWrapSide: GuandanSide?

    private let reducer = GuandanSessionReducer()

    init(
        initialSetup: SportsSetupResult? = nil,
        initialResumeSessionId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        onNavigationBack: (() -> Void)? = nil
    ) {
        self.initialSetup = initialSetup
        self.initialResumeSessionId = initialResumeSessionId
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
        var id = ScoreboardRecordIdentity.next(prefix: GameType.guandan.canonicalScoreboardIdentifier)
        var actions = 0
        var showFinished = false
        var restoredActions: [String] = []

        if let initialResumeSessionId,
           let record = ManualResumeSessionStore.load(recordID: initialResumeSessionId),
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
        _pendingEditWrapSide = State(initialValue: nil)
    }

    var body: some View {
        ZStack {
            SpecializedScoreboardScaffold(
                gameType: .guandan,
                leftName: state.redTeam.name,
                rightName: state.blueTeam.name,
                leftScore: state.displayRank(for: .red),
                rightScore: state.displayRank(for: .blue),
                leftDetail: nil,
                rightDetail: nil,
                finished: state.phase == .finished,
                onLeftTap: {},
                onRightTap: {},
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
                onEditAdjust: { isLeft, delta in
                    adjustRankInEditMode(side: isLeft ? .red : .blue, delta: delta)
                },
                seamOverlay: state.lastRoundWinner == nil ? nil : {
                    AnyView(
                        GeometryReader { geo in
                            let indicatorSize = ScoreboardLayoutMetrics.serveIndicatorSize(
                                halfViewportSize: CGSize(width: geo.size.width / 2, height: geo.size.height)
                            )
                            CenterLineServeIndicator(
                                isLeftServing: state.lastRoundWinner == .red,
                                triangleSize: indicatorSize,
                                color: ScoreboardTheme.serverIndicatorColor
                            )
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        }
                        .allowsHitTesting(false)
                    )
                },
                panelAccessory: { isLeft in
                    AnyView(guandanPanelActions(side: isLeft ? .red : .blue))
                },
                center: { _, _ in
                    EmptyView()
                }
            )

            if showGameOverDialog {
                let winnerName: String = switch state.finalWinner {
                case .red: state.redTeam.name
                case .blue: state.blueTeam.name
                case nil: ""
                }
                let winnerIndices: Set<Int> = switch state.finalWinner {
                case .red: [0]
                case .blue: [1]
                case nil: []
                }
                GameOverDialog(
                    winnerName: winnerName,
                    gameType: .guandan,
                    leftName: state.redTeam.name,
                    rightName: state.blueTeam.name,
                    leftScoreText: state.displayRank(for: .red),
                    rightScoreText: state.displayRank(for: .blue),
                    winnerIndices: winnerIndices,
                    onNewGame: {
                        startNewMatch()
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
        .alert(
            NSLocalizedString("guandan_edit_level_wrap_confirm_title", value: "级牌回到 2？", comment: ""),
            isPresented: Binding(
                get: { pendingEditWrapSide != nil },
                set: { if !$0 { pendingEditWrapSide = nil } }
            )
        ) {
            Button(NSLocalizedString("cancel", value: "取消", comment: ""), role: .cancel) {
                pendingEditWrapSide = nil
            }
            Button(NSLocalizedString("confirm", value: "确认", comment: ""), role: .destructive) {
                guard let side = pendingEditWrapSide else { return }
                pendingEditWrapSide = nil
                send(.adjustRank(side: side, delta: 1))
            }
        } message: {
            Text(NSLocalizedString(
                "guandan_edit_level_wrap_confirm_message",
                value: "继续增加会将该队级牌重置为 2。",
                comment: ""
            ))
        }
    }

    @ViewBuilder
    private func guandanPanelActions(side: GuandanSide) -> some View {
        if state.phase != .finished {
            HStack(spacing: 12) {
                ForEach([1, 2, 3], id: \.self) { step in
                    scoreboardCardActionButton("+\(step)") {
                        applyGuandanRound(side: side, step: step)
                    }
                    .accessibilityIdentifier("guandan_round_\(side.rawValue)_plus_\(step)")
                }
            }
        }
    }

    private func applyGuandanRound(side: GuandanSide, step: Int) {
        guard state.phase != .finished else { return }
        let before = state
        var working = state
        if working.phase == .roundResult {
            if working.roundWinner != side {
                working = reducer.reduce(
                    state: working,
                    intent: .cancelRoundResult,
                    at: Int64(Date().timeIntervalSince1970 * 1000)
                ).state
            }
        }
        if working.phase != .roundResult {
            let begin = reducer.reduce(
                state: working,
                intent: .beginRoundResult(winner: side),
                at: Int64(Date().timeIntervalSince1970 * 1000)
            )
            guard begin.accepted else { return }
            working = begin.state
        }
        let settled = reducer.reduce(
            state: working,
            intent: .applyRoundSettlement(step: step),
            at: Int64(Date().timeIntervalSince1970 * 1000)
        )
        guard settled.accepted else { return }
        history.append(before)
        if history.count > 80 { history.removeFirst() }
        state = settled.state
        actionCount += 1
        appendSnapshot("round_\(side.rawValue)_plus_\(step)")
        VibrationManager.shared.vibrateMedium()
        if state.phase == .finished { showGameOverDialog = true }
    }

    private func adjustRankInEditMode(side: GuandanSide, delta: Int) {
        guard delta != 0 else { return }
        if delta > 0, shouldConfirmRankWrap(side: side, delta: delta) {
            pendingEditWrapSide = side
            return
        }
        send(.adjustRank(side: side, delta: delta))
    }

    private func shouldConfirmRankWrap(side: GuandanSide, delta: Int) -> Bool {
        guard delta > 0 else { return false }
        let rank = side == .red ? state.redTeam.currentRank : state.blueTeam.currentRank
        let maxRankIndex = guandanRankOrder.count - 1
        let rankIndex = max(0, guandanRankOrder.firstIndex(of: rank) ?? 0)
        let currentDisplayIndex: Int
        if state.aStageMode == .tripleA, rankIndex == maxRankIndex {
            currentDisplayIndex = maxRankIndex + min(max(state.aFailCount(for: side), 0), 2)
        } else {
            currentDisplayIndex = rankIndex
        }
        let maxDisplayIndex = state.aStageMode == .tripleA ? maxRankIndex + 2 : maxRankIndex
        return currentDisplayIndex + delta > maxDisplayIndex
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
        send(.reset)
        showGameOverDialog = false
    }

    private func startNewMatch() {
        saveRecord()
        let reset = reducer.reduce(
            state: state,
            intent: .reset,
            at: Int64(Date().timeIntervalSince1970 * 1_000)
        )
        guard reset.accepted else { return }
        state = reset.state
        history.removeAll()
        actionLog.removeAll()
        actionCount = 0
        gameStartAt = Date()
        recordID = ScoreboardRecordIdentity.next(prefix: GameType.guandan.canonicalScoreboardIdentifier)
        pendingEditWrapSide = nil
        showGameOverDialog = false
    }

    private func finishMatch() {
        send(.finish)
    }

    private func applyEdit(left: String, right: String, leftScore: String, rightScore: String) {
        let previous = state
        let redRank = leftScore.uppercased().replacingOccurrences(of: "A1", with: "A")
            .replacingOccurrences(of: "A2", with: "A")
            .replacingOccurrences(of: "A3", with: "A")
        let blueRank = rightScore.uppercased().replacingOccurrences(of: "A1", with: "A")
            .replacingOccurrences(of: "A2", with: "A")
            .replacingOccurrences(of: "A3", with: "A")
        let result = reducer.reduce(
            state: state,
            intent: .adminCorrect(redName: left, blueName: right, redRank: redRank, blueRank: blueRank),
            at: Int64(Date().timeIntervalSince1970 * 1_000)
        )
        guard result.accepted, result.state != previous else { return }
        history.append(previous)
        state = result.state
        actionCount += 1
        appendSnapshot("adminCorrect")
        showGameOverDialog = false
    }

    private func saveRecord() {
        guard actionCount > 0 || state.phase != .notStarted else { return }
        let end = Date()
        let winnerName: String? = {
            guard let winner = state.finalWinner else { return nil }
            return winner == .red ? state.redTeam.name : state.blueTeam.name
        }()
        let snapshotData: Data
        do {
            snapshotData = try JSONEncoder().encode(state)
        } catch {
            ScoreboardPersistenceFailureReporter.report(error, context: "Failed to encode guandan record \(recordID)")
            return
        }
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
            status: .finished
        )
        do {
            try ScoreboardLifecyclePersistence.save(record, finished: finished)
        } catch {
            ScoreboardPersistenceFailureReporter.report(error, context: "Failed to save guandan record \(recordID)")
        }
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
