import ScoreCore
import SwiftUI

struct GuandanScoreboardView: View {
    var initialSetup: SportsSetupResult? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var state: GuandanMatchState
    @State private var history: [GuandanMatchState] = []
    @State private var recordSaved = false
    @State private var gameStartAt: Date?

    private let reducer = GuandanSessionReducer()

    init(
        initialSetup: SportsSetupResult? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        onNavigationBack: (() -> Void)? = nil
    ) {
        self.initialSetup = initialSetup
        self.onSetupConsumed = onSetupConsumed
        self.onNavigationBack = onNavigationBack
        let red = initialSetup?.team1Name.isEmpty == false
            ? initialSetup!.team1Name
            : NSLocalizedString("red_team", value: "红队", comment: "")
        let blue = initialSetup?.team2Name.isEmpty == false
            ? initialSetup!.team2Name
            : NSLocalizedString("blue_team", value: "蓝队", comment: "")
        _state = State(initialValue: GuandanMatchState.initial(redName: red, blueName: blue))
    }

    var body: some View {
        ZStack {
            SpecializedScoreboardScaffold(
                gameType: .guandan,
                leftName: state.redTeam.name,
                rightName: state.blueTeam.name,
                leftScore: state.redTeam.currentRank,
                rightScore: state.blueTeam.currentRank,
                leftDetail: leftDetail,
                rightDetail: rightDetail,
                finished: state.phase == .finished,
                onLeftTap: { handleSideTap(.red) },
                onRightTap: { handleSideTap(.blue) },
                onUndo: undo,
                onExchange: nil,
                onBack: {
                    saveRecordIfNeeded()
                    onNavigationBack?()
                    dismiss()
                },
                bottomBar: state.phase == .roundResult ? { AnyView(stepButtonsBar) } : nil,
                topCenter: {
                    AnyView(statusPill)
                },
                center: {
                    EmptyView()
                }
            )

            if state.phase == .finished, let winner = state.finalWinner {
                GameFinishedOverlay(winnerName: winner == .red ? state.redTeam.name : state.blueTeam.name)
            }
        }
        .onAppear {
            if state.phase == .notStarted {
                send(.startMatch)
                gameStartAt = Date()
            }
            onSetupConsumed?()
        }
        .onDisappear {
            saveRecordIfNeeded()
        }
    }

    private var leftDetail: String? {
        guard state.isInAStage, state.aStageTeam == .red else { return nil }
        let fails = state.redAFailCount
        if state.aStageMode == .tripleA, fails > 0 {
            return String(format: NSLocalizedString("guandan_a_fail_format", value: "闯A失败 %d/3", comment: ""), fails)
        }
        return NSLocalizedString("guandan_a_stage", value: "闯A中", comment: "")
    }

    private var rightDetail: String? {
        guard state.isInAStage, state.aStageTeam == .blue else { return nil }
        let fails = state.blueAFailCount
        if state.aStageMode == .tripleA, fails > 0 {
            return String(format: NSLocalizedString("guandan_a_fail_format", value: "闯A失败 %d/3", comment: ""), fails)
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
        VibrationManager.shared.vibrateMedium()
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        state = previous
    }

    private func saveRecordIfNeeded() {
        guard !recordSaved, let start = gameStartAt else { return }
        let end = Date()
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else { return }
        let winnerName: String? = {
            guard let winner = state.finalWinner else { return nil }
            return winner == .red ? state.redTeam.name : state.blueTeam.name
        }()
        let record = ScoreboardRecord(
            id: "guandan_\(Int(start.timeIntervalSince1970))_\(Int(end.timeIntervalSince1970))",
            gameType: .guandan,
            startTime: start,
            endTime: end,
            duration: duration,
            team1Name: state.redTeam.name,
            team2Name: state.blueTeam.name,
            team1FinalScore: GuandanMatchState.rankDisplayScore(state.redTeam.currentRank),
            team2FinalScore: GuandanMatchState.rankDisplayScore(state.blueTeam.currentRank),
            winner: winnerName,
            totalScoreChanges: history.count,
            status: state.phase == .finished ? .finished : .draft
        )
        try? ScoreboardRecordManager.shared.saveScoreboardRecord(record)
        recordSaved = true
    }
}

#Preview {
    GuandanScoreboardView()
}
