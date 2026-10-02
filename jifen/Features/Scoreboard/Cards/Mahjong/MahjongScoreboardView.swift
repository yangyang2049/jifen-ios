//
//  MahjongScoreboardView.swift
//  jifen
//
//  麻将记分板（4 家）：竖屏 2×2、横屏 1×4；顶部状态胶囊 + 溢出菜单，底部
//  撤销/流局/＋记本手/调整；结算面板用 core `MahjongReducer` 实时预览。
//  结构对齐安卓 `MahjongScoreScreen.kt`，视觉沿用 iOS 既有牌类计分板令牌。
//

import RecordCore
import ScoreCore
import SwiftUI
import UIKit

// MARK: - 展示辅助

private let mahjongPalette: [Color] = [
    Color(hex: "EF4444"),
    Color(hex: "3B82F6"),
    Color(hex: "22C55E"),
    Color(hex: "F59E0B")
]

private let mahjongWindCodes = ["east", "south", "west", "north"]

/// 顶/底栏悬浮控件底色：沿用 iOS 既有牌类计分板的半透明黑（Doudizhu 同款），
/// 不引入新的视觉语言。
private let mahjongFloatingControl = Color.black.opacity(0.25)

/// 麻将四座对应 V2 样式的 player_0…3 槽位（跨端与安卓自定义面板同名）。
private func mahjongSlotKey(_ index: Int) -> ScoreboardStyleSlotKeyV2 {
    switch index {
    case 0: return .player0
    case 1: return .player1
    case 2: return .player2
    default: return .player3
    }
}

/// 用户是否给该座位配过背景色；未配置时回落 iOS 麻将色板。
private func mahjongPanelHex(index: Int, appearance: ScoreboardAppearanceSnapshot) -> String {
    let slot = mahjongSlotKey(index)
    if appearance.styleProfileV2.panels?.contains(where: { $0.slotKey == slot }) == true {
        return appearance.styleProfileV2.slotBackgroundHex(slot)
    }
    if appearance.theme == .electronic || appearance.theme == .retro { return "000000" }
    return ["EF4444", "3B82F6", "22C55E", "F59E0B"][index % 4]
}

private func mahjongPanelColor(index: Int, appearance: ScoreboardAppearanceSnapshot) -> Color {
    Color(hex: mahjongPanelHex(index: index, appearance: appearance))
}

enum MahjongPresentation {
    /// 安卓 `mahjongSeatWindLabel`：座位风单字标签。
    static func seatWindLabel(_ code: String) -> String {
        switch code {
        case "east": return NSLocalizedString("mahjong_seat_east", value: "东", comment: "")
        case "south": return NSLocalizedString("mahjong_seat_south", value: "南", comment: "")
        case "west": return NSLocalizedString("mahjong_seat_west", value: "西", comment: "")
        default: return NSLocalizedString("mahjong_seat_north", value: "北", comment: "")
        }
    }

    static func seatWindLabel(dealerIndex: Int, playerIndex: Int) -> String {
        let winds = mahjongSeatWindsForDealer(dealerIndex: dealerIndex)
        return seatWindLabel(winds.indices.contains(playerIndex) ? winds[playerIndex] : "north")
    }

    /// 顶部状态胶囊里的模板短名（安卓「通用/血战」）。
    static func rulesetShortLabel(_ ruleset: MahjongRuleset) -> String {
        ruleset == .sichuanBloodBattle
            ? NSLocalizedString("mahjong_ruleset_short_blood", value: "血战", comment: "")
            : NSLocalizedString("mahjong_ruleset_short_generic", value: "通用", comment: "")
    }

    static func actionLabel(_ action: MahjongActionType) -> String {
        switch action {
        case .selfDraw: return NSLocalizedString("record_mahjong_self_draw", value: "自摸", comment: "")
        case .discardWin: return NSLocalizedString("record_mahjong_discard_win", value: "点炮", comment: "")
        case .kong: return NSLocalizedString("record_mahjong_kong", value: "杠", comment: "")
        case .draw: return NSLocalizedString("record_mahjong_draw", value: "流局", comment: "")
        case .transfer: return NSLocalizedString("record_mahjong_transfer", value: "转分", comment: "")
        case .notenPenalty: return NSLocalizedString("record_mahjong_noten", value: "查叫", comment: "")
        case .flowerPigPenalty: return NSLocalizedString("record_mahjong_flower_pig", value: "花猪", comment: "")
        case .kongRefund: return NSLocalizedString("record_mahjong_kong_refund", value: "退杠分", comment: "")
        case .adjustment: return NSLocalizedString("record_mahjong_adjustment", value: "调分", comment: "")
        }
    }

    static func kongKindLabel(_ kind: MahjongKongKind, ruleset: MahjongRuleset) -> String {
        switch kind {
        case .exposed:
            return ruleset == .sichuanBloodBattle
                ? NSLocalizedString("mahjong_kong_direct", value: "直杠", comment: "")
                : NSLocalizedString("mahjong_kong_exposed", value: "明杠", comment: "")
        case .added: return NSLocalizedString("mahjong_kong_added", value: "补杠", comment: "")
        case .concealed: return NSLocalizedString("mahjong_kong_concealed", value: "暗杠", comment: "")
        }
    }

    static func paymentModeLabel(_ mode: MahjongPaymentMode) -> String {
        switch mode {
        case .onePayer: return NSLocalizedString("mahjong_payment_one", value: "一家付", comment: "")
        case .allOpponents: return NSLocalizedString("mahjong_payment_all", value: "三家付", comment: "")
        }
    }

