//
//  DualPlayerTimerView.swift
//  jifen
//
//  Harmony-style board-game timer view for Go / Xiangqi / Chess.
//

import SwiftUI

private enum DualTimerGameState {
    case notStarted
    case running
    case paused
    case finished
}

private enum DualTimerEndReason {
    case timeout(loser: Int)
    case manualStop
}

private struct PlayerClockState {
    var mainRemaining: Double
    var inByoyomi: Bool
    var byoyomiRemaining: Double
    var byoyomiPeriodsRemaining: Int
}

struct DualPlayerTimerView: View {
    let gameType: GameType
    let config: BoardTimerConfig

    @Environment(\.dismiss) private var dismiss

    @State private var player1Clock: PlayerClockState
    @State private var player2Clock: PlayerClockState
    @State private var activePlayer: Int = 1
    @State private var gameState: DualTimerGameState = .notStarted
    @State private var isPlayerPositionSwapped: Bool = false
    @State private var winnerPlayer: Int? = nil
    @State private var totalMoves: Int = 0

    @State private var ticker: Timer?
    @State private var lastTickAt: Date?
    @State private var gameStartAt: Date?
    @State private var recordSaved: Bool = false
    @State private var actionTimeline: [TimerActionRecord] = []

    @State private var showExitConfirm = false
    @State private var showStopConfirm = false
    @State private var hasLockedOrientation = false
    @State private var autoPausedForExitConfirm = false

    init(gameType: GameType, config: BoardTimerConfig) {
        self.gameType = gameType
        self.config = config

        let initial = DualPlayerTimerView.makeInitialClock(config: config)
        _player1Clock = State(initialValue: initial)
        _player2Clock = State(initialValue: initial)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                HStack(spacing: 0) {
                    playerPanel(for: displayedPlayerID(isLeftSide: true), in: geo)
                    playerPanel(for: displayedPlayerID(isLeftSide: false), in: geo)
                }

                floatingControls
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 34)

