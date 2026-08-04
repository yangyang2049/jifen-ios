//
//  DoudizhuScoreboardView.swift
//  jifen
//
//  斗地主计分：3 人，3 列布局，点击加分、撤销、编辑名称、保存记录。
//

import ScoreCore
import SwiftUI
import UIKit

private let defaultDoudizhuNames = [
    NSLocalizedString("doudizhu_player_adam", value: "刘备", comment: ""),
    NSLocalizedString("doudizhu_player_bob", value: "关羽", comment: ""),
    NSLocalizedString("doudizhu_player_chris", value: "张飞", comment: "")
]
private var doudizhuTitle: String {
    NSLocalizedString("game_doudizhu", value: "Doudizhu", comment: "")
}

struct DoudizhuPlayerItem: Identifiable {
    let id: Int
    var name: String
    var score: Int
}

struct DoudizhuScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    var initialSetup: SportsSetupResult? = nil
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil
    @State private var players: [DoudizhuPlayerItem]
    @State private var history: [[Int]] = []
    @State private var actionCount = 0
    @State private var gameStartTime: Date
    @State private var recordID: String
    @State private var showMenu = false
    @State private var isEditMode = false
    @State private var editNames: [String]
    @State private var menuConfirm = ScoreboardMenuConfirmState()
    @State private var exitClickTime: TimeInterval = 0
    @State private var toastMessage: String? = nil
    @State private var showScorePanel = false
    @State private var selectedBaseScore = 1
    @State private var selectedMultiplierPower = 0 // 0番=1倍 … 5番=32倍
    @State private var selectedWinners = [false, false, false]
    @State private var appearance = ScoreboardAppearanceSnapshot.current()
    @State private var typographySession = ScoreboardTypographySession(
        styleID: ScoreboardStyleID(gameType: .doudizhu)
    )
    @State private var preferences = PreferencesManager.shared
    @State private var gameFinished = false
    @State private var showGameOverDialog = false
    @State private var showFinishedRecordDetail = false
    @State private var showDisplaySettings = false
    @State private var actions: [String]
    @State private var chromeVisible = true
    @State private var immersiveGeneration = 0
    @State private var previousIdleTimerDisabled: Bool?

    private let commonNamesManager = CommonNamesManager.shared
    private let baseScoreOptions = [1, 2, 3]
    private let multiplierPowers = [0, 1, 2, 3, 4, 5]

    private var shouldShowChrome: Bool {
        !appearance.immersiveMode || chromeVisible || isEditMode || showMenu || showDisplaySettings || showScorePanel
    }

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

        var start = Date()
        var id = ScoreboardRecordIdentity.next(prefix: GameType.doudizhu.canonicalScoreboardIdentifier)
        var initialPlayers = defaultDoudizhuNames.enumerated().map {
            DoudizhuPlayerItem(id: $0.offset, name: $0.element, score: 0)
        }
        var finished = false
        var restoredActions: [String] = []
        var restoredHistory: [[Int]] = []
        var restoredActionCount = 0

        if let initialResumeSessionId,
           let record = ManualResumeSessionStore.load(recordID: initialResumeSessionId) {
            start = record.startTime
            id = record.id
            restoredActions = record.actions
            restoredActionCount = record.totalScoreChanges
            if let data = record.stateSnapshot,
               let resumeState = try? JSONDecoder().decode(DoudizhuResumeState.self, from: data) {
                for (index, name) in resumeState.names.prefix(3).enumerated() where !name.isEmpty {
                    initialPlayers[index].name = name
                }
                for (index, score) in resumeState.scores.prefix(3).enumerated() {
                    initialPlayers[index].score = score
                }
                finished = resumeState.finished
                restoredHistory = Array(
                    resumeState.undoHistory
                        .filter { $0.count == 3 }
                        .suffix(50)
                )
                if !resumeState.intentTimeline.isEmpty {
                    restoredActions = resumeState.intentTimeline
                }
                restoredActionCount = max(
                    max(restoredActionCount, resumeState.actionCount),
                    restoredHistory.count
                )
            } else if let restoredPlayers = decodedDoudizhuPlayers(from: record.extraData),
                      !restoredPlayers.isEmpty {
                for (index, restored) in restoredPlayers.prefix(3).enumerated() {
                    if !restored.name.isEmpty { initialPlayers[index].name = restored.name }
                    initialPlayers[index].score = restored.score
                }
            } else if let names = record.extraData?["playerNames"]?.value as? [String] {
                for (index, name) in names.prefix(3).enumerated() where !name.isEmpty {
                    initialPlayers[index].name = name
                }
                initialPlayers[0].score = record.team1FinalScore
                if initialPlayers.count > 1 {
                    initialPlayers[1].score = record.team2FinalScore
                }
            }
        }

        _players = State(initialValue: initialPlayers)
        _history = State(initialValue: restoredHistory)
        _actionCount = State(initialValue: restoredActionCount)
        _gameStartTime = State(initialValue: start)
        _recordID = State(initialValue: id)
        _gameFinished = State(initialValue: finished)
        _showGameOverDialog = State(initialValue: finished)
        _actions = State(initialValue: restoredActions)
        _editNames = State(initialValue: initialPlayers.map(\.name))
    }

    /// HOS: left/right follow the scoreboard theme; the center stays success
    /// green except in retro, where all three panels are black.
    private var panelColors: [Color] {
        let center = appearance.theme == .retro ? Color.black : Color(hex: "4CAF50")
        return [
            appearance.theme.palette.left,
            center,
            appearance.theme.palette.right
        ]
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                appearance.theme.palette.background.ignoresSafeArea()
                HStack(spacing: 0) {
                    ForEach(Array(players.enumerated()), id: \.element.id) { index, p in
                        doudizhuPlayerPanel(
                            index: index,
                            player: p,
                            panelSize: CGSize(width: w / 3, height: h)
                        )
                    }
                }

                if shouldShowChrome {
                    topTrailingEditButton
                }

                if !isEditMode && !showScorePanel && shouldShowChrome {
                    bottomControls
                }

                if appearance.immersiveMode && !chromeVisible && !isEditMode && !showScorePanel {
                    ImmersiveCornerRevealZones(onReveal: revealImmersiveChrome)
                }

                if showMenu {
                    MenuDialog(
                        isVisible: true,
                        onClose: {
                            menuConfirm.clear()
                            showMenu = false
                        },
                        onMenuItemClick: handleDoudizhuMenuAction,
                        items: doudizhuMenuItems,
                        analyticsGameType: .doudizhu
                    )
                }

                if showScorePanel {
                    doudizhuBottomSettleOverlay(containerWidth: w)
                        .zIndex(20)
                }

                if showGameOverDialog {
                    GameOverDialog(
                        winnerName: finishedWinnerName,
                        gameType: .doudizhu,
                        multiNames: players.map(\.name),
                        multiScores: players.map(\.score),
                        onNewGame: {
                            startNewMatch()
                        },
                        onRecords: {
                            saveRecord(finished: gameFinished)
                            showFinishedRecordDetail = true
                        },
                        onShare: {
                            let text = zip(players.map(\.name), players.map(\.score))
                                .map { "\($0) \($1)" }
                                .joined(separator: " · ")
                            ScoreboardShareSupport.present(text: text)
                        },
                        onExit: {
                            saveRecord(finished: gameFinished)
                            onNavigationBack?()
                            dismiss()
                        }
                    )
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
            .simultaneousGesture(TapGesture().onEnded { revealImmersiveChrome() })
        }
        .ignoresSafeArea(.all)
        .navigationTitle(NSLocalizedString("game_doudizhu", comment: "Doudizhu"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.55)
                .onEnded { _ in
                    guard !isEditMode, !showScorePanel else { return }
                    showMenu = true
                    revealImmersiveChrome()
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    guard !isEditMode,
                          !showScorePanel,
                          value.translation.width < -50,
                          abs(value.translation.width) > abs(value.translation.height) else { return }
                    undoLast()
                }
        )
        .onAppear {
            typographySession.reload()
            if let setup = initialSetup {
                if let names = setup.playerNames, !names.isEmpty {
                    for index in 0..<min(3, names.count, players.count) {
                        let trimmed = names[index].trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            players[index].name = trimmed
                        }
                    }
                } else {
                    if !setup.team1Name.isEmpty, !players.isEmpty { players[0].name = setup.team1Name }
                    if !setup.team2Name.isEmpty, players.count > 1 { players[1].name = setup.team2Name }
                }
                onSetupConsumed?()
            }
            appearance = .current()
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            revealImmersiveChrome()
        }
        .onDisappear {
            saveRecord(finished: gameFinished)
            if let previousIdleTimerDisabled { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled }
        }
        .scoreboardDisplaySettingsOverlay(
            isPresented: $showDisplaySettings,
            session: typographySession,
            metrics: ScoreboardTypographyProfile.doudizhu.adjustableMetrics
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
        .onChange(of: preferences.scoreboardRevision) { _, _ in
            appearance = .current()
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            revealImmersiveChrome()
        }
        .onChange(of: showMenu) { _, _ in updateImmersiveForBlocking() }
        .onChange(of: showDisplaySettings) { _, _ in updateImmersiveForBlocking() }
        .onChange(of: isEditMode) { _, _ in updateImmersiveForBlocking() }
        .onChange(of: showScorePanel) { _, _ in updateImmersiveForBlocking() }
    }

    private var topTrailingEditButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    if isEditMode {
                        commitDoudizhuEditNames()
                    } else {
                        editNames = players.map(\.name)
                    }
                    isEditMode.toggle()
                    VibrationManager.shared.vibrateMedium()
                } label: {
                    Image(systemName: isEditMode ? "checkmark" : "pencil")
                        .font(.system(size: ScoreboardConstants.buttonIconSize))
                        .foregroundColor(.white)
                        .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                        .background(
                            Circle().fill(isEditMode ? Theme.primary : Color.black.opacity(0.25))
                        )
                }
                .padding(.trailing, ScoreboardConstants.buttonPadding)
                .padding(.top, ScoreboardConstants.buttonPadding)
            }
            Spacer()
        }
        .ignoresSafeArea(.all, edges: .top)
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
                    showScorePanel = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: ScoreboardConstants.buttonIconSize, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                        .background(Circle().fill(Color.black.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("add_score", value: "加分", comment: ""))
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

    private func doudizhuPlayerPanel(
        index: Int,
        player: DoudizhuPlayerItem,
        panelSize: CGSize
    ) -> some View {
        let typography = ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .doudizhu,
                containerSize: panelSize,
                nameText: player.name,
                scoreText: "\(player.score)",
                preference: typographySession.effectivePreference,
                horizontalPadding: 16,
                reservedHeight: 32,
                scoreBaseScale: 0.85,
                isLargeScreen: Theme.usesPadLayout
            )
        )
        let scoreSize = typography.scoreFontSize
        let nameSize = typography.nameFontSize
        return ZStack {
            panelColors[index % 3]
            if isEditMode {
                let editOffset = ScoreboardLayoutMetrics.editContentVerticalOffset(panelHeight: panelSize.height)
                ZStack {
                    HStack(spacing: 16) {
                        doudizhuEditCircleButton(systemName: "minus") {
                            adjustDoudizhuEditScore(index: index, delta: -1)
                        }
                        Text("\(player.score)")
                            .font(typographySession.effectivePreference.font.swiftUIFont(
                                size: ScoreboardLayoutMetrics.editMainScoreFontSize(regularSize: scoreSize)
                            ))
                            .monospacedDigit()
                            .foregroundColor(appearance.theme.palette.foreground)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        doudizhuEditCircleButton(systemName: "plus") {
                            adjustDoudizhuEditScore(index: index, delta: 1)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: editOffset)

                    VStack(spacing: 0) {
                        ScoreboardNameEditorField(
                            placeholder: NSLocalizedString("multi_score_player_default", value: "玩家", comment: ""),
                            text: playerNameBinding(index),
                            nameType: ScoreboardCommonNamePolicy.nameType(for: .doudizhu),
                            scoreboardFont: typographySession.effectivePreference.font,
                            accessibilityIdentifier: "doudizhu_player_\(index)_name_editor"
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, ScoreboardLayoutMetrics.nameTopPadding(panelHeight: panelSize.height))
                        Spacer(minLength: 0)
                    }
                    .offset(y: editOffset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: ScoreboardLayoutMetrics.mainToSetSpacing(halfViewportHeight: panelSize.height)) {
                    Text("\(player.score)")
                        .font(typographySession.effectivePreference.font.swiftUIFont(size: scoreSize))
                        .monospacedDigit()
                        .foregroundColor(appearance.theme.palette.foreground)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack {
                    Text(player.name)
                        .font(typographySession.effectivePreference.font.swiftUIFont(
                            size: nameSize,
                            weight: .bold
                        ))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, ScoreboardLayoutMetrics.nameTopPadding(panelHeight: panelSize.height))
                    Spacer()
                }
            }
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .contentShape(Rectangle())
    }

    private func playerNameBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { editNames.indices.contains(index) ? editNames[index] : "" },
            set: { value in
                guard editNames.indices.contains(index) else { return }
                editNames[index] = value
            }
        )
    }

    private func commitDoudizhuEditNames() {
        for index in players.indices where editNames.indices.contains(index) {
            let name = editNames[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                editNames[index] = players[index].name
                continue
            }
            guard name != players[index].name else { continue }
            players[index].name = name
            Task { await commonNamesManager.saveNameIfNeeded(name, .player) }
        }
    }

    private func doudizhuEditCircleButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.75))
                .frame(width: 50, height: 50)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func adjustDoudizhuEditScore(index: Int, delta: Int) {
        guard players.indices.contains(index) else { return }
        let (next, overflow) = players[index].score.addingReportingOverflow(delta)
        guard !overflow else { return }
        history.append(players.map(\.score))
        if history.count > 50 { history.removeFirst() }
        players[index].score = next
        actionCount += 1
        actions.append("\(Int64(Date().timeIntervalSince1970 * 1_000))|editScore|\(index),\(delta)")
        VibrationManager.shared.vibrateLight()
    }

    /// HOS-style 320pt bottom settle overlay (not a system sheet).
    private func doudizhuBottomSettleOverlay(containerWidth: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Theme.scoreboardDialogScrim
                .ignoresSafeArea()
                .onTapGesture { showScorePanel = false }

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    settleColumn(title: NSLocalizedString("doudizhu_base_score", value: "底分", comment: "")) {
                        HStack(spacing: 8) {
                            ForEach(baseScoreOptions, id: \.self) { score in
                                settleChip("\(score)", selected: selectedBaseScore == score) {
                                    selectedBaseScore = score
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    settleColumn(title: NSLocalizedString("doudizhu_multiplier", value: "番数", comment: "")) {
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                ForEach([0, 1, 2], id: \.self) { power in
                                    settleChip("\(power)番", selected: selectedMultiplierPower == power) {
                                        selectedMultiplierPower = power
                                    }
                                }
                            }
                            HStack(spacing: 8) {
                                ForEach([3, 4, 5], id: \.self) { power in
                                    settleChip("\(power)番", selected: selectedMultiplierPower == power) {
                                        selectedMultiplierPower = power
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    settleColumn(title: NSLocalizedString("doudizhu_winner", value: "获胜者", comment: "")) {
                        VStack(spacing: 8) {
                            ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                                Button {
                                    selectedWinners[index].toggle()
                                    if selectedWinners.filter(\.self).count > 2 {
                                        selectedWinners[index] = false
                                    }
                                } label: {
                                    Text(player.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity, minHeight: 46)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(selectedWinners[index] ? Theme.primary : Color.white.opacity(0.2))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)

                Spacer(minLength: 8)

                Text(doudizhuSettlePreviewText)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 16)

                Button {
                    applyDoudizhuRound()
                    showScorePanel = false
                } label: {
                    Text(String(format: NSLocalizedString("doudizhu_confirm_with_score", value: "确认 (底分: %d)", comment: ""), selectedBaseScore * (1 << selectedMultiplierPower)))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: containerWidth * 0.45, height: 50)
                        .background(Capsule().fill(doudizhuWinnerSelectionValid ? Theme.primary : Color.white.opacity(0.2)))
                }
                .buttonStyle(.plain)
                .disabled(!doudizhuWinnerSelectionValid)
                .padding(.vertical, 16)

            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .background(Theme.scoreboardDialogSurface)
            .onAppear {
                if selectedWinners.allSatisfy({ !$0 }) {
                    selectedWinners = [true, false, false]
                }
            }

            Button { showScorePanel = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: ScoreboardConstants.buttonIconSize, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .padding(.leading, ScoreboardConstants.buttonPadding)
            .padding(.bottom, ScoreboardConstants.buttonPadding)
        }
        .ignoresSafeArea()
    }

    private func settleColumn<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .center)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func settleChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 45)
                .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Theme.primary : Color.white.opacity(0.2)))
        }
        .buttonStyle(.plain)
    }

    private var doudizhuWinnerSelectionValid: Bool {
        let count = selectedWinners.filter(\.self).count
        return count == 1 || count == 2
    }

    private var doudizhuSettlePreviewText: String {
        let unit = selectedBaseScore * (1 << selectedMultiplierPower)
        let count = selectedWinners.filter(\.self).count
        switch count {
        case 1:
            return String(
                format: NSLocalizedString("doudizhu_settle_preview_one", value: "结算：赢家 +%d，另两人各 −%d", comment: ""),
                unit * 2,
                unit
            )
        case 2:
            return String(
                format: NSLocalizedString("doudizhu_settle_preview_two", value: "结算：两赢家各 +%d，输家 −%d", comment: ""),
                unit,
                unit * 2
            )
        default:
            return NSLocalizedString("doudizhu_select_one_or_two_winners", value: "请选择 1 或 2 位赢家", comment: "")
        }
    }

    /// 1 winner → +2x/−x/−x; 2 winners → +x/+x/−2x (x = base × 2^multiplier).
    private func applyDoudizhuRound() {
        guard !gameFinished else { return }
        guard let deltas = DoudizhuSettlement.deltas(
            winners: selectedWinners,
            baseScore: selectedBaseScore,
            multiplierPower: selectedMultiplierPower
        ) else { return }
        history.append(players.map(\.score))
        if history.count > 50 { history.removeFirst() }
        for i in players.indices where i < deltas.count {
            players[i].score += deltas[i]
        }
        actionCount += 1
        actions.append("\(Int64(Date().timeIntervalSince1970 * 1_000))|settleRound|\(deltas.map { String($0) }.joined(separator: ","))")
        VibrationManager.shared.vibrateMedium()
    }

    private var finishedWinnerName: String {
        guard gameFinished else { return "" }
        let scores = players.map(\.score)
        guard let best = scores.max(), scores.filter({ $0 == best }).count == 1,
              let index = scores.firstIndex(of: best) else { return "" }
        return players[index].name
    }

    private var doudizhuMenuItems: [ScoreboardMenuItem] {
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
                    title: NSLocalizedString("exit", value: "退出", comment: "Exit"),
                    action: "exit",
                    group: .match,
                    icon: "rectangle.portrait.and.arrow.right",
                    keepDialogOpen: true,
                    confirming: menuConfirm.exitConfirming
                )
            ]
        ).map { item in
            if item.action == "undo" {
                return ScoreboardMenuItem(
                    title: item.title,
                    action: item.action,
                    group: item.group,
                    icon: item.icon,
                    customText: item.customText,
                    keepDialogOpen: item.keepDialogOpen,
                    confirming: item.confirming,
                    enabled: !history.isEmpty && !gameFinished
                )
            }
            return item
        }
    }

    private func handleDoudizhuMenuAction(_ action: String) {
        menuConfirm.prepare(forMenuAction: action)
        switch action {
        case "undo":
            undoLast()
        case "endGame":
            confirmFinish()
        case "settleMatch":
            confirmSettle()
        case "reset":
            confirmReset()
        case "exit":
            handleExitAttempt(fromMenu: true)
        case "displaySettings":
            showDisplaySettings = true
            showMenu = false
        default:
            break
        }
    }

    private func markFinished() {
        guard !gameFinished else { return }
        gameFinished = true
        actions.append("\(Int64(Date().timeIntervalSince1970 * 1_000))|finish")
        showGameOverDialog = true
        showScorePanel = false
        saveRecord(finished: true)
        VibrationManager.shared.vibrateMedium()
    }

    private func confirmFinish() {
        if menuConfirm.armOrConfirm(.finish) {
            markFinished()
            showMenu = false
            return
        }
        toastMessage = ScoreboardMenuConfirmAction.finish.localizedToast
    }

    private func confirmReset() {
        if menuConfirm.armOrConfirm(.reset) {
            performMatchReset()
            showMenu = false
            toastMessage = NSLocalizedString("has_been_reset", value: "已重置", comment: "")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if toastMessage == NSLocalizedString("has_been_reset", value: "已重置", comment: "") {
                    toastMessage = nil
                }
            }
            return
        }
        toastMessage = ScoreboardMenuConfirmAction.reset.localizedToast
    }

    private func performMatchReset() {
        history.append(players.map(\.score))
        if history.count > 50 { history.removeFirst() }
        for index in players.indices { players[index].score = 0 }
        actionCount += 1
        actions.append("\(Int64(Date().timeIntervalSince1970 * 1_000))|reset")
        gameFinished = false
        showGameOverDialog = false
        showScorePanel = false
        saveRecord()
    }

    private func startNewMatch() {
        saveRecord(finished: true)
        recordID = ScoreboardRecordIdentity.next(prefix: GameType.doudizhu.canonicalScoreboardIdentifier)
        gameStartTime = Date()
        history.removeAll()
        actionCount = 0
        actions.removeAll()
        for index in players.indices { players[index].score = 0 }
        selectedBaseScore = 1
        selectedMultiplierPower = 0
        selectedWinners = [false, false, false]
        gameFinished = false
        showGameOverDialog = false
        showScorePanel = false
    }

    private func confirmSettle() {
        if menuConfirm.armOrConfirm(.settleMatch) {
            markFinished()
            showMenu = false
            return
        }
        toastMessage = ScoreboardMenuConfirmAction.settleMatch.localizedToast
    }

    private func undoLast() {
        guard let last = history.popLast() else {
            toastMessage = NSLocalizedString("no_undo_available", value: "没有可撤销的操作", comment: "")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if toastMessage == NSLocalizedString("no_undo_available", value: "没有可撤销的操作", comment: "") {
                    toastMessage = nil
                }
            }
            return
        }
        for i in players.indices where i < last.count {
            players[i].score = last[i]
        }
        actionCount = max(0, actionCount - 1)
        actions.append("\(Int64(Date().timeIntervalSince1970 * 1_000))|undo")
        VibrationManager.shared.vibrateLight()
        toastMessage = NSLocalizedString("undone", value: "已撤销", comment: "Undo done")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toastMessage == NSLocalizedString("undone", value: "已撤销", comment: "Undo done") {
                toastMessage = nil
            }
        }
    }

    private func saveRecord(finished: Bool = false) {
        let totalChanges = actionCount
        let hasProgress = totalChanges > 0 || players.contains(where: { $0.score != 0 }) || finished || gameFinished
        guard hasProgress else { return }
        let end = Date()
        let isFinished = finished || gameFinished
        let playersEnc: [[String: Any]] = players.map { p in
            ["name": p.name, "finalScore": p.score]
        }
        let resumeState = DoudizhuResumeState(
            names: players.map(\.name),
            scores: players.map(\.score),
            finished: isFinished,
            undoHistory: history,
            intentTimeline: actions,
            actionCount: actionCount
        )
        let snapshotData: Data
        do {
            snapshotData = try JSONEncoder().encode(resumeState)
        } catch {
            ScoreboardPersistenceFailureReporter.report(error, context: "Failed to encode doudizhu record \(recordID)")
            return
        }
        var winner: String?
        var winnerIdentity: ScoreboardWinnerIdentity?
        if isFinished {
            let scores = players.map(\.score)
            if let best = scores.max(), scores.filter({ $0 == best }).count == 1,
               let index = scores.firstIndex(of: best) {
                winner = players[index].name
                winnerIdentity = .participant(index: index)
            }
        }
        let record = ScoreboardRecord(
            id: recordID,
            gameType: .doudizhu,
            startTime: gameStartTime,
            endTime: end,
            duration: end.timeIntervalSince(gameStartTime),
            team1Name: players.first?.name ?? doudizhuTitle,
            team2Name: players.count > 1 ? players[1].name : "",
            team1FinalScore: players.first?.score ?? 0,
            team2FinalScore: players.count > 1 ? players[1].score : 0,
            team1SetScore: nil,
            team2SetScore: nil,
            winner: winnerIdentity?.legacyToken ?? winner,
            winnerIdentity: winnerIdentity,
            actions: actions,
            totalScoreChanges: max(totalChanges, 1),
            extraData: [
                "players": AnyCodable(playersEnc),
                "playerNames": AnyCodable(players.map(\.name)),
                "playerCount": AnyCodable(3)
            ],
            stateSnapshot: snapshotData,
            status: .finished
        )
        do {
            try ScoreboardLifecyclePersistence.save(record, finished: isFinished)
            if isFinished {
                ScoreboardRecordsViewModel.shared.refreshRecords()
            }
        } catch {
            ScoreboardPersistenceFailureReporter.report(error, context: "Failed to save doudizhu record \(recordID)")
        }
    }

    private func handleExitAttempt(fromMenu: Bool) {
        if fromMenu {
            if menuConfirm.armOrConfirm(.exit) {
                toastMessage = nil
                showMenu = false
                saveRecord(finished: gameFinished)
                OrientationLock.shared.unlock()
                onNavigationBack?()
                dismiss()
                return
            }
            toastMessage = ScoreboardMenuConfirmAction.exit.localizedToast
            return
        }

        let currentTime = Date().timeIntervalSince1970 * 1000
        if currentTime - exitClickTime < 2000 && exitClickTime > 0 {
            exitClickTime = 0
            toastMessage = nil
            saveRecord(finished: gameFinished)
            OrientationLock.shared.unlock()
            onNavigationBack?()
            dismiss()
            return
        }

        exitClickTime = currentTime
        toastMessage = NSLocalizedString("press_again_to_exit", comment: "Press again to exit")
        revealImmersiveChrome()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if Date().timeIntervalSince1970 * 1000 - exitClickTime >= 2000 {
                toastMessage = nil
                exitClickTime = 0
            }
        }
    }

    private func revealImmersiveChrome() {
        chromeVisible = true
        immersiveGeneration += 1
        guard appearance.immersiveMode, !isEditMode, !showMenu, !showDisplaySettings, !showScorePanel else { return }
        let hideDelay: TimeInterval
        let nowMs = Date().timeIntervalSince1970 * 1000
        if exitClickTime > 0, nowMs - exitClickTime < 2000 {
            hideDelay = max((2000 - (nowMs - exitClickTime)) / 1000, 0) + 0.05
        } else {
            hideDelay = 1.5
        }
        let generation = immersiveGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay) {
            guard generation == immersiveGeneration,
                  appearance.immersiveMode,
                  !isEditMode,
                  !showMenu,
                  !showDisplaySettings,
                  !showScorePanel else { return }
            let now = Date().timeIntervalSince1970 * 1000
            if exitClickTime > 0, now - exitClickTime < 2000 { return }
            chromeVisible = false
        }
    }

    private func updateImmersiveForBlocking() {
        if showMenu || showDisplaySettings || isEditMode || showScorePanel || !appearance.immersiveMode {
            immersiveGeneration += 1
            chromeVisible = true
        } else {
            revealImmersiveChrome()
        }
    }
}