    /// 安卓 `signed`：正数带 +。
    static func signedValue(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    /// 安卓 `mahjongPreviewDeltas`：预览被拒绝时全部按 0 展示。
    static func previewDeltas(accepted: Bool, candidate: [Int]?) -> [Int] {
        guard accepted, let candidate else {
            return [Int](repeating: 0, count: MAHJONG_PLAYER_COUNT)
        }
        var result = [Int](repeating: 0, count: MAHJONG_PLAYER_COUNT)
        for (index, value) in candidate.enumerated() where result.indices.contains(index) {
            result[index] = value
        }
        return result
    }

    /// 安卓 `settlementActionOptions`：动作胶囊顺序与安卓一致。
    static let settlementActionOptions: [MahjongActionType] = [
        .selfDraw, .discardWin, .kong, .transfer, .notenPenalty, .flowerPigPenalty, .draw, .adjustment
    ]

    static let manualActions: Set<MahjongActionType> = [.adjustment, .notenPenalty, .flowerPigPenalty]
}

// MARK: - 主视图

struct MahjongScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scoreboardUsageHintCoordinator) private var usageHintCoordinator

    var initialSetup: SportsSetupResult? = nil
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil

    @State private var store: MahjongScoreboardStore
    @State private var setupResult: MahjongSetupResult
    @State private var recordID: String
    @State private var gameStartTime: Date
    @State private var showSettlement = false
    @State private var settlementInitialAction: MahjongActionType = .selfDraw
    @State private var settlementSaving = false
    @State private var showMenu = false
    @State private var showDisplaySettings = false
    @State private var showGameOverDialog = false
    @State private var showFinishedRecordDetail = false
    @State private var showRoundLimitPrompt = false
    @State private var promptedAtHand = 0
    @State private var toastMessage: String?
    @State private var controlsVisible = true
    @State private var styleEditorEntry = ScoreboardStyleEditorEntry()
    @State private var menuConfirm = ScoreboardMenuConfirmState()
    @State private var appearance = ScoreboardAppearanceSnapshot.current(
        styleID: ScoreboardStyleID(gameType: .mahjong)
    )
    @State private var typographySession = ScoreboardTypographySession(
        styleID: ScoreboardStyleID(gameType: .mahjong)
    )
    @State private var previousIdleTimerDisabled: Bool?

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

        var setup = initialSetup?.mahjongSetup ?? MahjongSetupResult.generic(
            playerNames: (initialSetup?.playerNames ?? [])
        )
        if setup.validationError() != nil {
            setup = .generic()
        }
        var start = Date()
        var id = ScoreboardRecordIdentity.next(prefix: GameType.mahjong.canonicalScoreboardIdentifier)
        var restored: MahjongSessionState?
        var restoredActions: [String] = []

        if let initialResumeSessionId,
           let record = ManualResumeSessionStore.load(recordID: initialResumeSessionId),
           let data = record.stateSnapshot,
           let resume = try? JSONDecoder().decode(MahjongResumeState.self, from: data) {
            setup = resume.session.setup
            restored = resume.session
            restoredActions = resume.intentTimeline.isEmpty ? record.actions : resume.intentTimeline
            start = record.startTime
            id = record.id
        }

        let resolvedSetup = setup
        let initialRecordID = id
        let initialActions = restoredActions
        let initialState = restored
        _setupResult = State(initialValue: resolvedSetup)
        _recordID = State(initialValue: initialRecordID)
        _gameStartTime = State(initialValue: start)
        _store = State(initialValue: MahjongScoreboardStore(
            setup: resolvedSetup,
            restoredState: initialState,
            recordID: initialRecordID,
            restoredActions: initialActions,
            restoredActionCount: initialState?.ledger.count ?? 0
        ))
        _showGameOverDialog = State(initialValue: restored?.finished ?? false)
    }

    private var state: MahjongSessionState { store.state }

    private var roundLabel: String { mahjongRoundLabel(roundOrdinal: state.roundOrdinal) }

    private var statusPillText: String {
        String(
            format: NSLocalizedString(
                "mahjong_status_pill",
                value: "%1$@ · %2$@ · 第%3$@手 · 底%4$@",
                comment: ""
            ),
            MahjongPresentation.rulesetShortLabel(state.setup.ruleset),
            roundLabel,
            "\(state.handNumber)",
            "\(state.setup.baseScore)"
        )
    }

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            ZStack {
                appearance.palette.background.ignoresSafeArea()

                MahjongScoreGrid(
                    state: state,
                    handDeltas: store.currentHandDeltaByPlayer,
                    isLandscape: isLandscape,
                    appearance: appearance,
                    typographySession: typographySession
                )

                if controlsVisible && !showSettlement && !showMenu && !styleEditorEntry.isEditing {
                    topBar
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    bottomBar(isLandscape: isLandscape)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }

                if showSettlement {
                    MahjongSettlementSheet(
                        state: state,
                        handDeltas: store.currentHandDeltaByPlayer,
                        initialAction: settlementInitialAction,
                        saving: settlementSaving,
                        store: store,
                        onDismiss: {
                            guard !settlementSaving else { return }
                            showSettlement = false
                            controlsVisible = true
                        },
                        onSubmit: { settlement in
                            guard !settlementSaving else { return }
                            settlementSaving = true
                            store.submit(settlement) { committed in
                                settlementSaving = false
                                if committed {
                                    showSettlement = false
                                    controlsVisible = true
                                }
                            }
                        }
                    )
                    .zIndex(20)
                }

                if showMenu {
                    MenuDialog(
                        isVisible: true,
                        onClose: {
                            menuConfirm.clear()
                            showMenu = false
                        },
                        onMenuItemClick: handleMenuAction,
                        items: mahjongMenuItems,
                        analyticsGameType: .mahjong
                    )
                }

                if showGameOverDialog {
                    gameOverDialog
                }

                if let message = toastMessage {
                    VStack {
                        Spacer()
                        ToastView(message: message)
                            .padding(.bottom, 24)
                    }
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { controlsVisible = true }
        }
        .ignoresSafeArea(.all)
        .cloudSyncSharingEntryOverlay(respectsSafeArea: true)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("scoreboard_ready_mahjong")
        .onAppear {
            typographySession.reload()
            appearance = .current(styleID: ScoreboardStyleID(gameType: .mahjong))
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            LocalScoreboardSyncCoordinator.shared.registerHost(snapshot: syncSnapshot) { _ in }
            scheduleChromeHide()
        }
        .onDisappear {
            LocalScoreboardSyncCoordinator.shared.unregisterHost()
            saveRecord(finished: state.finished)
            if let previousIdleTimerDisabled {
                UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
            }
        }
        .scoreboardDisplaySettingsOverlay(
            isPresented: $showDisplaySettings,
            session: typographySession,
            metrics: ScoreboardTypographyProfile.multi.adjustableMetrics
        )
        .scoreboardStyleEditorEntry(
            styleEditorEntry,
            typographySession: typographySession,
            onEditingChange: { _ in }
        )
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
        .alert(isPresented: $showRoundLimitPrompt) { roundLimitAlert }
        .onChange(of: state.roundLimitReached) { _, reached in
            guard reached, promptedAtHand != state.handNumber else { return }
            promptedAtHand = state.handNumber
            showRoundLimitPrompt = true
        }
        .onChange(of: store.state) { _, _ in
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
            saveRecord(finished: state.finished)
            if let reason = store.lastRejectionReason {
                toastMessage = reason
                store.clearRejection()
            }
        }
        .onChange(of: preferences.scoreboardRevision) { _, _ in
            appearance = .current(styleID: ScoreboardStyleID(gameType: .mahjong))
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onChange(of: controlsVisible) { _, visible in
            guard visible else { return }
            scheduleChromeHide()
        }
    }

    private var preferences: PreferencesManager { PreferencesManager.shared }

    // MARK: 顶栏 / 底栏

    private var topBar: some View {
        HStack(spacing: 10) {
            floatingCircleButton(
                systemImage: "chevron.left",
                identifier: "mahjong_back"
            ) {
                saveRecord(finished: state.finished)
                performScoreboardExit(onNavigationBack: onNavigationBack, dismiss: dismiss)
            }

            HStack(spacing: 7) {
                if CloudSyncSession.shared.isSharingActive() {
                    Circle()
                        .fill(Theme.primary)
                        .frame(width: 7, height: 7)
                }
                Text(statusPillText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(mahjongFloatingControl))

            floatingCircleButton(
                systemImage: "line.3.horizontal",
                identifier: "mahjong_menu"
            ) {
                showMenu = true
            }
        }
        .padding(.horizontal, Theme.md)
        .padding(.vertical, 14)
    }

    private func bottomBar(isLandscape: Bool) -> some View {
        HStack(spacing: 10) {
            floatingTextButton(
                NSLocalizedString("undo", comment: "Undo"),
                identifier: "mahjong_undo",
                enabled: !state.ledger.isEmpty && !state.finished
            ) {
                store.undoLast()
            }
            floatingTextButton(
                NSLocalizedString("record_mahjong_draw", value: "流局", comment: ""),
                identifier: "mahjong_draw"
            ) {
                settlementInitialAction = .draw
                showSettlement = true
            }
            Button {
                settlementInitialAction = .selfDraw
                showSettlement = true
            } label: {
                Text("＋")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Theme.primary))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mahjong_add_hand")
            floatingTextButton(
                NSLocalizedString("mahjong_adjust", value: "调整", comment: ""),
                identifier: "mahjong_adjust"
            ) {
                settlementInitialAction = .adjustment
                showSettlement = true
            }
        }
        .padding(.horizontal, Theme.md)
        .padding(.vertical, isLandscape ? 10 : 18)
    }

    private func floatingCircleButton(systemImage: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(mahjongFloatingControl))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func floatingTextButton(
        _ title: String,
        identifier: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(enabled ? 1 : 0.4))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(Capsule().fill(mahjongFloatingControl))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
    }

    private func scheduleChromeHide() {
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled, !showSettlement, !showMenu else { return }
            controlsVisible = false
        }
    }

    // MARK: 菜单 / 弹窗

    private var mahjongMenuItems: [ScoreboardMenuItem] {
        ScoreboardMenuItemBuilder.defaultItems(
            showEndGame: true,
            showExchangeSide: false,
            showWhistle: false,
            showScreenshot: true,
            showDisplaySettings: true,
            showSettleMatch: false,
            resetConfirming: menuConfirm.resetConfirming,
            finishConfirming: menuConfirm.finishConfirming,
            extraItems: [
                ScoreboardMenuItem(
                    title: NSLocalizedString("mahjong_menu_restart", value: "沿用设置再开一场", comment: ""),
                    action: "restart",
                    group: .match,
                    icon: "arrow.triangle.2.circlepath",
                    keepDialogOpen: true,
                    confirming: menuConfirm.resetConfirming,
                    enabled: !state.finished
                )
            ]
        ).map { item in
            // 麻将没有「交换座位」，撤销按钮只在有流水且未结束时可用。
            if item.action == "undo" {
                var copy = item
                copy.enabled = !state.ledger.isEmpty && !state.finished
                return copy
            }
            return item
        }
    }

    private func handleMenuAction(_ action: String) {
        menuConfirm.prepare(forMenuAction: action)
        switch action {
        case "undo":
            store.undoLast()
        case "reset":
            if menuConfirm.armOrConfirm(.reset) {
                restartWithSameSetup()
                showMenu = false
                return
            }
            toastMessage = ScoreboardMenuConfirmAction.reset.localizedToast
        case "restart":
            if menuConfirm.armOrConfirm(.reset) {
                restartWithSameSetup()
                showMenu = false
                return
            }
            toastMessage = ScoreboardMenuConfirmAction.reset.localizedToast
        case "endGame", "finish":
            if menuConfirm.armOrConfirm(.finish) {
                finishMatch()
                showMenu = false
                return
            }
            toastMessage = ScoreboardMenuConfirmAction.finish.localizedToast
        case "screenshot":
            // 截图由 MenuDialog 统一实现（先收起菜单再抓当前窗口），这里只关菜单。
            showMenu = false
        case "displaySettings":
            showMenu = false
            if !styleEditorEntry.handleDisplaySettings(
                styleID: typographySession.styleID,
                typographySession: typographySession
            ) {
                showDisplaySettings = true
            }
        case "usageHint":
            showMenu = false
            usageHintCoordinator?.presentFromMenu()
        case "exit":
            showMenu = false
            saveRecord(finished: state.finished)
            performScoreboardExit(onNavigationBack: onNavigationBack, dismiss: dismiss)
        default:
            break
        }
    }

    private var roundLimitAlert: Alert {
        Alert(
            title: Text(NSLocalizedString("mahjong_round_limit_title", value: "已完成设定局程", comment: "")),
            message: Text(String(
                format: NSLocalizedString(
                    "mahjong_round_limit_message",
                    value: "预设的%@已完成。可以结束本场，也可以继续记分。",
                    comment: ""
                ),
                state.setup.matchLength == .eastOnly
                    ? NSLocalizedString("mahjong_match_east", value: "东风圈", comment: "")
                    : NSLocalizedString("mahjong_match_hanchan", value: "半庄", comment: "")
            )),
            primaryButton: .default(
                Text(NSLocalizedString("mahjong_finish_match", value: "结束本场", comment: ""))
            ) {
                finishMatch()
            },
            secondaryButton: .cancel(
                Text(NSLocalizedString("mahjong_continue_scoring", value: "继续记分", comment: ""))
            )
        )
    }

    private var gameOverDialog: some View {
        GameOverDialog(
            winnerName: finishedWinnerName,
            gameType: .mahjong,
            multiNames: state.setup.playerNames,
            multiScores: state.scores,
            winnerIndices: uniqueLeaderIndices,
            onNewGame: {
                startNewMatch()
            },
            onRecords: {
                saveRecord(finished: true)
                showFinishedRecordDetail = true
            },
            onShare: {
                ScoreboardShareSupport.present(text: finalScoreLine)
            },
            onExit: {
                saveRecord(finished: true)
                performScoreboardExit(onNavigationBack: onNavigationBack, dismiss: dismiss)
            }
        )
    }

    private var uniqueLeaderIndices: Set<Int>? {
        guard let best = state.scores.max(), state.scores.filter({ $0 == best }).count == 1,
              let index = state.scores.firstIndex(of: best) else { return nil }
        return [index]
    }

    private var finishedWinnerName: String {
        guard let indices = uniqueLeaderIndices, let index = indices.first,
              state.setup.playerNames.indices.contains(index) else { return "" }
        return state.setup.playerNames[index]
    }

    private var finalScoreLine: String {
        zip(state.setup.playerNames, state.scores)
            .map { "\($0) \($1)" }
            .joined(separator: " · ")
    }

    private func restartWithSameSetup() {
        store.restartWithCurrentSetup()
        promptedAtHand = 0
        showRoundLimitPrompt = false
        showGameOverDialog = false
        showSettlement = false
        saveRecord(finished: false, force: true)
        LocalScoreboardSyncCoordinator.shared.publishSnapshot()
    }

    /// 安卓 `startNewGame`：结算弹窗里再开一场，沿用同一份设置。
    private func startNewMatch() {
        saveRecord(finished: true)
        recordID = ScoreboardRecordIdentity.next(prefix: GameType.mahjong.canonicalScoreboardIdentifier)
        gameStartTime = Date()
        store = MahjongScoreboardStore(setup: setupResult, recordID: recordID)
        promptedAtHand = 0
        showRoundLimitPrompt = false
        showGameOverDialog = false
        showSettlement = false
        saveRecord(finished: false, force: true)
        LocalScoreboardSyncCoordinator.shared.publishSnapshot()
    }

    private func finishMatch() {
        store.finishMatch { accepted in
            guard accepted else { return }
            showRoundLimitPrompt = false
            showGameOverDialog = true
            saveRecord(finished: true)
        }
    }

    // MARK: 记录 / 投屏

    private func saveRecord(finished: Bool, force: Bool = false) {
        let names = state.setup.playerNames
        let playersPayload: [[String: Any]] = names.enumerated().map { index, name in
            ["id": index, "playerId": index, "name": name, "finalScore": state.scores.indices.contains(index) ? state.scores[index] : 0]
        }
        var extraData: [String: AnyCodable] = [
            "type": AnyCodable("mahjong"),
            "playerCount": AnyCodable(MAHJONG_PLAYER_COUNT),
            "players": AnyCodable(playersPayload),
            "mahjongSchemaVersion": AnyCodable(MAHJONG_CONTRACT_VERSION),
            "mahjongSetup": AnyCodable(jsonObject(state.setup)),
            "mahjongLedger": AnyCodable(jsonObject(state.ledger)),
            "mahjongPlayerStats": AnyCodable(jsonObject(mahjongPlayerStats(state: state)))
        ]
        let topScore = state.scores.max() ?? 0
        let topIndexes = state.scores.indices.filter { state.scores[$0] == topScore }
        if topIndexes.count != MAHJONG_PLAYER_COUNT {
            extraData["winnerPlayerIds"] = AnyCodable(topIndexes)
        }
        // 胜者写成跨端稳定的 `player_N` token（ScoreboardWinnerIdentity）；
        // 并列第一不写胜者，与斗地主「多赢家即 nil」一致。
        let winnerToken: String? = topIndexes.count == 1 ? "player_\(topIndexes[0])" : nil

        let resume = MahjongResumeState(
            session: state,
            intentTimeline: store.actions,
            actionCount: store.actionCount
        )
        guard let snapshotData = resume.encoded else { return }

        let record = ScoreboardRecord(
            id: recordID,
            gameType: .mahjong,
            startTime: gameStartTime,
            endTime: finished ? Date() : nil,
            duration: Date().timeIntervalSince(gameStartTime),
            team1Name: names.first ?? GameType.mahjong.displayName,
            team2Name: names.count > 1 ? names[1] : "",
            team1FinalScore: state.scores.first ?? 0,
            team2FinalScore: state.scores.count > 1 ? state.scores[1] : 0,
            winner: finished ? winnerToken : nil,
            actions: store.actions,
            totalScoreChanges: max(store.actionCount, state.ledger.count),
            extraData: extraData,
            projectConfiguration: [
                ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(ScoreCore.GameType.mahjong.rawValue)
            ],
            stateSnapshot: snapshotData,
            status: finished ? .finished : .draft
        )
        guard finished || force || !state.ledger.isEmpty || !store.actions.isEmpty else { return }
        do {
            try ScoreboardLifecyclePersistence.save(record, finished: finished)
            if finished {
                ScoreboardRecordsViewModel.shared.refreshRecords()
            }
        } catch {
            ScoreboardPersistenceFailureReporter.report(
                error,
                context: "Failed to save mahjong record \(recordID)"
            )
        }
    }

    private func syncSnapshot() -> LocalScoreboardDisplayState {
        var players: [ScoreboardDisplayPlayer] = []
        for index in 0..<MAHJONG_PLAYER_COUNT {
            players.append(ScoreboardDisplayPlayer(
                id: "player_\(index)",
                name: state.setup.playerNames.indices.contains(index) ? state.setup.playerNames[index] : "",
                score: state.scores.indices.contains(index) ? state.scores[index] : 0,
                order: index,
                color: "#\(mahjongPanelHex(index: index, appearance: appearance))"
            ))
        }
        let sportState = mahjongDisplaySportState(state: state)

        var compact = LocalScoreboardDisplayState(
            gameID: GameType.mahjong.canonicalScoreboardIdentifier,
            title: "\(roundLabel) · 第\(state.handNumber)手",
            leftName: players.first?.name ?? "",
            rightName: players.count > 1 ? players[1].name : "",
            leftScore: "\(players.first?.score ?? 0)",
            rightScore: "\(players.count > 1 ? players[1].score ?? 0 : 0)",
            themeID: appearance.theme.rawValue,
            fontID: typographySession.effectivePreference.font.rawValue,
            scoreMultiplier: typographySession.effectivePreference.scoreMultiplier,
            nameMultiplier: typographySession.effectivePreference.nameMultiplier,
            secondaryMultiplier: typographySession.effectivePreference.secondaryMultiplier,
            finished: state.finished,
            revision: UInt64(store.actionCount)
        )
        var value = ScoreboardDisplayState.enriched(
            compact: compact,
            layoutKind: .multiGrid,
            players: players,
            sportState: sportState
        )
        value.teams = players.map {
            ScoreboardDisplayTeam(
                id: $0.id,
                name: $0.name,
                score: $0.score ?? 0,
                color: $0.color,
                order: $0.order
            )
        }
        let multipliers = value.appearance.fontSizeMultipliers
        value.appearance = .init(
            snapshot: appearance,
            fontCode: typographySession.effectivePreference.font.rawValue
        )
        value.appearance.fontSizeMultipliers = multipliers
        if state.finished {
            value.result = ScoreboardDisplayResult(
                ended: true,
                winnerID: uniqueLeaderIndices?.first.map { "player_\($0)" } ?? "draw",
                finalScores: Dictionary(uniqueKeysWithValues: players.map {
                    ($0.id, ScoreboardDisplayFinalScore(score: $0.score ?? 0))
                })
            )
        }
        compact.externalState = value
        return compact
    }
}