                if gameState == .finished {
                    gameOverOverlay
                }
            }
            .background(Color.black)
            .ignoresSafeArea()
        }
        .navigationTitle(gameType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onAppear {
            guard !hasLockedOrientation else { return }
            OrientationLock.shared.lock(.landscape)
            hasLockedOrientation = true
        }
        .onDisappear {
            if hasLockedOrientation {
                OrientationLock.shared.unlock()
                hasLockedOrientation = false
            }
            stopTicker()
            if gameState != .notStarted {
                saveRecordIfNeeded(winnerLabel: winnerPlayerName)
            }
        }
        .alert(
            NSLocalizedString("timer_exit_confirm_title", value: "确认退出", comment: "Confirm exit title"),
            isPresented: $showExitConfirm
        ) {
            Button(NSLocalizedString("cancel", value: "取消", comment: ""), role: .cancel) {
                if autoPausedForExitConfirm {
                    autoPausedForExitConfirm = false
                    resumeGame(logAction: false)
                }
            }
            Button(NSLocalizedString("exit", value: "退出", comment: ""), role: .destructive) {
                autoPausedForExitConfirm = false
                stopTicker()
                saveRecordIfNeeded(winnerLabel: winnerPlayerName)
                dismiss()
            }
        } message: {
            Text(NSLocalizedString("timer_exit_confirm_message", value: "退出后将结束当前计时。", comment: "Confirm exit message"))
        }
        .alert(
            NSLocalizedString("timer_stop_confirm_title", value: "确认停止", comment: "Confirm stop title"),
            isPresented: $showStopConfirm
        ) {
            Button(NSLocalizedString("cancel", value: "取消", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("confirm", value: "确定", comment: ""), role: .destructive) {
                stopCurrentGame()
            }
        } message: {
            Text(NSLocalizedString("timer_stop_confirm_message", value: "停止后将结束本局。", comment: "Confirm stop message"))
        }
    }

    // MARK: - Panels

    private func playerPanel(for playerID: Int, in geo: GeometryProxy) -> some View {
        let clock = clockFor(playerID)
        let isCurrent = activePlayer == playerID
        let bgColor = panelBackgroundColor(for: playerID, isCurrent: isCurrent)
        let fgColor = panelTextColor(for: playerID)
        let timeColor = clock.inByoyomi ? Color(hex: "FF3B30") : fgColor

        let panelWidth = geo.size.width / 2
        let timeFontSize = min(max(76, panelWidth * 0.24), 190)

        return Button {
            onPlayerAreaTapped(playerID)
        } label: {
            ZStack {
                bgColor

                VStack(spacing: 10) {
                    Spacer(minLength: 0)

                    Text(formatClockText(clock))
                        .font(.system(size: timeFontSize, weight: .bold, design: .monospaced))
                        .foregroundColor(timeColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    if gameType == .go {
                        if clock.inByoyomi {
                            Text(String(
                                format: NSLocalizedString("timer_byoyomi_periods_format", value: "读秒 %d 次", comment: ""),
                                max(0, clock.byoyomiPeriodsRemaining)
                            ))
                            .font(.system(size: 42, weight: .medium))
                            .foregroundColor(Color(hex: "FF3B30"))
                        }
                    } else if config.incrementEnabled && config.incrementSeconds > 0 {
                        Text(String(
                            format: NSLocalizedString("timer_increment_format", value: "+%d 秒/步", comment: ""),
                            config.incrementSeconds
                        ))
                        .font(.system(size: 42, weight: .medium))
                        .foregroundColor(fgColor.opacity(0.6))
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 20)

                roleIcon(for: playerID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: iconAlignment(for: playerID))
                    .padding(20)

                if gameState == .notStarted && playerID == 1 {
                    Circle()
                        .fill(gameType == .chess ? Color.black.opacity(0.6) : .white)
                        .frame(width: 12, height: 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func roleIcon(for playerID: Int) -> some View {
        Group {
            switch gameType {
            case .go:
                if playerID == 1 {
                    Circle()
                        .fill(Color.black)
                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                } else {
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
                }
            case .xiangqi:
                ZStack {
                    Circle().fill(Color(hex: "F7E5C9"))
                    Text(playerID == 1 ? NSLocalizedString("timer_role_red", value: "帅", comment: "") : NSLocalizedString("timer_role_black", value: "将", comment: ""))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(playerID == 1 ? Color(hex: "A11F24") : Color(hex: "2C2C2E"))
                }
            case .chess:
                ZStack {
                    Circle().fill(playerID == 1 ? Color.white : Color.black)
                    Text(playerID == 1 ? "♔" : "♚")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(playerID == 1 ? .black : .white)
                }
            default:
                Circle().fill(Color.white)
            }
        }
        .frame(width: 34, height: 34)
        .rotationEffect(.degrees(shouldRotateIcon(for: playerID) ? 180 : 0))
    }

    // MARK: - Floating Controls

    private var floatingControls: some View {
        Group {
            switch gameState {
            case .notStarted:
                HStack(spacing: 40) {
                    circleIconButton(icon: "chevron.left", size: 56, background: Color.black.opacity(0.8)) {
                        presentExitConfirm()
                    }

                    Button {
                        startGame()
                    } label: {
                        Text(NSLocalizedString("start_game", value: "开始", comment: ""))
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 96, height: 96)
                            .background(Theme.accentColor)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    circleIconButton(icon: "arrow.left.arrow.right", size: 56, background: Color.black.opacity(0.8)) {
                        isPlayerPositionSwapped.toggle()
                        VibrationManager.shared.vibrateMedium()
                    }
                }

            case .running:
                circleIconButton(icon: "pause.fill", size: 96, background: Color.black.opacity(0.8)) {
                    pauseGame()
                }

            case .paused:
                HStack(spacing: 40) {
                    circleIconButton(icon: "chevron.left", size: 56, background: Color.black.opacity(0.8)) {
                        presentExitConfirm()
                    }

                    circleIconButton(icon: "play.fill", size: 96, background: Color.black.opacity(0.8)) {
                        resumeGame()
                    }

                    circleIconButton(icon: "stop.fill", size: 56, background: Color(hex: "FF3B30").opacity(0.92)) {
                        showStopConfirm = true
                    }
                }

            case .finished:
                EmptyView()
            }
        }
    }

    private func circleIconButton(icon: String, size: CGFloat, background: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size >= 90 ? 36 : 28, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(background)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var gameOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 18) {
                Text(NSLocalizedString("timer_game_over", value: "比赛结束", comment: ""))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)

                if let winnerPlayerName {
                    Text(String(format: NSLocalizedString("winner_wins", value: "%@ 获胜", comment: ""), winnerPlayerName))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(Theme.accentColor)
                }

                HStack(spacing: 12) {
                    Button {
                        restartGame()
                    } label: {
                        Text(NSLocalizedString("timer_restart", value: "重新开始", comment: ""))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 124, height: 42)
                            .background(Color(hex: "34C759"))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        presentExitConfirm()
                    } label: {
                        Text(NSLocalizedString("exit", value: "退出", comment: ""))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 124, height: 42)
                            .background(Color(hex: "FF3B30"))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(Color.black.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - State & Timer

    private static func makeInitialClock(config: BoardTimerConfig) -> PlayerClockState {
        PlayerClockState(
            mainRemaining: config.totalMainSeconds,
            inByoyomi: false,
            byoyomiRemaining: Double(max(0, config.byoyomiSeconds)),
            byoyomiPeriodsRemaining: max(0, config.byoyomiPeriods)
        )
    }

    private func startGame() {
        resetClocks()
        totalMoves = 0
        winnerPlayer = nil
        recordSaved = false
        actionTimeline = []
        gameStartAt = Date()
        gameState = .running
        lastTickAt = Date()
        startTicker()
        appendAction(.start)
        VibrationManager.shared.vibrateMedium()
    }

    private func pauseGame(logAction: Bool = true) {
        consumeElapsedTime()
        gameState = .paused
        stopTicker()
        if logAction {
            appendAction(.pause)
        }
        VibrationManager.shared.vibrateMedium()
    }

    private func resumeGame(logAction: Bool = true) {
        guard gameState == .paused else { return }
        gameState = .running
        lastTickAt = Date()
        startTicker()
        if logAction {
            appendAction(.resume)
        }
        VibrationManager.shared.vibrateMedium()
    }

    private func stopCurrentGame() {
        consumeElapsedTime()

        let p1 = displaySeconds(for: player1Clock)
        let p2 = displaySeconds(for: player2Clock)
        if p1 > p2 {
            finishGame(winner: 1, reason: .manualStop)
        } else if p2 > p1 {
            finishGame(winner: 2, reason: .manualStop)
        } else {
            finishGame(winner: nil, reason: .manualStop)
        }
    }

    private func finishGame(winner: Int?, reason: DualTimerEndReason) {
        guard gameState != .finished else { return }
        stopTicker()

        switch reason {
        case .timeout(let loser):
            appendAction(.timeout, actor: playerName(for: loser))
        case .manualStop:
            appendAction(.manualStop)
        }

        winnerPlayer = winner
        appendAction(.gameEnd, actor: winner.flatMap { playerName(for: $0) })
        gameState = .finished
        saveRecordIfNeeded(winnerLabel: winnerPlayerName)
        VibrationManager.shared.vibrateHeavy()
    }

    private func restartGame() {
        resetClocks()
        activePlayer = 1
        winnerPlayer = nil
        gameState = .notStarted
        totalMoves = 0
        lastTickAt = nil
        gameStartAt = nil
        recordSaved = false
        actionTimeline = []
    }

    private func presentExitConfirm() {
        if gameState == .running {
            autoPausedForExitConfirm = true
            pauseGame(logAction: false)
        } else {
            autoPausedForExitConfirm = false
        }
        showExitConfirm = true
    }

    private func resetClocks() {
        let initial = Self.makeInitialClock(config: config)
        player1Clock = initial
        player2Clock = initial
        activePlayer = 1
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            tick()
        }
        if let ticker {
            RunLoop.current.add(ticker, forMode: .common)
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        lastTickAt = nil
    }

    private func tick() {
        guard gameState == .running else { return }
        guard let lastTickAt else {
            self.lastTickAt = Date()
            return
        }

        let now = Date()
        let delta = now.timeIntervalSince(lastTickAt)
        self.lastTickAt = now

        applyDelta(delta, to: activePlayer)
    }

    private func consumeElapsedTime() {
        guard gameState == .running else { return }
        guard let lastTickAt else { return }

        let now = Date()
        let delta = now.timeIntervalSince(lastTickAt)
        self.lastTickAt = now
        applyDelta(delta, to: activePlayer)
    }

    private func applyDelta(_ delta: Double, to player: Int) {
        guard delta > 0 else { return }

        if player == 1 {
            var updated = player1Clock
            if config.gameType == .go {
                reduceGoTime(clock: &updated, delta: delta, loser: 1)
            } else {
                updated.mainRemaining -= delta
                if updated.mainRemaining <= 0 {
                    updated.mainRemaining = 0
                    player1Clock = updated
                    finishGame(winner: 2, reason: .timeout(loser: 1))
                    return
                }
            }
            player1Clock = updated
        } else {
            var updated = player2Clock
            if config.gameType == .go {
                reduceGoTime(clock: &updated, delta: delta, loser: 2)
            } else {
                updated.mainRemaining -= delta
                if updated.mainRemaining <= 0 {
                    updated.mainRemaining = 0
                    player2Clock = updated
                    finishGame(winner: 1, reason: .timeout(loser: 2))
                    return
                }
            }
            player2Clock = updated
        }
    }

    private func reduceGoTime(clock: inout PlayerClockState, delta: Double, loser: Int) {
        guard config.byoyomiEnabled else {
            clock.mainRemaining -= delta
            if clock.mainRemaining <= 0 {
                clock.mainRemaining = 0
                finishGame(winner: loser == 1 ? 2 : 1, reason: .timeout(loser: loser))
            }
            return
        }

        var remaining = delta

        if !clock.inByoyomi {
            if clock.mainRemaining > remaining {
                clock.mainRemaining -= remaining
                return
            }

            remaining -= clock.mainRemaining
            clock.mainRemaining = 0
            clock.inByoyomi = true
            if clock.byoyomiPeriodsRemaining <= 0 {
                clock.byoyomiPeriodsRemaining = max(1, config.byoyomiPeriods)
            }
            clock.byoyomiRemaining = Double(max(1, config.byoyomiSeconds))
        }

        while remaining > 0 && clock.inByoyomi {
            if clock.byoyomiRemaining > remaining {
                clock.byoyomiRemaining -= remaining
                return
            }

            remaining -= clock.byoyomiRemaining
            clock.byoyomiPeriodsRemaining -= 1

            if clock.byoyomiPeriodsRemaining <= 0 {
                clock.byoyomiPeriodsRemaining = 0
                clock.byoyomiRemaining = 0
                finishGame(winner: loser == 1 ? 2 : 1, reason: .timeout(loser: loser))
                return
            }

            clock.byoyomiRemaining = Double(max(1, config.byoyomiSeconds))
        }
    }

    private func onPlayerAreaTapped(_ playerID: Int) {
        guard gameState == .running else { return }
        guard activePlayer == playerID else { return }

        consumeElapsedTime()
        guard gameState == .running else { return }

        if config.gameType == .go {
            if playerID == 1 {
                if player1Clock.inByoyomi && player1Clock.byoyomiPeriodsRemaining > 0 {
                    player1Clock.byoyomiRemaining = Double(max(1, config.byoyomiSeconds))
                }
            } else {
                if player2Clock.inByoyomi && player2Clock.byoyomiPeriodsRemaining > 0 {
                    player2Clock.byoyomiRemaining = Double(max(1, config.byoyomiSeconds))
                }
            }
        } else if config.incrementEnabled && config.incrementSeconds > 0 {
            if playerID == 1 {
                player1Clock.mainRemaining += Double(config.incrementSeconds)
            } else {
                player2Clock.mainRemaining += Double(config.incrementSeconds)
            }
        }

        activePlayer = (playerID == 1) ? 2 : 1
        totalMoves += 1
        lastTickAt = Date()
        appendAction(.move, actor: playerName(for: playerID))
        VibrationManager.shared.vibrateMedium()
    }

    // MARK: - Helpers

    private func clockFor(_ playerID: Int) -> PlayerClockState {
        playerID == 1 ? player1Clock : player2Clock
    }

    private func displayedPlayerID(isLeftSide: Bool) -> Int {
        if isLeftSide {
            return isPlayerPositionSwapped ? 2 : 1
        }
        return isPlayerPositionSwapped ? 1 : 2
    }

    private func iconAlignment(for playerID: Int) -> Alignment {
        let leftID = displayedPlayerID(isLeftSide: true)
        return playerID == leftID ? .topLeading : .topTrailing
    }

    private func shouldRotateIcon(for playerID: Int) -> Bool {
        let leftID = displayedPlayerID(isLeftSide: true)
        return playerID != leftID
    }

    private func panelBackgroundColor(for playerID: Int, isCurrent: Bool) -> Color {
        if gameState == .running {
            return isCurrent ? Theme.primary : Color(hex: "333333")
        }

        switch gameType {
        case .go:
            return playerID == 1 ? .black : .white
        case .xiangqi:
            return playerID == 1 ? Color(hex: "A1262A") : .black
        case .chess:
            return playerID == 1 ? .white : .black
        default:
            return .black
        }
    }

    private func panelTextColor(for playerID: Int) -> Color {
        if gameState == .running { return .white }

        switch gameType {
        case .go:
            return playerID == 1 ? .white : .black
        case .xiangqi:
            return .white
        case .chess:
            return playerID == 1 ? .black : .white
        default:
            return .white
        }
    }

    private func formatClockText(_ clock: PlayerClockState) -> String {
        let seconds = displaySeconds(for: clock)
        let safe = max(0, Int(ceil(seconds)))
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let secs = safe % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func displaySeconds(for clock: PlayerClockState) -> Double {
        clock.inByoyomi ? max(0, clock.byoyomiRemaining) : max(0, clock.mainRemaining)
    }

    private var winnerPlayerName: String? {
        guard let winnerPlayer else { return nil }
        return playerName(for: winnerPlayer)
    }

    private func playerName(for playerID: Int) -> String {
        switch gameType {
        case .go:
            return playerID == 1
                ? NSLocalizedString("timer_black_player", value: "黑方", comment: "")
                : NSLocalizedString("timer_white_player", value: "白方", comment: "")
        case .xiangqi:
            return playerID == 1
                ? NSLocalizedString("timer_red_player", value: "红方", comment: "")
                : NSLocalizedString("timer_black_player", value: "黑方", comment: "")
        case .chess:
            return playerID == 1
                ? NSLocalizedString("timer_white_player", value: "白方", comment: "")
                : NSLocalizedString("timer_black_player", value: "黑方", comment: "")
        default:
            return NSLocalizedString("dual_timer_player", value: "玩家", comment: "") + " \(playerID)"
        }
    }

    private func appendAction(_ type: TimerActionType, actor: String? = nil) {
        guard type == .start || gameStartAt != nil else { return }
        let elapsed: TimeInterval
        if type == .start {
            elapsed = 0
        } else if let gameStartAt {
            elapsed = max(0, Date().timeIntervalSince(gameStartAt))
        } else {
            elapsed = 0
        }

        actionTimeline.append(
            TimerActionRecord(
                id: UUID().uuidString,
                elapsed: elapsed,
                type: type,
                actor: actor,
                leftRemaining: max(0, Int(ceil(displaySeconds(for: player1Clock)))),
                rightRemaining: max(0, Int(ceil(displaySeconds(for: player2Clock))))
            )
        )
    }

    private func saveRecordIfNeeded(winnerLabel: String?) {
        guard !recordSaved, let gameStartAt else { return }

        let end = Date()
        let duration = end.timeIntervalSince(gameStartAt)
        if duration <= 0 { return }

        let record = GameRecordSummary(
            id: "\(gameType.rawValue)_\(Int(gameStartAt.timeIntervalSince1970))_\(Int(end.timeIntervalSince1970))",
            gameType: gameType,
            timestamp: gameStartAt.timeIntervalSince1970,
            duration: duration,
            winner: winnerLabel,
            actions: actionTimeline
        )

        TimerRecordsViewModel.shared.addRecord(record)
        recordSaved = true
    }
}

#Preview {
    NavigationStack {
        DualPlayerTimerView(
            gameType: .go,
            config: BoardTimerConfig.default(for: .go)
        )
    }
}
