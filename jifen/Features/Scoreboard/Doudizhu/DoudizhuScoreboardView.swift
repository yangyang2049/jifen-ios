//
//  DoudizhuScoreboardView.swift
//  jifen
//
//  斗地主计分：3 人，3 列布局，点击加分、撤销、编辑名称、保存记录。
//

import ScoreCore
import SwiftUI

private let defaultDoudizhuNames = [
    NSLocalizedString("doudizhu_player_adam", value: "刘备", comment: ""),
    NSLocalizedString("doudizhu_player_bob", value: "关羽", comment: ""),
    NSLocalizedString("doudizhu_player_chris", value: "张飞", comment: "")
]
private let doudizhuTitle = "斗地主"

struct DoudizhuPlayerItem: Identifiable {
    let id: Int
    var name: String
    var score: Int
}

struct DoudizhuScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil
    @State private var players: [DoudizhuPlayerItem]
    @State private var history: [[Int]] = []
    @State private var gameStartTime: Date
    @State private var recordID: String
    @State private var showMenu = false
    @State private var isEditMode = false
    @State private var editingIndex: Int? = nil
    @State private var editName = ""
    @State private var activeCommonNameIndex: Int? = nil
    @State private var exitClickTime: TimeInterval = 0
    @State private var resetClickTime: TimeInterval = 0
    @State private var settleClickTime: TimeInterval = 0
    @State private var toastMessage: String? = nil
    @State private var showScorePanel = false
    @State private var selectedBaseScore = 1
    @State private var selectedMultiplierPower = 0 // 0番=1倍 … 5番=32倍
    @State private var selectedWinners = [false, false, false]
    @State private var appearance = ScoreboardAppearanceSnapshot.current()
    @State private var preferences = PreferencesManager.shared
    @State private var gameFinished = false
    @State private var showGameFinishedOverlay = false
    @State private var showDisplaySettings = false
    @State private var showLocalSync = false
    @State private var actions: [String]

    private let commonNamesManager = CommonNamesManager.shared
    private let baseScoreOptions = [1, 2, 3]
    private let multiplierPowers = [0, 1, 2, 3, 4, 5]

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

        var start = Date()
        var id = "doudizhu_\(Int(start.timeIntervalSince1970))"
        var initialPlayers = defaultDoudizhuNames.enumerated().map {
            DoudizhuPlayerItem(id: $0.offset, name: $0.element, score: 0)
        }
        var finished = false
        var restoredActions: [String] = []

        if let initialRecordId,
           let record = ScoreboardRecordManager.shared.getRecordById(initialRecordId),
           record.status == .draft {
            start = record.startTime
            id = record.id
            restoredActions = record.actions
            if let data = record.stateSnapshot,
               let draft = try? JSONDecoder().decode(DoudizhuDraftSnapshot.self, from: data) {
                for (index, name) in draft.names.prefix(3).enumerated() where !name.isEmpty {
                    initialPlayers[index].name = name
                }
                for (index, score) in draft.scores.prefix(3).enumerated() {
                    initialPlayers[index].score = score
                }
                finished = draft.finished
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
        _gameStartTime = State(initialValue: start)
        _recordID = State(initialValue: id)
        _gameFinished = State(initialValue: finished)
        _showGameFinishedOverlay = State(initialValue: finished)
        _actions = State(initialValue: restoredActions)
    }

    /// HOS: left red / center success green (black in retro) / right blue
    private var panelColors: [Color] {
        let center: Color = appearance.theme == .retro ? .black : Color(hex: "4CAF50")
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
                Color.black.ignoresSafeArea()
                HStack(spacing: 0) {
                    ForEach(Array(players.enumerated()), id: \.element.id) { index, p in
                        doudizhuPlayerPanel(index: index, player: p, width: w / 3, height: h)
                    }
                }

                topTrailingEditButton

                if !isEditMode && !showScorePanel {
                    bottomControls
                    // Center + button opens HOS-style settle panel
                    VStack {
                        Spacer()
                        Button {
                            showScorePanel = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 60, height: 60)
                                .background(Circle().fill(Color.black.opacity(0.35)))
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 100)
                    }
                }

                if showMenu {
                    MenuDialog(
                        isVisible: true,
                        onClose: { showMenu = false },
                        onMenuItemClick: handleDoudizhuMenuAction,
                        items: doudizhuMenuItems
                    )
                }

                if showScorePanel {
                    doudizhuBottomSettleOverlay
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(20)
                }

                if showGameFinishedOverlay {
                    GameFinishedOverlay(winnerName: finishedWinnerName)
                }

                if let message = toastMessage {
                    VStack {
                        Spacer()
                        ToastView(message: message)
                            .padding(.bottom, 24)
                    }
                }
            }
            .animation(.easeOut(duration: 0.3), value: showScorePanel)
        }
        .ignoresSafeArea(.all)
        .navigationTitle(NSLocalizedString("game_doudizhu", comment: "Doudizhu"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .onAppear {
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
        }
        .onDisappear {
            saveRecord(finished: gameFinished)
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
        .sheet(isPresented: $showDisplaySettings) {
            ScoreboardDisplaySettingsView(gameType: .doudizhu)
        }
        .sheet(isPresented: $showLocalSync) { LocalSyncView() }
        .onChange(of: preferences.scoreboardRevision) { _, _ in
            appearance = .current()
        }
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

    private func doudizhuPlayerPanel(index: Int, player: DoudizhuPlayerItem, width: CGFloat, height: CGFloat) -> some View {
        let scoreSize = ScoreboardLayoutMetrics.mainScoreFontSize(halfViewportHeight: height) * 0.85
        let nameSize = ScoreboardLayoutMetrics.defaultTeamNameFontSize
        return ZStack {
            panelColors[index % 3]
            VStack(spacing: ScoreboardLayoutMetrics.mainToSetSpacing(halfViewportHeight: height)) {
                Text("\(player.score)")
                    .font(.system(size: scoreSize, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                if isEditMode && editingIndex == index {
                    HStack(spacing: 6) {
                        TextField(NSLocalizedString("multi_score_player_default", value: "玩家", comment: ""), text: $editName)
                            .font(.system(size: nameSize, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.plain)
                            .onSubmit { confirmEdit(index: index) }
                        Button { activeCommonNameIndex = index } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.12))
                    .cornerRadius(8)
                    .padding(.top, ScoreboardLayoutMetrics.nameTopPadding(panelHeight: height, isEditMode: true))
                } else {
                    Text(player.name)
                        .font(.system(size: nameSize, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, ScoreboardLayoutMetrics.nameTopPadding(panelHeight: height))
                        .onTapGesture {
                            if isEditMode {
                                editingIndex = index
                                editName = player.name
                            }
                        }
                }
                Spacer()
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditMode {
                editingIndex = index
                editName = player.name
            }
        }
    }

    /// HOS-style 320pt bottom settle overlay (not a system sheet).
    private var doudizhuBottomSettleOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
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
                                                .fill(selectedWinners[index] ? Color(hex: "007AFF") : Color.white.opacity(0.2))
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
                        .frame(width: UIScreen.main.bounds.width * 0.45, height: 50)
                        .background(Capsule().fill(doudizhuWinnerSelectionValid ? Color(hex: "007AFF") : Color.white.opacity(0.2)))
                }
                .buttonStyle(.plain)
                .disabled(!doudizhuWinnerSelectionValid)
                .padding(.vertical, 16)

                HStack {
                    Button { showScorePanel = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(Color.black.opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 20)
                    .padding(.bottom, 16)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .background(Color.black.opacity(0.8))
            .onAppear {
                if selectedWinners.allSatisfy({ !$0 }) {
                    selectedWinners = [true, false, false]
                }
            }
        }
        .ignoresSafeArea()
    }

    private func settleColumn<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            content()
        }
    }

    private func settleChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 45)
                .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color(hex: "007AFF") : Color.white.opacity(0.2)))
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
        let exitConfirming = exitClickTime > 0 &&
            Date().timeIntervalSince1970 * 1000 - exitClickTime < 2000
        let resetConfirming = resetClickTime > 0 &&
            Date().timeIntervalSince1970 * 1000 - resetClickTime < 2000
        let settleConfirming = settleClickTime > 0 &&
            Date().timeIntervalSince1970 * 1000 - settleClickTime < 2000
        return ScoreboardMenuItemBuilder.defaultItems(
            showEndGame: true,
            showExchangeSide: false,
            showWhistle: true,
            showScreenshot: true,
            showSettleMatch: true,
            resetConfirming: resetConfirming,
            finishConfirming: false,
            settleConfirming: settleConfirming,
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
        switch action {
        case "undo":
            undoLast()
        case "endGame":
            markFinished()
        case "settleMatch":
            confirmSettle()
        case "reset":
            confirmReset()
        case "exit":
            handleExitAttempt(fromMenu: true)
        case "displaySettings":
            showDisplaySettings = true
        case "localSync":
            showLocalSync = true
        default:
            break
        }
    }

    private func markFinished() {
        guard !gameFinished else { return }
        gameFinished = true
        actions.append("\(Int64(Date().timeIntervalSince1970 * 1_000))|finish")
        showGameFinishedOverlay = true
        showScorePanel = false
        saveRecord(finished: true)
        VibrationManager.shared.vibrateMedium()
    }

    private func confirmReset() {
        let now = Date().timeIntervalSince1970 * 1000
        guard now - resetClickTime < 2000, resetClickTime > 0 else {
            resetClickTime = now
            toastMessage = NSLocalizedString("press_again_to_reset", value: "再按一次重置", comment: "")
            return
        }
        resetClickTime = 0
        history.append(players.map(\.score))
        for index in players.indices { players[index].score = 0 }
        actions.append("\(Int64(Date().timeIntervalSince1970 * 1_000))|reset")
        gameFinished = false
        showGameFinishedOverlay = false
        showScorePanel = false
        saveRecord()
    }

    private func confirmSettle() {
        let now = Date().timeIntervalSince1970 * 1000
        guard now - settleClickTime < 2000, settleClickTime > 0 else {
            settleClickTime = now
            toastMessage = NSLocalizedString("click_again_to_settle_match", value: "再按一次结算", comment: "")
            return
        }
        settleClickTime = 0
        markFinished()
        showMenu = false
    }

    private func undoLast() {
        guard let last = history.popLast() else { return }
        for i in players.indices where i < last.count {
            players[i].score = last[i]
        }
        actions.append("\(Int64(Date().timeIntervalSince1970 * 1_000))|undo")
        VibrationManager.shared.vibrateLight()
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

    private func saveRecord(finished: Bool = false) {
        let totalChanges = history.count
        let hasProgress = totalChanges > 0 || players.contains(where: { $0.score != 0 }) || finished || gameFinished
        guard hasProgress else { return }
        let end = Date()
        let isFinished = finished || gameFinished
        let playersEnc: [[String: Any]] = players.map { p in
            ["name": p.name, "finalScore": p.score]
        }
        let draft = DoudizhuDraftSnapshot(
            names: players.map(\.name),
            scores: players.map(\.score),
            finished: isFinished
        )
        let snapshotData = try? JSONEncoder().encode(draft)
        var winner: String?
        if isFinished {
            let scores = players.map(\.score)
            if let best = scores.max(), scores.filter({ $0 == best }).count == 1,
               let index = scores.firstIndex(of: best) {
                winner = players[index].name
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
            winner: winner,
            actions: actions,
            totalScoreChanges: max(totalChanges, 1),
            extraData: [
                "players": AnyCodable(playersEnc),
                "playerNames": AnyCodable(players.map(\.name)),
                "playerCount": AnyCodable(3)
            ],
            stateSnapshot: snapshotData,
            status: isFinished ? .finished : .draft
        )
        try? ScoreboardRecordManager.shared.saveScoreboardRecord(record)
        ScoreboardRecordsViewModel.shared.refreshRecords()
    }

    private func handleExitAttempt(fromMenu: Bool) {
        let currentTime = Date().timeIntervalSince1970 * 1000
        if currentTime - exitClickTime < 2000 && exitClickTime > 0 {
            exitClickTime = 0
            toastMessage = nil
            showMenu = false
            confirmEditIfNeeded()
            saveRecord(finished: gameFinished)
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

private struct DoudizhuDraftSnapshot: Codable {
    var names: [String]
    var scores: [Int]
    var finished: Bool
}

#Preview {
    NavigationStack {
        DoudizhuScoreboardView()
    }
}