/// 麻将投屏 sportState：12 个 `mahjong*` 键由 core 的 `MahjongDisplayProjection` 产出
/// （键序即 `mahjongDisplaySportStateKeys`），再补 3 个 `multiGrid*` 通用布局键。
/// 键集合与安卓黄金副本 `mahjong-display-state-v1.json` 逐键一致，列数不写：
/// 显示端按 4 人默认 2 列（2×2）。`jifenTests/ScoreboardDisplayTests.swift` 守住这份契约。
func mahjongDisplaySportState(state: MahjongSessionState) -> [String: ScoreboardDisplayValue] {
    let projection = MahjongDisplayProjection(state: state)
    var values: [String: ScoreboardDisplayValue] = [:]
    for key in mahjongDisplaySportStateKeys {
        guard let value = projection.value(for: key) else { continue }
        switch value {
        case .integer(let number): values[key] = .integer(number)
        case .string(let text): values[key] = .string(text)
        case .strings(let texts): values[key] = .strings(texts)
        case .integers(let numbers): values[key] = .integers(numbers)
        }
    }
    values["multiGridTileGap"] = .integer(2)
    values["multiGridOuterPadding"] = .integer(0)
    values["multiGridLargeScore"] = .boolean(true)
    return values
}

private func jsonObject<T: Encodable>(_ value: T) -> Any {
    guard let data = try? JSONEncoder().encode(value),
          let object = try? JSONSerialization.jsonObject(with: data) else {
        return [String: Any]()
    }
    return object
}

