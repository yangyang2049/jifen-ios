//
//  DoudizhuScoreboardView.swift
//  jifen
//
//  斗地主计分：3 人，3 列布局，点击加分、撤销、编辑名称、保存记录。
//

import SwiftUI

private let defaultDoudizhuNames = ["地主", "农民1", "农民2"]
private let doudizhuTitle = "斗地主"

struct DoudizhuPlayerItem: Identifiable {
    let id: Int
    var name: String
    var score: Int
}

struct DoudizhuScoreboardView: View {
    @Environment(\.dismiss) var dismiss
    var initialSetup: SportsSetupResult? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil
    @State private var players: [DoudizhuPlayerItem] = defaultDoudizhuNames.enumerated().map { DoudizhuPlayerItem(id: $0.offset, name: $0.element, score: 0) }
    @State private var history: [[Int]] = []
    @State private var gameStartTime = Date()
    @State private var recordSaved = false
    @State private var showMenu = false
    @State private var isEditMode = false
    @State private var editingIndex: Int? = nil
    @State private var editName = ""
    @State private var activeCommonNameIndex: Int? = nil
    @State private var exitClickTime: TimeInterval = 0
    @State private var toastMessage: String? = nil

    private let commonNamesManager = CommonNamesManager.shared

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

                if !isEditMode {
                    bottomControls
                }

                if showMenu {
                    doudizhuMenuOverlay(geo: geo)
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
        .navigationTitle(NSLocalizedString("game_doudizhu", comment: "Doudizhu"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
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

    /// 玩家名称与分数字号参考羽毛球计分板（TeamSection nameFontSize 32、大分数约 120）
    private static let doudizhuNameFontSize: CGFloat = 32
    private static let doudizhuScoreFontSizeMin: CGFloat = 72
    private static let doudizhuScoreFontScale: CGFloat = 0.38

    private func doudizhuPlayerPanel(index: Int, player: DoudizhuPlayerItem, width: CGFloat, height: CGFloat) -> some View {
        let colors: [Color] = [
            Color(hex: "D32F2F"),
            Color(hex: "1976D2"),
            Color(hex: "388E3C")
        ]
        let scoreSize = max(Self.doudizhuScoreFontSizeMin, min(width, height) * Self.doudizhuScoreFontScale)
        return Button {
            if !isEditMode {
                addScore(index: index)
            }
        } label: {
            VStack(spacing: 12) {
                if isEditMode && editingIndex == index {
                    HStack(spacing: 6) {
                        TextField(NSLocalizedString("multi_score_player_default", value: "玩家", comment: ""), text: $editName)
                            .font(.system(size: Self.doudizhuNameFontSize, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.plain)
                            .onSubmit { confirmEdit(index: index) }

                        Button {
                            activeCommonNameIndex = index
                        } label: {
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
                } else {
                    Text(player.name)
                        .font(.system(size: Self.doudizhuNameFontSize, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .onTapGesture {
                            if isEditMode {
                                editingIndex = index
                                editName = player.name
                            }
                        }
                }
                Text("\(player.score)")
                    .font(.system(size: scoreSize, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(.white)
            }
            .frame(width: width, height: height)
            .background(colors[index % 3])
        }
        .buttonStyle(.plain)
    }

    private func doudizhuMenuOverlay(geo: GeometryProxy) -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { showMenu = false }
            VStack(spacing: 16) {
                Button {
                    undoLast()
                    showMenu = false
                } label: {
                    Text(NSLocalizedString("menu_undo", comment: "Undo"))
                        .frame(width: 200, height: 44)
                        .background(Theme.homeCardDark)
                        .foregroundColor(.white)
                        .cornerRadius(22)
                }
                .buttonStyle(.plain)
                .disabled(history.isEmpty)
                Button {
                    handleExitAttempt(fromMenu: true)
                } label: {
                    Text(NSLocalizedString("exit", value: "退出", comment: "Exit"))
                        .frame(width: 200, height: 44)
                        .background(Theme.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(22)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .background(Theme.homeCardDark)
            .cornerRadius(16)
        }
    }

    private func addScore(index: Int) {
        history.append(players.map { $0.score })
        if history.count > 50 { history.removeFirst() }
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

    private func saveRecordIfNeeded() {
        guard !recordSaved else { return }
        let totalChanges = history.count
        if totalChanges == 0 { return }
        let end = Date()
        let playersEnc: [AnyCodable] = players.map { p in
            AnyCodable(["name": AnyCodable(p.name), "finalScore": AnyCodable(p.score)])
        }
        let extraData: [String: AnyCodable] = [
            "players": AnyCodable(playersEnc),
            "playerCount": AnyCodable(3)
        ]
        let record = ScoreboardRecord(
            id: "doudizhu_\(Int(gameStartTime.timeIntervalSince1970))_\(Int(end.timeIntervalSince1970))",
            gameType: .doudizhu,
            startTime: gameStartTime,
            endTime: end,
            duration: end.timeIntervalSince(gameStartTime),
            team1Name: doudizhuTitle,
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
        DoudizhuScoreboardView()
    }
}
