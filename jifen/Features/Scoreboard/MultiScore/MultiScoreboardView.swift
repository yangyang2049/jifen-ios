//
//  MultiScoreboardView.swift
//  jifen
//
//  多人计分：支持 3-9 人，点击加分，支持编辑名称、撤销、重置与记录保存。
//

import ScoreCore
import SwiftUI
import UIKit

private func defaultMultiPlayerNames(count: Int) -> [String] {
    let base = NSLocalizedString("multi_score_player_default", value: "玩家", comment: "")
    return (1...count).map { "\(base) \($0)" }
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
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil

    @State private var players: [MultiPlayerItem]
    @State private var history: [[Int]] = []
    @State private var gameStartTime = Date()
    @State private var recordSaved = false
    @State private var showMenu = false
    @State private var isEditMode = false
    @State private var editingIndex: Int? = nil
    @State private var editName = ""
    @State private var initialSetupApplied = false
    @State private var activeCommonNameIndex: Int? = nil
    @State private var exitClickTime: TimeInterval = 0
    @State private var toastMessage: String? = nil
    @State private var gameFinished = false
    @State private var finishedWinnerName = ""
    @State private var showUnoRoundPanel = false
    @State private var unoRoundPlayerIndex: Int? = nil
    @State private var unoNumberTotal = 0
    @State private var unoAction20 = 0
    @State private var unoWild40 = 0
    @State private var unoWild50 = 0
    @State private var appearance = ScoreboardAppearanceSnapshot.current()
    @State private var showDisplaySettings = false
    @State private var showLocalSync = false
    @State private var previousIdleTimerDisabled: Bool?
    @State private var chromeVisible = true
    @State private var immersiveGeneration = 0

    private let commonNamesManager = CommonNamesManager.shared

    init(
        gameType: GameType = .multiScoreboard,
        defaultPlayerCount: Int = 4,
        targetScore: Int? = nil,
        initialSetup: SportsSetupResult? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        onNavigationBack: (() -> Void)? = nil
    ) {
        self.gameType = gameType
        let maxPlayers = gameType == .uno ? 10 : 9
        let minPlayers = gameType == .uno ? 2 : 2
        self.defaultPlayerCount = min(maxPlayers, max(minPlayers, defaultPlayerCount))
        self.targetScore = targetScore
        self.initialSetup = initialSetup
        self.onSetupConsumed = onSetupConsumed
        self.onNavigationBack = onNavigationBack
        _players = State(initialValue: defaultMultiPlayerNames(count: self.defaultPlayerCount).enumerated().map {
            MultiPlayerItem(id: $0.offset, name: $0.element, score: 0)
        })
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

                if shouldShowChrome { topTrailingEditButton }

                if !isEditMode && shouldShowChrome {
                    bottomControls
                }

                if showMenu {
                    MenuDialog(
                        isVisible: true,
                        onClose: { showMenu = false },
                        onMenuItemClick: handleMultiScoreMenuAction,
                        items: multiScoreMenuItems
                    )
                }

                if let message = toastMessage {
                    VStack {
                        Spacer()
                        ToastView(message: message)
                            .padding(.bottom, 24)
                    }
                }

                if gameFinished {
                    GameFinishedOverlay(winnerName: finishedWinnerName)
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
        .onAppear {
            applySetupIfNeeded()
            appearance = .current()
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            registerScoreboardSync()
            revealImmersiveChrome()
        }
        .onReceive(NotificationCenter.default.publisher(for: .scoreboardPreferencesDidChange)) { _ in
            appearance = .current()
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            revealImmersiveChrome()
        }
        .onDisappear {
            LocalScoreboardSyncCoordinator.shared.unregisterHost()
            if let previousIdleTimerDisabled { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled }
            saveRecordIfNeeded()
        }
        .sheet(isPresented: $showDisplaySettings) {
            ScoreboardDisplaySettingsView(gameType: gameType)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showLocalSync, onDismiss: registerScoreboardSync) { LocalSyncView() }
        .sheet(isPresented: $showUnoRoundPanel, onDismiss: resetUnoRoundPanel) {
            unoRoundPanel
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: Binding(
            get: { activeCommonNameIndex != nil },
            set: { if !$0 { activeCommonNameIndex = nil } }
        )) {
            CommonNameSelectorDialog(nameType: .player) { selectedName in
                if let index = activeCommonNameIndex, players.indices.contains(index) {
                    players[index].name = selectedName
                    if editingIndex == index {
                        editName = selectedName
                    }
                }
                activeCommonNameIndex = nil
            }
        }
    }

    private func scoreboardGrid(geo: GeometryProxy) -> some View {
        let columns = columnsForCurrentPlayers()
        let rows = Int(ceil(Double(players.count) / Double(columns)))
        let totalCells = rows * columns
        let extraCellCount = totalCells - players.count
        let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: columns)
        let cellHeight = geo.size.height / CGFloat(max(1, rows))

        return LazyVGrid(columns: gridColumns, spacing: 0) {
            ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                playerPanel(index: index, player: player, height: cellHeight)
            }
            ForEach(0..<max(0, extraCellCount - 1), id: \.self) { _ in
                extraCellPlaceholder(height: cellHeight, showEmoji: false)
            }
            if extraCellCount > 0 {
                extraCellPlaceholder(height: cellHeight, showEmoji: true)
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

    private var topTrailingEditButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    if isEditMode {
                        confirmEditIfNeeded()
                        editingIndex = nil
                    }
                    isEditMode.toggle()
                    VibrationManager.shared.vibrateMedium()
                } label: {
                    Image(systemName: isEditMode ? "checkmark" : "pencil")
                        .font(.system(size: ScoreboardConstants.buttonIconSize))
                        .foregroundColor(.white)
                        .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                        .background(
                            Circle().fill(isEditMode ? Color(hex: "00C853") : Color.black.opacity(0.25))
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
                .padding(.trailing, ScoreboardConstants.buttonPadding)
                .padding(.bottom, ScoreboardConstants.buttonPadding)
            }
        }
        .ignoresSafeArea(.all, edges: [.bottom, .leading, .trailing])
    }

    private func playerPanel(index: Int, player: MultiPlayerItem, height: CGFloat) -> some View {
        Button {
            if !isEditMode {
                if gameType == .uno {
                    openUnoRoundPanel(index: index)
                } else {
                    addScore(index: index)
                }
            } else {
                beginEdit(index: index)
            }
        } label: {
            GeometryReader { panelGeo in
                let nameFont = ScoreboardLayoutMetrics.playerGridNameFontSize(cellHeight: panelGeo.size.height)
                let scoreFont = ScoreboardLayoutMetrics.playerGridScoreFontSize(
                    cellHeight: panelGeo.size.height,
                    reservedHeight: nameFont + 16,
                    fontScale: scoreMultiplier
                )
                VStack(spacing: Theme.sm) {
                    if isEditMode && editingIndex == index {
                        HStack(spacing: 8) {
                            TextField(playerPlaceholder(index), text: $editName)
                                .font(.system(size: min(nameFont, 22), weight: .medium))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .textFieldStyle(.plain)
                                .onSubmit {
                                    confirmEdit(index: index)
                                }

                            Button {
                                activeCommonNameIndex = index
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9))
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, Theme.sm)
                        .padding(.vertical, Theme.xs)
                        .background(Color.black.opacity(0.15))
                        .cornerRadius(8)
                    } else {
                        Text(player.name)
                            .font(.system(size: nameFont, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, Theme.sm)
                    }

                    Text("\(player.score)")
                        .font(appearance.font.swiftUIFont(size: scoreFont))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: height)
            .background(panelColor(index: index))
        }
        .buttonStyle(.plain)
    }

    private var multiScoreMenuItems: [ScoreboardMenuItem] {
        let exitConfirming = exitClickTime > 0 &&
            Date().timeIntervalSince1970 * 1000 - exitClickTime < 2000
        return ScoreboardMenuItemBuilder.defaultItems(
            showEndGame: false,
            showExchangeSide: false,
            showWhistle: false,
            showScreenshot: false,
            extraItems: [
                ScoreboardMenuItem(
                    title: NSLocalizedString("exit", value: "退出", comment: "Exit"),
                    action: "exit",
                    group: .match,
                    icon: "rectangle.portrait.and.arrow.right",
                    keepDialogOpen: true,
                    confirming: exitConfirming
                )
            ]
        )
    }

    private func handleMultiScoreMenuAction(_ action: String) {
        switch action {
        case "undo":
            undoLast()
        case "reset":
            resetScores()
        case "displaySettings":
            showDisplaySettings = true
        case "localSync":
            showLocalSync = true
        case "exit":
            handleExitAttempt(fromMenu: true)
        default:
            break
        }
    }

    private func columnsForCurrentPlayers() -> Int {
        // HOS MultiGroupScore.getGridColumns() landscape path
        switch players.count {
        case 2: return 2
        case 3: return 3
        case 4: return 4
        case 5, 6: return 3
        case 7, 8: return 4
        case 9: return 5
        default: return 2
        }
    }

    private func panelColor(index: Int) -> Color {
        // Electronic / retro: pure black panels (HOS).
        if appearance.theme == .electronic || appearance.theme == .retro {
            return .black
        }
        return colors[index % colors.count]
    }

    private func playerPlaceholder(_ index: Int) -> String {
        let base = NSLocalizedString("multi_score_player_default", value: "玩家", comment: "")
        return "\(base) \(index + 1)"
    }

    private func beginEdit(index: Int) {
        editingIndex = index
        editName = players[index].name
    }

    private func confirmEdit(index: Int) {
        let name = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            players[index].name = name
            Task {
                await commonNamesManager.recordUsage(name, .player)
            }
        }
        editingIndex = nil
        editName = ""
    }

    private func confirmEditIfNeeded() {
        if let index = editingIndex {
            confirmEdit(index: index)
        }
    }

    private var effectiveTargetScore: Int {
        targetScore ?? (gameType == .uno ? 500 : Int.max)
    }

    private var unoRoundPanel: some View {
        NavigationStack {
            Form {
                if let index = unoRoundPlayerIndex, players.indices.contains(index) {
                    Section {
                        Text(players[index].name)
                            .font(.headline)
                    }
                }
                Section(NSLocalizedString("uno_number_points", value: "数字分", comment: "")) {
                    Stepper(value: $unoNumberTotal, in: 0...500, step: 1) {
                        Text("\(unoNumberTotal)")
                    }
                }
                Section(NSLocalizedString("uno_card_bonuses", value: "功能牌", comment: "")) {
                    Stepper(value: $unoAction20, in: 0...20) {
                        Text("+20 × \(unoAction20)")
                    }
                    Stepper(value: $unoWild40, in: 0...20) {
                        Text("+40 × \(unoWild40)")
                    }
                    Stepper(value: $unoWild50, in: 0...20) {
                        Text("+50 × \(unoWild50)")
                    }
                }
                Section {
                    Text(String(
                        format: NSLocalizedString("uno_round_total_format", value: "本回合合计 %d", comment: ""),
                        UnoRoundScore.total(number: unoNumberTotal, action20: unoAction20, wild40: unoWild40, wild50: unoWild50)
                    ))
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(NSLocalizedString("uno_round_settle_title", value: "UNO 回合计分", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", value: "取消", comment: "")) {
                        showUnoRoundPanel = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("confirm", value: "确认", comment: "")) {
                        confirmUnoRound()
                    }
                    .disabled(UnoRoundScore.total(number: unoNumberTotal, action20: unoAction20, wild40: unoWild40, wild50: unoWild50) <= 0)
                }
            }
        }
    }

    private func openUnoRoundPanel(index: Int) {
        guard !gameFinished else { return }
        unoRoundPlayerIndex = index
        unoNumberTotal = 0
        unoAction20 = 0
        unoWild40 = 0
        unoWild50 = 0
        showUnoRoundPanel = true
    }

    private func resetUnoRoundPanel() {
        unoRoundPlayerIndex = nil
        unoNumberTotal = 0
        unoAction20 = 0
        unoWild40 = 0
        unoWild50 = 0
    }

    private func confirmUnoRound() {
        guard let index = unoRoundPlayerIndex, players.indices.contains(index) else {
            showUnoRoundPanel = false
            return
        }
        let delta = UnoRoundScore.total(
            number: unoNumberTotal,
            action20: unoAction20,
            wild40: unoWild40,
            wild50: unoWild50
        )
        guard delta > 0 else { return }
        history.append(players.map(\.score))
        if history.count > 50 { history.removeFirst() }
        players[index].score += delta
        VibrationManager.shared.vibrateLight()
        LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        showUnoRoundPanel = false
        checkTargetReached(for: index)
    }

    private func checkTargetReached(for index: Int) {
        guard gameType == .uno else {
            if let targetScore, players[index].score >= targetScore {
                toastMessage = String(
                    format: NSLocalizedString("scoreboard_target_reached", value: "%@ 已达到目标分", comment: ""),
                    players[index].name
                )
            }
            return
        }
        let target = effectiveTargetScore
        if let winner = players.first(where: { $0.score >= target }) {
            gameFinished = true
            finishedWinnerName = winner.name
            VibrationManager.shared.vibrateHeavy()
        }
    }

    private func addScore(index: Int) {
        guard !gameFinished else { return }
        history.append(players.map { $0.score })
        if history.count > 50 {
            history.removeFirst()
        }
        players[index].score += 1
        checkTargetReached(for: index)
        VibrationManager.shared.vibrateLight()
        LocalScoreboardSyncCoordinator.shared.publishSnapshot()
    }

    private func undoLast() {
        guard let last = history.popLast() else { return }
        for i in players.indices where i < last.count {
            players[i].score = last[i]
        }
        if gameType == .uno {
            let target = effectiveTargetScore
            gameFinished = players.contains { $0.score >= target }
            finishedWinnerName = players.first(where: { $0.score >= target })?.name ?? ""
        }
        VibrationManager.shared.vibrateLight()
        LocalScoreboardSyncCoordinator.shared.publishSnapshot()
    }

    private func resetScores() {
        history.append(players.map { $0.score })
        if history.count > 50 {
            history.removeFirst()
        }
        for i in players.indices {
            players[i].score = 0
        }
        VibrationManager.shared.vibrateMedium()
        LocalScoreboardSyncCoordinator.shared.publishSnapshot()
    }

    private var scoreMultiplier: CGFloat {
        CGFloat(PreferencesManager.shared.fontSizeMultipliers(for: gameType)[ScoreboardFontMetric.score.rawValue] ?? 1)
    }

    private var shouldShowChrome: Bool {
        !appearance.immersiveMode || chromeVisible || isEditMode || showMenu || showDisplaySettings || showLocalSync
    }

    private func revealImmersiveChrome() {
        chromeVisible = true
        immersiveGeneration += 1
        guard appearance.immersiveMode, !isEditMode, !showMenu, !showDisplaySettings, !showLocalSync else { return }
        let generation = immersiveGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard generation == immersiveGeneration,
                  appearance.immersiveMode,
                  !isEditMode,
                  !showMenu,
                  !showDisplaySettings,
                  !showLocalSync else { return }
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
                    rightDetail: nil,
                    themeID: appearance.theme.rawValue,
                    fontID: appearance.font.rawValue,
                    finished: gameFinished || (gameType == .uno
                        ? players.contains { $0.score >= effectiveTargetScore }
                        : (targetScore.map { target in players.contains { $0.score >= target } } ?? false)),
                    revision: 0
                )
            },
            handleIntent: { intent in
                switch intent {
                case .addLeft: if !players.isEmpty { addScore(index: 0) }
                case .addRight: if players.count > 1 { addScore(index: 1) }
                case .subtractLeft, .subtractRight, .undo: undoLast()
                case .exchangeSides:
                    guard players.count > 1 else { return }
                    players.swapAt(0, 1)
                case .requestSnapshot: break
                }
            }
        )
    }

    private func applySetupIfNeeded() {
        guard !initialSetupApplied else { return }
        initialSetupApplied = true

        guard let setup = initialSetup else { return }

        let setupCount: Int
        let allowedRange: ClosedRange<Int> = gameType == .uno ? 2...10 : 3...9
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
            if !name1.isEmpty {
                names[0] = name1
            }
            if !name2.isEmpty && names.count > 1 {
                names[1] = name2
            }
        }

        players = names.enumerated().map { MultiPlayerItem(id: $0.offset, name: $0.element, score: 0) }
        onSetupConsumed?()
    }

    private func saveRecordIfNeeded() {
        guard !recordSaved else { return }
        let totalChanges = history.count
        if totalChanges == 0 { return }

        let end = Date()
        let playersEnc: [AnyCodable] = players.map { p in
            AnyCodable([
                "name": AnyCodable(p.name),
                "finalScore": AnyCodable(p.score),
            ])
        }
        let extraData: [String: AnyCodable] = [
            "players": AnyCodable(playersEnc),
            "playerCount": AnyCodable(players.count),
        ]
        let record = ScoreboardRecord(
            id: "\(gameType.canonicalScoreboardIdentifier)_\(Int(gameStartTime.timeIntervalSince1970))_\(Int(end.timeIntervalSince1970))",
            gameType: gameType,
            startTime: gameStartTime,
            endTime: end,
            duration: end.timeIntervalSince(gameStartTime),
            team1Name: gameType.displayName,
            team2Name: "",
            team1FinalScore: players.first?.score ?? 0,
            team2FinalScore: players.count > 1 ? players[1].score : 0,
            team1SetScore: nil,
            team2SetScore: nil,
            winner: nil,
            actions: [],
            totalScoreChanges: totalChanges,
            extraData: extraData
        )
        do {
            try ScoreboardRecordManager.shared.saveScoreboardRecord(record)
            recordSaved = true
            ScoreboardRecordsViewModel.shared.refreshRecords()
        } catch { }
    }

    private func handleExitAttempt(fromMenu: Bool) {
        let currentTime = Date().timeIntervalSince1970 * 1000
        if currentTime - exitClickTime < 2000 && exitClickTime > 0 {
            exitClickTime = 0
            toastMessage = nil
            showMenu = false
            confirmEditIfNeeded()
            saveRecordIfNeeded()
            OrientationLock.shared.unlock()
            onNavigationBack?()
            dismiss()
            return
        }

        exitClickTime = currentTime
        // Keep menu open so the second tap can confirm exit.
        toastMessage = NSLocalizedString("press_again_to_exit", comment: "Press again to exit")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if Date().timeIntervalSince1970 * 1000 - exitClickTime >= 2000 {
                toastMessage = nil
                exitClickTime = 0
            }
        }
    }
}

#Preview {
    NavigationStack {
        MultiScoreboardView()
    }
}