struct DoudizhuResumeState: Codable, Equatable {
    var schemaVersion: Int
    var names: [String]
    var scores: [Int]
    var finished: Bool
    var undoHistory: [[Int]]
    var intentTimeline: [String]
    var actionCount: Int

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case names
        case scores
        case finished
        case undoHistory
        case intentTimeline
        case actionCount
    }

    init(
        schemaVersion: Int = 2,
        names: [String],
        scores: [Int],
        finished: Bool,
        undoHistory: [[Int]] = [],
        intentTimeline: [String] = [],
        actionCount: Int = 0
    ) {
        self.schemaVersion = schemaVersion
        self.names = names
        self.scores = scores
        self.finished = finished
        self.undoHistory = undoHistory
        self.intentTimeline = intentTimeline
        self.actionCount = actionCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        names = try container.decode([String].self, forKey: .names)
        scores = try container.decode([Int].self, forKey: .scores)
        finished = try container.decode(Bool.self, forKey: .finished)
        undoHistory = try container.decodeIfPresent([[Int]].self, forKey: .undoHistory) ?? []
        intentTimeline = try container.decodeIfPresent([String].self, forKey: .intentTimeline) ?? []
        actionCount = try container.decodeIfPresent(Int.self, forKey: .actionCount) ?? undoHistory.count
    }
}

