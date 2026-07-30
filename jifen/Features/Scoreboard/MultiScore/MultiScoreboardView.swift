//
//  MultiScoreboardView.swift
//  jifen
//
//  多人计分 / UNO：对齐鸿蒙/安卓 MultiScore（手势、自定义加减、草稿、结束比赛、UNO 回合面板）。
//

import ScoreCore
import SwiftUI
import UIKit

private func defaultMultiPlayerNames(count: Int) -> [String] {
    let base = NSLocalizedString("multi_score_player_default", value: "玩家", comment: "")
    return (1...count).map { "\(base) \($0)" }
}

enum MultiScoreRules {
    static let scoreRange = -9999 ... 9999

    static func normalizedPlayerCount(_ requested: Int, gameType: GameType) -> Int {
        let range = gameType == .uno ? 2 ... 10 : 3 ... 9
        return min(range.upperBound, max(range.lowerBound, requested))
    }

    static func adjustedScore(_ current: Int, delta: Int) -> Int {
        scoreRange.clamp(current + delta)
    }

    static func uniqueLeaderIndex(scores: [Int]) -> Int? {
        guard let best = scores.max(), scores.filter({ $0 == best }).count == 1 else { return nil }
        return scores.firstIndex(of: best)
    }

    static func targetWinnerIndex(scores: [Int], target: Int) -> Int? {
        scores.firstIndex { $0 >= target }
    }
}

struct MultiPlayerItem: Identifiable {
    let id: Int
    var name: String
    var score: Int
}

