//
//  DoudizhuScoreboardView.swift
//  jifen
//
//  斗地主计分：3/4 人自适应布局，点击加分、撤销、编辑名称、保存记录。
//

import RecordCore
import ScoreCore
import SwiftUI
import UIKit

private let defaultDoudizhuNames = [
    NSLocalizedString("doudizhu_player_adam", value: "刘备", comment: ""),
    NSLocalizedString("doudizhu_player_bob", value: "关羽", comment: ""),
    NSLocalizedString("doudizhu_player_chris", value: "张飞", comment: ""),
    NSLocalizedString("doudizhu_player_david", value: "诸葛亮", comment: "")
]
private var doudizhuTitle: String {
    NSLocalizedString("game_doudizhu", value: "Doudizhu", comment: "")
}

enum DoudizhuUndoPolicy {
    static func isAllowed(gameFinished: Bool) -> Bool { !gameFinished }

    @discardableResult
    static func performIfAllowed(gameFinished: Bool, undo: () -> Void) -> Bool {
        guard isAllowed(gameFinished: gameFinished) else { return false }
        undo()
        return true
    }
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
    @State private var historyTimeline: [DoudizhuUndoTimelineCheckpoint] = []
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
    @State private var selectedWinners: [Bool]
    @State private var appearance = ScoreboardAppearanceSnapshot.current(
        styleID: ScoreboardStyleID(gameType: .doudizhu)
    )
    @State private var typographySession = ScoreboardTypographySession(
        styleID: ScoreboardStyleID(gameType: .doudizhu)
    )
    @State private var preferences = PreferencesManager.shared
    @State private var gameFinished = false
    @State private var showGameOverDialog = false
    @State private var showFinishedRecordDetail = false
    @State private var showDisplaySettings = false
    @State private var styleEditorEntry = ScoreboardStyleEditorEntry()
    @State private var actions: [String]
    @State private var detailedActions: [DetailedScoreAction]
    @State private var chromeVisible = true
    @State private var immersiveGeneration = 0
    @State private var previousIdleTimerDisabled: Bool?

    private let commonNamesManager = CommonNamesManager.shared
    private let baseScoreOptions = [1, 2, 3]
    private let multiplierPowers = [0, 1, 2, 3, 4, 5]
    private let reducer = DoudizhuScoreReducer()

