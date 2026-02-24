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
    @State private var undoButtonVisible: Bool = false
    @State private var recordSaved: Bool = false
    @State private var toastMessage: String? = nil
    @State private var history: [(redScore: Int, blueScore: Int, redSets: Int, blueSets: Int, currentShooter: Bool, arrowsRed: Int, arrowsBlue: Int, arrowsPerSet: Int)] = []
    @State private var matchStartTime: Date = Date()
    @State private var scoreboardLayout: String = "vertical"
    
    private var isMatchFinished: Bool {
        winner != nil
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
        .navigationBarHidden(true)
        .onAppear {
            scoreboardLayout = WatchPreferences.shared.scoreboardLayout
            if scoreboardLayout != "horizontal" && scoreboardLayout != "vertical" { scoreboardLayout = "vertical" }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = WatchPreferences.shared.scoreboardLayout
        }
    }

    private var mainBoard: some View {
        Group {
            if scoreboardLayout == "horizontal" {
                HStack(spacing: 0) {
                    side(isRed: true)
                    side(isRed: false)
                }
            } else {
                VStack(spacing: 0) {
                    side(isRed: true)
                    side(isRed: false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if dx > 50 && abs(dy) < 50 {
                        dismiss()
                        return
                    }
                    if dy > 40 && !showScorePanel && !showMenu && !setEnding {
                        undoScore()
                    }
                }
        )
        .onLongPressGesture(minimumDuration: 0.5) {
            if !isStopped && !setEnding { showMenu = true }
        }
    }

    private func side(isRed: Bool) -> some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { showScorePanel = false }
            VStack(spacing: 12) {
                Text(currentShooter ? NSLocalizedString("watch_team_red", comment: "Red") : NSLocalizedString("watch_team_blue", comment: "Blue"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(currentShooter ? Color(hex: 0xE53935) : Color(hex: 0x1E88E5))
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 2) {
                            ForEach(0..<4, id: \.self) { col in
                                let val = scoreGrid[row][col]
                                Button {
                                    addArrow(value: val == -1 ? nil : val)
                                    showScorePanel = false
                                } label: {
                                    Text(val == -1 ? "M" : "\(val!)")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(val == -1 ? Color.white : Color.black)
                                        .frame(width: 44, height: 44)
                                        .background(val == -1 ? Color.orange : Color.white.opacity(0.8))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Text(NSLocalizedString("cancel", comment: "Cancel"))
                    .font(.system(size: 14))
                    .foregroundColor(WatchTheme.secondaryText)
                    .padding(.top, 16)
                    .onTapGesture { showScorePanel = false }
            }
            .padding(20)
            .background(Color.black.opacity(0.65))
            .cornerRadius(18)
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
            .padding(20)
            .background(Color.black.opacity(0.65))
            .cornerRadius(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stoppedOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(isMatchFinished ? "🏁" : "⏸")
                        .font(.system(size: 28, weight: .bold))
                    Text(isMatchFinished ? NSLocalizedString("watch_match_finished", comment: "Match finished") : NSLocalizedString("watch_stop", comment: "Stop"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    if isMatchFinished {
                        Text("\(NSLocalizedString("watch_team_red", comment: "Red")) \(redSets) - \(blueSets) \(NSLocalizedString("watch_team_blue", comment: "Blue"))")
                            .font(.system(size: 14))
                            .foregroundColor(WatchTheme.accent)
                    }
                }

                VStack(spacing: 8) {
                    if undoButtonVisible && isMatchFinished {
                        Button {
                            undoScore()
                            undoButtonVisible = false
                        } label: {
                            Text(NSLocalizedString("menu_undo", comment: "Undo"))
                                .frame(width: 160, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(WatchTheme.card)
                        .foregroundColor(.white)
                        .cornerRadius(22)
                    }

                    if !isMatchFinished {
                        Button {
                            isStopped = false
                        } label: {
                            Text(NSLocalizedString("watch_continue", comment: "Continue"))
                                .frame(width: 140, height: 44)
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
                            .frame(width: 140, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(isMatchFinished ? WatchTheme.successGreen : WatchTheme.card)
                    .foregroundColor(.white)
                    .cornerRadius(22)
                }
            }
            .padding(24)
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
                Text(NSLocalizedString("game_archery", comment: "Archery"))
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
                        handleStopToggle()
                        showMenu = false
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: isStopped ? "play.fill" : "stop.fill")
                                .font(.system(size: 22, weight: .medium))
                            Text(isStopped ? NSLocalizedString("watch_continue", comment: "Continue") : NSLocalizedString("watch_stop", comment: "Stop"))
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(isStopped ? WatchTheme.successGreen : WatchTheme.warningOrange)
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
            }
            .padding(12)
            .background(WatchTheme.overlayCard)
            .cornerRadius(16)
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
            winner = redSets > blueSets ? true : (blueSets > redSets ? false : nil)
            isStopped = true
            undoButtonVisible = true
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
        WatchHaptics.shared.play(.undo)
        showToast(NSLocalizedString("watch_undo_toast", value: "已撤销", comment: "Undo toast"))
    }
    
    private func handleStopToggle() {
        guard !isMatchFinished else { return }
        isStopped.toggle()
        if isStopped {
            showScorePanel = false
        }
        WatchHaptics.shared.play(.medium)
    }
    
    private func resetMatch() {
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