struct MultiScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    var gameType: GameType = .multiScoreboard
    var defaultPlayerCount: Int = 4
    var targetScore: Int? = nil
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil

    @State private var players: [MultiPlayerItem]
    @State private var history: [[Int]] = []
    @State private var actions: [String] = []
    @State private var gameStartTime = Date()
    @State private var recordId: String
    @State private var gameFinished = false
    @State private var finishedWinnerName = ""
    @State private var showMenu = false
    @State private var playerEditIndex: Int? = nil
    @State private var playerEditName = ""
    @State private var playerEditScore = 0
    @State private var initialSetupApplied = false
    @State private var suppressedTapIndex: Int? = nil
    @State private var suppressedTapUntil: Date = .distantPast
    @State private var menuConfirm = ScoreboardMenuConfirmState()
    @State private var exitClickTime: TimeInterval = 0
    @State private var toastMessage: String? = nil
    @State private var showUnoRoundPanel = false
    @State private var showFinishedRecordDetail = false
    @State private var unoRoundPlayerIndex: Int? = nil
    @State private var unoSelectedWinnerIndex: Int = 0
    @State private var unoNumberTotalText = ""
    @State private var unoAction20 = 0
    @State private var unoWild40 = 0
    @State private var unoWild50 = 0
    @State private var unoRoundCount = 0
    @State private var customAdjustEnabled = false
    @State private var customAdjustIndex: Int? = nil
    @State private var resolvedTargetScore: Int?
    @State private var appearance = ScoreboardAppearanceSnapshot.current()
    @State private var typographySession: ScoreboardTypographySession
    @State private var preferences = PreferencesManager.shared
    @State private var showDisplaySettings = false
    @State private var previousIdleTimerDisabled: Bool?
    @State private var chromeVisible = true
    @State private var immersiveGeneration = 0
    @State private var draftSaveGeneration = 0
    @State private var pendingTapIndex: Int?
    @State private var pendingTapAt: Date = .distantPast
    @State private var useLandscapeLayout: Bool

    private let commonNamesManager = CommonNamesManager.shared
    private let doubleTapWindow: TimeInterval = 0.24

    init(
        gameType: GameType = .multiScoreboard,
        defaultPlayerCount: Int = 4,
        targetScore: Int? = nil,
        initialSetup: SportsSetupResult? = nil,
        initialRecordId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        onNavigationBack: (() -> Void)? = nil
    ) {
        self.gameType = gameType
        let safeCount = MultiScoreRules.normalizedPlayerCount(defaultPlayerCount, gameType: gameType)
        self.defaultPlayerCount = safeCount
        self.targetScore = targetScore
        self.initialSetup = initialSetup
        self.initialRecordId = initialRecordId
        self.onSetupConsumed = onSetupConsumed
        self.onNavigationBack = onNavigationBack

        let start = Date()
        _gameStartTime = State(initialValue: start)
        _recordId = State(initialValue: initialRecordId ?? "\(gameType.canonicalScoreboardIdentifier)_\(Int(start.timeIntervalSince1970))")
        _players = State(initialValue: defaultMultiPlayerNames(count: safeCount).enumerated().map {
            MultiPlayerItem(id: $0.offset, name: $0.element, score: 0)
        })
        _typographySession = State(initialValue: ScoreboardTypographySession(
            styleID: ScoreboardStyleID(gameType: gameType)
        ))
        _resolvedTargetScore = State(initialValue: targetScore ?? (gameType == .uno ? 500 : nil))
        let adjust = initialSetup?.multiScoreCustomAdjustEnabled
            ?? (gameType == .multiScoreboard ? PreferencesManager.shared.multiScoreboardCustomAdjustEnabled : false)
        _customAdjustEnabled = State(initialValue: adjust)
        let layoutKey = gameType == .uno ? "uno_use_landscape_layout" : "multi_scoreboard_use_landscape_layout"
        _useLandscapeLayout = State(initialValue: UserDefaults.standard.object(forKey: layoutKey) as? Bool ?? true)
    }

    // HOS MULTI_PLAYER_GRID_COLORS order
    private let colors: [Color] = [
        Color(hex: "EF4444"),
        Color(hex: "3B82F6"),
        Color(hex: "22C55E"),
        Color(hex: "F59E0B"),
        Color(hex: "A855F7"),
        Color(hex: "EC4899"),
        Color(hex: "14B8A6"),
        Color(hex: "F97316"),
        Color(hex: "6366F1"),
        Color(hex: "84CC16"),
        Color(hex: "06B6D4"),
        Color(hex: "E11D48"),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                appearance.theme.palette.background.ignoresSafeArea()

                scoreboardGrid(geo: geo)

                if gameType == .uno,
                   !showUnoRoundPanel,
                   playerEditIndex == nil,
                   customAdjustIndex == nil,
                   shouldShowChrome {
                    unoTargetBadge
                }

                if shouldShowChrome,
                   !showUnoRoundPanel,
                   playerEditIndex == nil,
                   customAdjustIndex == nil {
                    bottomControls
                }

                if showMenu {
                    MenuDialog(
                        isVisible: true,
                        onClose: {
                            menuConfirm.clear()
                            showMenu = false
                        },
                        onMenuItemClick: handleMultiScoreMenuAction,
                        items: multiScoreMenuItems
                    )
                }

                if let index = customAdjustIndex, players.indices.contains(index) {
                    ScoreCustomAdjustPanel(
                        targetName: players[index].name,
                        currentScore: players[index].score,
                        onDismiss: { customAdjustIndex = nil },
                        onAdjust: { delta in
                            adjustScore(index: index, delta: delta)
                        }
                    )
                }

                if let index = playerEditIndex, players.indices.contains(index) {
                    playerEditOverlay(index: index)
                }

                if showUnoRoundPanel {
                    unoRoundOverlay
                }

                if let message = toastMessage {
                    VStack {
                        Spacer()
                        ToastView(message: message)
                            .padding(.bottom, 24)
                    }
                    .allowsHitTesting(false)
                }

                if gameFinished {
                    GameOverDialog(
                        winnerName: finishedWinnerName,
                        gameType: gameType,
                        multiNames: players.map(\.name),
                        multiScores: players.map(\.score),
                        onNewGame: {
                            resetScores()
                            showTransientToast(NSLocalizedString("has_been_reset", value: "已重置", comment: ""))
                        },
                        onRecords: {
                            persistRecord(finished: gameFinished)
                            showFinishedRecordDetail = true
                        },
                        onShare: {
                            let text = zip(players.map(\.name), players.map(\.score))
                                .map { "\($0) \($1)" }
                                .joined(separator: " · ")
                            ScoreboardShareSupport.present(text: text)
                        },
                        onExit: {
                            persistRecord(finished: gameFinished)
                            onNavigationBack?()
                            dismiss()
                        }
                    )
                }
            }
        }
        .ignoresSafeArea(.all)
        .navigationTitle(gameType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .simultaneousGesture(TapGesture().onEnded { revealImmersiveChrome() })
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.55)
                .onEnded { _ in
                    guard playerEditIndex == nil,
                          customAdjustIndex == nil,
                          !showUnoRoundPanel else { return }
                    showMenu = true
                    revealImmersiveChrome()
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    guard playerEditIndex == nil,
                          customAdjustIndex == nil,
                          !showUnoRoundPanel,
                          value.translation.width < -50,
                          abs(value.translation.width) > abs(value.translation.height) else { return }
                    undoLast()
                }
        )
        .onAppear {
            typographySession.reload()
            applySetupIfNeeded()
            restoreDraftIfNeeded()
            appearance = .current()
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            registerScoreboardSync()
            revealImmersiveChrome()
        }
        .onChange(of: preferences.scoreboardRevision) { _, _ in
            appearance = .current()
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            revealImmersiveChrome()
        }
        .onChange(of: typographySession.effectivePreference) { _, _ in
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onDisappear {
            LocalScoreboardSyncCoordinator.shared.unregisterHost()
            if let previousIdleTimerDisabled { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled }
            persistRecord(finished: gameFinished)
        }
        .scoreboardDisplaySettingsOverlay(
            isPresented: $showDisplaySettings,
            session: typographySession,
            metrics: gameType == .uno
                ? ScoreboardTypographyProfile.uno.adjustableMetrics
                : ScoreboardTypographyProfile.multi.adjustableMetrics
        )
        .fullScreenCover(isPresented: $showFinishedRecordDetail) {
            NavigationStack {
                ScoreboardRecordDetailPage(recordId: recordId)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(NSLocalizedString("done", value: "完成", comment: "")) {
                                showFinishedRecordDetail = false
                            }
                        }
                    }
            }
        }
    }

    // MARK: - Grid

    private func scoreboardGrid(geo: GeometryProxy) -> some View {
        let rows = layoutRows()
        let cellHeight = geo.size.height / CGFloat(max(1, rows.count))

        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, playerIndex in
                        if let playerIndex, players.indices.contains(playerIndex) {
                            playerPanel(index: playerIndex, player: players[playerIndex], height: cellHeight)
                                .frame(maxWidth: .infinity)
                        } else {
                            extraCellPlaceholder(height: cellHeight, showEmoji: true)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: cellHeight)
            }
        }
        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
    }

    private func extraCellPlaceholder(height: CGFloat, showEmoji: Bool) -> some View {
        Group {
            if showEmoji {
                Text("🤡")
                    .font(.system(size: min(48, height * 0.5)))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color.white.opacity(0.08))
    }

    private var bottomControls: some View {
        VStack {
            Spacer()
            HStack {
                Button {
                    handleExitAttempt(fromMenu: false)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: ScoreboardConstants.buttonIconSize))
                        .foregroundColor(.white)
                        .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                        .background(Circle().fill(Color.black.opacity(0.25)))
                }
                .modifier(ScoreboardBackButtonAccessibility(isBack: true))
                .padding(.leading, ScoreboardConstants.buttonPadding)
                .padding(.bottom, ScoreboardConstants.buttonPadding)

                Spacer()

                Button {
                    showMenu = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: ScoreboardConstants.buttonIconSize))
                        .foregroundColor(.white)
                        .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                        .background(Circle().fill(Color.black.opacity(0.25)))
                }
                .accessibilityIdentifier("scoreboard_menu_button")
                .padding(.trailing, ScoreboardConstants.buttonPadding)
                .padding(.bottom, ScoreboardConstants.buttonPadding)
            }
        }
        .ignoresSafeArea(.all, edges: [.bottom, .leading, .trailing])
    }

    private var unoTargetBadge: some View {
        GeometryReader { proxy in
            let targetText = String(
                format: NSLocalizedString("uno_target_badge", value: "目标 %d", comment: ""),
                effectiveTargetScore
            )
            let secondarySize = ScoreboardTypographyResolver.resolve(
                ScoreboardTypographyLayoutContext(
                    profile: .uno,
                    containerSize: CGSize(width: min(proxy.size.width * 0.5, 320), height: max(80, proxy.size.height * 0.22)),
                    nameText: "",
                    scoreText: "",
                    secondaryText: targetText,
                    preference: typographySession.effectivePreference,
                    horizontalPadding: 20,
                    isLargeScreen: Theme.usesPadLayout
                )
            ).secondaryFontSize
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Text("🎴")
                            .font(.system(size: max(13, secondarySize * 0.45)))
                        Text(targetText)
                            .font(typographySession.effectivePreference.font.swiftUIFont(
                                size: max(13, secondarySize * 0.45),
                                weight: .medium
                            ))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.35)))
                    Spacer()
                }
                .padding(.bottom, 72)
            }
        }
        .allowsHitTesting(false)
    }

    private func playerPanel(index: Int, player: MultiPlayerItem, height: CGFloat) -> some View {
        GeometryReader { panelGeo in
            let gap = gameType == .uno ? max(0, effectiveTargetScore - player.score) : 0
            let typography = ScoreboardTypographyResolver.resolve(
                ScoreboardTypographyLayoutContext(
                    profile: gameType == .uno ? .uno : .multi,
                    containerSize: panelGeo.size,
                    nameText: player.name,
                    scoreText: "\(player.score)",
                    secondaryText: gameType == .uno ? "\(gap)" : "",
                    preference: typographySession.effectivePreference,
                    horizontalPadding: 12,
                    reservedHeight: gameType == .uno ? 28 : 12,
                    isLargeScreen: Theme.usesPadLayout
                )
            )
            VStack(spacing: typography.nameToScoreSpacing) {
                Text(player.name)
                    .font(typographySession.effectivePreference.font.swiftUIFont(
                        size: typography.nameFontSize,
                        weight: .medium
                    ))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, Theme.sm)

                Text("\(player.score)")
                    .font(typographySession.effectivePreference.font.swiftUIFont(size: typography.scoreFontSize))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if gameType == .uno, !gameFinished {
                    Text(String(
                        format: NSLocalizedString("uno_gap_format", value: "差 %d", comment: ""),
                        gap
                    ))
                    .font(typographySession.effectivePreference.font.swiftUIFont(
                        size: max(10, typography.secondaryFontSize * 0.4),
                        weight: .regular
                    ))
                    .foregroundStyle(.white.opacity(0.75))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: height)
        .background(panelColor(index: index))
        .contentShape(Rectangle())
        .onTapGesture {
            handlePlayerTap(index: index)
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            openPlayerEdit(index: index)
        }
        .simultaneousGesture(playerGesture(index: index))
    }

    private func playerGesture(index: Int) -> some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                guard !gameFinished, gameType != .uno, !customAdjustEnabled, playerEditIndex == nil else { return }
                if value.translation.height < -40, abs(value.translation.width) < 60 {
                    adjustScore(index: index, delta: 1)
                } else if value.translation.height > 40, abs(value.translation.width) < 60 {
                    adjustScore(index: index, delta: -1)
                }
            }
    }

    private func handlePlayerTap(index: Int) {
        revealImmersiveChrome()
        if suppressedTapIndex == index, Date() < suppressedTapUntil {
            return
        }
        guard !gameFinished else { return }

        if gameType == .uno {
            openUnoRoundPanel(index: index)
            return
        }

        if customAdjustEnabled {
            customAdjustIndex = index
            return
        }

        if !appearance.doubleTapSubtract {
            adjustScore(index: index, delta: 1)
            return
        }

        let now = Date()
        if pendingTapIndex == index,
           now.timeIntervalSince(pendingTapAt) <= doubleTapWindow {
            pendingTapIndex = nil
            adjustScore(index: index, delta: -1)
            return
        }

        pendingTapIndex = index
        pendingTapAt = now
        let capturedIndex = index
        DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow) {
            guard pendingTapIndex == capturedIndex else { return }
            pendingTapIndex = nil
            adjustScore(index: capturedIndex, delta: 1)
        }
    }

    // MARK: - Menu

    private var multiScoreMenuItems: [ScoreboardMenuItem] {
        return ScoreboardMenuItemBuilder.defaultItems(
            showEndGame: true,
            showExchangeSide: false,
            showWhistle: true,
            showScreenshot: true,
            showSettleMatch: true,
            resetConfirming: menuConfirm.resetConfirming,
            finishConfirming: menuConfirm.finishConfirming,
            settleConfirming: menuConfirm.settleConfirming,
            extraItems: [
                ScoreboardMenuItem(
                    title: NSLocalizedString("scoreboard_rotate_orientation", value: "切换布局", comment: ""),
                    action: "layout",
                    group: .match,
                    icon: "rectangle.portrait.rotate.90"
                ),
                ScoreboardMenuItem(
                    title: NSLocalizedString("exit", value: "退出", comment: "Exit"),
                    action: "exit",
                    group: .match,
                    icon: "rectangle.portrait.and.arrow.right",
                    keepDialogOpen: true,
                    confirming: menuConfirm.exitConfirming
                )
            ]
        )
    }

    private func handleMultiScoreMenuAction(_ action: String) {
        menuConfirm.prepare(forMenuAction: action)
        switch action {
        case "undo":
            undoLast()
        case "reset":
            handleResetAttempt()
        case "endGame":
            handleEndGameAttempt()
        case "settleMatch":
            handleSettleAttempt()
        case "displaySettings":
            showDisplaySettings = true
            showMenu = false
        case "layout":
            toggleLayout()
        case "exit":
            handleExitAttempt(fromMenu: true)
        default:
            break
        }
    }

    private func handleEndGameAttempt() {
        if menuConfirm.armOrConfirm(.finish) {
            markFinished()
            showMenu = false
            return
        }
        showTransientToast(ScoreboardMenuConfirmAction.finish.localizedToast)
    }

    private func handleSettleAttempt() {
        if menuConfirm.armOrConfirm(.settleMatch) {
            markFinished()
            showMenu = false
            return
        }
        showTransientToast(ScoreboardMenuConfirmAction.settleMatch.localizedToast)
    }

    private func handleResetAttempt() {
        if menuConfirm.armOrConfirm(.reset) {
            resetScores()
            showTransientToast(NSLocalizedString("has_been_reset", value: "已重置", comment: ""))
            showMenu = false
            return
        }
        showTransientToast(ScoreboardMenuConfirmAction.reset.localizedToast)
    }

    private func showTransientToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    private func markFinished() {
        guard !gameFinished else { return }
        gameFinished = true
        if let winnerIndex = MultiScoreRules.uniqueLeaderIndex(scores: players.map(\.score)) {
            finishedWinnerName = players[winnerIndex].name
        } else {
            finishedWinnerName = ""
        }
        VibrationManager.shared.vibrateHeavy()
        persistRecord(finished: true)
        LocalScoreboardSyncCoordinator.shared.publishSnapshot()
    }

    // MARK: - Layout helpers

    private func layoutRows() -> [[Int?]] {
        ScoreboardPlayerGridLayout.multiRows(
            playerCount: players.count,
            usesWideLayout: useLandscapeLayout
        )
    }

    private func toggleLayout() {
        useLandscapeLayout.toggle()
        let key = gameType == .uno ? "uno_use_landscape_layout" : "multi_scoreboard_use_landscape_layout"
        UserDefaults.standard.set(useLandscapeLayout, forKey: key)
        appendRecordAction("layout:\(useLandscapeLayout ? "landscape" : "portrait")")
        showMenu = false
    }

    private func panelColor(index: Int) -> Color {
        if appearance.theme == .electronic || appearance.theme == .retro {
            return .black
        }
        return colors[index % colors.count]
    }

    private func playerPlaceholder(_ index: Int) -> String {
        let base = NSLocalizedString("multi_score_player_default", value: "玩家", comment: "")
        return "\(base) \(index + 1)"
    }

    private func openPlayerEdit(index: Int) {
        guard players.indices.contains(index), !gameFinished else { return }
        pendingTapIndex = nil
        customAdjustIndex = nil
        suppressedTapIndex = index
        suppressedTapUntil = Date().addingTimeInterval(0.5)
        playerEditName = players[index].name
        playerEditScore = players[index].score
        playerEditIndex = index
        VibrationManager.shared.vibrateMedium()
        revealImmersiveChrome()
    }

    private func cancelPlayerEdit() {
        playerEditIndex = nil
        playerEditName = ""
    }

    private func confirmPlayerEdit(index: Int) {
        guard players.indices.contains(index) else {
            cancelPlayerEdit()
            return
        }
        let name = playerEditName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            showTransientToast(NSLocalizedString(
                "multi_score_rename_warning",
                value: "请输入玩家名称",
                comment: ""
            ))
            return
        }

        let old = players[index]
        let newScore = MultiScoreRules.scoreRange.clamp(playerEditScore)
        guard old.name != name || old.score != newScore else {
            cancelPlayerEdit()
            return
        }

        if old.score != newScore {
            history.append(players.map(\.score))
            if history.count > 50 { history.removeFirst() }
            appendRecordAction("edit:\(index):\(newScore - old.score)")
        }
        players[index].name = name
        players[index].score = newScore
        Task { await commonNamesManager.saveNameIfNeeded(name, .player) }
        cancelPlayerEdit()
        LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        scheduleDraftPersist()
    }

    private func playerEditAdjustButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 56, height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    private func playerEditOverlay(index: Int) -> some View {
        GeometryReader { proxy in
            let dialogWidth = Theme.dialogWidth(
                availableWidth: proxy.size.width,
                phonePreferredWidth: 320,
                padPreferredWidth: 420
            )

            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { cancelPlayerEdit() }

                VStack(spacing: 16) {
                    Text(NSLocalizedString("multi_score_edit_title", value: "编辑玩家", comment: ""))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)

                    TextField(
                        NSLocalizedString("multi_score_rename_placeholder", value: "玩家名称", comment: ""),
                        text: $playerEditName
                    )
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
                    .onSubmit { confirmPlayerEdit(index: index) }

                    VStack(spacing: 8) {
                        Text(NSLocalizedString("multi_score_edit_score_label", value: "分数", comment: ""))
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.65))

                        HStack(spacing: 12) {
                            playerEditAdjustButton(systemName: "minus") {
                                playerEditScore = MultiScoreRules.adjustedScore(playerEditScore, delta: -1)
                            }
                            Text("\(playerEditScore)")
                                .font(typographySession.effectivePreference.font.swiftUIFont(size: 30))
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)
                            playerEditAdjustButton(systemName: "plus") {
                                playerEditScore = MultiScoreRules.adjustedScore(playerEditScore, delta: 1)
                            }
                        }
                    }

                    HStack(spacing: 16) {
                        Button(NSLocalizedString("cancel", value: "取消", comment: "")) {
                            cancelPlayerEdit()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))

                        Button(NSLocalizedString("confirm", value: "确定", comment: "")) {
                            confirmPlayerEdit(index: index)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.primary))
                    }
                }
                .padding(24)
                .frame(width: dialogWidth)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.88)))
            }
        }
        .zIndex(20)
    }

    private var effectiveTargetScore: Int {
        resolvedTargetScore ?? (gameType == .uno ? 500 : Int.max)
    }

    // MARK: - UNO round overlay

    private var unoRoundTotal: Int {
        let number = Int(unoNumberTotalText).map { max(0, min(9999, $0)) } ?? 0
        return UnoRoundScore.total(number: number, action20: unoAction20, wild40: unoWild40, wild50: unoWild50)
    }

    private var unoRoundOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { showUnoRoundPanel = false }

            VStack(spacing: 0) {
                Spacer(minLength: 12)
                VStack(alignment: .leading, spacing: 14) {
                    Capsule()
                        .fill(Color.white.opacity(0.32))
                        .frame(width: 44, height: 5)
                        .frame(maxWidth: .infinity)

                    HStack {
                        Text(NSLocalizedString("uno_round_sheet_title", value: "UNO 结算", comment: ""))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(String(
                            format: NSLocalizedString("uno_round_total_format", value: "本局 %d 分", comment: ""),
                            unoRoundTotal
                        ))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.primary)
                    }

                    Text(NSLocalizedString("uno_round_winner", value: "本局赢家", comment: ""))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)

                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 8),
                            count: min(5, max(2, players.count))
                        ),
                        spacing: 8
                    ) {
                        ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                            Button {
                                unoSelectedWinnerIndex = index
                                VibrationManager.shared.vibrateLight()
                            } label: {
                                Text(player.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(unoSelectedWinnerIndex == index ? Color.white : Theme.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(unoSelectedWinnerIndex == index ? Theme.primary : Theme.dialogControlBackground)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text(NSLocalizedString("uno_number_total", value: "数字牌合计", comment: ""))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    TextField("0", text: $unoNumberTotalText)
                        .keyboardType(.numberPad)
                        .font(.system(size: 22, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(Theme.dialogControlBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    unoCountStepper(
                        title: NSLocalizedString("uno_action_20_count", value: "20 分功能牌张数", comment: ""),
                        hint: NSLocalizedString("uno_action_20_hint", value: "+2 / 跳过 / 反转 x20", comment: ""),
                        value: $unoAction20
                    )
                    unoCountStepper(
                        title: NSLocalizedString("uno_wild_40_count", value: "40 分万能牌张数", comment: ""),
                        hint: NSLocalizedString("uno_wild_40_hint", value: "洗手牌 / 自定义万能牌 x40", comment: ""),
                        value: $unoWild40
                    )
                    unoCountStepper(
                        title: NSLocalizedString("uno_wild_50_count", value: "50 分万能牌张数", comment: ""),
                        hint: NSLocalizedString("uno_wild_50_hint", value: "万能牌 / +4 x50", comment: ""),
                        value: $unoWild50
                    )

                    HStack(spacing: 12) {
                        Button {
                            showUnoRoundPanel = false
                        } label: {
                            Text(NSLocalizedString("cancel", value: "取消", comment: ""))
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Theme.dialogControlBackground)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            confirmUnoRound()
                        } label: {
                            Text(NSLocalizedString("uno_confirm_round", value: "确认记分", comment: ""))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Theme.primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
                .frame(maxWidth: 720)
                .background(Theme.homeDialogBackground)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private func unoCountStepper(title: String, hint: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Stepper(value: value, in: 0...20) {
                    Text("\(value.wrappedValue)")
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                        .frame(minWidth: 28, alignment: .trailing)
                }
                .labelsHidden()
            }
        }
    }

    private func openUnoRoundPanel(index: Int) {
        guard !gameFinished else { return }
        unoRoundPlayerIndex = index
        unoSelectedWinnerIndex = index
        unoNumberTotalText = ""
        unoAction20 = 0
        unoWild40 = 0
        unoWild50 = 0
        showUnoRoundPanel = true
    }

    private func confirmUnoRound() {
        guard players.indices.contains(unoSelectedWinnerIndex) else {
            toastMessage = NSLocalizedString("uno_select_winner_toast", value: "请选择本局赢家", comment: "")
            return
        }
        let number = Int(unoNumberTotalText).map { max(0, min(9999, $0)) } ?? 0
        let delta = UnoRoundScore.total(
            number: number,
            action20: unoAction20,
            wild40: unoWild40,
            wild50: unoWild50
        )
        guard delta > 0 else {
            toastMessage = NSLocalizedString(
                "uno_zero_score_toast",
                value: "本局分数不能为 0，请输入赢家手中剩余牌的分值",
                comment: ""
            )
            return
        }
        history.append(players.map(\.score))
        if history.count > 50 { history.removeFirst() }
        players[unoSelectedWinnerIndex].score = MultiScoreRules.adjustedScore(
            players[unoSelectedWinnerIndex].score,
            delta: delta
        )
        unoRoundCount += 1
        appendRecordAction("uno_round:\(unoSelectedWinnerIndex):+\(delta)")
        VibrationManager.shared.vibrateLight()
        LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        showUnoRoundPanel = false
        scheduleDraftPersist()
        checkTargetReached(for: unoSelectedWinnerIndex)
    }

    // MARK: - Scoring

    private func adjustScore(index: Int, delta: Int) {
        guard !gameFinished, players.indices.contains(index), delta != 0 else { return }
        history.append(players.map(\.score))
        if history.count > 50 { history.removeFirst() }
        players[index].score = MultiScoreRules.adjustedScore(players[index].score, delta: delta)
        appendRecordAction("adjust:\(index):\(delta > 0 ? "+" : "")\(delta)")
        checkTargetReached(for: index)
        VibrationManager.shared.vibrateLight()
        LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        scheduleDraftPersist()
    }

    private func checkTargetReached(for index: Int) {
        guard gameType == .uno else { return }
        if let winnerIndex = MultiScoreRules.targetWinnerIndex(
            scores: players.map(\.score),
            target: effectiveTargetScore
        ) {
            gameFinished = true
            finishedWinnerName = players[winnerIndex].name
            VibrationManager.shared.vibrateHeavy()
            persistRecord(finished: true)
        }
    }

    private func undoLast() {
        guard let last = history.popLast() else {
            showTransientToast(NSLocalizedString("no_undo_available", value: "没有可撤销的操作", comment: ""))
            return
        }
        for i in players.indices where i < last.count {
            players[i].score = last[i]
        }
        if !actions.isEmpty { actions.removeLast() }
        if gameType == .uno {
            let target = effectiveTargetScore
            let stillFinished = players.contains { $0.score >= target }
            gameFinished = stillFinished
            finishedWinnerName = players.first(where: { $0.score >= target })?.name ?? ""
            if stillFinished == false, unoRoundCount > 0 {
                unoRoundCount -= 1
            }
        }
        VibrationManager.shared.vibrateLight()
        LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        scheduleDraftPersist()
        showTransientToast(NSLocalizedString("undone", value: "已撤销", comment: "Undo done"))
    }

    private func resetScores() {
        history.append(players.map(\.score))
        if history.count > 50 { history.removeFirst() }
        for i in players.indices {
            players[i].score = 0
        }
        appendRecordAction("reset")
        gameFinished = false
        finishedWinnerName = ""
        unoRoundCount = 0
        VibrationManager.shared.vibrateMedium()
        LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        scheduleDraftPersist()
    }

    // MARK: - Appearance / sync

    private var shouldShowChrome: Bool {
        !appearance.immersiveMode || chromeVisible || showMenu || showDisplaySettings || showUnoRoundPanel || playerEditIndex != nil
    }

    private func revealImmersiveChrome() {
        chromeVisible = true
        immersiveGeneration += 1
        guard appearance.immersiveMode, !showMenu, !showDisplaySettings, !showUnoRoundPanel, playerEditIndex == nil else { return }
        let generation = immersiveGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard generation == immersiveGeneration,
                  appearance.immersiveMode,
                  !showMenu,
                  !showDisplaySettings,
                  !showUnoRoundPanel,
                  playerEditIndex == nil else { return }
            chromeVisible = false
        }
    }

    private func registerScoreboardSync() {
        LocalScoreboardSyncCoordinator.shared.registerHost(
            snapshot: {
                let left = players.first ?? MultiPlayerItem(id: 0, name: "", score: 0)
                let right = players.dropFirst().first ?? MultiPlayerItem(id: 1, name: "", score: 0)
                return LocalScoreboardDisplayState(
                    gameID: gameType.canonicalScoreboardIdentifier,
                    title: gameType.displayName,
                    leftName: left.name,
                    rightName: right.name,
                    leftScore: "\(left.score)",
                    rightScore: "\(right.score)",
                    leftDetail: String(format: NSLocalizedString("sync_players_format", value: "共 %d 人", comment: ""), players.count),
                    rightDetail: gameType == .uno
                        ? String(format: NSLocalizedString("uno_target_badge", value: "目标 %d", comment: ""), effectiveTargetScore)
                        : nil,
                    themeID: appearance.theme.rawValue,
                    fontID: typographySession.effectivePreference.font.rawValue,
                    scoreMultiplier: typographySession.effectivePreference.scoreMultiplier,
                    nameMultiplier: typographySession.effectivePreference.nameMultiplier,
                    secondaryMultiplier: typographySession.effectivePreference.secondaryMultiplier,
                    finished: gameFinished,
                    revision: 0
                )
            },
            handleIntent: { intent in
                guard LocalScoreboardMutationPolicy.allowsMutation(
                    isEditing: playerEditIndex != nil,
                    finished: gameFinished,
                    scoringLocked: false
                ) else { return }
                switch intent {
                case .addLeft: if !players.isEmpty { adjustScore(index: 0, delta: 1) }
                case .addRight: if players.count > 1 { adjustScore(index: 1, delta: 1) }
                case .subtractLeft: if !players.isEmpty { adjustScore(index: 0, delta: -1) }
                case .subtractRight: if players.count > 1 { adjustScore(index: 1, delta: -1) }
                case .undo: undoLast()
                case .exchangeSides:
                    guard players.count > 1 else { return }
                    players.swapAt(0, 1)
                    scheduleDraftPersist()
                case .requestSnapshot: break
                }
            }
        )
    }

    // MARK: - Setup / draft

    private func applySetupIfNeeded() {
        guard !initialSetupApplied else { return }
        initialSetupApplied = true
        guard let setup = initialSetup else { return }

        let allowedRange: ClosedRange<Int> = gameType == .uno ? 2...10 : 3...9
        let setupCount: Int
        if let count = setup.playerCount, allowedRange.contains(count) {
            setupCount = count
        } else {
            setupCount = defaultPlayerCount
        }
        var names = defaultMultiPlayerNames(count: setupCount)

        if let playerNames = setup.playerNames, !playerNames.isEmpty {
            for i in 0..<min(setupCount, playerNames.count) {
                let value = playerNames[i].trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    names[i] = value
                }
            }
        } else {
            let name1 = setup.team1Name.trimmingCharacters(in: .whitespacesAndNewlines)
            let name2 = setup.team2Name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name1.isEmpty { names[0] = name1 }
            if !name2.isEmpty && names.count > 1 { names[1] = name2 }
        }

        players = names.enumerated().map { MultiPlayerItem(id: $0.offset, name: $0.element, score: 0) }
        if let flag = setup.multiScoreCustomAdjustEnabled {
            customAdjustEnabled = flag
        }
        if gameType == .uno {
            resolvedTargetScore = setup.targetScore ?? resolvedTargetScore ?? 500
        }
        onSetupConsumed?()
    }

    private func restoreDraftIfNeeded() {
        guard let draftId = initialRecordId,
              let record = ScoreboardRecordManager.shared.getRecordById(draftId),
              record.status == .draft,
              record.gameType == gameType else { return }

        recordId = record.id
        gameStartTime = record.startTime
        actions = record.actions
        gameFinished = false

        if let playersData = record.extraData?["players"]?.value as? [Any] {
            let restored: [MultiPlayerItem] = playersData.enumerated().compactMap { index, raw in
                guard let dict = raw as? [String: Any] else { return nil }
                let name = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let score = (dict["finalScore"] as? Int)
                    ?? (dict["score"] as? Int)
                    ?? 0
                return MultiPlayerItem(
                    id: index,
                    name: (name?.isEmpty == false ? name! : playerPlaceholder(index)),
                    score: MultiScoreRules.scoreRange.clamp(score)
                )
            }
            if !restored.isEmpty {
                players = restored
            }
        }

        if gameType == .uno {
            if let target = record.extraData?["unoTargetScore"]?.value as? Int {
                resolvedTargetScore = target
            }
            if let rounds = record.extraData?["unoRoundCount"]?.value as? Int {
                unoRoundCount = rounds
            }
        }
        if let flag = record.extraData?["multiScoreCustomAdjustEnabled"]?.value as? Bool {
            customAdjustEnabled = flag
        }
    }

    private func scheduleDraftPersist() {
        guard !gameFinished else { return }
        draftSaveGeneration += 1
        let generation = draftSaveGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard generation == draftSaveGeneration else { return }
            persistRecord(finished: false)
        }
    }

    private func appendRecordAction(_ action: String) {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
        actions.append("\(timestamp)|\(action)")
    }

    private func persistRecord(finished: Bool) {
        let hasProgress = !history.isEmpty
            || players.contains { $0.score != 0 }
            || !actions.isEmpty
            || finished
            || gameFinished
        guard hasProgress else { return }

        let end = Date()
        let playersEnc: [AnyCodable] = players.map { p in
            AnyCodable([
                "name": AnyCodable(p.name),
                "finalScore": AnyCodable(p.score),
                "score": AnyCodable(p.score),
            ])
        }
        var extraData: [String: AnyCodable] = [
            "players": AnyCodable(playersEnc),
            "playerCount": AnyCodable(players.count),
        ]
        if gameType == .multiScoreboard {
            extraData["multiScoreCustomAdjustEnabled"] = AnyCodable(customAdjustEnabled)
        }
        if gameType == .uno {
            extraData["unoTargetScore"] = AnyCodable(effectiveTargetScore)
            extraData["unoRoundCount"] = AnyCodable(unoRoundCount)
        }

        var winner: String?
        if finished || gameFinished {
            if let index = MultiScoreRules.uniqueLeaderIndex(scores: players.map(\.score)) {
                winner = "\(index)"
            }
        }

        let record = ScoreboardRecord(
            id: recordId,
            gameType: gameType,
            startTime: gameStartTime,
            endTime: (finished || gameFinished) ? end : nil,
            duration: end.timeIntervalSince(gameStartTime),
            team1Name: players.first?.name ?? gameType.displayName,
            team2Name: players.count > 1 ? players[1].name : "",
            team1FinalScore: players.first?.score ?? 0,
            team2FinalScore: players.count > 1 ? players[1].score : 0,
            team1SetScore: nil,
            team2SetScore: nil,
            winner: winner,
            actions: actions,
            totalScoreChanges: max(actions.count, history.count),
            extraData: extraData,
            status: (finished || gameFinished) ? .finished : .draft
        )
        do {
            try ScoreboardRecordManager.shared.saveScoreboardRecord(record)
            ScoreboardRecordsViewModel.shared.refreshRecords()
        } catch {
            ScoreboardPersistenceFailureReporter.report(
                error,
                context: "Failed to save \(gameType.rawValue) record \(recordId)"
            )
            #if DEBUG
            print("[MultiScoreboardView] Failed to save record: \(error)")
            #endif
        }
    }

    private func handleExitAttempt(fromMenu: Bool) {
        if fromMenu {
            if menuConfirm.armOrConfirm(.exit) {
                toastMessage = nil
                showMenu = false
                cancelPlayerEdit()
                persistRecord(finished: gameFinished)
                OrientationLock.shared.unlock()
                onNavigationBack?()
                dismiss()
                return
            }
            showTransientToast(ScoreboardMenuConfirmAction.exit.localizedToast)
            return
        }

        let currentTime = Date().timeIntervalSince1970 * 1000
        if currentTime - exitClickTime < 2000 && exitClickTime > 0 {
            exitClickTime = 0
            toastMessage = nil
            cancelPlayerEdit()
            persistRecord(finished: gameFinished)
            OrientationLock.shared.unlock()
            onNavigationBack?()
            dismiss()
            return
        }

        exitClickTime = currentTime
        toastMessage = NSLocalizedString("press_again_to_exit", comment: "Press again to exit")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if Date().timeIntervalSince1970 * 1000 - exitClickTime >= 2000 {
                toastMessage = nil
                exitClickTime = 0
            }
        }
    }
}

private extension ClosedRange where Bound == Int {
    func clamp(_ value: Int) -> Int {
        Swift.min(upperBound, Swift.max(lowerBound, value))
    }
}

#Preview {
    NavigationStack {
        MultiScoreboardView()
    }
}
