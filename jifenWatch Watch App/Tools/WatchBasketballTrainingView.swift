import SwiftUI

struct WatchBasketballTrainingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchResumeSessionStore.self) private var resumeStore

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
    @State private var showFreeGuide = false
    @State private var confirmation: WatchScoreboardConfirmation?

    init(
        mode: WatchBasketballTrainingMode,
        resumedHistory: [WatchBasketballTrainingShot] = [],
        resumedStartTime: Date? = nil
    ) {
        self.mode = mode
        _history = State(initialValue: resumedHistory)
        _startTime = State(initialValue: resumedStartTime ?? Date())
    }

    var body: some View {
        ZStack {
            board
                .contentShape(Rectangle())
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: WatchTiming.longPressThreshold)
                        .onEnded { _ in
                            guard !showMenu, !showEndDialog, confirmation == nil else { return }
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
                            guard !showMenu, !showEndDialog, confirmation == nil else { return }
                            if value.translation.width > 55,
                               abs(value.translation.height) < 50 {
                                dismiss()
                            } else if value.translation.height > 40 {
                                undo()
                            }
                        }
                )

            if showMenu {
                trainingMenuOverlay
            }
            if showEndDialog {
                endOverlay
            }
            if showFreeGuide {
                freeGuideOverlay
            }
            if let confirmation {
                WatchConfirmationOverlay(
                    confirmation: confirmation,
                    titleOverride: confirmation == .finish
                        ? NSLocalizedString(
                            "watch_training_finish_confirm_title",
                            value: "结束训练？",
                            comment: ""
                        )
                        : nil,
                    messageOverride: confirmation == .finish
                        ? NSLocalizedString(
                            "watch_training_finish_confirm_message",
                            value: "将结束并保存本次训练。",
                            comment: ""
                        )
                        : nil,
                    onCancel: { self.confirmation = nil },
                    onConfirm: { confirmTraining(confirmation) }
                )
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
            if mode == .free {
                showFreeGuide = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showFreeGuide = false
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = WatchPreferences.shared.scoreboardLayout
        }
        .onChange(of: history) { _, _ in
            persistResumeSession()
        }
        .onDisappear {
            persistResumeSession()
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

    private var trainingMenuOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { showMenu = false }

            VStack(spacing: WatchLayout.isCompactScreen ? 5 : 6) {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: WatchLayout.isCompactScreen ? 5 : 6
                ) {
                    WatchMenuGridButton(
                        title: NSLocalizedString("menu_undo", value: "撤销", comment: ""),
                        systemImage: "arrow.uturn.backward"
                    ) {
                        showMenu = false
                        undo()
                    }
                    WatchMenuGridButton(
                        title: NSLocalizedString("watch_menu_restart", value: "重新开始", comment: ""),
                        systemImage: "arrow.counterclockwise"
                    ) {
                        showMenu = false
                        confirmation = .reset
                    }
                }
                WatchMenuGridButton(
                    title: NSLocalizedString("watch_bb_end_training", value: "结束训练", comment: ""),
                    systemImage: "flag.checkered",
                    background: WatchTheme.dangerRed
                ) {
                    showMenu = false
                    confirmation = .finish
                }
            }
            .padding(.horizontal, WatchLayout.isCompactScreen ? 20 : 26)
            .padding(.bottom, WatchLayout.isCompactScreen ? 5 : 7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .overlay(alignment: .top) {
                if !showMenu && !showEndDialog {
                    Text(
                        String.localizedStringWithFormat(
                            NSLocalizedString("watch_training_point_value", value: "%d分", comment: ""),
                            points
                        )
                    )
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.62))
                    .clipShape(Capsule())
                    .padding(.top, 6)
                    .allowsHitTesting(false)
                }
            }
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
                            trainingCell(points: 1, made: true, size: .init(width: fullWidth / 2, height: fullHeight / 3))
                            trainingCell(points: 2, made: true, size: .init(width: fullWidth / 2, height: fullHeight / 3))
                            trainingCell(points: 3, made: true, size: .init(width: fullWidth / 2, height: fullHeight / 3))
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            trainingCell(points: 1, made: false, size: .init(width: fullWidth / 3, height: fullHeight / 2))
                            trainingCell(points: 2, made: false, size: .init(width: fullWidth / 3, height: fullHeight / 2))
                            trainingCell(points: 3, made: false, size: .init(width: fullWidth / 3, height: fullHeight / 2))
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
            .overlay {
                freeDivisionLines
                    .allowsHitTesting(false)
            }
            .overlay {
                freePointBadges
                    .allowsHitTesting(false)
            }
        }
    }

    private func trainingCell(
        points: Int,
        made: Bool,
        size: CGSize
    ) -> some View {
        let count = shotCount(points: points, made: made)
        let isRecent = history.last?.id == recentShotID
            && history.last?.points == points
            && history.last?.made == made
        return VStack(spacing: 1) {
            if mode != .free {
                Text(
                    made
                        ? NSLocalizedString("watch_training_made", value: "命中", comment: "")
                        : NSLocalizedString("watch_training_miss", value: "未中", comment: "")
                )
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
            }

            Text("\(count)")
                .font(.system(size: mode == .free ? 30 : 64, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size.width, height: size.height)
        .background(made ? WatchTheme.successGreen : Color(hex: 0xD84343))
        .overlay {
            if isRecent {
                Color.white.opacity(0.14)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !showMenu, !showEndDialog, confirmation == nil,
                  !suppressTapAfterLongPress else { return }
            addShot(points: points, made: made)
        }
    }

    private var endOverlay: some View {
        ZStack {
            Color.black.opacity(0.40).ignoresSafeArea()
            VStack(spacing: WatchLayout.isCompactScreen ? 5 : 7) {
                Text(NSLocalizedString("watch_bb_hit_rate", value: "命中率", comment: ""))
                    .font(.system(size: WatchLayout.isCompactScreen ? 12 : 14))
                    .foregroundStyle(WatchTheme.secondaryText)
                Text(hitRateText)
                    .font(.system(
                        size: WatchLayout.isCompactScreen ? 17 : 19,
                        weight: .bold,
                        design: .rounded
                    ))
                    .foregroundStyle(WatchTheme.accent)
                if mode == .free {
                    VStack(spacing: 2) {
                        ForEach(1...3, id: \.self) { points in
                            Text(String.localizedStringWithFormat(
                                NSLocalizedString(
                                    "watch_training_breakdown_format",
                                    value: "%d分  %d/%d",
                                    comment: ""
                                ),
                                points,
                                shotCount(points: points, made: true),
                                shotCount(points: points, made: true) + shotCount(points: points, made: false)
                            ))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                        }
                    }
                }
                Button {
                    restartAfterFinish()
                } label: {
                    Text(NSLocalizedString("watch_bb_restart", value: "再来一次", comment: ""))
                        .frame(
                            width: WatchLayout.isCompactScreen ? 134 : 144,
                            height: WatchLayout.isCompactScreen ? 34 : 38
                        )
                }
                .buttonStyle(.plain)
                .background(WatchTheme.successGreen)
                .clipShape(Capsule())
                Button {
                    dismiss()
                } label: {
                    Text(NSLocalizedString("exit", value: "退出", comment: ""))
                        .frame(
                            width: WatchLayout.isCompactScreen ? 134 : 144,
                            height: WatchLayout.isCompactScreen ? 34 : 38
                        )
                }
                .buttonStyle(.plain)
                .background(WatchTheme.card)
                .clipShape(Capsule())
            }
            .padding(WatchLayout.isCompactScreen ? 10 : 12)
            .background(Color.black.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
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
        resumeStore.clear()
        history = []
        recentShotID = nil
    }

    private func restartAfterFinish() {
        resumeStore.clear()
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
        resumeStore.clear()
        savedRecordID = recordID
        showEndDialog = true
    }

    private func persistResumeSession() {
        guard savedRecordID == nil, !history.isEmpty else {
            resumeStore.clear()
            return
        }
        resumeStore.save(WatchResumeSession(
            startedAt: startTime,
            scoreLine: hitRateText,
            emoji: "🏀",
            payload: .basketballTraining(
                mode: mode,
                history: history
            )
        ))
    }

    private func trainingActionDescription(for shot: WatchBasketballTrainingShot) -> String {
        "training_\(shot.points)pt_\(shot.made ? "made" : "miss")"
    }

    private func confirmTraining(_ value: WatchScoreboardConfirmation) {
        confirmation = nil
        switch value {
        case .finish:
            finishTraining()
        case .reset:
            reset()
        }
    }

    private func pointBadge(_ points: Int) -> some View {
        Text("\(points)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.75))
            .frame(width: 18, height: 18)
            .background(Color.white.opacity(0.95))
            .clipShape(Circle())
    }

    @ViewBuilder
    private var freePointBadges: some View {
        if scoreboardLayout == "horizontal" {
            VStack(spacing: 0) {
                ForEach(1...3, id: \.self) { points in
                    pointBadge(points)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            HStack(spacing: 0) {
                ForEach(1...3, id: \.self) { points in
                    pointBadge(points)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var freeDivisionLines: some View {
        if scoreboardLayout == "horizontal" {
            VStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(Color.white.opacity(0.20))
                    .frame(height: 1)
                Spacer()
                Rectangle()
                    .fill(Color.white.opacity(0.20))
                    .frame(height: 1)
                Spacer()
            }
        } else {
            HStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: 1)
                Spacer()
                Rectangle()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: 1)
                Spacer()
            }
        }
    }

    private var freeGuideOverlay: some View {
        ZStack {
            Color.black.opacity(0.50).ignoresSafeArea()

            Group {
                if scoreboardLayout == "horizontal" {
                    HStack(spacing: 0) {
                        freeGuideLabel(
                            NSLocalizedString("watch_training_miss", value: "未中", comment: "")
                        )
                        Rectangle()
                            .fill(Color.white.opacity(0.28))
                            .frame(width: 1)
                        freeGuideLabel(
                            NSLocalizedString("watch_training_made", value: "命中", comment: "")
                        )
                    }
                } else {
                    VStack(spacing: 0) {
                        freeGuideLabel(
                            NSLocalizedString("watch_training_miss", value: "未中", comment: "")
                        )
                        Rectangle()
                            .fill(Color.white.opacity(0.28))
                            .frame(height: 1)
                        freeGuideLabel(
                            NSLocalizedString("watch_training_made", value: "命中", comment: "")
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func freeGuideLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
