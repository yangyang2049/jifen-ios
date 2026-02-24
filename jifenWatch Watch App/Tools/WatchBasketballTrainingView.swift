//
//  WatchBasketballTrainingView.swift
//  jifenWatch Watch App
//
//  Left = Shots (attempts), Right = Made. Swipe down undo, swipe up menu: End training.
//

import SwiftUI

struct WatchBasketballTrainingView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var shots: Int = 0
    @State private var made: Int = 0
    @State private var showMenu: Bool = false
    @State private var showEndDialog: Bool = false
    @State private var lastOperation: String? = nil // "shot" | "made"
    @State private var actionHistory: [(shots: Int, made: Int)] = []
    @State private var startTime: Date?
    @State private var toastMessage: String? = nil
    @State private var scoreboardLayout: String = "vertical"

    var body: some View {
        ZStack {
            layoutBoard
                .gesture(
                    DragGesture(minimumDistance: 30, coordinateSpace: .local)
                        .onEnded { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            if dx > 50 && abs(dy) < 50 {
                                dismiss()
                                return
                            }
                            if dy > 40 && !showEndDialog && !showMenu {
                                undo()
                            } else if dy < -40 && !showEndDialog && !showMenu {
                                showMenu = true
                            }
                        }
                )

            if showEndDialog {
                endOverlay
            }
            if showMenu {
                menuOverlay
            }
            if let toastMessage = toastMessage {
                VStack {
                    Spacer()
                    WatchToastView(message: toastMessage)
                        .padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
        .onAppear {
            scoreboardLayout = WatchPreferences.shared.scoreboardLayout
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = WatchPreferences.shared.scoreboardLayout
        }
    }

    private var layoutBoard: some View {
        GeometryReader { proxy in
            let boardWidth = proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing
            let boardHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            Group {
                if scoreboardLayout == "horizontal" {
                    HStack(spacing: 0) {
                        shotsColumn(size: CGSize(width: boardWidth / 2, height: boardHeight))
                        madeColumn(size: CGSize(width: boardWidth / 2, height: boardHeight))
                    }
                    .frame(width: boardWidth, height: boardHeight)
                } else {
                    VStack(spacing: 0) {
                        shotsColumn(size: CGSize(width: boardWidth, height: boardHeight / 2))
                        madeColumn(size: CGSize(width: boardWidth, height: boardHeight / 2))
                    }
                    .frame(width: boardWidth, height: boardHeight)
                }
            }
            .offset(x: -proxy.safeAreaInsets.leading, y: -proxy.safeAreaInsets.top)
        }
        .ignoresSafeArea()
    }

    private func shotsColumn(size: CGSize) -> some View {
        VStack(spacing: 4) {
            Text(NSLocalizedString("watch_bb_shots", comment: "Shots"))
                .font(.system(size: 14))
                .foregroundColor(Color.white.opacity(0.8))
            Text("\(shots)")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: size.width, height: size.height)
        .background(Color(hex: 0x1E88E5))
        .contentShape(Rectangle())
        .onTapGesture {
            if showEndDialog || showMenu { return }
            addShot()
        }
    }

    private func madeColumn(size: CGSize) -> some View {
        VStack(spacing: 4) {
            Text(NSLocalizedString("watch_bb_made", comment: "Made"))
                .font(.system(size: 14))
                .foregroundColor(Color.white.opacity(0.8))
            Text("\(made)")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: size.width, height: size.height)
        .background(Color(hex: 0x4CAF50))
        .contentShape(Rectangle())
        .onTapGesture {
            if showEndDialog || showMenu { return }
            addMade()
        }
    }

    private var endOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Text(NSLocalizedString("watch_bb_hit_rate", comment: "Hit rate"))
                    .font(.system(size: 16))
                    .foregroundColor(WatchTheme.primaryText)
                Text(hitRateText)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(WatchTheme.accent)
                VStack(spacing: 10) {
                    Button {
                        restart()
                    } label: {
                        Text(NSLocalizedString("watch_bb_restart", comment: "Restart"))
                            .frame(width: 144, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(WatchTheme.successGreen)
                    .foregroundColor(.white)
                    .cornerRadius(22)
                    Button {
                        saveAndExit()
                    } label: {
                        Text(NSLocalizedString("exit", value: "Exit", comment: "Exit"))
                            .frame(width: 144, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(WatchTheme.card)
                    .foregroundColor(.white)
                    .cornerRadius(22)
                }
                .padding(.top, 8)
            }
            .padding(20)
            .background(Color.black.opacity(0.75))
            .cornerRadius(16)
        }
    }

    private var menuOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { showMenu = false }

            VStack {
                Spacer(minLength: 0)
                VStack(spacing: 12) {
                    Button {
                        showMenu = false
                        showEndDialog = true
                    } label: {
                        Text(NSLocalizedString("watch_bb_end_training", comment: "End training"))
                            .frame(width: 160, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(WatchTheme.warningOrange)
                    .foregroundColor(.white)
                    .cornerRadius(22)
                    Button {
                        showMenu = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(WatchTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                }
                .padding(24)
                .background(WatchTheme.overlayCard)
                .cornerRadius(20)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var hitRateText: String {
        if shots <= 0 { return "0%" }
        let pct = Int(round(Double(made) / Double(shots) * 100))
        return "\(made)/\(shots) = \(pct)%"
    }

    private func addShot() {
        if startTime == nil { startTime = Date() }
        actionHistory.append((shots, made))
        shots += 1
        lastOperation = "shot"
        WatchHaptics.shared.play(.score)
    }

    private func addMade() {
        guard lastOperation == "shot" else {
            WatchHaptics.shared.play(.strong)
            showToast(NSLocalizedString("watch_bb_shot_first_toast", value: "请先记录出手", comment: "Shot first toast"))
            return
        }
        if startTime == nil { startTime = Date() }
        actionHistory.append((shots, made))
        made += 1
        lastOperation = "made"
        WatchHaptics.shared.play(.score)
    }

    private func undo() {
        guard let last = actionHistory.popLast() else { return }
        shots = last.shots
        made = last.made
        if actionHistory.isEmpty {
            lastOperation = nil
        } else {
            let prev = actionHistory.last!
            lastOperation = prev.shots < shots || prev.made < made ? "shot" : "made"
        }
        WatchHaptics.shared.play(.undo)
        showToast(NSLocalizedString("watch_undo_toast", value: "已撤销", comment: "Undo toast"))
    }

    private func showToast(_ text: String) {
        toastMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            toastMessage = nil
        }
    }

    private func restart() {
        shots = 0
        made = 0
        lastOperation = nil
        actionHistory = []
        showEndDialog = false
        startTime = nil
    }

    private func saveAndExit() {
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime ?? endTime)
        let record = WatchScoreboardRecord(
            id: "watch-basketballTraining-\(Int(endTime.timeIntervalSince1970))",
            gameType: .basketballTraining,
            startTime: startTime ?? endTime,
            endTime: endTime,
            duration: duration,
            team1Name: NSLocalizedString("watch_bb_shots", comment: "Shots"),
            team2Name: NSLocalizedString("watch_bb_made", comment: "Made"),
            team1FinalScore: shots,
            team2FinalScore: made,
            team1SetScore: 0,
            team2SetScore: 0,
            winner: nil,
            actions: [
                WatchScoreAction(actionType: .gameStart, description: NSLocalizedString("watch_match_start", comment: "Match start")),
                WatchScoreAction(actionType: .scoreAdd, description: "\(made)/\(shots)", team1Score: shots, team2Score: made, team1SetScore: 0, team2SetScore: 0)
            ],
            totalScoreChanges: shots + made
        )
        WatchRecordManager.shared.saveRecord(record)
        dismiss()
    }
}