private func decodedDoudizhuPlayers(
    from extraData: [String: AnyCodable]?
) -> [(name: String, score: Int)]? {
    guard let rawPlayers = extraData?["players"]?.value else { return nil }
    let values: [Any]
    if let rawPlayers = rawPlayers as? [Any] {
        values = rawPlayers
    } else if let rawPlayers = rawPlayers as? [AnyCodable] {
        values = rawPlayers.map(\.value)
    } else {
        return nil
    }
    return values.compactMap { rawValue in
        let value = (rawValue as? AnyCodable)?.value ?? rawValue
        let dictionary: [String: Any]
        if let value = value as? [String: Any] {
            dictionary = value
        } else if let value = value as? [String: AnyCodable] {
            dictionary = value.mapValues(\.value)
        } else {
            return nil
        }
        let name = dictionary["name"] as? String ?? ""
        let rawScore = dictionary["finalScore"] ?? dictionary["score"] ?? 0
        let score: Int
        if let value = rawScore as? Int { score = value }
        else if let value = rawScore as? Double { score = Int(value) }
        else if let value = rawScore as? String { score = Int(value) ?? 0 }
        else { score = 0 }
        return (name, score)
    }
}

#Preview {
    NavigationStack {
        DoudizhuScoreboardView()
    }
}
