//
//  MultiScoreboardView.swift
//  jifen
//
//  多人计分：支持 3-9 人，点击加分，支持编辑名称、撤销、重置与记录保存。
//

import SwiftUI

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
    var initialSetup: SportsSetupResult? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil

    @State private var players: [MultiPlayerItem] = defaultMultiPlayerNames(count: 4).enumerated().map {
        MultiPlayerItem(id: $0.offset, name: $0.element, score: 0)
    }
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

    private let commonNamesManager = CommonNamesManager.shared

    private let colors: [Color] = [
        Color(hex: "E53935"),
        Color(hex: "1E88E5"),
        Color(hex: "43A047"),
        Color(hex: "FB8C00"),
        Color(hex: "8E24AA"),
        Color(hex: "00897B"),
        Color(hex: "6D4C41"),
        Color(hex: "3949AB"),
        Color(hex: "C62828"),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                scoreboardGrid(geo: geo)

                topTrailingEditButton

                if !isEditMode {
                    bottomControls
                }

                if showMenu {
                    menuOverlay
                }

                if let message = toastMessage {
                    VStack {
                        Spacer()
                        ToastView(message: message)
                            .padding(.bottom, 24)
                    }
                }
            }
        }
        .ignoresSafeArea(.all)
        .navigationTitle(NSLocalizedString("game_multi_scoreboard", value: "多人计分", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .onAppear {
            applySetupIfNeeded()
        }
        .onDisappear {
            saveRecordIfNeeded()
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
        let rows = max(2, Int(ceil(Double(players.count) / Double(columns))))
        let totalCells = rows * columns
        let extraCellCount = totalCells - players.count
        let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: columns)
        let cellHeight = geo.size.height / CGFloat(rows)

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
                addScore(index: index)
            } else {
                beginEdit(index: index)
            }
        } label: {
            GeometryReader { panelGeo in
                let scoreFont = min(panelGeo.size.width, panelGeo.size.height) * 0.34
                VStack(spacing: Theme.sm) {
                    if isEditMode && editingIndex == index {
                        HStack(spacing: 8) {
                            TextField(playerPlaceholder(index), text: $editName)
                                .font(.system(size: 18, weight: .medium))
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
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, Theme.sm)
                    }

                    Text("\(player.score)")
                        .font(.system(size: scoreFont, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: height)
            .background(colors[index % colors.count])
        }
        .buttonStyle(.plain)
    }

    private var menuOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    showMenu = false
                }

            VStack(spacing: Theme.md) {
                menuActionButton(title: NSLocalizedString("menu_undo", comment: "Undo"), disabled: history.isEmpty) {
                    undoLast()
                    showMenu = false
                }

                menuActionButton(title: NSLocalizedString("menu_reset", comment: "Reset")) {
                    resetScores()
                    showMenu = false
                }

                menuActionButton(title: NSLocalizedString("exit", value: "退出", comment: "Exit"), primary: true) {
                    handleExitAttempt(fromMenu: true)
                }
            }
            .padding(Theme.lg)
            .background(Theme.homeCardDark)
            .cornerRadius(16)
        }
    }

    private func menuActionButton(title: String, disabled: Bool = false, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .frame(width: 220, height: 44)
                .background(primary ? Theme.accentColor : Theme.homeCardDark.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.white.opacity(primary ? 0 : 0.12), lineWidth: primary ? 0 : 1)
                )
                .cornerRadius(22)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }

    private func columnsForCurrentPlayers() -> Int {
        switch players.count {
        case 3:
            return 3
        case 4:
            return 2
        case 5, 6:
            return 3
        case 7, 8, 9:
            return 3
        default:
            return 2
        }
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

    private func addScore(index: Int) {
        history.append(players.map { $0.score })
        if history.count > 50 {
            history.removeFirst()
        }
        players[index].score += 1
        VibrationManager.shared.vibrateLight()
    }

    private func undoLast() {
        guard let last = history.popLast() else { return }
        for i in players.indices where i < last.count {
            players[i].score = last[i]
        }
        VibrationManager.shared.vibrateLight()
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
    }

    private func applySetupIfNeeded() {
        guard !initialSetupApplied else { return }
        initialSetupApplied = true

        guard let setup = initialSetup else { return }

        let setupCount: Int
        if let count = setup.playerCount, (3...9).contains(count) {
            setupCount = count
        } else {
            setupCount = 4
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
            id: "multi_\(Int(gameStartTime.timeIntervalSince1970))_\(Int(end.timeIntervalSince1970))",
            gameType: .multiScoreboard,
            startTime: gameStartTime,
            endTime: end,
            duration: end.timeIntervalSince(gameStartTime),
            team1Name: NSLocalizedString("game_multi_scoreboard", value: "多人计分", comment: ""),
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
            if fromMenu { showMenu = false }
            confirmEditIfNeeded()
            saveRecordIfNeeded()
            OrientationLock.shared.unlock()
            onNavigationBack?()
            dismiss()
            return
        }

        exitClickTime = currentTime
        if fromMenu { showMenu = false }
        toastMessage = NSLocalizedString("press_again_to_exit", comment: "Press again to exit")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if Date().timeIntervalSince1970 * 1000 - exitClickTime >= 2000 {
                toastMessage = nil
            }
        }
    }
}

#Preview {
    NavigationStack {
        MultiScoreboardView()
    }
}
