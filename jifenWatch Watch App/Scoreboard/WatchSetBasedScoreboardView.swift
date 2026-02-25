import SwiftUI

struct WatchScoreboardView<Rules: WatchGameRules>: View {
    @Environment(\.dismiss) private var dismiss

    let rules: Rules

    @State private var redScore = 0
    @State private var blueScore = 0
    @State private var redGames = 0
    @State private var blueGames = 0
    @State private var redSets = 0
    @State private var blueSets = 0
    @State private var winner: String? = nil
    @State private var isStopped = false
    @State private var isFinished = false
    @State private var isManualFinish = false
    @State private var isTiebreak = false
    @State private var showMenu = false
    @State private var showSwapChip = false
    @State private var swapChipText = ""
    @State private var swapChipOpacity: Double = 0
    @State private var isResting = false
    @State private var restTitle = ""
    @State private var restRemaining = 0
    @State private var restFinished = false
    @State private var restCardOpacity: Double = 1
    @State private var undoButtonVisible = false

    @State private var history: [ScoreSnapshot] = []
    @State private var midGameRestTaken = false
    @State private var decidingSetSwapDone = false
    @State private var pendingNextSetReset = false
    @State private var recordSaved = false
    @State private var actions: [WatchScoreAction] = []

    @State private var restTimer: Timer? = nil
    @State private var undoHideTimer: Timer? = nil
    @State private var showDecidingSetSwapOverlay = false

    @State private var toastMessage: String? = nil

    @State private var matchStartTime = Date()
    @State private var currentSetStartTime = Date()

    /// "vertical" = red top, blue bottom; "horizontal" = red left, blue right. Persisted in WatchPreferences.
    @State private var scoreboardLayout: String = "vertical"