    private var shouldShowChrome: Bool {
        !styleEditorEntry.isEditing
            && (!appearance.immersiveMode || chromeVisible || isEditMode || showMenu || showDisplaySettings || showScorePanel)
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
        let configuredPlayerCount = min(4, max(3, initialSetup?.playerCount ?? initialSetup?.playerNames?.count ?? 3))
        var initialPlayers = defaultDoudizhuNames.prefix(configuredPlayerCount).enumerated().map {
            DoudizhuPlayerItem(id: $0.offset, name: $0.element, score: 0)
        }
        var finished = false
        var restoredActions: [String] = []
        var restoredDetailedActions: [DetailedScoreAction] = []
        var restoredHistory: [[Int]] = []
        var restoredHistoryTimeline: [DoudizhuUndoTimelineCheckpoint] = []
        var restoredActionCount = 0

        if let initialResumeSessionId,
           let record = ManualResumeSessionStore.load(recordID: initialResumeSessionId) {
            start = record.startTime
            id = record.id
            restoredActions = record.actions
            restoredDetailedActions = record.detailedActions ?? []
            restoredActionCount = record.totalScoreChanges
            if let data = record.stateSnapshot,
               let resumeState = try? JSONDecoder().decode(DoudizhuResumeState.self, from: data) {
                let restoredPlayerCount = min(4, max(3, resumeState.playerCount))
                initialPlayers = defaultDoudizhuNames.prefix(restoredPlayerCount).enumerated().map {
                    DoudizhuPlayerItem(id: $0.offset, name: $0.element, score: 0)
                }
                for (index, name) in resumeState.names.prefix(restoredPlayerCount).enumerated() where !name.isEmpty {
                    initialPlayers[index].name = name
                }
                for (index, score) in resumeState.scores.prefix(restoredPlayerCount).enumerated() {
                    initialPlayers[index].score = score
                }
                finished = resumeState.finished
                restoredHistory = Array(
                    resumeState.undoHistory
                        .filter { $0.count == restoredPlayerCount }
                        .suffix(50)
                )
                restoredHistoryTimeline = Array(resumeState.undoTimeline.suffix(50))
                if !resumeState.intentTimeline.isEmpty {
                    restoredActions = resumeState.intentTimeline
                }
                if !resumeState.detailedActions.isEmpty {
                    restoredDetailedActions = resumeState.detailedActions
                }
                restoredActionCount = max(
                    max(restoredActionCount, resumeState.actionCount),
                    restoredHistory.count
                )
            } else if let restoredPlayers = decodedDoudizhuPlayers(from: record.extraData),
                      !restoredPlayers.isEmpty {
                let restoredPlayerCount = min(4, max(3, restoredPlayers.count))
                initialPlayers = defaultDoudizhuNames.prefix(restoredPlayerCount).enumerated().map {
                    DoudizhuPlayerItem(id: $0.offset, name: $0.element, score: 0)
                }
                for (index, restored) in restoredPlayers.prefix(restoredPlayerCount).enumerated() {
                    if !restored.name.isEmpty { initialPlayers[index].name = restored.name }
                    initialPlayers[index].score = restored.score
                }
            } else if let names = record.extraData?["playerNames"]?.value as? [String] {
                let restoredPlayerCount = min(4, max(3, names.count))
                initialPlayers = defaultDoudizhuNames.prefix(restoredPlayerCount).enumerated().map {
                    DoudizhuPlayerItem(id: $0.offset, name: $0.element, score: 0)
                }
                for (index, name) in names.prefix(restoredPlayerCount).enumerated() where !name.isEmpty {
                    initialPlayers[index].name = name
                }
                initialPlayers[0].score = record.team1FinalScore
                if initialPlayers.count > 1 {
                    initialPlayers[1].score = record.team2FinalScore
                }
            }
        }

        if restoredHistoryTimeline.count != restoredHistory.count {
            let historyCount = restoredHistory.count
            restoredHistoryTimeline = restoredHistory.indices.map { index in
                let distance = historyCount - index
                return .init(
                    actionLogCount: max(0, restoredActions.count - distance),
                    detailedActionsCount: max(0, restoredDetailedActions.count - distance),
                    actionCount: max(0, restoredActionCount - distance)
                )
            }
        }

        _players = State(initialValue: initialPlayers)
        _history = State(initialValue: restoredHistory)
        _historyTimeline = State(initialValue: restoredHistoryTimeline)
        _actionCount = State(initialValue: restoredActionCount)
        _gameStartTime = State(initialValue: start)
        _recordID = State(initialValue: id)
        _gameFinished = State(initialValue: finished)
        _showGameOverDialog = State(initialValue: finished)
        _actions = State(initialValue: restoredActions)
        _detailedActions = State(initialValue: restoredDetailedActions)
        _editNames = State(initialValue: initialPlayers.map(\.name))
        _selectedWinners = State(initialValue: Array(repeating: false, count: initialPlayers.count))
    }

    /// HOS: left/right follow the scoreboard theme; the center stays success
    /// green except in retro, where all three panels are black.
    private var doudizhuSlotKeys: [ScoreboardStyleSlotKeyV2] { [.sideLeft, .sideCenter, .sideRight] }

    /// 样式编辑锚点槽位：0/1/2 → 左/中/右；第 4 人编辑归中间槽（对齐鸿蒙 getPlayerStyleSide）。
    private func slotKey(for index: Int) -> ScoreboardStyleSlotKeyV2 {
        index < 3 ? doudizhuSlotKeys[index] : .sideCenter
    }

    /// 渲染槽位：第 4 人优先 player_3 槽位（安卓自定义面板可跨端同步），未配置时回落
    /// 中间槽（对齐安卓 panelColorOr(player(3), centerTeamColor) 与鸿蒙 centerColor）。
    private func renderSlotKey(for index: Int) -> ScoreboardStyleSlotKeyV2 {
        guard index >= 3 else { return doudizhuSlotKeys[index] }
        let profile = appearance.styleProfileV2
        let hasPlayer3Config = profile.panels?.contains { $0.slotKey == .player3 } == true
            || profile.elements?.contains { $0.textColors.contains { $0.slotKey == .player3 } } == true
        return hasPlayer3Config ? .player3 : .sideCenter
    }

    private func panelColor(for index: Int) -> Color {
        Color(hex: appearance.styleProfileV2.slotBackgroundHex(renderSlotKey(for: index)))
    }

