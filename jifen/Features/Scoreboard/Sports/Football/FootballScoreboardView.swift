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
    @State private var showPostRegulationDialog = false
    @State private var showSwitchHalfConfirm = false
    @State private var showStoppageSettings = false
    @State private var lastOutcomeSignature: String? = nil
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
                contentOverlayProvider: { _, _ in AnyView(footballClockOverlay) },
                showSettleMatch: true,
                extraMenuItemsProvider: {
                    // 对齐安卓 S1DualSideScoreRouteScreen 的足球菜单项。
                    var items: [ScoreboardMenuItem] = []
                    if viewModel.allowsStoppageTime {
                        items.append(ScoreboardMenuItem(
                            title: NSLocalizedString("football_injury_title", value: "伤停补时", comment: ""),
                            action: "footballInjury", group: .match,
                            icon: "clock.badge.plus", placeAtEnd: true
                        ))
                    }
                    if firstHalfEnded {
                        items.append(ScoreboardMenuItem(
                            title: NSLocalizedString("football_switch_half", value: "进入下半场", comment: ""),
                            action: "footballSwitchHalf",
                            group: .tools
                        ))
                    }
                    if regulationEndedTied {
                        items.append(ScoreboardMenuItem(
                            title: NSLocalizedString("football_post_regulation_action", value: "赛后处理", comment: ""),
                            action: "footballPostRegulation",
                            group: .match,
                            customText: "ET",
                            sortOrder: 10,
                            placeAtEnd: true
                        ))
                    }
                    return items
                },
                onMenuAction: { action in
                    switch action {
                    case "footballInjury":
                        showStoppageSettings = true
                    case "footballSwitchHalf":
                        _ = viewModel.advanceClockStage()
                    case "footballPostRegulation":
                        showPostRegulationDialog = true
                    default:
                        break
                    }
                },
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
                            label: clockStageTitle,
                            footballHalf: viewModel.clockStage,
                            footballHalfLengthMs: Int64(viewModel.clockSession.currentPeriodLengthSeconds) * 1_000,
                            footballInjuryTargetMs: Int64(viewModel.clockSession.currentStoppageSeconds) * 1_000
                        )
                    )
                    let multipliers = value.appearance.fontSizeMultipliers
                    value.appearance = .init(snapshot: .current(
                        styleID: ScoreboardStyleID(gameType: isFiveAside ? .football5v5 : .football)
                    ))
                    value.appearance.fontSizeMultipliers = multipliers
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

            if showPostRegulationDialog {
                postRegulationDialog
            }

            if showStoppageSettings {
                stoppageSettingsPanel
            }

            if showSwitchHalfConfirm {
                switchHalfConfirmDialog
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showGameOverDialog)
        .animation(.easeInOut(duration: 0.2), value: showPostRegulationDialog)
        .animation(.easeInOut(duration: 0.2), value: showSwitchHalfConfirm)
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
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            // 先处理时钟到期，再统一发布一次快照，确保广播的是到期后的最新状态。
            _ = viewModel.checkClockExpiry()
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
            refreshFootballOutcomePrompt()
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
            refreshFootballOutcomePrompt()
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

    /// 对齐安卓 FootballClockPanel：上半场结束/加时上半场结束/常规时间平局时用持久决策卡片替换时钟胶囊，
    /// 其余情况显示时钟胶囊（整半场跑满时追加红色完成提示）。
    private var footballClockOverlay: some View {
        VStack {
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                if firstHalfEnded {
                    footballBreakCard(
                        title: NSLocalizedString("football_first_half_over", value: "上半场结束", comment: ""),
                        titleColor: Color(hex: "FFD9D9"),
                        background: Color(hex: "EF4444").opacity(0.08),
                        buttonTitle: NSLocalizedString("football_switch_half", value: "进入下半场", comment: "")
                    ) {
                        showSwitchHalfConfirm = true
                    }
                } else if extraTimeFirstHalfEnded {
                    footballBreakCard(
                        title: NSLocalizedString("football_extra_time_first_over", value: "加时赛上半场结束", comment: ""),
                        titleColor: Color(hex: "FFE4B5"),
                        background: Color(hex: "F59E0B").opacity(0.12),
                        buttonTitle: NSLocalizedString("football_switch_extra_time_half", value: "进入加时赛下半场", comment: "")
                    ) {
                        _ = viewModel.advanceClockStage()
                    }
                } else if regulationEndedTied {
                    footballBreakCard(
                        title: NSLocalizedString("football_enter_extra_time_title", value: "常规时间结束", comment: ""),
                        titleColor: Color(hex: "DDF5FF"),
                        background: Color(hex: "38BDF8").opacity(0.12),
                        buttonTitle: NSLocalizedString("football_post_regulation_action", value: "赛后处理", comment: "")
                    ) {
                        showPostRegulationDialog = true
                    }
                } else {
                    footballClockCapsule
                }
                Spacer(minLength: 0)
            }
            if completionHintVisible {
                Text(viewModel.clockStage == 4
                    ? NSLocalizedString("football_extra_time_finished", value: "加时赛结束", comment: "")
                    : NSLocalizedString("football_injury_finished", value: "补时结束", comment: ""))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "FF6B6B"))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            Spacer()
        }
        .padding(.top, 12)
        .padding(.horizontal, 72)
        .allowsHitTesting(!showGameOverDialog)
    }

    /// 对齐安卓 HalftimeBreakCard / ExtraTimeBreakCard / PostRegulationDecisionCard：
    /// 14dp 圆角、横向 18 纵向 12 内边距、纵向 8 间距，14pt heavy 标题 + 主色胶囊按钮。
    private func footballBreakCard(
        title: String,
        titleColor: Color,
        background: Color,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .heavy))
                .foregroundColor(titleColor)
            Button(action: action) {
                Text(buttonTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 36)
                    .background(Capsule().fill(Theme.primary))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(background))
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

    // MARK: - 对齐安卓 FootballClockPanel 的阶段判定

    private var firstHalfEnded: Bool {
        viewModel.clockStage == 1 && viewModel.clockPeriodCompleted
    }

    private var extraTimeFirstHalfEnded: Bool {
        viewModel.clockStage == 3 && viewModel.clockPeriodCompleted
    }

    /// 常规时间（下半场）跑满且打平：需要用户决策进入加时还是以平局结束。
    private var regulationEndedTied: Bool {
        !isFiveAside
            && viewModel.clockStage == 2
            && viewModel.clockPeriodCompleted
            && viewModel.leftTeam.score == viewModel.rightTeam.score
    }

    /// 胶囊分支下整半场跑满的红色提示（上半场/加时上半场由决策卡片接管）。
    private var completionHintVisible: Bool {
        viewModel.clockPeriodCompleted && !firstHalfEnded && !extraTimeFirstHalfEnded
    }

    /// 对齐安卓 S1DualSideScoreRouteScreen 的 outcome 弹窗签名触发：
    /// 进入“常规时间打平待决策”状态时自动弹出；比分变化（重新打平）后再次弹出。
    private func refreshFootballOutcomePrompt() {
        guard !showGameOverDialog else { return }
        guard regulationEndedTied else {
            if showPostRegulationDialog {
                showPostRegulationDialog = false
            }
            lastOutcomeSignature = nil
            return
        }
        let signature = "\(viewModel.clockStage):\(viewModel.leftTeam.score):\(viewModel.rightTeam.score)"
        if lastOutcomeSignature != signature {
            lastOutcomeSignature = signature
            showPostRegulationDialog = true
        }
    }

    // MARK: - 决策弹窗（复刻安卓 AlertDialog 文案 + 项目自定义深卡样式）

    private var postRegulationDialog: some View {
        CustomConfirmDialog(
            title: NSLocalizedString("football_enter_extra_time_title", value: "常规时间结束", comment: ""),
            message: String(
                format: NSLocalizedString(
                    "football_enter_extra_time_message",
                    value: "常规时间及补时结束，比分为 %1$d–%2$d。是否进入上下半场各 15 分钟的加时赛？",
                    comment: ""
                ),
                viewModel.leftTeam.score,
                viewModel.rightTeam.score
            ),
            confirmText: NSLocalizedString("football_enter_extra_time", value: "进入加时赛", comment: ""),
            cancelText: NSLocalizedString("football_end_as_draw", value: "以平局结束", comment: ""),
            confirmColor: Theme.primary,
            onConfirm: {
                if viewModel.advanceClockStage() {
                    showPostRegulationDialog = false
                }
            },
            onCancel: {
                showPostRegulationDialog = false
                viewModel.endGame()
            },
            onDismiss: {
                showPostRegulationDialog = false
            }
        )
    }

    private var stoppageSettingsPanel: some View {
        ZStack {
            Theme.scoreboardDialogScrim.ignoresSafeArea()
                .onTapGesture { showStoppageSettings = false }
            VStack(spacing: 20) {
                Text(NSLocalizedString("football_injury_title", value: "伤停补时", comment: ""))
                    .font(.headline)
                Text("+\(viewModel.clockSession.currentStoppageSeconds / 60):\(String(format: "%02d", viewModel.clockSession.currentStoppageSeconds % 60))")
                    .font(.system(size: 32, weight: .bold)).monospacedDigit()
                HStack(spacing: 12) {
                    ForEach([15, 30, 60, 90], id: \.self) { seconds in
                        Button("+\(seconds) \(NSLocalizedString("seconds_short", value: "秒", comment: ""))") {
                            viewModel.addStoppage(seconds)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("football_stoppage_add_\(seconds)")
                    }
                }
                HStack {
                    Button(NSLocalizedString("football_undo_stoppage", value: "撤销最近一次补时", comment: "")) {
                        viewModel.undoLastStoppage()
                    }.disabled(!viewModel.canUndoLastStoppage)
                        .accessibilityIdentifier("football_stoppage_undo")
                    Spacer()
                    Button(NSLocalizedString("done", value: "完成", comment: "")) {
                        showStoppageSettings = false
                    }
                }
            }
            .padding(24).frame(maxWidth: 440)
            .foregroundStyle(.white)
            .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("football_stoppage_settings")
        }
    }

    private var switchHalfConfirmDialog: some View {
        CustomConfirmDialog(
            title: NSLocalizedString("football_switch_half_title", value: "进入下半场？", comment: ""),
            message: NSLocalizedString("football_switch_half_message", value: "上半场将暂停，且不能切回。", comment: ""),
            confirmText: NSLocalizedString("confirm", value: "确认", comment: ""),
            cancelText: NSLocalizedString("cancel", value: "取消", comment: ""),
            confirmColor: Theme.primary,
            onConfirm: {
                showSwitchHalfConfirm = false
                _ = viewModel.advanceClockStage()
            },
            onDismiss: {
                showSwitchHalfConfirm = false
            }
        )
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
