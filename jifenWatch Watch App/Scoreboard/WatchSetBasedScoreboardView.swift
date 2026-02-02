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

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    scoreboardSide(isRed: true, size: CGSize(width: proxy.size.width, height: proxy.size.height / 2))
                    scoreboardSide(isRed: false, size: CGSize(width: proxy.size.width, height: proxy.size.height / 2))
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
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
                Text("抢七")
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
        .background(WatchTheme.background)
        .ignoresSafeArea()
        .onAppear {
            matchStartTime = Date()
            currentSetStartTime = Date()
            actions = [WatchScoreAction(actionType: .gameStart, description: "比赛开始")]
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
                if value.translation.height > 40 {
                    undoScore()
                } else if value.translation.height < -40 {
                    showMenu = true
                }
            }
    }

    private func scoreboardSide(isRed: Bool, size: CGSize) -> some View {
        ZStack {
            if rules.gameType == .tennis {
                tennisLayout(isRed: isRed)
            } else {
                defaultLayout(isRed: isRed)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(isRed ? Color(hex: 0xE53935) : Color(hex: 0x1E88E5))
        .opacity(isStopped && winner != nil && winner != (isRed ? "red" : "blue") ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            addPoint(isRed: isRed)
        }
    }
    
    private func defaultLayout(isRed: Bool) -> some View {
        ZStack {
            if redSets + blueSets > 0 {
                HStack {
                    Text(isRed ? "\(redSets)" : "\(blueSets)")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.65))
                        .padding(.leading, 20)
                    Spacer()
                }
            }

            Text(rules.displayScore(for: isRed ? redScore : blueScore, isTiebreak: isTiebreak))
                .font(.system(size: 72, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private func tennisLayout(isRed: Bool) -> some View {
        ZStack {
            HStack {
                if redGames + blueGames > 0 {
                    Text(isRed ? "\(redGames)" : "\(blueGames)")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.65))
                        .padding(.leading, 20)
                } else {
                    Spacer().frame(width: 20)
                }
                Spacer()
                if redSets + blueSets > 0 {
                    VStack(spacing: 4) {
                        ForEach(0..<(isRed ? redSets : blueSets), id: \.self) { _ in
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

            Text(rules.displayScore(for: isRed ? redScore : blueScore, isTiebreak: isTiebreak))
                .font(.system(size: 72, weight: .bold))
                .foregroundColor(.white)
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
                    Text(isFinished ? "比赛结束" : "比赛暂停")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    if isFinished, let w = winner {
                        Text(winnerResultText(winnerSide: w))
                            .font(.system(size: 14))
                            .foregroundColor(WatchTheme.accent)
                    }
                }

                VStack(spacing: 8) {
                    if undoButtonVisible && isFinished {
                        Button {
                            handleUndoFromOverlay()
                        } label: {
                            Text("撤销")
                                .frame(width: 160, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: 160, height: 44)
                        .background(WatchTheme.card)
                        .foregroundColor(.white)
                        .cornerRadius(22)
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("退出")
                            .frame(width: 140, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: 140, height: 44)
                    .background(WatchTheme.successGreen)
                    .foregroundColor(.white)
                    .cornerRadius(22)
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 24)
            .background(Color.black.opacity(0.65))
            .cornerRadius(18)
        }
    }

    private var menuOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    showMenu = false
                    showToast("已撤销")
                }

            VStack(spacing: 12) {
                Text(rules.setOptionsText)
                    .font(.system(size: 16))
                    .foregroundColor(.white)

                Button {
                    undoScore()
                    showMenu = false
                } label: {
                    Text("撤销")
                        .frame(width: 160, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 160, height: 44)
                .background(WatchTheme.card)
                .foregroundColor(.white)
                .cornerRadius(22)

                Button {
                    handleStopToggle()
                    showMenu = false
                } label: {
                    Text(isStopped ? "继续" : "暂停")
                        .frame(width: 160, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 160, height: 44)
                .background(isStopped ? WatchTheme.successGreen : WatchTheme.warningOrange)
                .foregroundColor(.white)
                .cornerRadius(22)
            }
            .padding(16)
            .background(WatchTheme.overlayCard)
            .cornerRadius(16)
        }
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

                if restTitle == "局间休息" {
                    Text("换边")
                        .font(.system(size: 14))
                        .foregroundColor(WatchTheme.accent)
                }

                Button {
                    finishRestAndResume()
                } label: {
                    Text(restFinished ? "继续比赛" : "关闭")
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
                        Text("撤销")
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
    }

    /// 羽毛球等有局中休息的项目：决胜局换边用 overlay
    private var decidingSetSwapOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("决胜局换边")
                    .font(.system(size: 20))
                    .foregroundColor(Color.white.opacity(0.85))

                Button {
                    showDecidingSetSwapOverlay = false
                } label: {
                    Text("关闭")
                        .frame(width: 160, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 160, height: 44)
                .background(WatchTheme.card)
                .foregroundColor(.white)
                .cornerRadius(22)
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 24)
            .background(Color.black.opacity(0.65))
            .cornerRadius(18)
        }
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
        
        rules.onScoreChange(redScore: &redScore, blueScore: &blueScore, redGames: &redGames, blueGames: &blueGames, redSets: &redSets, blueSets: &blueSets, isTiebreak: &isTiebreak)

        actions.append(WatchScoreAction(
            actionType: .scoreAdd,
            description: "\(isRed ? "红方" : "蓝方")得分",
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
                startRest(title: "局中休息", seconds: rules.restBetweenSets, allowAutoFinish: false)
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
                    showSwapReminder("决胜局换边")
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
            description: "局结束",
            team1Score: redGames,
            team2Score: blueGames,
            team1SetScore: redSets,
            team2SetScore: blueSets
        ))

        redScore = 0
        blueScore = 0

        if rules.shouldStartTiebreak(redGames: redGames, blueGames: blueGames) {
            isTiebreak = true
            showToast("进入抢七")
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
        
        redGames = 0
        blueGames = 0
        redScore = 0
        blueScore = 0
        isTiebreak = false

        actions.append(WatchScoreAction(
            actionType: .setEnd,
            description: "第\(redSets + blueSets)局结束",
            team1Score: redScore,
            team2Score: blueScore,
            team1SetScore: redSets,
            team2SetScore: blueSets
        ))

        showToast("第\(redSets + blueSets)局结束")

        let setsToWin = (rules.maxSets + 1) / 2
        let isGameFinished = redSets >= setsToWin || blueSets >= setsToWin

        if isGameFinished {
            isFinished = true
            isStopped = true
            self.winner = redSets > blueSets ? "red" : "blue"
            WatchHaptics.shared.play(.finish)
            showUndoButton()
            saveMatchRecord()
            return
        }

        pendingNextSetReset = true
        startRest(title: "局间休息", seconds: rules.restBetweenSets, allowAutoFinish: true)
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
        winner = nil
        pendingNextSetReset = false
        midGameRestTaken = false
        decidingSetSwapDone = false
        currentSetStartTime = Date()

        showToast("第\(redSets + blueSets + 1)局开始")
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
        WatchHaptics.shared.play(.undo)
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
            isResting: isResting,
            isTiebreak: isTiebreak,
            winner: winner,
            midGameRestTaken: midGameRestTaken,
            pendingNextSetReset: pendingNextSetReset,
            decidingSetSwapDone: decidingSetSwapDone,
            recordSaved: recordSaved,
            actionsCount: actions.count
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
        isResting = snapshot.isResting
        isTiebreak = snapshot.isTiebreak
        winner = snapshot.winner
        midGameRestTaken = snapshot.midGameRestTaken
        pendingNextSetReset = snapshot.pendingNextSetReset
        decidingSetSwapDone = snapshot.decidingSetSwapDone
        recordSaved = snapshot.recordSaved
    }

    private func handleStopToggle() {
        let wasStopped = isStopped
        isStopped.toggle()
        isFinished = false

        if !wasStopped && isStopped && !recordSaved {
            if redSets > blueSets {
                winner = "red"
            } else if blueSets > redSets {
                winner = "blue"
            } else {
                winner = nil
            }
            isFinished = true
            WatchHaptics.shared.play(.finish)
            showUndoButton()
            saveMatchRecord()
        }
    }

    private func saveMatchRecord() {
        guard !recordSaved else { return }
        let endTime = Date()
        let duration = endTime.timeIntervalSince(matchStartTime)
        let winnerName: String?
        if let winner = winner {
            winnerName = winner == "red" ? "红方" : "蓝方"
        } else if redSets != blueSets {
            winnerName = redSets > blueSets ? "红方" : "蓝方"
        } else {
            winnerName = nil
        }
        let record = WatchScoreboardRecord(
            id: "watch-\(rules.gameType.rawValue)-\(Int(endTime.timeIntervalSince1970))",
            gameType: rules.gameType,
            startTime: matchStartTime,
            endTime: endTime,
            duration: duration,
            team1Name: "红方",
            team2Name: "蓝方",
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
        let name = winnerSide == "red" ? "红方" : "蓝方"
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
    let isResting: Bool
    let isTiebreak: Bool
    let winner: String?
    let midGameRestTaken: Bool
    let pendingNextSetReset: Bool
    let decidingSetSwapDone: Bool
    let recordSaved: Bool
    let actionsCount: Int
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
        }
    }
}