    private func panelTextColor(for index: Int) -> Color {
        appearance.elementForeground(.teamName, slotKey: renderSlotKey(for: index))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                appearance.palette.background.ignoresSafeArea()
                HStack(spacing: 0) {
                    ForEach(Array(players.enumerated()), id: \.element.id) { index, p in
                        doudizhuPlayerPanel(
                            index: index,
                            player: p,
                            panelSize: CGSize(width: w / CGFloat(players.count), height: h)
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
                            performScoreboardExit(
                                onNavigationBack: onNavigationBack,
                                dismiss: dismiss
                            )
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
            .animation(.easeInOut(duration: 0.2), value: showMenu)
            .animation(.easeInOut(duration: 0.2), value: showScorePanel)
            .animation(.easeInOut(duration: 0.2), value: showGameOverDialog)
            .simultaneousGesture(TapGesture().onEnded { revealImmersiveChrome() })
        }
        .ignoresSafeArea(.all)
        .cloudSyncSharingEntryOverlay(respectsSafeArea: true)
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
                          DoudizhuUndoPolicy.isAllowed(gameFinished: gameFinished),
                          value.translation.width < -50,
                          abs(value.translation.width) > abs(value.translation.height) else { return }
                    undoLast()
                }
        )
        .onAppear {
            typographySession.reload()
            if let setup = initialSetup {
                if let names = setup.playerNames, !names.isEmpty {
                    for index in 0..<min(names.count, players.count) {
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
            appearance = .current(styleID: ScoreboardStyleID(gameType: .doudizhu))
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            registerSync()
            revealImmersiveChrome()
        }
        .onDisappear {
            LocalScoreboardSyncCoordinator.shared.unregisterHost()
            saveRecord(finished: gameFinished)
            if let previousIdleTimerDisabled { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled }
        }
        .scoreboardDisplaySettingsOverlay(
            isPresented: $showDisplaySettings,
            session: typographySession,
            metrics: ScoreboardTypographyProfile.doudizhu.adjustableMetrics
        )
        .scoreboardStyleEditorEntry(
            styleEditorEntry,
            typographySession: typographySession,
            onEditingChange: { _ in updateImmersiveForBlocking() }
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
            appearance = .current(styleID: ScoreboardStyleID(gameType: .doudizhu))
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            revealImmersiveChrome()
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onChange(of: typographySession.effectivePreference) { _, _ in
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onChange(of: syncSnapshot()) { _, _ in
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onChange(of: showMenu) { _, _ in updateImmersiveForBlocking() }
        .onChange(of: showDisplaySettings) { _, _ in updateImmersiveForBlocking() }
        .onChange(of: isEditMode) { _, _ in updateImmersiveForBlocking() }
        .onChange(of: showScorePanel) { _, _ in updateImmersiveForBlocking() }
    }

    private func registerSync() {
        LocalScoreboardSyncCoordinator.shared.registerHost(snapshot: syncSnapshot) { _ in }
    }

    private func syncSnapshot() -> LocalScoreboardDisplayState {
        var compact = LocalScoreboardDisplayState(
            gameID: GameType.doudizhu.canonicalScoreboardIdentifier,
            title: "",
            leftName: players.first?.name ?? "",
            rightName: players.dropFirst().first?.name ?? "",
            leftScore: "\(players.first?.score ?? 0)",
            rightScore: "\(players.dropFirst().first?.score ?? 0)",
            themeID: appearance.theme.rawValue,
            fontID: typographySession.effectivePreference.font.rawValue,
            scoreMultiplier: typographySession.effectivePreference.scoreMultiplier,
            nameMultiplier: typographySession.effectivePreference.nameMultiplier,
            secondaryMultiplier: typographySession.effectivePreference.secondaryMultiplier,
            finished: gameFinished,
            revision: UInt64(actionCount)
        )
        let displayPlayers = players.enumerated().map { index, player in
            let slot = renderSlotKey(for: index)
            return ScoreboardDisplayPlayer(
                id: "player_\(player.id)",
                name: player.name,
                score: player.score,
                order: index,
                color: "#\(appearance.styleProfileV2.slotBackgroundHex(slot))"
            )
        }
        var value = ScoreboardDisplayState.enriched(
            compact: compact,
            layoutKind: .boardCard,
            players: displayPlayers,
            sportState: ["multiGridColumns": .integer(players.count)]
        )
        value.teams = displayPlayers.map {
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
        if gameFinished {
            let best = players.map(\.score).max() ?? 0
            let winners = players.filter { $0.score == best }
            value.result = ScoreboardDisplayResult(
                ended: true,
                winnerID: winners.count == 1 ? "player_\(winners[0].id)" : "draw",
                finalScores: Dictionary(uniqueKeysWithValues: players.map {
                    ("player_\($0.id)", ScoreboardDisplayFinalScore(score: $0.score))
                })
            )
        }
        compact.externalState = value
        return compact
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
                    selectedBaseScore = 1
                    selectedMultiplierPower = 0
                    selectedWinners = Array(repeating: false, count: players.count)
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
        let textColor = panelTextColor(for: index)
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
            panelColor(for: index)
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
                            .foregroundColor(textColor)
                        .styleElementSelectable(.teamName, slotKey: slotKey(for: index))
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
                            textColor: textColor,
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
                        .foregroundColor(appearance.elementForeground(.mainScore, slotKey: renderSlotKey(for: index)))
                        .styleElementSelectable(.mainScore, slotKey: slotKey(for: index))
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
                        .foregroundColor(textColor)
                        .styleElementSelectable(.teamName, slotKey: slotKey(for: index))
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
        var changed = false
        for index in players.indices where editNames.indices.contains(index) {
            let name = editNames[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                editNames[index] = players[index].name
                continue
            }
            guard name != players[index].name else { continue }
            players[index].name = name
            changed = true
            Task { await commonNamesManager.saveNameIfNeeded(name, .player) }
        }
        if changed { saveRecord(force: true) }
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
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
        let result = reducer.reduce(
            state: .init(scores: players.map(\.score)),
            intent: .adjustScore(playerIndex: index, delta: delta),
            at: timestamp
        )
        guard result.accepted else { return }
        pushUndoSnapshot()
        applyDoudizhuScores(result.state.scores)
        actionCount += 1
        actions.append("\(timestamp)|snapshot|doudizhu_adjust_\(index + 1)|\(result.state.scores.map(String.init).joined(separator: ","))|")
        detailedActions.append(doudizhuDetailedAction(
            type: .scoreChanged,
            epochMilliseconds: timestamp,
            team: doudizhuRecordTeam(index),
            scoreChange: delta,
            operationCode: "doudizhu_adjust_player_\(index + 1)"
        ))
        saveRecord()
        VibrationManager.shared.vibrateLight()
    }

    /// HOS-style bottom settle overlay (not a system sheet).
    private func doudizhuBottomSettleOverlay(containerWidth: CGFloat) -> some View {
        let columnWidth = settleColumnWidth(containerWidth: containerWidth)
        let chipWidth = settleChipWidth(columnWidth: columnWidth)

        return ZStack(alignment: .bottomLeading) {
            Theme.scoreboardDialogScrim
                .ignoresSafeArea()
                .onTapGesture { showScorePanel = false }

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    settleColumn(title: NSLocalizedString("doudizhu_base_score", value: "底分", comment: "")) {
                        HStack(spacing: 8) {
                            ForEach(baseScoreOptions, id: \.self) { score in
                                settleChip(
                                    "\(score)",
                                    width: chipWidth,
                                    height: settleBaseChipHeight,
                                    selected: selectedBaseScore == score
                                ) {
                                    selectedBaseScore = score
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    settleColumn(title: NSLocalizedString("doudizhu_multiplier", value: "番数", comment: "")) {
                        // 两行各 3 个（对齐鸿蒙的 0-2 / 3-5 分行）；四人时曾按 2 列栅格排布，
                        // 6 枚按钮横排溢出列宽，压到相邻的底分/获胜者栏。
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                ForEach([0, 1, 2], id: \.self) { power in
                                    settleChip(
                                        fanTitle(power),
                                        width: chipWidth,
                                        height: settleFanChipHeight,
                                        selected: selectedMultiplierPower == power
                                    ) {
                                        selectedMultiplierPower = power
                                    }
                                }
                            }
                            HStack(spacing: 8) {
                                ForEach([3, 4, 5], id: \.self) { power in
                                    settleChip(
                                        fanTitle(power),
                                        width: chipWidth,
                                        height: settleFanChipHeight,
                                        selected: selectedMultiplierPower == power
                                    ) {
                                        selectedMultiplierPower = power
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    settleColumn(title: NSLocalizedString("doudizhu_winner", value: "获胜者", comment: "")) {
                        if usesCompactSettleLayout && players.count == 4 {
                            // 小屏四人：2×2 网格，四枚纵向按钮会和预览文案、确认按钮抢高度
                            let gridWidth = settleWinnerGridItemWidth(columnWidth: columnWidth)
                            VStack(spacing: 8) {
                                ForEach([[0, 1], [2, 3]], id: \.self) { rowIndexes in
                                    HStack(spacing: 8) {
                                        ForEach(rowIndexes, id: \.self) { index in
                                            settleWinnerButton(
                                                index: index,
                                                width: gridWidth,
                                                height: settleWinnerHeight(inGrid: true),
                                                fontSize: 12
                                            )
                                        }
                                    }
                                }
                            }
                        } else {
                            VStack(spacing: 8) {
                                ForEach(Array(players.enumerated()), id: \.element.id) { index, _ in
                                    settleWinnerButton(
                                        index: index,
                                        width: nil,
                                        height: settleWinnerHeight(inGrid: false),
                                        fontSize: usesCompactSettleLayout ? 13 : 14
                                    )
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.top, usesCompactSettleLayout ? 12 : 20)

                Spacer(minLength: usesCompactSettleLayout ? 4 : 8)

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
                        .frame(width: containerWidth * 0.45, height: usesCompactSettleLayout ? 46 : 50)
                        .background(Capsule().fill(doudizhuWinnerSelectionValid ? Theme.primary : Color.white.opacity(0.2)))
                }
                .buttonStyle(.plain)
                .disabled(!doudizhuWinnerSelectionValid)
                .padding(.top, usesCompactSettleLayout ? 10 : 16)
                // 手机横屏底部还有一条 Home 指示条，留出可点区域
                .padding(.bottom, usesCompactSettleLayout ? 20 : 16)

            }
            .frame(maxWidth: .infinity)
            // 设计高度只是下限：ZStack 会把整屏高度提议下来，固定 frame 会与确认按钮叠压，
            // 所以让面板按内容取高（四人/长文案时向上生长），再夹到设计高度下限。
            .frame(minHeight: settlePanelHeight)
            .fixedSize(horizontal: false, vertical: true)
            .background(Theme.scoreboardDialogSurface)

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

    /// 斗地主在手机上是横屏锁定的，横屏可用高度仅 ~375pt，整块面板需要紧凑排布。
    private var usesCompactSettleLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var settlePanelHeight: CGFloat {
        usesCompactSettleLayout ? 272 : 320
    }

    private var settleBaseChipHeight: CGFloat {
        usesCompactSettleLayout ? 42 : 50
    }

    private var settleFanChipHeight: CGFloat {
        usesCompactSettleLayout ? 36 : 45
    }

    /// 高度档位对齐鸿蒙 DoudizhuScore：2×2 网格 36、手机纵向 40、宽屏四人 36 / 三人 46。
    private func settleWinnerHeight(inGrid: Bool) -> CGFloat {
        if inGrid { return 36 }
        if usesCompactSettleLayout { return 40 }
        return players.count == 4 ? 36 : 46
    }

    private var settleColumnInnerSpacing: CGFloat {
        usesCompactSettleLayout ? 6 : 10
    }

    /// 三栏等分后的单栏可用宽度（扣除面板左右 16 内边距与栏间距 10×2）。
    private func settleColumnWidth(containerWidth: CGFloat) -> CGFloat {
        max((containerWidth - 32 - 20) / 3, 0)
    }

    private func settleChipWidth(columnWidth: CGFloat) -> CGFloat {
        ScoreboardLayoutMetrics.fittedGridItemSize(
            containerWidth: columnWidth,
            columns: 3,
            spacing: 8,
            horizontalPadding: 0,
            preferredSize: 60,
            minimumSize: 36
        )
    }

    private func settleWinnerGridItemWidth(columnWidth: CGFloat) -> CGFloat {
        ScoreboardLayoutMetrics.fittedGridItemSize(
            containerWidth: columnWidth,
            columns: 2,
            spacing: 8,
            horizontalPadding: 0,
            preferredSize: 96,
            minimumSize: 44
        )
    }

    private func fanTitle(_ power: Int) -> String {
        // 对齐安卓 doudizhu_fan_suffix：中文“番”，英文“x”。
        let fanSuffix = NSLocalizedString("doudizhu_fan_suffix", value: "番", comment: "")
        return "\(power)\(fanSuffix)"
    }

    private func settleWinnerButton(
        index: Int,
        width: CGFloat?,
        height: CGFloat,
        fontSize: CGFloat
    ) -> some View {
        Button {
            toggleDoudizhuWinner(index)
        } label: {
            Text(players[index].name)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: width, minHeight: height)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selectedWinners[index] ? Theme.primary : Color.white.opacity(0.2))
                )
        }
        .buttonStyle(.plain)
    }

    /// 最多选中 N-1 人（一对多结算），超出的那次点选自愈回滚。
    private func toggleDoudizhuWinner(_ index: Int) {
        selectedWinners[index].toggle()
        if selectedWinners.filter(\.self).count > players.count - 1 {
            selectedWinners[index] = false
        }
    }

    private func settleColumn<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .center, spacing: settleColumnInnerSpacing) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .center)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func settleChip(
        _ title: String,
        width: CGFloat,
        height: CGFloat,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: width, height: height)
                .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Theme.primary : Color.white.opacity(0.2)))
        }
        .buttonStyle(.plain)
    }

    private var doudizhuWinnerSelectionValid: Bool {
        let count = selectedWinners.filter(\.self).count
        return count == 1 || count == players.count - 1
    }

    private var doudizhuSettlePreviewText: String {
        let unit = selectedBaseScore * (1 << selectedMultiplierPower)
        let count = selectedWinners.filter(\.self).count
        switch count {
        case 1:
            return String(
                format: NSLocalizedString("doudizhu_settle_preview_one_n", value: "结算：赢家 +%d，其他 %d 人各 −%d", comment: ""),
                unit * (players.count - 1),
                players.count - 1,
                unit
            )
        case let winnerCount where winnerCount == players.count - 1:
            return String(
                format: NSLocalizedString("doudizhu_settle_preview_many", value: "结算：%d 位赢家各 +%d，输家 −%d", comment: ""),
                players.count - 1,
                unit,
                unit * (players.count - 1)
            )
        default:
            return NSLocalizedString("doudizhu_select_one_or_all_but_one", value: "请选择一位赢家，或除一人外的全部赢家", comment: "")
        }
    }

    /// One winner or one loser; settlement stays zero-sum for 3/4 players.
    private func applyDoudizhuRound() {
        guard !gameFinished else { return }
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
        let result = reducer.reduce(
            state: .init(scores: players.map(\.score)),
            intent: .confirmRound(
                winners: selectedWinners,
                baseScore: selectedBaseScore,
                multiplierPower: selectedMultiplierPower
            ),
            at: timestamp
        )
        guard result.accepted,
              case .roundConfirmed(let winners, let losers, let landlord, let farmers, let scoreChange, _) = result.events.first else { return }
        pushUndoSnapshot()
        applyDoudizhuScores(result.state.scores)
        actionCount += 1
        actions.append("\(timestamp)|snapshot|doudizhu_round|\(result.state.scores.map(String.init).joined(separator: ","))|")
        detailedActions.append(doudizhuDetailedAction(
            type: .roundFinished,
            epochMilliseconds: timestamp,
            roundNumber: detailedActions.filter { $0.type == .roundFinished }.count + 1,
            scoreChange: scoreChange,
            winner: winners.count == 1 ? doudizhuRecordTeam(winners[0]) : nil,
            loser: losers.count == 1 ? doudizhuRecordTeam(losers[0]) : nil,
            landlord: doudizhuRecordTeam(landlord),
            winners: winners.compactMap(doudizhuRecordTeam),
            losers: losers.compactMap(doudizhuRecordTeam),
            farmers: farmers.compactMap(doudizhuRecordTeam),
            operationCode: "doudizhu_round_landlord_\(landlord + 1)_farmers_\(farmers.map { String($0 + 1) }.joined(separator: "_"))"
        ))
        saveRecord()
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
            // 对齐安卓 DoudizhuScoreScreen：菜单无哨子项。
            showWhistle: false,
            showScreenshot: true,
            showDisplaySettings: true,
            showSettleMatch: true,
            resetConfirming: menuConfirm.resetConfirming,
            finishConfirming: menuConfirm.finishConfirming,
            settleConfirming: menuConfirm.settleConfirming
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
        case "displaySettings":
            showMenu = false
            // 白名单项目打开新样式编辑器（对齐安卓 useStyleEditLabel 分叉）。
            if !styleEditorEntry.handleDisplaySettings(
                styleID: typographySession.styleID,
                typographySession: typographySession
            ) {
                showDisplaySettings = true
            }
        default:
            break
        }
    }

    private func markFinished() {
        guard !gameFinished else { return }
        gameFinished = true
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
        actions.append("\(timestamp)|finish")
        detailedActions.append(doudizhuDetailedAction(
            type: .matchFinished,
            epochMilliseconds: timestamp,
            operationCode: "doudizhu_match_finished"
        ))
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
        let result = reducer.reduce(
            state: .init(scores: players.map(\.score)),
            intent: .resetScores,
            at: Int64(Date().timeIntervalSince1970 * 1_000)
        )
        guard result.accepted else { return }
        applyDoudizhuScores(result.state.scores)
        history.removeAll()
        historyTimeline.removeAll()
        actionCount = 0
        actions.removeAll()
        detailedActions.removeAll()
        gameFinished = false
        showGameOverDialog = false
        showScorePanel = false
        saveRecord(force: true)
    }

    private func startNewMatch() {
        saveRecord(finished: true)
        recordID = ScoreboardRecordIdentity.next(prefix: GameType.doudizhu.canonicalScoreboardIdentifier)
        gameStartTime = Date()
        history.removeAll()
        historyTimeline.removeAll()
        actionCount = 0
        actions.removeAll()
        detailedActions.removeAll()
        for index in players.indices { players[index].score = 0 }
        selectedBaseScore = 1
        selectedMultiplierPower = 0
        selectedWinners = Array(repeating: false, count: players.count)
        gameFinished = false
        showGameOverDialog = false
        showScorePanel = false
        LocalScoreboardSyncCoordinator.shared.publishSnapshot()
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
        DoudizhuUndoPolicy.performIfAllowed(gameFinished: gameFinished) {
            performUndoLast()
        }
    }

    private func performUndoLast() {
        guard let last = history.popLast() else {
            toastMessage = NSLocalizedString("no_undo_available", value: "没有可撤销的操作", comment: "")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if toastMessage == NSLocalizedString("no_undo_available", value: "没有可撤销的操作", comment: "") {
                    toastMessage = nil
                }
            }
            return
        }
        let timeline = historyTimeline.popLast()
        for i in players.indices where i < last.count {
            players[i].score = last[i]
        }
        actionCount = timeline?.actionCount ?? max(0, actionCount - 1)
        actions = Array(actions.prefix(timeline?.actionLogCount ?? max(0, actions.count - 1)))
        detailedActions = Array(detailedActions.prefix(
            timeline?.detailedActionsCount ?? max(0, detailedActions.count - 1)
        ))
        saveRecord()
        VibrationManager.shared.vibrateLight()
        toastMessage = NSLocalizedString("undone", value: "已撤销", comment: "Undo done")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toastMessage == NSLocalizedString("undone", value: "已撤销", comment: "Undo done") {
                toastMessage = nil
            }
        }
    }

    private func saveRecord(finished: Bool = false, force: Bool = false) {
        let totalChanges = actionCount
        let hasProgress = totalChanges > 0 || players.contains(where: { $0.score != 0 }) || finished || gameFinished
        guard hasProgress || force else { return }
        let end = Date()
        let isFinished = finished || gameFinished
        let playersEnc: [[String: Any]] = players.map { p in
            ["name": p.name, "finalScore": p.score]
        }
        let resumeState = DoudizhuResumeState(
            playerCount: players.count,
            names: players.map(\.name),
            scores: players.map(\.score),
            finished: isFinished,
            undoHistory: history,
            intentTimeline: actions,
            actionCount: actionCount,
            detailedActions: detailedActions,
            undoTimeline: historyTimeline
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
            detailedActions: detailedActions,
            setResults: ScoreboardRecordActionAdapter.setResults(from: detailedActions),
            totalScoreChanges: totalChanges,
            extraData: [
                "players": AnyCodable(playersEnc),
                "playerNames": AnyCodable(players.map(\.name)),
                "playerCount": AnyCodable(players.count)
            ],
            stateSnapshot: snapshotData,
            status: isFinished ? .finished : .draft
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

    private func pushUndoSnapshot() {
        history.append(players.map(\.score))
        historyTimeline.append(.init(
            actionLogCount: actions.count,
            detailedActionsCount: detailedActions.count,
            actionCount: actionCount
        ))
        if history.count > 50 {
            history.removeFirst(history.count - 50)
            historyTimeline.removeFirst(max(0, historyTimeline.count - 50))
        }
    }

    private func applyDoudizhuScores(_ scores: [Int]) {
        for index in players.indices where scores.indices.contains(index) {
            players[index].score = scores[index]
        }
    }

    private func doudizhuRecordTeam(_ index: Int) -> RecordTeam? {
        guard RecordTeam.allCases.indices.contains(index) else { return nil }
        return RecordTeam.allCases[index]
    }

    private func doudizhuDetailedAction(
        type: DetailedScoreActionType,
        epochMilliseconds: Int64,
        team: RecordTeam? = nil,
        roundNumber: Int? = nil,
        scoreChange: Int? = nil,
        winner: RecordTeam? = nil,
        loser: RecordTeam? = nil,
        landlord: RecordTeam? = nil,
        winners: [RecordTeam]? = nil,
        losers: [RecordTeam]? = nil,
        farmers: [RecordTeam]? = nil,
        operationCode: String
    ) -> DetailedScoreAction {
        DetailedScoreAction(
            type: type,
            epochMilliseconds: epochMilliseconds,
            team: team,
            scores: players.map(\.score),
            roundNumber: roundNumber,
            scoreChange: scoreChange,
            winner: winner,
            loser: loser,
            landlord: landlord,
            winners: winners,
            losers: losers,
            farmers: farmers,
            participants: players.map { player in
                ParticipantScoreSnapshot(
                    id: "player_\(player.id + 1)",
                    name: player.name,
                    score: player.score,
                    role: landlord.map {
                        $0 == doudizhuRecordTeam(player.id) ? "landlord" : "farmer"
                    }
                )
            },
            operationCode: operationCode
        )
    }

    private func handleExitAttempt(fromMenu: Bool) {
        if fromMenu {
            if menuConfirm.armOrConfirm(.exit) {
                toastMessage = nil
                showMenu = false
                saveRecord(finished: gameFinished)
                performScoreboardExit(
                    onNavigationBack: onNavigationBack,
                    dismiss: dismiss
                )
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
            performScoreboardExit(
                onNavigationBack: onNavigationBack,
                dismiss: dismiss
            )
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
                  !showScorePanel,
                  !styleEditorEntry.isEditing else { return }
            let now = Date().timeIntervalSince1970 * 1000
            if exitClickTime > 0, now - exitClickTime < 2000 { return }
            chromeVisible = false
        }
    }

    private func updateImmersiveForBlocking() {
        if showMenu || showDisplaySettings || isEditMode || showScorePanel || styleEditorEntry.isEditing || !appearance.immersiveMode {
            immersiveGeneration += 1
            chromeVisible = true
        } else {
            revealImmersiveChrome()
        }
    }
}

struct DoudizhuResumeState: Codable, Equatable {
    var schemaVersion: Int
    var playerCount: Int
    var names: [String]
    var scores: [Int]
    var finished: Bool
    var undoHistory: [[Int]]
    var intentTimeline: [String]
    var actionCount: Int
    var detailedActions: [DetailedScoreAction]
    var undoTimeline: [DoudizhuUndoTimelineCheckpoint]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case playerCount
        case names
        case scores
        case finished
        case undoHistory
        case intentTimeline
        case actionCount
        case detailedActions
        case undoTimeline
    }

    init(
        schemaVersion: Int = 3,
        playerCount: Int? = nil,
        names: [String],
        scores: [Int],
        finished: Bool,
        undoHistory: [[Int]] = [],
        intentTimeline: [String] = [],
        actionCount: Int = 0,
        detailedActions: [DetailedScoreAction] = [],
        undoTimeline: [DoudizhuUndoTimelineCheckpoint] = []
    ) {
        self.schemaVersion = schemaVersion
        self.playerCount = min(4, max(3, playerCount ?? max(names.count, scores.count)))
        self.names = names
        self.scores = scores
        self.finished = finished
        self.undoHistory = undoHistory
        self.intentTimeline = intentTimeline
        self.actionCount = actionCount
        self.detailedActions = detailedActions
        self.undoTimeline = undoTimeline
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        names = try container.decode([String].self, forKey: .names)
        scores = try container.decode([Int].self, forKey: .scores)
        playerCount = min(
            4,
            max(3, try container.decodeIfPresent(Int.self, forKey: .playerCount) ?? max(names.count, scores.count))
        )
        finished = try container.decode(Bool.self, forKey: .finished)
        undoHistory = try container.decodeIfPresent([[Int]].self, forKey: .undoHistory) ?? []
        intentTimeline = try container.decodeIfPresent([String].self, forKey: .intentTimeline) ?? []
        actionCount = try container.decodeIfPresent(Int.self, forKey: .actionCount) ?? undoHistory.count
        detailedActions = try container.decodeIfPresent([DetailedScoreAction].self, forKey: .detailedActions) ?? []
        undoTimeline = try container.decodeIfPresent([DoudizhuUndoTimelineCheckpoint].self, forKey: .undoTimeline) ?? []
    }
}

struct DoudizhuUndoTimelineCheckpoint: Codable, Equatable {
    let actionLogCount: Int
    let detailedActionsCount: Int
    let actionCount: Int
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
