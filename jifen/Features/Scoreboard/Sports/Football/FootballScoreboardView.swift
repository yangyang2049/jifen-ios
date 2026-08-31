//
//  FootballScoreboardView.swift
//  jifen
//
//  Football scoreboard view
//

import ScoreCore
import SwiftUI
import UIKit
import Combine

struct FootballScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase
    var onNavigationBack: (() -> Void)? = nil
    var initialSetup: SportsSetupResult? = nil
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var isFiveAside = false
    @State private var controller: FootballScoreboardController
    @State private var viewModel: FootballViewModel
    @State private var showGameOverDialog: Bool = false
    @State private var showFinishedRecordDetail = false
    @State private var recordID: String
    @State private var clockTick = Date()
    @State private var showClockPrompt = false
    @State private var didApplyInitialSetup = false
    @State private var clockPulseScale: CGFloat = 1

    init(
        onNavigationBack: (() -> Void)? = nil,
        initialSetup: SportsSetupResult? = nil,
        initialResumeSessionId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        isFiveAside: Bool = false
    ) {
        self.onNavigationBack = onNavigationBack
        self.initialSetup = initialSetup
        self.initialResumeSessionId = initialResumeSessionId
        self.onSetupConsumed = onSetupConsumed
        self.isFiveAside = isFiveAside
        let controller = FootballScoreboardController(
            gameType: isFiveAside ? .football5v5 : .football
        )
        _controller = State(initialValue: controller)
        _viewModel = State(initialValue: FootballViewModel(
            controller: controller,
            gameType: isFiveAside ? .football5v5 : .football,
            halfLengthSeconds: initialSetup?.footballHalfLengthSeconds ?? (isFiveAside ? 20 * 60 : 45 * 60)
        ))
        _recordID = State(initialValue: ScoreboardRecordIdentity.initial(
            prefix: (isFiveAside ? GameType.football5v5 : GameType.football).canonicalScoreboardIdentifier,
            resuming: initialResumeSessionId
        ))
    }

    var body: some View {
        ZStack {
        ScoreboardTemplate(
            config: TemplateConfig(
                gameType: isFiveAside ? .football5v5 : .football,
                controller: controller,
                viewModel: viewModel,
                scoreFontSize: 120,
                nameType: ScoreboardCommonNamePolicy.nameType(for: .football),
                showSettleMatch: true,
                externalStateEnricher: { compact in
                    var value = ScoreboardDisplayState.enriched(
                        compact: compact,
                        layoutKind: .twoSide,
                        sportState: [
                            "clockStage": .integer(viewModel.clockStage),
                            "clockStageTitle": .string(clockStageTitle)
                        ],
                        clock: ScoreboardDisplayClock(
                            elapsedMilliseconds: Int64(viewModel.clockElapsedSeconds * 1_000),
                            isRunning: viewModel.clockIsRunning,
                            anchorWallClockMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
                            label: clockStageTitle
                        )
                    )
                    value.appearance = .init(snapshot: .current(
                        styleID: ScoreboardStyleID(gameType: isFiveAside ? .football5v5 : .football)
                    ))
                    return value
                }
            ),
            onBack: {
                if let onNavigationBack = onNavigationBack {
                    onNavigationBack()
                } else {
                    dismiss()
                }
                }
            )

            footballClockOverlay

            if showGameOverDialog {
                GameOverDialog(
                    winnerName: viewModel.getWinnerName(),
                    gameType: isFiveAside ? .football5v5 : .football,
                    leftName: viewModel.leftTeam.name,
                    rightName: viewModel.rightTeam.name,
                    leftScore: viewModel.leftTeam.score,
                    rightScore: viewModel.rightTeam.score,
                    onNewGame: {
                        startNewMatch()
                    },
                    onRecords: {
                        viewModel.saveGameRecordInRealTime(
                            recordID: recordID,
                            isGameFinished: viewModel.gameFinished
                        )
                        showFinishedRecordDetail = true
                    },
                    onShare: {
                        ScoreboardShareSupport.present(
                            text: "\(viewModel.leftTeam.name) \(viewModel.leftTeam.score) - \(viewModel.rightTeam.score) \(viewModel.rightTeam.name)"
                        )
                    },
                    onExit: {
                        viewModel.saveGameRecordInRealTime(
                            recordID: recordID,
                            isGameFinished: viewModel.gameFinished
                        )
                        if let onNavigationBack {
                            onNavigationBack()
                        } else {
                            dismiss()
                        }
                    }
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showGameOverDialog)
        .fullScreenCover(isPresented: $showFinishedRecordDetail) {
            NavigationStack {
                ScoreboardRecordDetailPage(recordId: recordID)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            ModalCloseButton { showFinishedRecordDetail = false }
                        }
                    }
            }
        }
        .navigationTitle(isFiveAside ? GameType.football5v5.displayName : NSLocalizedString("game_football", comment: "Football"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .confirmationDialog(
            clockPromptTitle,
            isPresented: $showClockPrompt,
            titleVisibility: .visible
        ) {
            if canAdvanceClock {
                Button(clockAdvanceLabel) { _ = viewModel.advanceClockStage() }
            }
            if shouldOfferOvertime {
                Button(NSLocalizedString("football_enter_overtime", value: "进入加时", comment: "")) {
                    _ = viewModel.advanceClockStage()
                }
            }
            Button(NSLocalizedString("finish", value: "结束比赛", comment: ""), role: .destructive) {
                viewModel.endGame()
            }
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(clockPromptMessage)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            clockTick = now
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
            if viewModel.checkClockExpiry() {
                showClockPrompt = true
            }
        }
        .onChange(of: viewModel.clockRevision) { _, _ in
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onAppear {
            viewModel.controller = controller
            if let setup = initialSetup, !didApplyInitialSetup {
                viewModel.leftTeam.name = setup.team1Name.isEmpty
                    ? NSLocalizedString("team_home", comment: "")
                    : setup.team1Name
                viewModel.rightTeam.name = setup.team2Name.isEmpty
                    ? NSLocalizedString("team_away", comment: "")
                    : setup.team2Name
                viewModel.resetClock(halfLengthSeconds: setup.footballHalfLengthSeconds)
                didApplyInitialSetup = true
                onSetupConsumed?()
            }
            restoreResumeIfNeeded()
            // Hide tab bar
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let tabBarController = window.rootViewController?.findTabBarController() {
                tabBarController.tabBar.isHidden = true
            }
        }
        .onChange(of: viewModel.gameFinished) { _, newValue in
            if newValue {
                showGameOverDialog = true
                viewModel.saveGameRecordInRealTime(recordID: recordID, isGameFinished: true)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                viewModel.saveGameRecordInRealTime(
                    recordID: recordID,
                    isGameFinished: viewModel.gameFinished
                )
            }
        }
        .onDisappear {
            // Save record when leaving (for incomplete games)
            #if DEBUG
            print("[FootballScoreboardView] 📤 View disappearing, saving record")
            #endif
            viewModel.saveGameRecordInRealTime(
                recordID: recordID,
                isGameFinished: viewModel.gameFinished
            )

            // Show tab bar when leaving
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let tabBarController = window.rootViewController?.findTabBarController() {
                tabBarController.tabBar.isHidden = false
            }
        }
    }

    private func startNewMatch() {
        viewModel.saveGameRecordInRealTime(recordID: recordID, isGameFinished: true)

        let freshState = viewModel.makeFreshMatchState()
        controller.beginNewMatch()
        recordID = ScoreboardRecordIdentity.next(prefix: (isFiveAside ? GameType.football5v5 : GameType.football).canonicalScoreboardIdentifier)
        viewModel.restoreSession(state: freshState, history: [])
        viewModel.resetClock()
        showGameOverDialog = false
    }

    private func restoreResumeIfNeeded() {
        guard let recordId = initialResumeSessionId,
              let record = ManualResumeSessionStore.load(recordID: recordId) else {
            return
        }

        controller.gameStartTime = record.startTime
        controller.gameActions = record.actions
        controller.gameRecordSaved = false

        if let data = record.stateSnapshot,
           let resumeState = try? JSONDecoder().decode(FootballResumeStateV2.self, from: data) {
            controller.gameActions = resumeState.lineScore.intentTimeline
            viewModel.restoreFootballSession(resumeState)
            return
        } else if let data = record.stateSnapshot,
                  let resumeState = try? JSONDecoder().decode(LineScoreResumeState.self, from: data) {
            controller.gameActions = resumeState.intentTimeline
            viewModel.restoreLegacyFootballSession(resumeState)
            return
        }

        viewModel.leftTeam.name = record.team1Name
        viewModel.rightTeam.name = record.team2Name
        viewModel.leftTeam.score = record.team1FinalScore
        viewModel.rightTeam.score = record.team2FinalScore
        viewModel.restoreLegacyFootballSession()
    }

    /// 对齐安卓 FootballClockPanel：时钟胶囊固定在计分板顶部正中心（TopCenter + 72dp 边距）。
    private var footballClockOverlay: some View {
        VStack {
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                footballClockCapsule
                if viewModel.allowsStoppageTime {
                    stoppageMenu
                }
                Spacer(minLength: 0)
            }
            Spacer()
        }
        .padding(.top, 12)
        .padding(.horizontal, 72)
        .allowsHitTesting(!showGameOverDialog)
    }

    /// 1:1 复刻安卓 CompactClockCapsule：阶段徽标（1H/2H/1T/2T）+ mm:ss + 补时 + 内联暂停图标，
    /// 黑色 42% 圆角底（AppRadius.sm = 10），未运行且允许手动暂停时做脉冲呼吸动画。
    private var footballClockCapsule: some View {
        let shouldPulse = viewModel.allowsManualClockPause
            && !viewModel.clockIsRunning
            && !viewModel.clockPeriodCompleted
        return HStack(spacing: 10) {
            Text(clockStageBadge)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(clockStageAccent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(viewModel.formattedClock())
                .font(.system(size: 22, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(.white)

            if !isFiveAside, viewModel.clockStoppageElapsedSeconds > 0 {
                Text(viewModel.formattedStoppageClock())
                    .font(.system(size: 16, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: "FFD166"))
            }

            if viewModel.allowsManualClockPause {
                Image(systemName: viewModel.clockIsRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        // 对齐安卓 resolveBasketballClockPulseScale：900ms 半周期往复，最大放大 1.12，smoothstep≈easeInOut。
        .scaleEffect(clockPulseScale)
        .animation(
            shouldPulse ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .easeInOut(duration: 0.2),
            value: clockPulseScale
        )
        .onChange(of: shouldPulse) { _, pulsing in
            clockPulseScale = pulsing ? 1.12 : 1
        }
        .onAppear {
            clockPulseScale = shouldPulse ? 1.12 : 1
        }
        .onTapGesture {
            if viewModel.allowsManualClockPause {
                viewModel.toggleClock()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(clockStageTitle) \(viewModel.formattedClock())")
        .accessibilityAddTraits(viewModel.allowsManualClockPause ? [.isButton] : [])
        .accessibilityIdentifier("football_timer_toggle")
    }

    /// 11 人制补时加减菜单（iOS 既有功能），样式与时钟胶囊统一的深色圆角底。
    private var stoppageMenu: some View {
        Menu {
            Button("+15 \(NSLocalizedString("seconds_short", value: "秒", comment: ""))") {
                viewModel.addStoppage(15)
            }
            Button("+30 \(NSLocalizedString("seconds_short", value: "秒", comment: ""))") {
                viewModel.addStoppage(30)
            }
            Button("+1 \(NSLocalizedString("minute", value: "分钟", comment: ""))") {
                viewModel.addStoppage(60)
            }
            Button("+1 \(NSLocalizedString("minute", value: "分钟", comment: "")) 30 \(NSLocalizedString("seconds_short", value: "秒", comment: ""))") {
                viewModel.addStoppage(90)
            }
            if viewModel.canUndoLastStoppage {
                Button(NSLocalizedString("football_undo_stoppage", value: "撤销最近一次补时", comment: "")) {
                    viewModel.undoLastStoppage()
                }
            }
        } label: {
            Image(systemName: "plus.forwardslash.minus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 38, height: 38)
                .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .accessibilityIdentifier("football_stoppage_menu")
    }

    /// 对齐安卓 CompactClockCapsule 的阶段徽标与强调色。
    private var clockStageBadge: String {
        switch viewModel.clockStage {
        case 1: return "1H"
        case 2: return "2H"
        case 3: return "1T"
        default: return "2T"
        }
    }

    private var clockStageAccent: Color {
        switch viewModel.clockStage {
        case 1: return Color(hex: "22C55E")
        case 2: return Color(hex: "38BDF8")
        case 3: return Color(hex: "F59E0B")
        default: return Color(hex: "F97316")
        }
    }

    private var clockStageTitle: String {
        switch viewModel.clockStage {
        case 1: return NSLocalizedString("football_first_half", value: "上半场", comment: "")
        case 2: return NSLocalizedString("football_second_half", value: "下半场", comment: "")
        case 3: return NSLocalizedString("football_extra_time_first", value: "加时上半场", comment: "")
        default: return NSLocalizedString("football_extra_time_second", value: "加时下半场", comment: "")
        }
    }

    private var clockPromptTitle: String {
        switch viewModel.clockStage {
        case 1:
            return NSLocalizedString("football_half_time", value: "中场休息", comment: "")
        case 2:
            return NSLocalizedString("football_full_time", value: "常规时间结束", comment: "")
        case 3:
            return NSLocalizedString("football_extra_time_break", value: "加时中场休息", comment: "")
        default:
            return NSLocalizedString("football_extra_time_finished", value: "加时赛结束", comment: "")
        }
    }

    private var clockPromptMessage: String {
        if shouldOfferOvertime {
            return NSLocalizedString("football_overtime_prompt", value: "常规时间打平，是否进入加时？", comment: "")
        }
        if canAdvanceClock {
            return NSLocalizedString("football_continue_prompt", value: "继续比赛？", comment: "")
        }
        return NSLocalizedString("football_finish_prompt", value: "比赛时间已结束。", comment: "")
    }

    private var canAdvanceClock: Bool {
        if isFiveAside { return viewModel.clockStage == 1 }
        return viewModel.clockStage == 1 || viewModel.clockStage == 3
    }

    private var shouldOfferOvertime: Bool {
        !isFiveAside && viewModel.clockStage == 2 && viewModel.leftTeam.score == viewModel.rightTeam.score
    }

    private var clockAdvanceLabel: String {
        viewModel.clockStage == 1
            ? NSLocalizedString("football_start_second_half", value: "开始下半场", comment: "")
            : NSLocalizedString("football_start_next_period", value: "进入下一阶段", comment: "")
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct FootballScoreboardView_Previews: PreviewProvider {
    static var previews: some View {
        FootballScoreboardView()
    }
}
