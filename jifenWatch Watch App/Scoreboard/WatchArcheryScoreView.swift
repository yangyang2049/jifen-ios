//
//  WatchArcheryScoreView.swift
//  jifenWatch Watch App
//
//  Set points: first to 6. Each set: 3 arrows each (1 at 5-5). Tap side to open score grid (0-10, M).
//  Shoot-off: win +1; same rings → closest-to-centre; next set first shooter via ArcheryShooterRules.
//

import LinkCore
import ScoreCore
import SwiftUI

private let arrowsPerSetNormal = 3
private let arrowsPerSetShootoff = 1
private let setPointsToWin = 6
private let setPointsWin = 2
private let setPointsShootOffWin = 1
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
    @Environment(WatchLinkService.self) private var linkService
    @Environment(WatchResumeSessionStore.self) private var resumeStore

    let linkedSessionId: UUID?

    @State private var store: WatchArcherySessionStore
    @State private var setEnding: Bool = false
    @State private var showScorePanel: Bool = false
    @State private var showClosestToCenter: Bool = false
    @State private var showMenu: Bool = false
    @State private var isStopped: Bool = false
    @State private var winner: Bool? = nil
    @State private var isManualFinish: Bool = false
    @State private var undoButtonVisible: Bool = false
    @State private var undoHideTimer: Timer? = nil
    @State private var recordSaved: Bool = false
    @State private var toastMessage: String? = nil
    @State private var scoreboardLayout: String = "horizontal"
    @State private var restState: WatchRestState?
    @State private var confirmation: WatchScoreboardConfirmation?
    @State private var suppressTapAfterLongPress = false
    @State private var finishCommitted = false

    private var redScore: Int { store.state.leftArrowSum }
    private var blueScore: Int { store.state.rightArrowSum }
    private var redSets: Int { store.state.leftSetPoints }
    private var blueSets: Int { store.state.rightSetPoints }
    /// `true` = red/left engine slot currently shooting.
    private var currentShooter: Bool { store.state.currentShooterIsLeft }
    private var openingShooterIsRed: Bool { store.state.openingShooterIsLeft }
    private var arrowsRedThisSet: Int { store.state.arrowsLeftThisSet }
    private var arrowsBlueThisSet: Int { store.state.arrowsRightThisSet }
    private var arrowsPerSet: Int { store.state.arrowsPerSet }
    private var setNumber: Int { store.state.currentSet }
    private var pendingSetNumber: Int { store.state.pendingSetNumber }
    private var pendingSetWinner: Bool? { store.state.pendingSetWinnerIsLeft }
    private var leftName: String { store.state.leftName }
    private var rightName: String { store.state.rightName }
    private var matchStartTime: Date { store.startedAt }

    init(
        initialState: LinkedArcheryState? = nil,
        linkedSessionId: UUID? = nil,
        resumedState: ArcheryMatchState? = nil,
        resumedUndoStates: [ArcheryMatchState] = [],
        resumedStartTime: Date? = nil,
        resumedRestState: WatchRestState? = nil,
        resumedActionLog: WatchScoreActionLog? = nil
    ) {
        self.linkedSessionId = linkedSessionId
        _store = State(initialValue: WatchArcherySessionStore(
            initialState: initialState,
            resumedState: resumedState,
            resumedUndoStates: resumedUndoStates,
            resumedStartTime: resumedStartTime,
            resumedActionLog: resumedActionLog
        ))
        _restState = State(initialValue: resumedRestState)
        let restoredState = resumedState ?? {
            guard let initialState else { return nil }
            var state = ArcheryMatchState(
                leftName: initialState.leftName,
                rightName: initialState.rightName
            )
            initialState.applying(to: &state)
            return state
        }()
        if let restoredState, restoredState.finished {
            _winner = State(initialValue: restoredState.leftSetPoints == restoredState.rightSetPoints
                ? nil
                : (restoredState.leftSetPoints > restoredState.rightSetPoints))
            _isStopped = State(initialValue: true)
        }
    }

    private var isMatchFinished: Bool {
        isStopped
    }

    private var scoringLocked: Bool {
        linkedSessionId != nil && linkService.isFollower
    }

    private var isShootOffSet: Bool {
        arrowsPerSet == arrowsPerSetShootoff
    }

    var body: some View {
        ZStack {
            mainBoard
            if showScorePanel { scorePanelOverlay }
            if setEnding { setEndOverlay }
            if showClosestToCenter { closestToCenterOverlay }
            if isStopped { stoppedOverlay }
            if let restState {
                WatchRestOverlay(
                    state: restState,
                    onContinue: { self.restState = nil },
                    onUndo: {
                        self.restState = nil
                        undoScore()
                    }
                )
            }
            if showMenu {
                WatchScoreboardMenuOverlay(
                    onDismiss: { showMenu = false },
                    onUndo: {
                        undoScore()
                        showMenu = false
                    },
                    onFinish: {
                        showMenu = false
                        confirmation = .finish
                    },
                    onReset: {
                        showMenu = false
                        confirmation = .reset
                    }
                )
            }
            if let confirmation {
                WatchConfirmationOverlay(
                    confirmation: confirmation,
                    onCancel: { self.confirmation = nil },
                    onConfirm: { confirmArchery(confirmation) }
                )
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
            if scoreboardLayout != "horizontal" && scoreboardLayout != "vertical" { scoreboardLayout = "horizontal" }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = WatchPreferences.shared.scoreboardLayout
        }
        .onChange(of: linkService.latestSnapshot) { _, update in
            guard let linkedSessionId, let update, update.sessionId == linkedSessionId,
                  let remote = update.snapshot.archeryState else { return }
            store.mergeRemoteActions(update.detailedActions)
            applyRemote(remote)
        }
        .onChange(of: store.state) { _, _ in
            persistResumeSession()
        }
        .onDisappear {
            undoHideTimer?.invalidate()
            if isMatchFinished {
                finalizeArcheryFinish()
            }
            persistResumeSession()
        }
        .watchScoreboardGestures(
            suppressTapAfterLongPress: $suppressTapAfterLongPress,
            enabled: !scoringLocked && !showScorePanel && !setEnding && !showClosestToCenter
                && !isStopped && !showMenu && restState == nil && confirmation == nil,
            onMenu: { showMenu = true },
            onUndo: undoScore,
            onExit: exitArchery
        )
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
            let isCurrent = (isRed && currentShooter) || (!isRed && !currentShooter)
            if !isCurrent || suppressTapAfterLongPress || scoringLocked || isStopped || setEnding
                || showClosestToCenter || showMenu || restState != nil { return }
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
                Text(currentShooter ? leftName : rightName)
                    .font(.system(size: WatchLayout.isCompactScreen ? 12 : 14, weight: .bold))
                    .foregroundColor(currentShooter ? Color(hex: 0xE53935) : Color(hex: 0x1E88E5))
                VStack(spacing: gridSpacing) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: gridSpacing) {
                            ForEach(0..<4, id: \.self) { col in
                                let val = scoreGrid[row][col]
                                let isMiss = val == nil || val == -1
                                Button {
                                    addArrow(value: isMiss ? nil : val)
                                    showScorePanel = false
                                } label: {
                                    Text(
                                        isMiss
                                            ? NSLocalizedString("watch_archery_miss", value: "M", comment: "Archery miss")
                                            : String(val ?? 0)
                                    )
                                        .font(.system(size: fontSize, weight: .medium))
                                        .foregroundColor(isMiss ? Color.white : Color.black)
                                        .frame(width: btnSize, height: btnSize)
                                        .background(isMiss ? Color.orange : Color.white.opacity(0.8))
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
                    Text(leftName)
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: 0xE53935))
                    Text("\(redScore) - \(blueScore)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    Text(rightName)
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

    private var closestToCenterOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            VStack(spacing: WatchLayout.isCompactScreen ? 8 : 12) {
                Text(NSLocalizedString("archery_closest_title", value: "一箭决胜 · 近心", comment: ""))
                    .font(.system(size: WatchLayout.isCompactScreen ? 13 : 15, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text(String(
                    format: NSLocalizedString("archery_closest_message", value: "双方同环 %d，请选择更近心的一方", comment: ""),
                    redScore
                ))
                .font(.system(size: WatchLayout.isCompactScreen ? 11 : 12))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    Button {
                        applyClosestToCenter(redWins: true)
                    } label: {
                        Text(leftName)
                            .font(.system(size: WatchLayout.isCompactScreen ? 12 : 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: WatchLayout.isCompactScreen ? 36 : 40)
                            .background(Color(hex: 0xE53935))
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)

                    Button {
                        applyClosestToCenter(redWins: false)
                    } label: {
                        Text(rightName)
                            .font(.system(size: WatchLayout.isCompactScreen ? 12 : 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: WatchLayout.isCompactScreen ? 36 : 40)
                            .background(Color(hex: 0x1E88E5))
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(WatchLayout.isCompactScreen ? 12 : 16)
            .background(Color.black.opacity(0.7))
            .cornerRadius(WatchLayout.isCompactScreen ? 14 : 18)
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stoppedOverlay: some View {
        ZStack {
            Color.black.opacity(0.40)
                .ignoresSafeArea()
            VStack(spacing: WatchLayout.isCompactScreen ? 10 : 16) {
                VStack(spacing: 4) {
                    Text(NSLocalizedString("watch_match_finished", comment: "Match finished"))
                        .font(.system(size: WatchLayout.isCompactScreen ? 16 : 20, weight: .bold))
                        .foregroundColor(.white)
                    Text("\(leftName) \(redSets) - \(blueSets) \(rightName)")
                        .font(.system(size: WatchLayout.isCompactScreen ? 12 : 14))
                        .foregroundColor(WatchTheme.accent)
                }

                VStack(spacing: 8) {
                    if undoButtonVisible {
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

                    Button {
                        finalizeArcheryFinish()
                        exitArchery()
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
            .background(Color.black.opacity(0.62))
            .cornerRadius(WatchLayout.isCompactScreen ? 14 : 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private func addArrow(value: Int?) {
        guard !scoringLocked else { return }
        let result = store.apply(.recordArrow(side: nil, value: value))
        guard result.accepted else { return }
        applyMatch(result.state)
        WatchHaptics.shared.play(.score)
        publishLinked()
        for event in result.events {
            switch event {
            case .closestToCenterRequired, .setReady:
                endSetFromPending()
            default:
                break
            }
        }
    }

    private var matchState: ArcheryMatchState { store.state }

    private func applyMatch(_ state: ArcheryMatchState) {
        store.replaceDisplayedState(state)
        showClosestToCenter = state.closestToCenterPending
        if state.finished {
            winner = state.winnerSide.map { $0 == .left }
            isStopped = true
        }
    }

    private func endSetFromPending() {
        setEnding = true
        DispatchQueue.main.asyncAfter(deadline: .now() + setEndDelay) {
            applySetEnd()
        }
    }

    private func applySetEnd() {
        if matchState.closestToCenterPending || (isShootOffSet && pendingSetWinner == nil && pendingSetNumber > 0) {
            setEnding = false
            showClosestToCenter = true
            return
        }
        let result = store.apply(.completeSet(closestToCenterWinner: nil), recordHistory: false)
        guard result.accepted else {
            setEnding = false
            return
        }
        applyMatch(result.state)
        finishAfterReducer(result.state)
    }

    private func applyClosestToCenter(redWins: Bool) {
        showClosestToCenter = false
        if !store.state.closestToCenterPending {
            var pending = store.state
            pending.closestToCenterPending = true
            pending.pendingSetNumber = max(pending.pendingSetNumber, pending.currentSet)
            store.replaceDisplayedState(pending)
        }
        let result = store.apply(
            .completeSet(closestToCenterWinner: redWins ? .left : .right),
            recordHistory: false
        )
        guard result.accepted else { return }
        applyMatch(result.state)
        finishAfterReducer(result.state)
    }

    private func finishAfterReducer(_ state: ArcheryMatchState) {
        if state.finished {
            isManualFinish = false
            winner = state.winnerSide.map { $0 == .left }
            isStopped = true
            showUndoButton()
            publishLinked(finished: true)
            WatchHaptics.shared.play(.finish)
            setEnding = false
            return
        }
        setEnding = false
        if WatchPreferences.shared.setBreakEnabled {
            restState = WatchRestState(
                kind: .archerySet,
                title: NSLocalizedString("watch_archery_set_rest", value: "组间休息", comment: ""),
                durationSeconds: 60,
                triggerID: "archery-\(max(1, state.currentSet - 1))"
            )
        }
        publishLinked()
    }

    private func undoScore() {
        guard store.undo() else { return }
        showClosestToCenter = store.state.closestToCenterPending
        setEnding = false
        restState = nil
        if isStopped { recordSaved = false }
        finishCommitted = false
        isManualFinish = false
        if !store.state.finished {
            isStopped = false
            winner = nil
        }
        WatchHaptics.shared.play(.undo)
        showToast(NSLocalizedString("watch_undo_toast", value: "已撤销", comment: "Undo toast"))
        publishLinked()
    }

    private func showUndoButton() {
        isManualFinish = false
        undoButtonVisible = true
        undoHideTimer?.invalidate()
        undoHideTimer = Timer.scheduledTimer(withTimeInterval: WatchTiming.undoCountdown, repeats: false) { _ in
            undoButtonVisible = false
            finalizeArcheryFinish()
        }
    }

    private func endMatchFromMenu() {
        guard !isMatchFinished else { return }
        showScorePanel = false
        showClosestToCenter = false
        let result = store.apply(.finish)
        if result.accepted {
            applyMatch(result.state)
        }
        isStopped = true
        isManualFinish = true
        winner = redSets > blueSets ? true : (blueSets > redSets ? false : nil)
        showUndoButton()
        isManualFinish = true
        WatchHaptics.shared.play(.finish)
        publishLinked(finished: true)
    }

    private func resetMatch() {
        resumeStore.clear()
        undoHideTimer?.invalidate()
        undoHideTimer = nil
        let result = store.apply(.reset, recordHistory: false)
        if result.accepted {
            applyMatch(result.state)
        }
        store.clearHistory()
        setEnding = false
        showScorePanel = false
        showClosestToCenter = false
        showMenu = false
        restState = nil
        isStopped = false
        winner = nil
        isManualFinish = false
        undoButtonVisible = false
        recordSaved = false
        finishCommitted = false
        WatchHaptics.shared.play(.light)
        showToast(NSLocalizedString("watch_reset_toast", comment: "Match reset"))
    }

    private func confirmArchery(_ value: WatchScoreboardConfirmation) {
        confirmation = nil
        switch value {
        case .finish:
            endMatchFromMenu()
        case .reset:
            resetMatch()
        }
    }

    private func exitArchery() {
        if linkedSessionId != nil {
            if store.state.finished {
                linkService.leaveSession()
            } else {
                linkService.exitScoreboardToHome()
            }
        }
        persistResumeSession()
        dismiss()
    }

    private func persistResumeSession() {
        guard !store.state.finished,
              redScore + blueScore + redSets + blueSets > 0
                || !store.resumeUndoStates().isEmpty else {
            resumeStore.clear()
            return
        }
        let score = redSets + blueSets > 0
            ? "\(redSets) : \(blueSets)"
            : "\(redScore) : \(blueScore)"
        resumeStore.save(WatchResumeSession(
            startedAt: matchStartTime,
            scoreLine: score,
            emoji: "🏹",
            payload: .archery(
                state: store.state,
                undoStates: store.resumeUndoStates(),
                restState: restState
            ),
            actionLog: store.actionLog,
            link: linkService.resumeContext
        ))
    }

    private func showToast(_ text: String) {
        toastMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            toastMessage = nil
        }
    }

    private func linkedSnapshot(finished: Bool = false) -> LinkedArcheryState {
        var snap = LinkedArcheryState(match: matchState)
        if finished || isMatchFinished { snap.finished = true }
        return snap
    }

    private func publishLinked(finished: Bool = false, commitFinish: Bool = false) {
        guard linkedSessionId != nil, linkService.isController else { return }
        let snapshot = linkedSnapshot(finished: finished)
        linkService.publishSnapshot(.archery(snapshot), detailedActions: store.actionLog.detailedActions)
        if snapshot.finished, commitFinish {
            linkService.publishMatchFinished(
                snapshot: .archery(snapshot),
                recordId: "w_archery_\(UUID().uuidString)",
                winnerSide: redSets == blueSets ? nil : (redSets > blueSets ? .left : .right),
                manualEnd: isManualFinish,
                startTime: matchStartTime,
                endTime: Date(),
                totalScoreChanges: store.actionLog.scoreChangeCount,
                detailedActions: store.actionLog.detailedActions
            )
        }
    }

    private func finalizeArcheryFinish() {
        guard isMatchFinished, !finishCommitted else { return }
        resumeStore.clear()
        if linkedSessionId != nil {
            publishLinked(finished: true, commitFinish: true)
        } else {
            saveMatchRecord()
        }
        finishCommitted = true
    }

    private func applyRemote(_ remote: LinkedArcheryState) {
        var state = store.state
        remote.applying(to: &state)
        applyMatch(state)
        if remote.finished {
            winner = remote.leftSetPoints == remote.rightSetPoints
                ? nil
                : (remote.leftSetPoints > remote.rightSetPoints)
            isStopped = true
        }
    }

    private func saveMatchRecord() {
        guard !recordSaved else { return }
        let endTime = Date()
        let duration = endTime.timeIntervalSince(matchStartTime)
        let redName = leftName
        let blueName = rightName
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
            actions: store.actionLog.actions,
            totalScoreChanges: store.actionLog.scoreChangeCount,
            participants: [
                WatchRecordParticipant(name: redName, score: redSets),
                WatchRecordParticipant(name: blueName, score: blueSets)
            ]
        )
        WatchRecordManager.shared.saveRecord(record)
        recordSaved = true
    }
}
