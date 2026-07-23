import SwiftUI

struct WatchBasketballTrainingView: View {
    @Environment(\.dismiss) private var dismiss

    let mode: WatchBasketballTrainingMode

    @State private var history: [WatchBasketballTrainingShot] = []
    @State private var startTime = Date()
    @State private var savedRecordID: String?
    @State private var showMenu = false
    @State private var showEndDialog = false
    @State private var toastMessage: String?
    @State private var recentShotID: String?
    @State private var scoreboardLayout = "horizontal"
    @State private var suppressTapAfterLongPress = false

    var body: some View {
        ZStack {
            board
                .contentShape(Rectangle())
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.55)
                        .onEnded { _ in
                            guard !showMenu, !showEndDialog else { return }
                            suppressTapAfterLongPress = true
                            WatchHaptics.shared.play(.strong)
                            showMenu = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                suppressTapAfterLongPress = false
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 30)
                        .onEnded { value in
                            guard !showMenu, !showEndDialog else { return }
                            if value.translation.width > 55,
                               abs(value.translation.height) < 50 {
                                dismiss()
                            } else if value.translation.height > 40 {
                                undo()
                            }
                        }
                )

            if showMenu {
                menuOverlay
            }
            if showEndDialog {
                endOverlay
            }
            if let toastMessage {
                VStack {
                    Spacer()
                    WatchToastView(message: toastMessage)
                        .padding(.bottom, 16)
                }
            }
        }
        .background(.black)
        .ignoresSafeArea()
        .onAppear {
            scoreboardLayout = WatchPreferences.shared.scoreboardLayout
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = WatchPreferences.shared.scoreboardLayout
        }
    }

    @ViewBuilder
    private var board: some View {
        if let points = mode.fixedPoints {
            fixedBoard(points: points)
        } else {
            freeBoard
        }
    }

    private func fixedBoard(points: Int) -> some View {
        GeometryReader { proxy in
            let fullWidth = proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing
            let fullHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            Group {
                if scoreboardLayout == "horizontal" {
                    HStack(spacing: 0) {
                        trainingCell(
                            points: points,
                            made: false,
                            size: CGSize(width: fullWidth / 2, height: fullHeight)
                        )
                        trainingCell(
                            points: points,
                            made: true,
                            size: CGSize(width: fullWidth / 2, height: fullHeight)
                        )
                    }
                } else {
                    VStack(spacing: 0) {
                        trainingCell(
                            points: points,
                            made: false,
                            size: CGSize(width: fullWidth, height: fullHeight / 2)
                        )
                        trainingCell(
                            points: points,
                            made: true,
                            size: CGSize(width: fullWidth, height: fullHeight / 2)
                        )
                    }
                }
            }
            .frame(width: fullWidth, height: fullHeight)
            .offset(x: -proxy.safeAreaInsets.leading, y: -proxy.safeAreaInsets.top)
        }
    }

    private var freeBoard: some View {
        GeometryReader { proxy in
            let fullWidth = proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing
            let fullHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            Group {
                if scoreboardLayout == "horizontal" {
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            trainingCell(points: 1, made: false, size: .init(width: fullWidth / 2, height: fullHeight / 3))
                            trainingCell(points: 2, made: false, size: .init(width: fullWidth / 2, height: fullHeight / 3))
                            trainingCell(points: 3, made: false, size: .init(width: fullWidth / 2, height: fullHeight / 3))
                        }
                        VStack(spacing: 0) {
                            trainingCell(
                                points: 1,
                                made: true,
                                size: .init(width: fullWidth / 2, height: fullHeight / 3),
                                contentOffsetY: 22
                            )
                            trainingCell(points: 2, made: true, size: .init(width: fullWidth / 2, height: fullHeight / 3))
                            trainingCell(points: 3, made: true, size: .init(width: fullWidth / 2, height: fullHeight / 3))
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            trainingCell(points: 1, made: false, size: .init(width: fullWidth / 3, height: fullHeight / 2))
                            trainingCell(points: 2, made: false, size: .init(width: fullWidth / 3, height: fullHeight / 2))
                            trainingCell(
                                points: 3,
                                made: false,
                                size: .init(width: fullWidth / 3, height: fullHeight / 2),
                                contentOffsetY: 22
                            )
                        }
                        HStack(spacing: 0) {
                            trainingCell(points: 1, made: true, size: .init(width: fullWidth / 3, height: fullHeight / 2))
                            trainingCell(points: 2, made: true, size: .init(width: fullWidth / 3, height: fullHeight / 2))
                            trainingCell(points: 3, made: true, size: .init(width: fullWidth / 3, height: fullHeight / 2))
                        }
                    }
                }
            }
            .frame(width: fullWidth, height: fullHeight)
            .offset(x: -proxy.safeAreaInsets.leading, y: -proxy.safeAreaInsets.top)
        }
    }

    private func trainingCell(
        points: Int,
        made: Bool,
        size: CGSize,
        contentOffsetY: CGFloat = 0
    ) -> some View {
        let count = shotCount(points: points, made: made)
        let isRecent = history.last?.id == recentShotID
            && history.last?.points == points
            && history.last?.made == made
        return VStack(spacing: 1) {
            Text(
                made
                    ? NSLocalizedString("watch_training_made", value: "命中", comment: "")
                    : NSLocalizedString("watch_training_miss", value: "未中", comment: "")
            )
            .font(.system(size: mode == .free ? 10 : 14, weight: .medium))
            .foregroundStyle(.white.opacity(0.82))

            Text("\(count)")
                .font(.system(size: mode == .free ? 28 : 48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(
                String.localizedStringWithFormat(
                    NSLocalizedString("watch_training_point_value", value: "%d分", comment: ""),
                    points
                )
            )
            .font(.system(size: mode == .free ? 9 : 12))
            .foregroundStyle(.white.opacity(isRecent ? 1 : 0.64))
        }
        .offset(y: contentOffsetY)
        .frame(width: size.width, height: size.height)
        .background(made ? WatchTheme.successGreen : Color(hex: 0xD84343))
        .overlay {
            if isRecent {
                Color.white.opacity(0.14)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !showMenu, !showEndDialog, !suppressTapAfterLongPress else { return }
            addShot(points: points, made: made)
        }
    }

    private var menuOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { showMenu = false }

            VStack(spacing: 8) {
                menuButton(
                    title: NSLocalizedString("watch_undo", value: "撤销", comment: ""),
                    color: WatchTheme.card
                ) {
                    showMenu = false
                    undo()
                }
                menuButton(
                    title: NSLocalizedString("watch_bb_end_training", value: "结束训练", comment: ""),
                    color: WatchTheme.warningOrange
                ) {
                    showMenu = false
                    finishTraining()
                }
                menuButton(
                    title: NSLocalizedString("watch_reset", value: "重置", comment: ""),
                    color: Color(hex: 0x8E2430)
                ) {
                    reset()
                    showMenu = false
                }
                menuButton(
                    title: NSLocalizedString("watch_switch_layout", value: "切换布局", comment: ""),
                    color: Color(hex: 0x334155)
                ) {
                    WatchPreferences.shared.scoreboardLayout =
                        scoreboardLayout == "horizontal" ? "vertical" : "horizontal"
                    scoreboardLayout = WatchPreferences.shared.scoreboardLayout
                    showMenu = false
                }
            }
            .padding(14)
            .background(WatchTheme.overlayCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func menuButton(
        title: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 148, height: 36)
                .background(color)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var endOverlay: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            VStack(spacing: 10) {
                Text(NSLocalizedString("watch_bb_hit_rate", value: "命中率", comment: ""))
                    .font(.system(size: 14))
                    .foregroundStyle(WatchTheme.secondaryText)
                Text(hitRateText)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(WatchTheme.accent)
                Button {
                    restartAfterFinish()
                } label: {
                    Text(NSLocalizedString("watch_bb_restart", value: "再来一次", comment: ""))
                        .frame(width: 144, height: 42)
                }
                .buttonStyle(.plain)
                .background(WatchTheme.successGreen)
                .clipShape(Capsule())
                Button {
                    dismiss()
                } label: {
                    Text(NSLocalizedString("exit", value: "退出", comment: ""))
                        .frame(width: 144, height: 42)
                }
                .buttonStyle(.plain)
                .background(WatchTheme.card)
                .clipShape(Capsule())
            }
            .padding(18)
            .background(Color.black.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var totalAttempts: Int {
        history.count
    }

    private var totalMade: Int {
        history.lazy.filter(\.made).count
    }

    private var hitRateText: String {
        guard totalAttempts > 0 else { return "0/0 = 0%" }
        let percentage = Int((Double(totalMade) / Double(totalAttempts) * 100).rounded())
        return "\(totalMade)/\(totalAttempts) = \(percentage)%"
    }

    private func shotCount(points: Int, made: Bool) -> Int {
        history.lazy.filter { $0.points == points && $0.made == made }.count
    }

    private func addShot(points: Int, made: Bool) {
        let shot = WatchBasketballTrainingShot(points: points, made: made)
        history.append(shot)
        recentShotID = shot.id
        WatchHaptics.shared.play(made ? .score : .strong)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if recentShotID == shot.id {
                recentShotID = nil
            }
        }
    }

    private func undo() {
        guard history.popLast() != nil else { return }
        recentShotID = nil
        WatchHaptics.shared.play(.undo)
        showToast(NSLocalizedString("watch_undo_toast", value: "已撤销", comment: ""))
    }

    private func reset() {
        history = []
        recentShotID = nil
    }

    private func restartAfterFinish() {
        history = []
        startTime = Date()
        savedRecordID = nil
        recentShotID = nil
        showEndDialog = false
    }

    private func showToast(_ text: String) {
        toastMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toastMessage == text {
                toastMessage = nil
            }
        }
    }

    private func finishTraining() {
        guard savedRecordID == nil else {
            showEndDialog = true
            return
        }
        let endTime = Date()
        let modeName = mode.fixedPoints.map(String.init) ?? "free"
        var misses = 0
        var made = 0
        var actions = [
            WatchScoreAction(
                actionType: .gameStart,
                description: "training_start",
                team1Score: 0,
                team2Score: 0,
                timestamp: startTime
            )
        ]
        actions.append(contentsOf: history.map { shot in
            if shot.made {
                made += 1
            } else {
                misses += 1
            }
            return WatchScoreAction(
                actionType: .scoreAdd,
                description: trainingActionDescription(for: shot),
                team1Score: misses,
                team2Score: made,
                timestamp: shot.timestamp
            )
        })
        let percentage = history.isEmpty
            ? 0
            : Int((Double(made) / Double(history.count) * 100).rounded())
        actions.append(
            WatchScoreAction(
                actionType: .gameEnd,
                description: "training_rate_\(percentage)",
                team1Score: misses,
                team2Score: made,
                timestamp: endTime
            )
        )
        let recordID = "watch-basketballTraining-\(UUID().uuidString)"
        var projectConfiguration = [
            "type": "basketball_training",
            "gameMode": mode.fixedPoints.map { "\($0)pt" } ?? "free",
            "basketballTrainingMode": mode.fixedPoints == nil ? "mixed" : "fixed",
            "basketballTrainingScoringMode": mode.fixedPoints.map { "fixed_\($0)" } ?? "free",
            "trainingMode": modeName
        ]
        if let fixedPoints = mode.fixedPoints {
            projectConfiguration["targetScore"] = String(fixedPoints)
        }
        let record = WatchScoreboardRecord(
            id: recordID,
            gameType: .basketballTraining,
            startTime: startTime,
            endTime: endTime,
            duration: endTime.timeIntervalSince(startTime),
            team1Name: NSLocalizedString("watch_training_miss", value: "未中", comment: ""),
            team2Name: NSLocalizedString("watch_training_made", value: "命中", comment: ""),
            team1FinalScore: totalAttempts - totalMade,
            team2FinalScore: totalMade,
            team1SetScore: 0,
            team2SetScore: 0,
            winner: nil,
            actions: actions,
            totalScoreChanges: history.count,
            projectConfiguration: projectConfiguration,
            basketballTrainingDetails: WatchBasketballTrainingDetails(mode: mode, shots: history)
        )
        WatchRecordManager.shared.saveRecord(record)
        savedRecordID = recordID
        showEndDialog = true
    }

    private func trainingActionDescription(for shot: WatchBasketballTrainingShot) -> String {
        "training_\(shot.points)pt_\(shot.made ? "made" : "miss")"
    }
}