    /// Badminton only: who is serving (rally scoring: scorer gets serve; new set: loser serves first).
    @State private var servingIsRed: Bool = true

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let boardWidth = proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing
                let boardHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
                Group {
                    if scoreboardLayout == "horizontal" {
                        HStack(spacing: 0) {
                            scoreboardSide(isRed: true, size: CGSize(width: boardWidth / 2, height: boardHeight))
                            scoreboardSide(isRed: false, size: CGSize(width: boardWidth / 2, height: boardHeight))
                        }
                        .frame(width: boardWidth, height: boardHeight)
                    } else {
                        VStack(spacing: 0) {
                            scoreboardSide(isRed: true, size: CGSize(width: boardWidth, height: boardHeight / 2))
                            scoreboardSide(isRed: false, size: CGSize(width: boardWidth, height: boardHeight / 2))
                        }
                        .frame(width: boardWidth, height: boardHeight)
                    }
                }
                .offset(x: -proxy.safeAreaInsets.leading, y: -proxy.safeAreaInsets.top)
            }
            .ignoresSafeArea()
            .gesture(dragGesture)

            if isStopped {
                stoppedOverlay
            }

            if showMenu {
                menuOverlay
            }

            if isResting {
                restOverlay
            }

            if showDecidingSetSwapOverlay {
                decidingSetSwapOverlay
            }
            
            if isTiebreak && !isStopped && !isResting && !showMenu {
                Text(NSLocalizedString("watch_tiebreak_indicator", value: "抢七", comment: "Tiebreak indicator"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black)
                    .cornerRadius(4)
            }

            if showSwapChip {
                swapChip
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
        .background(WatchTheme.background)
        .ignoresSafeArea()
        .onAppear {
            scoreboardLayout = WatchPreferences.shared.scoreboardLayout
            if scoreboardLayout != "vertical" && scoreboardLayout != "horizontal" {
                scoreboardLayout = "vertical"
            }
            matchStartTime = Date()
            currentSetStartTime = Date()
            actions = [WatchScoreAction(actionType: .gameStart, description: NSLocalizedString("watch_match_start", comment: "Match start"))]
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = WatchPreferences.shared.scoreboardLayout
        }
        .onDisappear {
            restTimer?.invalidate()
            restTimer = nil
            undoHideTimer?.invalidate()
            undoHideTimer = nil

            if !recordSaved && (redScore > 0 || blueScore > 0 || redGames > 0 || blueGames > 0 || redSets > 0 || blueSets > 0) {
                saveMatchRecord()
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onEnded { value in
                if showMenu || isResting || showDecidingSetSwapOverlay || isStopped {
                    return
                }
                let dx = value.translation.width
                let dy = value.translation.height
                // 右滑返回（从左边缘向右）：与系统返回手势一致，优先于上下滑
                if dx > 50 && abs(dy) < 50 {
                    dismiss()
                    return
                }
                if dy > 40 {
                    undoScore()
                } else if dy < -40 {
                    showMenu = true
                }
            }
    }

    /// Whether the given side (red/blue) is currently serving. Aligned with Harmony isServingTeam.
    /// Badminton: rally scoring — scorer gets serve; new set — loser of previous set serves first.
    /// Ping pong: rotate every 2 points, first server alternates by set. Tennis: rotate each game.
    /// Pickleball: not shown (ball-possession/side-out rules are complex; server indicator disabled for now).
    private func isServing(isRed: Bool) -> Bool {
        if rules.gameType == .badminton {
            return isRed == servingIsRed
        }
        if rules.gameType == .tennis {
            let totalGames = redGames + blueGames
            let firstServerIsRed = (currentSetNumber % 2 == 1)
            let servingIsRed = firstServerIsRed == (totalGames % 2 == 0)
            return isRed == servingIsRed
        }
        let totalPointsInSet = redScore + blueScore
        let firstServerIsRed = (currentSetNumber % 2 == 1)
        let pairsOfPoints = totalPointsInSet / 2
        let computedServingIsRed = firstServerIsRed == (pairsOfPoints % 2 == 0)
        return isRed == computedServingIsRed
    }

    private var currentSetNumber: Int {
        redSets + blueSets + 1
    }

    private func scoreboardSide(isRed: Bool, size: CGSize) -> some View {
        ZStack {
            if rules.gameType == .tennis {
                tennisLayout(isRed: isRed)
            } else {
                defaultLayout(isRed: isRed)
            }
            serverIndicatorOverlay(isRed: isRed, size: size)
        }
        .frame(width: size.width, height: size.height)
        .background(isRed ? Color(hex: 0xE53935) : Color(hex: 0x1E88E5))
        .opacity(isStopped && winner != nil && winner != (isRed ? "red" : "blue") ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            addPoint(isRed: isRed)
        }
    }

    @ViewBuilder
    private func serverIndicatorOverlay(isRed: Bool, size: CGSize) -> some View {
        if rules.gameType != .pickleball && isServing(isRed: isRed) {
            let direction: WatchServerIndicatorDirection = scoreboardLayout == "horizontal" ? (isRed ? .right : .left) : (isRed ? .bottom : .top)
            let alignment: Alignment = scoreboardLayout == "horizontal" ? (isRed ? .leading : .trailing) : (isRed ? .top : .bottom)
            let insets = EdgeInsets(
                top: alignment == .top ? 0 : 12,
                leading: alignment == .leading ? 0 : 12,
                bottom: alignment == .bottom ? 0 : 12,
                trailing: alignment == .trailing ? 0 : 12
            )
            WatchServerIndicator(direction: direction, size: 14, color: WatchTheme.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                .padding(insets)
                .allowsHitTesting(false)
        }
    }
    
    private func defaultLayout(isRed: Bool) -> some View {
        let setScore = isRed ? redSets : blueSets
        let pointScore = rules.displayScore(for: isRed ? redScore : blueScore, isTiebreak: isTiebreak)
        let mainScoreFontSize: CGFloat = scoreboardLayout == "horizontal" ? 64 : 72
        let sideScoreYOffset: CGFloat = 56

        return ZStack {
            if scoreboardLayout == "horizontal" {
                Text(pointScore)
                    .font(.system(size: mainScoreFontSize, weight: .bold))
                    .foregroundColor(.white)

                if redSets + blueSets > 0 {
                    Text("\(setScore)")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.65))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .offset(y: sideScoreYOffset)
                }
            } else {
                if redSets + blueSets > 0 {
                    HStack {
                        Text("\(setScore)")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.65))
                            .padding(.leading, 20)
                        Spacer()
                    }
                }

                Text(pointScore)
                    .font(.system(size: mainScoreFontSize, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }

    private func tennisLayout(isRed: Bool) -> some View {
        let gameScore = isRed ? redGames : blueGames
        let setScore = isRed ? redSets : blueSets
        let pointScore = rules.displayScore(for: isRed ? redScore : blueScore, isTiebreak: isTiebreak)
        let mainScoreFontSize: CGFloat = scoreboardLayout == "horizontal" ? 64 : 72
        let setDotsYOffset: CGFloat = -56
        let gameScoreYOffset: CGFloat = 56

        return ZStack {
            if scoreboardLayout == "horizontal" {
                Text(pointScore)
                    .font(.system(size: mainScoreFontSize, weight: .bold))
                    .foregroundColor(.white)

                if redSets + blueSets > 0 {
                    HStack(spacing: 4) {
                        ForEach(0..<setScore, id: \.self) { _ in
                            Circle()
                                .fill(Color.white.opacity(0.65))
                                .frame(width: 10, height: 10)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .offset(y: setDotsYOffset)
                }

                if redGames + blueGames > 0 {
                    Text("\(gameScore)")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.65))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .offset(y: gameScoreYOffset)
                }
            } else {
                HStack {
                    if redGames + blueGames > 0 {
                        Text("\(gameScore)")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.65))
                            .padding(.leading, 20)
                    } else {
                        Spacer().frame(width: 20)
                    }
                    Spacer()
                    if redSets + blueSets > 0 {
                        VStack(spacing: 4) {
                            ForEach(0..<setScore, id: \.self) { _ in
                                Circle()
                                    .fill(Color.white.opacity(0.65))
                                    .frame(width: 10, height: 10)
                            }
                        }
                        .padding(.trailing, 20)
                    } else {
                        Spacer().frame(width: 20)
                    }
                }

                Text(pointScore)
                    .font(.system(size: mainScoreFontSize, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }


    private var stoppedOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(isFinished ? "🏁" : "⏸")
                        .font(.system(size: 28, weight: .bold))
                    Text(isFinished ? NSLocalizedString("watch_match_finished", comment: "Match finished") : NSLocalizedString("watch_stop", comment: "Stop"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    if isFinished, let w = winner {
                        Text(winnerResultText(winnerSide: w))
                            .font(.system(size: 14))
                            .foregroundColor(WatchTheme.accent)
                    }
                }

                VStack(spacing: 8) {
                    if isFinished {
                        if !isManualFinish && undoButtonVisible {
                            Button {
                                handleUndoFromOverlay()
                            } label: {
                                Text(NSLocalizedString("menu_undo", comment: "Undo"))
                                    .frame(width: 160, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .frame(width: 160, height: 44)
                            .background(WatchTheme.card)
                            .foregroundColor(.white)
                            .cornerRadius(22)
                        } else {
                            Button {
                                resetMatch()
                            } label: {
                                Text(NSLocalizedString("watch_play_again", value: "Play Again", comment: "Play again"))
                                    .frame(width: 160, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .frame(width: 160, height: 44)
                            .background(WatchTheme.successGreen)
                            .foregroundColor(.white)
                            .cornerRadius(22)
                        }
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text(NSLocalizedString("exit", value: "Exit", comment: "Exit"))
                            .frame(width: 140, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: 140, height: 44)
                    .background(WatchTheme.card)
                    .foregroundColor(.white)
                    .cornerRadius(22)
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 24)
            .background(Color.black.opacity(0.65))
            .cornerRadius(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var menuOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    showMenu = false
                }

            VStack(spacing: 10) {
                Text(rules.setOptionsText)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.9))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    Button {
                        undoScore()
                        showMenu = false
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 22, weight: .medium))
                            Text(NSLocalizedString("menu_undo", comment: "Undo"))
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(WatchTheme.card)
                    .foregroundColor(.white)
                    .cornerRadius(12)

                    Button {
                        endMatchFromMenu()
                        showMenu = false
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "flag.checkered")
                                .font(.system(size: 22, weight: .medium))
                            Text(NSLocalizedString("watch_end_match", value: "End", comment: "End match"))
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(WatchTheme.dangerRed)
                    .foregroundColor(.white)
                    .cornerRadius(12)

                    Button {
                        resetMatch()
                        showMenu = false
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 22, weight: .medium))
                            Text(NSLocalizedString("menu_reset", comment: "Reset"))
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(WatchTheme.card)
                    .foregroundColor(.white)
                    .cornerRadius(12)

                    Button {
                        toggleLayout()
                        showMenu = false
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: scoreboardLayout == "vertical" ? "rectangle.split.2x1" : "rectangle.split.1x2")
                                .font(.system(size: 22, weight: .medium))
                            Text(scoreboardLayout == "vertical" ? NSLocalizedString("watch_layout_horizontal", comment: "Horizontal") : NSLocalizedString("watch_layout_vertical", comment: "Vertical"))
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(WatchTheme.card)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(12)

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
            .padding(12)
            .background(WatchTheme.overlayCard)
            .cornerRadius(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var restOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text(restTitle)
                    .font(.system(size: 20))
                    .foregroundColor(Color.white.opacity(0.85))

                Text(formatSeconds(restRemaining))
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(WatchTheme.timerAccent)
                    .opacity(restCardOpacity)

                if restTitle == NSLocalizedString("watch_rest_between_sets", value: "局间休息", comment: "Rest between sets") {
                    Text(NSLocalizedString("watch_swap_sides", value: "换边", comment: "Swap sides"))
                        .font(.system(size: 14))
                        .foregroundColor(WatchTheme.accent)
                }

                Button {
                    finishRestAndResume()
                } label: {
                    Text(NSLocalizedString("watch_continue", value: "继续", comment: "Continue"))
                        .frame(width: 160, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 160, height: 44)
                .background(restFinished ? WatchTheme.successGreen : WatchTheme.card)
                .foregroundColor(.white)
                .cornerRadius(22)

                if undoButtonVisible {
                    Button {
                        handleUndoFromOverlay()
                    } label: {
                        Text(NSLocalizedString("menu_undo", comment: "Undo"))
                            .frame(width: 160, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: 160, height: 44)
                    .background(WatchTheme.card)
                    .foregroundColor(.white)
                    .cornerRadius(22)
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 20)
            .background(Color.black.opacity(0.65))
            .cornerRadius(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 羽毛球等有局中休息的项目：决胜局换边用 overlay；关闭与射箭加分面板一致为 x 图标
    private var decidingSetSwapOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text(NSLocalizedString("watch_deciding_set_swap", value: "决胜局换边", comment: "Deciding set swap"))
                    .font(.system(size: 20))
                    .foregroundColor(Color.white.opacity(0.85))

                Button {
                    showDecidingSetSwapOverlay = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: WatchLayout.isCompactScreen ? 20 : 24))
                        .foregroundColor(WatchTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .frame(width: WatchLayout.isCompactScreen ? 36 : 44, height: WatchLayout.isCompactScreen ? 36 : 44)
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 24)
            .background(Color.black.opacity(0.65))
            .cornerRadius(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var swapChip: some View {
        VStack {
            Spacer()
            Text(swapChipText)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(hex: 0x4CAF50).opacity(0.65))
                .cornerRadius(18)
                .opacity(swapChipOpacity)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addPoint(isRed: Bool) {
        if isStopped || showMenu || isResting { return }

        saveHistory()
        if isRed {
            redScore += 1
        } else {
            blueScore += 1
        }
        if rules.gameType == .badminton {
            servingIsRed = isRed
        }
        rules.onScoreChange(redScore: &redScore, blueScore: &blueScore, redGames: &redGames, blueGames: &blueGames, redSets: &redSets, blueSets: &blueSets, isTiebreak: &isTiebreak)

        let teamName = isRed ? NSLocalizedString("watch_team_red", comment: "Red") : NSLocalizedString("watch_team_blue", comment: "Blue")
        actions.append(WatchScoreAction(
            actionType: .scoreAdd,
            description: String(format: NSLocalizedString("watch_score_add_format", value: "%@得分", comment: "Score add format"), teamName),
            team1Score: redScore,
            team2Score: blueScore,
            team1SetScore: redSets,
            team2SetScore: blueSets
        ))

        WatchHaptics.shared.play(.score)

        if let mid = rules.midGameRestAt, !midGameRestTaken {
            if redScore == mid || blueScore == mid {
                midGameRestTaken = true
                showUndoButton()
                startRest(title: NSLocalizedString("watch_mid_game_rest", value: "局中休息", comment: "Mid-game rest"), seconds: rules.restBetweenSets, allowAutoFinish: false)
            }
        }
        
        if rules.shouldEndGame(redScore: redScore, blueScore: blueScore, redGames: redGames, blueGames: blueGames, isTiebreak: isTiebreak) {
            handleGameEnd(winner: isRed ? "red" : "blue")
            return
        }

        if rules.shouldEndSet(redScore: redScore, blueScore: blueScore, redGames: redGames, blueGames: blueGames, isTiebreak: isTiebreak) {
            handleSetEnd(winner: isRed ? "red" : "blue")
        } else if let swapAt = rules.decidingSetSwapAt {
            let isDecidingSet = (redSets + blueSets + 1) == rules.maxSets
            if isDecidingSet && !decidingSetSwapDone && (redScore == swapAt || blueScore == swapAt) {
                decidingSetSwapDone = true
                if rules.midGameRestAt != nil {
                    showDecidingSetSwapOverlay = true
                } else {
                    showSwapReminder(NSLocalizedString("watch_deciding_set_swap", value: "决胜局换边", comment: "Deciding set swap"))
                }
            }
        }
    }
    
    private func handleGameEnd(winner: String) {
        if winner == "red" {
            redGames += 1
        } else {
            blueGames += 1
        }

        actions.append(WatchScoreAction(
            actionType: .scoreAdd,
            description: NSLocalizedString("watch_game_end", value: "局结束", comment: "Game end"),
            team1Score: redGames,
            team2Score: blueGames,
            team1SetScore: redSets,
            team2SetScore: blueSets
        ))

        redScore = 0
        blueScore = 0

        if rules.gameType == .tennis && (redGames + blueGames) % 2 != 0 {
            showSwapReminder(NSLocalizedString("watch_swap_sides", value: "换边", comment: "Swap sides"))
        }

        if rules.shouldStartTiebreak(redGames: redGames, blueGames: blueGames) {
            isTiebreak = true
            showToast(NSLocalizedString("watch_tiebreak_start", value: "进入抢七", comment: "Tiebreak start"))
            return
        }

        if rules.shouldEndSet(redScore: redScore, blueScore: blueScore, redGames: redGames, blueGames: blueGames, isTiebreak: isTiebreak) {
            handleSetEnd(winner: winner)
        }
    }

    private func handleSetEnd(winner: String) {
        let winningRed = winner == "red"
        if winningRed {
            redSets += 1
        } else {
            blueSets += 1
        }
        if rules.gameType == .badminton {
            servingIsRed = !winningRed
        }
        redGames = 0
        blueGames = 0
        redScore = 0
        blueScore = 0
        isTiebreak = false

        actions.append(WatchScoreAction(
            actionType: .setEnd,
            description: String(format: NSLocalizedString("watch_set_end_format", comment: "Set end format"), redSets + blueSets),
            team1Score: redScore,
            team2Score: blueScore,
            team1SetScore: redSets,
            team2SetScore: blueSets
        ))

        showToast(String(format: NSLocalizedString("watch_set_end_format", comment: "Set end format"), redSets + blueSets))

        let setsToWin = (rules.maxSets + 1) / 2
        let isGameFinished = redSets >= setsToWin || blueSets >= setsToWin

        if isGameFinished {
            isManualFinish = false
            isFinished = true
            isStopped = true
            self.winner = redSets > blueSets ? "red" : "blue"
            WatchHaptics.shared.play(.finish)
            showUndoButton()
            saveMatchRecord()
            return
        }

        pendingNextSetReset = true
        startRest(title: NSLocalizedString("watch_rest_between_sets", value: "局间休息", comment: "Rest between sets"), seconds: rules.restBetweenSets, allowAutoFinish: true)
    }

    private func startRest(title: String, seconds: Int, allowAutoFinish: Bool) {
        restTitle = title
        restRemaining = seconds
        restFinished = false
        restCardOpacity = 1
        isResting = true
        undoHideTimer?.invalidate() // keep undo visible on rest overlay

        restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if restRemaining > 0 {
                restRemaining -= 1
            }
            if restRemaining <= 0 {
                restFinished = true
                if allowAutoFinish {
                    restTimer?.invalidate()
                }
            }
        }
    }

    private func finishRestAndResume() {
        restTimer?.invalidate()
        restTimer = nil
        withAnimation(.easeIn(duration: 0.15)) {
            restCardOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            isResting = false
            restFinished = false
            restTitle = ""
            restRemaining = 0
            restCardOpacity = 1

            if pendingNextSetReset {
                startNextSet()
            }
        }
    }

    private func startNextSet() {
        redScore = 0
        blueScore = 0
        redGames = 0
        blueGames = 0
        isStopped = false
        isFinished = false
        isManualFinish = false
        winner = nil
        pendingNextSetReset = false
        midGameRestTaken = false
        decidingSetSwapDone = false
        currentSetStartTime = Date()

        showToast(String(format: NSLocalizedString("watch_set_start_format", value: "第%d局开始", comment: "Set start format"), redSets + blueSets + 1))
    }

    private func showSwapReminder(_ text: String) {
        swapChipText = text
        showSwapChip = true
        withAnimation(.easeInOut(duration: WatchAnimations.swapChipFade)) {
            swapChipOpacity = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: WatchAnimations.swapChipFade)) {
                swapChipOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showSwapChip = false
            }
        }
    }

    private func undoScore() {
        guard let snapshot = history.popLast() else { return }
        restore(snapshot)
        isManualFinish = false
        WatchHaptics.shared.play(.undo)
        showToast(NSLocalizedString("watch_undo_toast", value: "已撤销", comment: "Undo toast"))
        showUndoButton()
        recordSaved = false
        if actions.count > snapshot.actionsCount {
            actions = Array(actions.prefix(snapshot.actionsCount))
        }
    }

    private func saveHistory() {
        history.append(ScoreSnapshot(
            redScore: redScore,
            blueScore: blueScore,
            redGames: redGames,
            blueGames: blueGames,
            redSets: redSets,
            blueSets: blueSets,
            isStopped: isStopped,
            isFinished: isFinished,
            isManualFinish: isManualFinish,
            isResting: isResting,
            isTiebreak: isTiebreak,
            winner: winner,
            midGameRestTaken: midGameRestTaken,
            pendingNextSetReset: pendingNextSetReset,
            decidingSetSwapDone: decidingSetSwapDone,
            recordSaved: recordSaved,
            actionsCount: actions.count,
            servingIsRed: servingIsRed
        ))
    }

    private func restore(_ snapshot: ScoreSnapshot) {
        redScore = snapshot.redScore
        blueScore = snapshot.blueScore
        redGames = snapshot.redGames
        blueGames = snapshot.blueGames
        redSets = snapshot.redSets
        blueSets = snapshot.blueSets
        isStopped = snapshot.isStopped
        isFinished = snapshot.isFinished
        isManualFinish = snapshot.isManualFinish
        isResting = snapshot.isResting
        isTiebreak = snapshot.isTiebreak
        winner = snapshot.winner
        midGameRestTaken = snapshot.midGameRestTaken
        pendingNextSetReset = snapshot.pendingNextSetReset
        decidingSetSwapDone = snapshot.decidingSetSwapDone
        recordSaved = snapshot.recordSaved
        servingIsRed = snapshot.servingIsRed
    }

    private func endMatchFromMenu() {
        guard !isFinished else { return }
        isStopped = true
        isFinished = true
        isManualFinish = true
        undoButtonVisible = false
        undoHideTimer?.invalidate()
        undoHideTimer = nil
        if redSets > blueSets {
            winner = "red"
        } else if blueSets > redSets {
            winner = "blue"
        } else {
            winner = nil
        }
        WatchHaptics.shared.play(.finish)
        saveMatchRecord()
    }

    /// Reset match to 0-0, clear history and rest state (aligned with Harmony Watch).
    private func resetMatch() {
        restTimer?.invalidate()
        restTimer = nil
        undoHideTimer?.invalidate()
        undoHideTimer = nil
        redScore = 0
        blueScore = 0
        redGames = 0
        blueGames = 0
        redSets = 0
        blueSets = 0
        winner = nil
        isStopped = false
        isFinished = false
        isManualFinish = false
        isResting = false
        restFinished = false
        restRemaining = 0
        restTitle = ""
        restCardOpacity = 1
        midGameRestTaken = false
        decidingSetSwapDone = false
        pendingNextSetReset = false
        recordSaved = false
        showDecidingSetSwapOverlay = false
        undoButtonVisible = false
        servingIsRed = true
        history.removeAll()
        actions = [WatchScoreAction(actionType: .gameStart, description: NSLocalizedString("watch_match_start", comment: "Match start"))]
        matchStartTime = Date()
        currentSetStartTime = Date()
        showToast(NSLocalizedString("watch_reset_toast", comment: "Match reset"))
    }

    /// Toggle vertical (red top, blue bottom) / horizontal (red left, blue right) and persist.
    private func toggleLayout() {
        let next = scoreboardLayout == "vertical" ? "horizontal" : "vertical"
        scoreboardLayout = next
        WatchPreferences.shared.scoreboardLayout = next
    }

    private func saveMatchRecord() {
        guard !recordSaved else { return }
        let endTime = Date()
        let duration = endTime.timeIntervalSince(matchStartTime)
        let winnerName: String?
        let redName = NSLocalizedString("watch_team_red", comment: "Red")
        let blueName = NSLocalizedString("watch_team_blue", comment: "Blue")

        if let winner = winner {
            winnerName = winner == "red" ? redName : blueName
        } else if redSets != blueSets {
            winnerName = redSets > blueSets ? redName : blueName
        } else {
            winnerName = nil
        }
        let record = WatchScoreboardRecord(
            id: "watch-\(rules.gameType.rawValue)-\(Int(endTime.timeIntervalSince1970))",
            gameType: rules.gameType,
            startTime: matchStartTime,
            endTime: endTime,
            duration: duration,
            team1Name: redName,
            team2Name: blueName,
            team1FinalScore: rules.gameType == .tennis ? redGames : redScore,
            team2FinalScore: rules.gameType == .tennis ? blueGames : blueScore,
            team1SetScore: redSets,
            team2SetScore: blueSets,
            winner: winnerName,
            actions: actions,
            totalScoreChanges: actions.count
        )
        WatchRecordManager.shared.saveRecord(record)
        recordSaved = true
    }

    private func showUndoButton() {
        isManualFinish = false
        undoButtonVisible = true
        undoHideTimer?.invalidate()
        undoHideTimer = Timer.scheduledTimer(withTimeInterval: WatchTiming.undoCountdown, repeats: false) { _ in
            undoButtonVisible = false
        }
    }

    private func handleUndoFromOverlay() {
        undoScore()
        undoButtonVisible = false
    }

    /// 比赛结束弹窗：若有胜方则显示一行结果，如「红方 2-1 获胜」
    private func winnerResultText(winnerSide: String) -> String {
        let name = winnerSide == "red" ? NSLocalizedString("watch_team_red", comment: "Red") : NSLocalizedString("watch_team_blue", comment: "Blue")
        return String(format: NSLocalizedString("winner_result_format", comment: "Winner result"), name, redSets, blueSets)
    }

    private func showToast(_ text: String) {
        toastMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            toastMessage = nil
        }
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

private struct ScoreSnapshot {
    let redScore: Int
    let blueScore: Int
    let redGames: Int
    let blueGames: Int
    let redSets: Int
    let blueSets: Int
    let isStopped: Bool
    let isFinished: Bool
    let isManualFinish: Bool
    let isResting: Bool
    let isTiebreak: Bool
    let winner: String?
    let midGameRestTaken: Bool
    let pendingNextSetReset: Bool
    let decidingSetSwapDone: Bool
    let recordSaved: Bool
    let actionsCount: Int
    let servingIsRed: Bool
}

struct WatchSetBasedConfig {
    let gameType: WatchGameType
    let maxSets: Int
}

struct WatchSetBasedScoreboardView: View {
    let config: WatchSetBasedConfig

    var body: some View {
        // This is now a wrapper to maintain compatibility with the old name.
        // You can gradually replace its usages with WatchScoreboardView.
        switch config.gameType {
        case .pingpong:
            WatchScoreboardView(rules: WatchPingPongRules(maxSets: config.maxSets))
        case .badminton:
            WatchScoreboardView(rules: WatchBadmintonRules(maxSets: config.maxSets))
        case .tennis:
            WatchScoreboardView(rules: WatchTennisRules(maxSets: config.maxSets))
        case .pickleball:
            WatchScoreboardView(rules: WatchPickleballRules(maxSets: config.maxSets))
        case .archery, .basketballTraining:
            EmptyView()
        }
    }
}
