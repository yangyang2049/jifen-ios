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

    @State private var lastAppliedRemoteRevision: UInt64?
    @State private var lastAppliedRemoteGeneration: UInt64?

    @State private var showRecordSaveFailure = false
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
        linkedSessionId != nil && !linkService.canEditLinkedMatch
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
            if let restState, !scoringLocked {
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
                        guard !scoringLocked else { return }
                        undoScore()
                        showMenu = false
                    },
                    onFinish: {
                        guard !scoringLocked else { return }
                        showMenu = false
                        confirmation = .finish
                    },
                    onReset: {
                        guard !scoringLocked else { return }
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
        .watchFinishSaveFailure(isPresented: $showRecordSaveFailure) { finalizeArcheryFinish() }
        .onAppear {
            scoreboardLayout = WatchPreferences.shared.scoreboardLayout
            if scoreboardLayout != "horizontal" && scoreboardLayout != "vertical" { scoreboardLayout = "horizontal" }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = WatchPreferences.shared.scoreboardLayout
        }
        .onChange(of: scoringLocked) { _, locked in
            if locked { restState = nil }
        }
        .onChange(of: linkService.latestSnapshot, initial: true) { previous, update in
            guard let linkedSessionId, let update, update.sessionId == linkedSessionId,
                  update.matchGeneration == linkService.activeHandle?.matchGeneration,
                  let remote = update.snapshot.archeryState else { return }
            let acceptsScore = linkService.incomingSnapshot != nil
            if acceptsScore, update.beginsMatch(after: previous) {
                var fresh = store.state
                remote.applying(to: &fresh)
                store = WatchArcherySessionStore(resumedState: fresh, resumedStartTime: Date())
                recordSaved = false
                finishCommitted = false
                undoButtonVisible = false
            }
            let historyChanged = store.mergeRemoteActions(update.detailedActions, removing: update.removedActionIDs)
            let advancesScore = lastAppliedRemoteGeneration != update.matchGeneration
                || update.revision > (lastAppliedRemoteRevision ?? 0)
            let finishesCurrentScore = update.revision == lastAppliedRemoteRevision
                && update.snapshot.isFinished && previous?.snapshot.isFinished == false
            guard acceptsScore, advancesScore || finishesCurrentScore else {
                if historyChanged { persistResumeSession() }
                return
            }
            lastAppliedRemoteGeneration = update.matchGeneration
            lastAppliedRemoteRevision = update.revision
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
            enabled: !showScorePanel && !setEnding && !showClosestToCenter
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
        let isHorizontal = scoreboardLayout == "horizontal"
        let setPts = isRed ? redSets : blueSets
        let ringPts = isRed ? redScore : blueScore
        let name = isRed ? leftName : rightName
        let scoreText = "\(ringPts)"
        let mainScoreFontSize = WatchScoreTypography.adaptiveFontSize(
            baseSize: isHorizontal ? 64 : 72,
            scoreText: scoreText,
            minimumSize: isHorizontal ? 42 : 48,
            availableWidth: size.width,
            horizontalPadding: 12
        )
        let setScoreYOffset: CGFloat = 56 + WatchLayout.scoreboardMetaVerticalOffset
        let showSets = redSets + blueSets > 0
        let scoreLabel = Text(scoreText)
            .font(WatchScoreTypography.primaryScore(size: mainScoreFontSize))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
        let setLabel = Text("\(setPts)")
            .font(WatchScoreTypography.secondaryScore(size: isHorizontal ? 24 : 18))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.65))

        return ZStack {
            WatchScoreboardFace(isHorizontal: isHorizontal) {
                Text(name)
                    .font(.system(size: WatchScoreTypography.teamNameSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(isHorizontal ? 0.6 : 1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            } score: {
                if !isHorizontal, showSets {
                    VStack(spacing: 0) {
                        scoreLabel.frame(maxHeight: .infinity)
                        setLabel.padding(.bottom, 6)
                    }
                } else {
                    scoreLabel
                }
            }
            if isHorizontal, showSets {
                setLabel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: setScoreYOffset)
            }
            serverIndicatorOverlay(isRed: isRed)
        }
        .frame(width: size.width, height: size.height)
        .background(isRed ? WatchTheme.teamRed : WatchTheme.teamBlue)
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

            WatchServerIndicator(
                direction: direction,
                size: WatchLayout.serverIndicatorSize,
                color: WatchTheme.accent
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                .padding(insets)
                .offset(y: WatchLayout.serverIndicatorVerticalOffset(isHorizontal: scoreboardLayout == "horizontal"))
                .allowsHitTesting(false)
        }
    }

    private var scorePanelOverlay: some View {
        let btnSize = WatchLayout.archeryScoreButtonSize
        let fontSize = WatchLayout.archeryScoreButtonFontSize
        let gridSpacing = WatchLayout.archeryScoreGridSpacing
        return WatchFullScreenOverlay(
            scrim: Color.black.opacity(0.84),
            onBackgroundTap: { showScorePanel = false }
        ) { _, _ in
            VStack(spacing: WatchLayout.archeryScorePanelVStackSpacing) {
                Text(currentShooter ? leftName : rightName)
                    .font(.system(size: WatchLayout.isCompactScreen ? 14 : 16, weight: .bold))
                    .foregroundColor(currentShooter ? WatchTheme.teamRed : WatchTheme.teamBlue)
                    .padding(.bottom, WatchLayout.archeryScoreTitleBottomPadding)
                VStack(spacing: gridSpacing) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: gridSpacing) {
                            ForEach(scoreGrid[row].indices, id: \.self) { col in
                                let val = scoreGrid[row][col]
                                let isMiss = val == nil || val == -1
                                Button {
                                    addArrow(value: isMiss ? nil : val)
                                    showScorePanel = false
                                } label: {
                                    Text(verbatim: isMiss ? "×" : String(val ?? 0))
                                        .font(.system(size: fontSize, weight: .medium))
                                        .foregroundColor(isMiss ? Color.white : Color.black)
                                        .frame(width: btnSize, height: btnSize)
                                        .background(isMiss ? Color.orange : Color.white.opacity(0.8))
                                        .cornerRadius(WatchLayout.isCompactScreen ? 6 : 8)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(isMiss
                                    ? NSLocalizedString("watch_archery_miss", value: "Miss", comment: "Archery miss")
                                    : String(val ?? 0))
                            }
                        }
                    }
                }
                WatchMenuCloseButton { showScorePanel = false }
                .padding(.top, WatchLayout.archeryScorePanelCloseTopPadding)
            }
            .padding(.horizontal, WatchLayout.archeryScorePanelHorizontalPadding)
            .padding(.vertical, WatchLayout.archeryScorePanelVerticalPadding)
        }
    }

    private var setEndOverlay: some View {
        WatchFullScreenOverlay(scrim: Color.black.opacity(0.84)) { _, _ in
            VStack(spacing: 12) {
                Text(String(format: NSLocalizedString("watch_set_end_format", comment: "Set end"), pendingSetNumber))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.95))
                HStack(spacing: 6) {
                    VStack(spacing: 4) {
                        Text(leftName)
                            .font(.system(size: 14))
                            .foregroundColor(WatchTheme.teamRed)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                        Text("\(redScore)")
                            .font(WatchScoreTypography.primaryScore(size: 24))
                            .monospacedDigit()
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    Text("—")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                        .frame(width: 18)
                    VStack(spacing: 4) {
                        Text(rightName)
                            .font(.system(size: 14))
                            .foregroundColor(WatchTheme.teamBlue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                        Text("\(blueScore)")
                            .font(WatchScoreTypography.primaryScore(size: 24))
                            .monospacedDigit()
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(WatchLayout.isCompactScreen ? 14 : 20)
        }
    }

    private var closestToCenterOverlay: some View {
        WatchFullScreenOverlay(scrim: Color.black.opacity(0.86)) { _, _ in
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
                            .background(WatchTheme.teamRed)
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
                            .background(WatchTheme.teamBlue)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    repeatShootOff()
                } label: {
                    Text(NSLocalizedString("archery_repeat_shoot_off", value: "距离相同，继续加赛", comment: ""))
                        .font(.system(size: WatchLayout.isCompactScreen ? 11 : 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: WatchLayout.isCompactScreen ? 34 : 38)
                        .background(Color.white.opacity(0.14))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            .padding(WatchLayout.isCompactScreen ? 12 : 16)
        }
    }

    private var stoppedOverlay: some View {
        WatchFinishedOverlay(
            title: NSLocalizedString("watch_match_finished", comment: "Match finished"),
            scoreItems: [
                WatchFinishedScoreItem(name: leftName, score: redSets),
                WatchFinishedScoreItem(name: rightName, score: blueSets)
            ],
            winner: .side(winner.map { $0 ? .left : .right }),
            undoAvailable: undoButtonVisible,
            canPlayAgain: !scoringLocked,
            onUndo: {
                undoScore()
                undoButtonVisible = false
            },
            onPlayAgain: resetMatch,
            onExit: {
                guard finalizeArcheryFinish() else { return }
                exitArchery()
            }
        )
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
            if matchState.closestToCenterPending && redScore == 0 && blueScore == 0 {
                repeatShootOff()
                return
            }
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
        guard !scoringLocked else { return }
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

    private func repeatShootOff() {
        guard !scoringLocked else { return }
        let result = store.apply(.repeatShootOff, recordHistory: false)
        guard result.accepted else { return }
        setEnding = false
        showClosestToCenter = false
        applyMatch(result.state)
        publishLinked()
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
                title: NSLocalizedString("watch_archery_set_rest", value: "局间休息", comment: ""),
                durationSeconds: 60,
                triggerID: "archery-\(max(1, state.currentSet - 1))"
            )
        }
        publishLinked()
    }

    private func undoScore() {
        guard !scoringLocked else { return }
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
        undoHideTimer = Timer.scheduledTimer(withTimeInterval: WatchTiming.finishedUndoCountdown, repeats: false) { _ in
            undoButtonVisible = false
            finalizeArcheryFinish()
        }
    }

    private func endMatchFromMenu() {
        guard !scoringLocked, !isMatchFinished else { return }
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
        guard !scoringLocked, !isMatchFinished || finalizeArcheryFinish() else { return }
        resumeStore.clear()
        undoHideTimer?.invalidate()
        undoHideTimer = nil
        let timestamp = Date()
        let freshState = ArcheryMatchState(
            leftName: store.state.leftName,
            rightName: store.state.rightName,
            currentShooterIsLeft: store.state.openingShooterIsLeft,
            openingShooterIsLeft: store.state.openingShooterIsLeft
        )
        store = WatchArcherySessionStore(
            resumedState: freshState,
            resumedStartTime: timestamp
        )
        applyMatch(freshState)
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
        if linkedSessionId != nil {
            linkService.startNextMatch(
                snapshot: .archery(LinkedArcheryState(match: freshState)),
                participantNames: [freshState.leftName, freshState.rightName]
            )
        }
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
        if let linkedSessionId { linkService.exitScoreboard(sessionId: linkedSessionId) }
        persistResumeSession()
        dismiss()
    }

    private func persistResumeSession() {
        if isMatchFinished {
            if finishCommitted { resumeStore.clear() }
            return
        }
        guard redScore + blueScore + redSets + blueSets > 0
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
            linkHandle: linkService.resumeContext?.handle
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

    @discardableResult
    private func publishLinked(finished: Bool = false, commitFinish: Bool = false) -> Bool {
        guard linkedSessionId != nil, linkService.canEditLinkedMatch else { return false }
        let snapshot = linkedSnapshot(finished: finished)
        linkService.publishSnapshot(.archery(snapshot), detailedActions: store.actionLog.detailedActions)
        if snapshot.finished, commitFinish {
            return linkService.publishMatchFinished(
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
        return true
    }

    @discardableResult
    private func finalizeArcheryFinish() -> Bool {
        guard isMatchFinished, !finishCommitted, !scoringLocked else { return true }
        undoButtonVisible = false
        let saved = linkedSessionId != nil
            ? publishLinked(finished: true, commitFinish: true)
            : saveMatchRecord()
        guard saved else {
            showRecordSaveFailure = true
            return false
        }
        finishCommitted = true
        resumeStore.clear()
        return true
    }

    private func applyRemote(_ remote: LinkedArcheryState) {
        var state = store.state
        remote.applying(to: &state)
        store.rebase(to: state)
        applyMatch(state)
        showScorePanel = false
        confirmation = nil
        restState = nil
        setEnding = state.setCompletionPending && !state.closestToCenterPending
        showClosestToCenter = state.closestToCenterPending
        if remote.finished {
            winner = remote.leftSetPoints == remote.rightSetPoints
                ? nil
                : (remote.leftSetPoints > remote.rightSetPoints)
            isStopped = true
        } else {
            winner = nil
            isStopped = false
            isManualFinish = false
        }
    }

    private func saveMatchRecord() -> Bool {
        guard !recordSaved else { return true }
        let endTime = Date()
        guard let record = WatchScoreboardRecord(
            localSnapshot: .archery(linkedSnapshot(finished: true)), gameType: .archeryDual,
            id: "w_\(UUID().uuidString)", startTime: matchStartTime, endTime: endTime,
            winnerSide: winner.map { $0 ? .left : .right },
            detailedActions: store.actionLog.detailedActions, totalScoreChanges: store.actionLog.scoreChangeCount
        ) else { return false }
        guard resumeStore.saveFinishedRecord(record) else { return false }
        recordSaved = true
        return true
    }
}