// MARK: - 四家网格

private struct MahjongScoreGrid: View {
    let state: MahjongSessionState
    let handDeltas: [Int]
    let isLandscape: Bool
    let appearance: ScoreboardAppearanceSnapshot
    let typographySession: ScoreboardTypographySession

    var body: some View {
        if isLandscape {
            HStack(spacing: 2) {
                ForEach(0..<MAHJONG_PLAYER_COUNT, id: \.self) { index in
                    panel(index)
                }
            }
        } else {
            VStack(spacing: 2) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<2, id: \.self) { column in
                            panel(row * 2 + column)
                        }
                    }
                }
            }
        }
    }

    private func panel(_ index: Int) -> some View {
        MahjongPlayerPanel(
            state: state,
            index: index,
            handDelta: handDeltas.indices.contains(index) ? handDeltas[index] : 0,
            appearance: appearance,
            typographySession: typographySession
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MahjongPlayerPanel: View {
    let state: MahjongSessionState
    let index: Int
    let handDelta: Int
    let appearance: ScoreboardAppearanceSnapshot
    let typographySession: ScoreboardTypographySession

    private var won: Bool { state.currentHandWinnerIndexes.contains(index) }
    private var isDealer: Bool { state.dealerIndex == index }

    var body: some View {
        let seatWind = MahjongPresentation.seatWindLabel(
            dealerIndex: state.dealerIndex,
            playerIndex: index
        )
        let score = state.scores.indices.contains(index) ? state.scores[index] : 0
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                badge(seatWind, background: Color.black.opacity(0.24), foreground: .white)
                if isDealer {
                    badge(
                        state.dealerStreak > 1
                            ? String(
                                format: NSLocalizedString("mahjong_dealer_streak", value: "庄×%ld", comment: ""),
                                state.dealerStreak
                            )
                            : NSLocalizedString("mahjong_dealer", value: "庄", comment: ""),
                        background: Color.black.opacity(0.28),
                        foreground: Color(hex: "FFC857")
                    )
                }
                Spacer()
                Text(state.setup.playerNames.indices.contains(index) ? state.setup.playerNames[index] : "")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
                if handDelta != 0 || hasHandEntries {
                    badge(
                        MahjongPresentation.signedValue(handDelta),
                        background: Color.black.opacity(0.24),
                        foreground: deltaColor
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Spacer()
            Text("\(score)")
                .font(typographySession.effectivePreference.font.swiftUIFont(
                    size: typographySession.effectivePreference.scoreMultiplier * 56,
                    weight: .bold
                ))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .padding(.horizontal, 14)
            if won {
                Text(NSLocalizedString("mahjong_won", value: "已胡", comment: ""))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.primary))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panelColor)
        .overlay(
            Rectangle()
                .strokeBorder(won ? Theme.primary : Color.clear, lineWidth: won ? 2 : 0)
        )
        .accessibilityIdentifier("mahjong_player_\(index)")
    }

    private var hasHandEntries: Bool {
        state.ledger.contains { $0.handNumber == state.handNumber }
    }

    private var deltaColor: Color {
        if handDelta > 0 { return Color(hex: "CCFFD8") }
        if handDelta < 0 { return Color(hex: "FFD2D2") }
        return Color.white.opacity(0.72)
    }

    private var panelColor: Color {
        if appearance.theme == .electronic || appearance.theme == .retro {
            return .black
        }
        return mahjongPalette[index % mahjongPalette.count]
    }

    private func badge(_ text: String, background: Color, foreground: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(background))
    }
}

// MARK: - 结算面板

private struct MahjongSettlementSheet: View {
    let state: MahjongSessionState
    let handDeltas: [Int]
    let initialAction: MahjongActionType
    let saving: Bool
    let store: MahjongScoreboardStore
    let onDismiss: () -> Void
    let onSubmit: (MahjongSettlementIntent) -> Void

    @State private var action: MahjongActionType
    @State private var winners: [Int] = []
    @State private var payers: [Int] = []
    @State private var factorText = "0"
    @State private var kongKind: MahjongKongKind = .exposed
    @State private var paymentMode: MahjongPaymentMode = .allOpponents
    @State private var manual: [String] = ["0", "0", "0", "0"]
    @State private var note = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case factor, manual(Int), note }

    /// 血战模板：杠种、支付方式与「已胡」置灰都由它决定（对齐安卓同一判定）。
    private var isSichuan: Bool { state.setup.ruleset == .sichuanBloodBattle }

    init(
        state: MahjongSessionState,
        handDeltas: [Int],
        initialAction: MahjongActionType,
        saving: Bool,
        store: MahjongScoreboardStore,
        onDismiss: @escaping () -> Void,
        onSubmit: @escaping (MahjongSettlementIntent) -> Void
    ) {
        self.state = state
        self.handDeltas = handDeltas
        self.initialAction = initialAction
        self.saving = saving
        self.store = store
        self.onDismiss = onDismiss
        self.onSubmit = onSubmit
        _action = State(initialValue: initialAction)
    }

    private var manualDeltas: [Int] { manual.map { Int($0) ?? 0 } }

    private var intent: MahjongSettlementIntent {
        MahjongSettlementIntent(
            actionType: action,
            winnerIndexes: winners,
            payerIndexes: payers,
            factor: Int(factorText) ?? 0,
            kongKind: action == .kong ? kongKind : nil,
            paymentMode: action == .kong ? paymentMode : nil,
            manualDeltas: MahjongPresentation.manualActions.contains(action) ? manualDeltas : nil,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private var preview: ReduceResult<MahjongSessionState, MahjongSessionEvent> {
        store.preview(intent)
    }

    private var previewDeltas: [Int] {
        MahjongPresentation.previewDeltas(
            accepted: preview.accepted,
            candidate: preview.state.ledger.last?.deltas
        )
    }

    private var nonZeroWarning: Bool {
        action == .adjustment && manualDeltas.reduce(0, +) != 0
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .accessibilityIdentifier("mahjong_settlement_panel")

            content
                .padding(.horizontal, 12)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 24,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 24
                    )
                    .fill(Theme.scoreboardDialogSurface)
                )
                .padding(.bottom, 0)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Capsule()
                .fill(Color.white.opacity(0.32))
                .frame(width: 44, height: 5)
                .frame(maxWidth: .infinity)

            HStack {
                Text(NSLocalizedString("mahjong_settlement_title", value: "记本手", comment: ""))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text(preview.accepted
                    ? String(
                        format: NSLocalizedString("mahjong_preview_total", value: "合计 %ld", comment: ""),
                        previewDeltas.reduce(0, +)
                    )
                    : NSLocalizedString("mahjong_preview_incomplete", value: "待完善", comment: ""))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(preview.accepted ? Theme.primary : Theme.scoreboardDialogTextSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MahjongPresentation.settlementActionOptions, id: \.self) { item in
                        choiceChip(MahjongPresentation.actionLabel(item), selected: action == item, enabled: true) {
                            selectAction(item)
                        }
                    }
                }
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    actionSpecificSection
                    noteField
                    deltaPreview
                    if nonZeroWarning {
                        Text(NSLocalizedString(
                            "mahjong_non_zero_warning",
                            value: "警告：本次四家调分不是零和，流水中会明确标记。",
                            comment: ""
                        ))
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "FF7B72"))
                    }
                    if let reason = preview.reason {
                        Text(reason)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "FF7B72"))
                    }
                }
            }
            .frame(maxHeight: 340)

            HStack(spacing: 12) {
                panelButton(
                    NSLocalizedString("cancel", comment: "Cancel button"),
                    background: Color.white.opacity(0.12),
                    enabled: !saving
                ) { onDismiss() }
                panelButton(
                    saving
                        ? NSLocalizedString("mahjong_saving", value: "保存中…", comment: "")
                        : NSLocalizedString("mahjong_confirm_record", value: "确认记入", comment: ""),
                    background: Theme.primary,
                    enabled: preview.accepted && !saving
                ) { onSubmit(intent) }
                .accessibilityIdentifier("mahjong_settlement_confirm")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .onChange(of: action) { _, _ in
            focusedField = nil
        }
    }

    @ViewBuilder
    private var actionSpecificSection: some View {
        if action == .draw {
            Text(NSLocalizedString(
                "mahjong_draw_hint",
                value: "流局默认不改分；确认后将推进手数并按设置处理庄家。",
                comment: ""
            ))
            .font(.system(size: 13))
            .foregroundStyle(Theme.scoreboardDialogTextSecondary)
        } else if MahjongPresentation.manualActions.contains(action) {
            Text(NSLocalizedString("mahjong_manual_four_label", value: "四家变化", comment: ""))
                .font(.system(size: 13))
                .foregroundStyle(Theme.scoreboardDialogTextSecondary)
            HStack(spacing: 6) {
                ForEach(0..<MAHJONG_PLAYER_COUNT, id: \.self) { index in
                    compactInput(
                        MahjongPresentation.seatWindLabel(
                            dealerIndex: state.dealerIndex,
                            playerIndex: index
                        ),
                        text: bindingForManual(index),
                        signed: true,
                        field: .manual(index)
                    )
                }
            }
        } else {
            selectorRow(
                title: action == .transfer
                    ? NSLocalizedString("mahjong_receiver", value: "收分方", comment: "")
                    : NSLocalizedString("mahjong_winner", value: "赢家", comment: ""),
                selected: Set(winners),
                onSelect: selectWinner
            )
            if action != .selfDraw && !(action == .kong && paymentMode == .allOpponents) {
                selectorRow(
                    title: action == .transfer
                        ? NSLocalizedString("mahjong_giver", value: "转出方", comment: "")
                        : NSLocalizedString("mahjong_payer", value: "支付方", comment: ""),
                    selected: Set(payers),
                    onSelect: selectPayer
                )
            }
            if action == .kong {
                kongKindRow
                if !isSichuan {
                    chipRow([
                        (MahjongPaymentMode.allOpponents.rawValue, MahjongPresentation.paymentModeLabel(.allOpponents)),
                        (MahjongPaymentMode.onePayer.rawValue, MahjongPresentation.paymentModeLabel(.onePayer))
                    ], selected: paymentMode.rawValue) { value in
                        paymentMode = MahjongPaymentMode(rawValue: value) ?? .allOpponents
                        payers = []
                    }
                }
            }
            if action != .kong || !isSichuan {
                compactInput(
                    NSLocalizedString("mahjong_factor_label", value: "番数（无番填 0）", comment: ""),
                    text: Binding(
                        get: { factorText },
                        set: { factorText = String($0.filter { $0.isNumber }.prefix(9)) }
                    ),
                    signed: false,
                    field: .factor
                )
            }
        }
    }

    private var kongKindRow: some View {
        let kinds: [MahjongKongKind] = isSichuan ? MahjongKongKind.allCases : [.exposed, .concealed]
        return chipRow(
            kinds.map { ($0.rawValue, MahjongPresentation.kongKindLabel($0, ruleset: state.setup.ruleset)) },
            selected: kongKind.rawValue
        ) { value in
            kongKind = MahjongKongKind(rawValue: value) ?? .exposed
            if isSichuan {
                paymentMode = kongKind == .exposed ? .onePayer : .allOpponents
                payers = []
            }
        }
    }

    /// 备注是自由文本（≤80 字），不能复用数字输入框的键盘。
    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("mahjong_note_label", value: "备注（可选）", comment: ""))
                .font(.system(size: 12))
                .foregroundStyle(Theme.scoreboardDialogTextSecondary)
                .lineLimit(1)
            TextField("", text: Binding(
                get: { note },
                set: { note = String($0.prefix(80)) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .focused($focusedField, equals: .note)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 20).fill(Theme.scoreboardDialogControl))
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var deltaPreview: some View {
        HStack(spacing: 6) {
            ForEach(0..<MAHJONG_PLAYER_COUNT, id: \.self) { index in
                VStack(spacing: 3) {
                    Text(state.setup.playerNames.indices.contains(index) ? state.setup.playerNames[index] : "")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.scoreboardDialogTextSecondary)
                        .lineLimit(1)
                    let delta = previewDeltas.indices.contains(index) ? previewDeltas[index] : 0
                    Text(MahjongPresentation.signedValue(delta))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(
                            delta > 0 ? Color(hex: "65D68A")
                                : delta < 0 ? Color(hex: "FF7B72")
                                : Color.white
                        )
                }
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.12)))
            }
        }
    }

    private func selectorRow(title: String, selected: Set<Int>, onSelect: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.scoreboardDialogTextSecondary)
            HStack(spacing: 8) {
                ForEach(0..<MAHJONG_PLAYER_COUNT, id: \.self) { index in
                    let unavailable = isSichuan
                        && [MahjongActionType.selfDraw, .discardWin, .kong].contains(action)
                        && state.currentHandWinnerIndexes.contains(index)
                    choiceChip(
                        "\(MahjongPresentation.seatWindLabel(dealerIndex: state.dealerIndex, playerIndex: index)) "
                            + (state.setup.playerNames.indices.contains(index) ? state.setup.playerNames[index] : "")
                            + (unavailable ? " · \(NSLocalizedString("mahjong_won", value: "已胡", comment: ""))" : ""),
                        selected: selected.contains(index),
                        enabled: !unavailable
                    ) { onSelect(index) }
                }
            }
        }
    }

    private func selectAction(_ item: MahjongActionType) {
        action = item
        winners = []
        payers = []
        if item == .kong && isSichuan {
            kongKind = .exposed
            paymentMode = .onePayer
        }
    }

    /// 安卓 `selectWinner`：点炮可多选，其余单选；赢家不能同时是支付方。
    private func selectWinner(_ index: Int) {
        if action == .discardWin {
            if winners.contains(index) {
                winners.removeAll { $0 == index }
            } else {
                winners.append(index)
            }
        } else {
            winners = [index]
        }
        payers.removeAll { $0 == index }
    }

    /// 安卓 `selectPayer`：自摸与三家付杠不选支付方。
    private func selectPayer(_ index: Int) {
        if action == .selfDraw { return }
        if action == .kong, paymentMode == .allOpponents { return }
        payers = [index]
        winners.removeAll { $0 == index }
    }

    private func bindingForManual(_ index: Int) -> Binding<String> {
        Binding(
            get: { manual.indices.contains(index) ? manual[index] : "0" },
            set: { raw in
                let filtered = String(raw.filter { $0.isNumber || $0 == "-" }.prefix(11))
                if manual.indices.contains(index) { manual[index] = filtered }
            }
        )
    }

    private func choiceChip(_ label: String, selected: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(enabled ? 1 : 0.45))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(Capsule().fill(selected ? Theme.primary : Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func chipRow(_ options: [(String, String)], selected: String, onSelect: @escaping (String) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.0) { option in
                choiceChip(option.1, selected: selected == option.0, enabled: true) { onSelect(option.0) }
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func compactInput(
        _ label: String,
        text: Binding<String>,
        signed: Bool,
        field: Field? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.scoreboardDialogTextSecondary)
                .lineLimit(1)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .keyboardType(signed ? .numbersAndPunctuation : .numberPad)
                .focused($focusedField, equals: field)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 20).fill(Theme.scoreboardDialogControl))
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
    }

    private func panelButton(_ title: String, background: Color, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(enabled ? 1 : 0.45))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Capsule().fill(background))
                .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
