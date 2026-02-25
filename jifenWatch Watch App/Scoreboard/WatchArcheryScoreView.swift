//
//  WatchArcheryScoreView.swift
//  jifenWatch Watch App
//
//  Set points: first to 6. Each set: 3 arrows each (1 at 5-5). Tap side to open score grid (0-10, M).
//

import SwiftUI

private let arrowsPerSetNormal = 3
private let arrowsPerSetShootoff = 1
private let setPointsToWin = 6
private let setPointsWin = 2
private let setPointsTie = 1
private let setEndDelay: TimeInterval = 3.5

private let scoreGrid: [[Int?]] = [
    [10, 9, 8, 7],
    [6, 5, 4, 3],
    [2, 1, 0, -1]
]
// -1 means M (miss)

struct WatchArcheryScoreView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var redScore: Int = 0
    @State private var blueScore: Int = 0
    @State private var redSets: Int = 0
    @State private var blueSets: Int = 0
    @State private var currentShooter: Bool = true
    @State private var arrowsRedThisSet: Int = 0
    @State private var arrowsBlueThisSet: Int = 0
    @State private var arrowsPerSet: Int = arrowsPerSetNormal
    @State private var setNumber: Int = 1
    @State private var setEnding: Bool = false
    @State private var pendingSetNumber: Int = 0
    @State private var pendingSetWinner: Bool? = nil
    @State private var showScorePanel: Bool = false
    @State private var showMenu: Bool = false
    @State private var isStopped: Bool = false
    @State private var winner: Bool? = nil
    @State private var isManualFinish: Bool = false
    @State private var undoButtonVisible: Bool = false
    @State private var undoHideTimer: Timer? = nil
    @State private var recordSaved: Bool = false
    @State private var toastMessage: String? = nil
    @State private var history: [(redScore: Int, blueScore: Int, redSets: Int, blueSets: Int, currentShooter: Bool, arrowsRed: Int, arrowsBlue: Int, arrowsPerSet: Int)] = []
    @State private var matchStartTime: Date = Date()
    @State private var scoreboardLayout: String = "vertical"
    
    private var isMatchFinished: Bool {
        winner != nil || isManualFinish
    }

    var body: some View {
        ZStack {
            mainBoard
            if showScorePanel { scorePanelOverlay }
            if setEnding { setEndOverlay }
            if isStopped { stoppedOverlay }
            if showMenu { menuOverlay }
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
            if scoreboardLayout != "horizontal" && scoreboardLayout != "vertical" { scoreboardLayout = "vertical" }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = WatchPreferences.shared.scoreboardLayout
        }
    }

    private var mainBoard: some View {
        GeometryReader { proxy in
            let boardWidth = proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing
            let boardHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            Group {
                if scoreboardLayout == "horizontal" {
                    HStack(spacing: 0) {
                        side(isRed: true, size: CGSize(width: boardWidth / 2, height: boardHeight))
                        side(isRed: false, size: CGSize(width: boardWidth / 2, height: boardHeight))
                    }
                    .frame(width: boardWidth, height: boardHeight)
                } else {
                    VStack(spacing: 0) {
                        side(isRed: true, size: CGSize(width: boardWidth, height: boardHeight / 2))
                        side(isRed: false, size: CGSize(width: boardWidth, height: boardHeight / 2))
                    }
                    .frame(width: boardWidth, height: boardHeight)
                }
            }
            .offset(x: -proxy.safeAreaInsets.leading, y: -proxy.safeAreaInsets.top)
        }
        .ignoresSafeArea()
        .gesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if dx > 50 && abs(dy) < 50 {
                        dismiss()
                        return
                    }
                    if dy > 40 && !showScorePanel && !showMenu && !setEnding && !isStopped {
                        undoScore()
                    } else if dy < -40 && !showScorePanel && !showMenu && !setEnding && !isStopped {
                        showMenu = true
                    }
                }
        )
    }

    private func side(isRed: Bool, size: CGSize) -> some View {
        let setPts = isRed ? redSets : blueSets
        let ringPts = isRed ? redScore : blueScore
        let mainScoreFontSize: CGFloat = scoreboardLayout == "horizontal" ? 64 : 72
        let setScoreYOffset: CGFloat = 56
        return ZStack {
            if scoreboardLayout == "horizontal" {
                Text("\(ringPts)")
                    .font(.system(size: mainScoreFontSize, weight: .bold))
                    .foregroundColor(.white)

                if redSets + blueSets > 0 {
                    Text("\(setPts)")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.65))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .offset(y: setScoreYOffset)
                }
            } else {
                VStack(spacing: 4) {
                    if redSets + blueSets > 0 {
                        Text("\(setPts)")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.65))
                    }
                    Text("\(ringPts)")
                        .font(.system(size: mainScoreFontSize, weight: .bold))
                        .foregroundColor(.white)
                }
            }

            serverIndicatorOverlay(isRed: isRed)
        }
        .frame(width: size.width, height: size.height)
        .background(isRed ? Color(hex: 0xE53935) : Color(hex: 0x1E88E5))
        .opacity(isStopped && winner != nil && (isRed ? winner != true : winner != false) ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            if isStopped || setEnding || showMenu { return }
            showScorePanel = true
        }
    }

    @ViewBuilder
    private func serverIndicatorOverlay(isRed: Bool) -> some View {
        let isCurrent = (isRed && currentShooter) || (!isRed && !currentShooter)
        if isCurrent {
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

    private var scorePanelOverlay: some View {
        let btnSize = WatchLayout.archeryScoreButtonSize
        let fontSize = WatchLayout.archeryScoreButtonFontSize
        let gridSpacing = WatchLayout.archeryScoreGridSpacing
        let panelPadding = WatchLayout.archeryScorePanelPadding
        return ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { showScorePanel = false }
            VStack(spacing: WatchLayout.archeryScorePanelVStackSpacing) {
                Text(currentShooter ? NSLocalizedString("watch_team_red", comment: "Red") : NSLocalizedString("watch_team_blue", comment: "Blue"))
                    .font(.system(size: WatchLayout.isCompactScreen ? 12 : 14, weight: .bold))
                    .foregroundColor(currentShooter ? Color(hex: 0xE53935) : Color(hex: 0x1E88E5))
                VStack(spacing: gridSpacing) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: gridSpacing) {
                            ForEach(0..<4, id: \.self) { col in
                                let val = scoreGrid[row][col]
                                Button {
                                    addArrow(value: val == -1 ? nil : val)
                                    showScorePanel = false
                                } label: {
                                    Text(val == -1 ? NSLocalizedString("watch_archery_miss", value: "M", comment: "Archery miss") : "\(val!)")
                                        .font(.system(size: fontSize, weight: .medium))
                                        .foregroundColor(val == -1 ? Color.white : Color.black)
                                        .frame(width: btnSize, height: btnSize)
                                        .background(val == -1 ? Color.orange : Color.white.opacity(0.8))
                                        .cornerRadius(WatchLayout.isCompactScreen ? 6 : 8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Button {
                    showScorePanel = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: WatchLayout.isCompactScreen ? 20 : 24))
                        .foregroundColor(WatchTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .frame(width: WatchLayout.isCompactScreen ? 36 : 44, height: WatchLayout.isCompactScreen ? 36 : 44)
                .padding(.top, WatchLayout.archeryScorePanelCloseTopPadding)
            }
            .padding(panelPadding)
            .background(Color.black.opacity(0.65))
            .cornerRadius(WatchLayout.isCompactScreen ? 14 : 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var setEndOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Text(String(format: NSLocalizedString("watch_set_end_format", comment: "Set end"), pendingSetNumber))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.95))
                HStack(spacing: 8) {
                    Text(NSLocalizedString("watch_team_red", comment: "Red"))
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: 0xE53935))
                    Text("\(redScore) - \(blueScore)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    Text(NSLocalizedString("watch_team_blue", comment: "Blue"))
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: 0x1E88E5))
                }
            }
            .padding(WatchLayout.isCompactScreen ? 14 : 20)
            .background(Color.black.opacity(0.65))
            .cornerRadius(WatchLayout.isCompactScreen ? 14 : 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stoppedOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            VStack(spacing: WatchLayout.isCompactScreen ? 10 : 16) {
                VStack(spacing: 4) {
                    Text(isMatchFinished ? "🏁" : "⏸")
                        .font(.system(size: WatchLayout.isCompactScreen ? 22 : 28, weight: .bold))
                    Text(isMatchFinished ? NSLocalizedString("watch_match_finished", comment: "Match finished") : NSLocalizedString("watch_stop", comment: "Stop"))
                        .font(.system(size: WatchLayout.isCompactScreen ? 16 : 20, weight: .bold))
                        .foregroundColor(.white)
                    if isMatchFinished {
                        Text("\(NSLocalizedString("watch_team_red", comment: "Red")) \(redSets) - \(blueSets) \(NSLocalizedString("watch_team_blue", comment: "Blue"))")
                            .font(.system(size: WatchLayout.isCompactScreen ? 12 : 14))
                            .foregroundColor(WatchTheme.accent)
                    }
                }

                VStack(spacing: 8) {
                    if isMatchFinished {
                        if !isManualFinish && undoButtonVisible {
                            Button {
                                undoScore()
                                undoButtonVisible = false
                            } label: {
                                Text(NSLocalizedString("menu_undo", comment: "Undo"))
                                    .frame(width: WatchLayout.archeryStoppedButtonWidth, height: WatchLayout.archeryStoppedButtonHeight)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(WatchTheme.card)
                            .foregroundColor(.white)
                            .cornerRadius(22)
                        } else {
                            Button {
                                resetMatch()
                            } label: {
                                Text(NSLocalizedString("watch_play_again", value: "Play Again", comment: "Play again"))
                                    .frame(width: WatchLayout.archeryStoppedButtonWidth, height: WatchLayout.archeryStoppedButtonHeight)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(WatchTheme.successGreen)
                            .foregroundColor(.white)
                            .cornerRadius(22)
                        }
                    }

                    if !isMatchFinished {
                        Button {
                            isStopped = false
                        } label: {
                            Text(NSLocalizedString("watch_continue", comment: "Continue"))
                                .frame(width: WatchLayout.archeryStoppedButtonWidthSmall, height: WatchLayout.archeryStoppedButtonHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(WatchTheme.successGreen)
                        .foregroundColor(.white)
                        .cornerRadius(22)
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text(NSLocalizedString("exit", value: "Exit", comment: "Exit"))
                            .frame(width: WatchLayout.archeryStoppedButtonWidthSmall, height: WatchLayout.archeryStoppedButtonHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(WatchTheme.card)
                    .foregroundColor(.white)
                    .cornerRadius(22)
                }
            }
            .padding(WatchLayout.archeryStoppedOverlayPadding)
            .background(Color.black.opacity(0.65))
            .cornerRadius(WatchLayout.isCompactScreen ? 14 : 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var menuOverlay: some View {
        let menuPad = WatchLayout.archeryMenuPadding
        let btnH = WatchLayout.archeryMenuButtonHeight
        let iconSz = WatchLayout.archeryMenuIconSize
        return ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    showMenu = false
                }

            VStack(spacing: WatchLayout.isCompactScreen ? 6 : 10) {
                Text(NSLocalizedString("game_archery", comment: "Archery"))
                    .font(.system(size: WatchLayout.isCompactScreen ? 12 : 14))
                    .foregroundColor(.white.opacity(0.9))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: WatchLayout.isCompactScreen ? 6 : 8) {
                    Button {
                        undoScore()
                        showMenu = false
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: iconSz, weight: .medium))
                            Text(NSLocalizedString("menu_undo", comment: "Undo"))
                                .font(.system(size: WatchLayout.isCompactScreen ? 10 : 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: btnH)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(WatchTheme.card)
                    .foregroundColor(.white)
                    .cornerRadius(WatchLayout.isCompactScreen ? 10 : 12)

                    Button {
                        endMatchFromMenu()
                        showMenu = false
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "flag.checkered")
                                .font(.system(size: iconSz, weight: .medium))
                            Text(NSLocalizedString("watch_end_match", value: "End", comment: "End match"))
                                .font(.system(size: WatchLayout.isCompactScreen ? 10 : 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: btnH)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(WatchTheme.dangerRed)
                    .foregroundColor(.white)
                    .cornerRadius(WatchLayout.isCompactScreen ? 10 : 12)

                    Button {
                        resetMatch()
                        showMenu = false
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: iconSz, weight: .medium))
                            Text(NSLocalizedString("menu_reset", comment: "Reset"))
                                .font(.system(size: WatchLayout.isCompactScreen ? 10 : 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: btnH)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(WatchTheme.card)
                    .foregroundColor(.white)
                    .cornerRadius(WatchLayout.isCompactScreen ? 10 : 12)

                    Button {
                        toggleLayout()
                        showMenu = false
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: scoreboardLayout == "vertical" ? "rectangle.split.2x1" : "rectangle.split.1x2")
                                .font(.system(size: iconSz, weight: .medium))
                            Text(scoreboardLayout == "vertical" ? NSLocalizedString("watch_layout_horizontal", comment: "Horizontal") : NSLocalizedString("watch_layout_vertical", comment: "Vertical"))
                                .font(.system(size: WatchLayout.isCompactScreen ? 10 : 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: btnH)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(WatchTheme.card)
                    .foregroundColor(.white)
                    .cornerRadius(WatchLayout.isCompactScreen ? 10 : 12)
                }
                .padding(menuPad)

                Button {
                    showMenu = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: WatchLayout.isCompactScreen ? 20 : 24))
                        .foregroundColor(WatchTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .frame(width: WatchLayout.isCompactScreen ? 36 : 44, height: WatchLayout.isCompactScreen ? 36 : 44)
            }
            .padding(menuPad)
            .background(WatchTheme.overlayCard)
            .cornerRadius(WatchLayout.isCompactScreen ? 12 : 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addArrow(value: Int?) {
        let points = value ?? 0
        saveHistory()
        if currentShooter {
            redScore += points
            arrowsRedThisSet += 1
        } else {
            blueScore += points
            arrowsBlueThisSet += 1
        }
        currentShooter.toggle()
        WatchHaptics.shared.play(.score)
        if arrowsRedThisSet == arrowsPerSet && arrowsBlueThisSet == arrowsPerSet {
            endSet()
        }
    }

    private func endSet() {
        let setWinner: Bool? = redScore > blueScore ? true : (blueScore > redScore ? false : nil)
        pendingSetNumber = setNumber
        pendingSetWinner = setWinner
        setEnding = true
        DispatchQueue.main.asyncAfter(deadline: .now() + setEndDelay) {
            applySetEnd()
        }
    }

    private func applySetEnd() {
        if let w = pendingSetWinner {
            if w { redSets += setPointsWin } else { blueSets += setPointsWin }
        } else {
            redSets += setPointsTie
            blueSets += setPointsTie
        }
        if redSets >= setPointsToWin || blueSets >= setPointsToWin {
            isManualFinish = false
            winner = redSets > blueSets ? true : (blueSets > redSets ? false : nil)
            isStopped = true
            showUndoButton()
            saveMatchRecord()
            WatchHaptics.shared.play(.finish)
            setEnding = false
            return
        }
        arrowsPerSet = (redSets == 5 && blueSets == 5) ? arrowsPerSetShootoff : arrowsPerSetNormal
        redScore = 0
        blueScore = 0
        arrowsRedThisSet = 0
        arrowsBlueThisSet = 0
        currentShooter = true
        setNumber += 1
        setEnding = false
        pendingSetNumber = 0
        pendingSetWinner = nil
    }

    private func saveHistory() {
        history.append((redScore, blueScore, redSets, blueSets, currentShooter, arrowsRedThisSet, arrowsBlueThisSet, arrowsPerSet))
        if history.count > 50 { history.removeFirst() }
    }

    private func undoScore() {
        guard let s = history.popLast() else { return }
        redScore = s.redScore
        blueScore = s.blueScore
        redSets = s.redSets
        blueSets = s.blueSets
        currentShooter = s.currentShooter
        arrowsRedThisSet = s.arrowsRed
        arrowsBlueThisSet = s.arrowsBlue
        arrowsPerSet = s.arrowsPerSet
        if isStopped { recordSaved = false }
        isManualFinish = false
        WatchHaptics.shared.play(.undo)
        showToast(NSLocalizedString("watch_undo_toast", value: "已撤销", comment: "Undo toast"))
    }

    private func showUndoButton() {
        isManualFinish = false
        undoButtonVisible = true
        undoHideTimer?.invalidate()
        undoHideTimer = Timer.scheduledTimer(withTimeInterval: WatchTiming.undoCountdown, repeats: false) { _ in
            undoButtonVisible = false
        }
    }

    private func endMatchFromMenu() {
        guard !isMatchFinished else { return }
        showScorePanel = false
        isStopped = true
        isManualFinish = true
        undoButtonVisible = false
        undoHideTimer?.invalidate()
        undoHideTimer = nil
        winner = redSets > blueSets ? true : (blueSets > redSets ? false : nil)
        WatchHaptics.shared.play(.finish)
        saveMatchRecord()
    }
    
    private func resetMatch() {
        undoHideTimer?.invalidate()
        undoHideTimer = nil
        redScore = 0
        blueScore = 0
        redSets = 0
        blueSets = 0
        currentShooter = true
        arrowsRedThisSet = 0
        arrowsBlueThisSet = 0
        arrowsPerSet = arrowsPerSetNormal
        setNumber = 1
        setEnding = false
        pendingSetNumber = 0
        pendingSetWinner = nil
        showScorePanel = false
        showMenu = false
        isStopped = false
        winner = nil
        isManualFinish = false
        undoButtonVisible = false
        recordSaved = false
        history.removeAll()
        matchStartTime = Date()
        WatchHaptics.shared.play(.light)
        showToast(NSLocalizedString("watch_reset_toast", comment: "Match reset"))
    }
    
    private func toggleLayout() {
        let next = scoreboardLayout == "vertical" ? "horizontal" : "vertical"
        scoreboardLayout = next
        WatchPreferences.shared.scoreboardLayout = next
    }

    private func showToast(_ text: String) {
        toastMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            toastMessage = nil
        }
    }

    private func saveMatchRecord() {
        guard !recordSaved else { return }
        let endTime = Date()
        let duration = endTime.timeIntervalSince(matchStartTime)
        let redName = NSLocalizedString("watch_team_red", comment: "Red")
        let blueName = NSLocalizedString("watch_team_blue", comment: "Blue")
        let winnerName = winner == true ? redName : (winner == false ? blueName : nil)
        let record = WatchScoreboardRecord(
            id: "watch-archery-\(Int(endTime.timeIntervalSince1970))",
            gameType: .archery,
            startTime: matchStartTime,
            endTime: endTime,
            duration: duration,
            team1Name: redName,
            team2Name: blueName,
            team1FinalScore: redSets,
            team2FinalScore: blueSets,
            team1SetScore: redSets,
            team2SetScore: blueSets,
            winner: winnerName,
            actions: [WatchScoreAction(actionType: .gameStart, description: NSLocalizedString("watch_match_start", comment: ""))],
            totalScoreChanges: history.count
        )
        WatchRecordManager.shared.saveRecord(record)
        recordSaved = true
    }
}
