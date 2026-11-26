//
//  WatchArcheryScoreView.swift
//  jifenWatch Watch App
//
//  Set points: first to 6. Each set: 3 arrows each (1 at 5-5). Tap side to open score grid (0-10, M).
//  Shoot-off: win +1; same rings → closest-to-centre; next set first shooter via ArcheryShooterRules.
//

import LinkCore
import ScoreCore
import SessionCore
import SwiftUI

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

    @State private var showRecordSaveFailure = false
    @State private var store: WatchArcherySessionStore
    @State private var setEnding: Bool = false
    @State private var setEndTask: Task<Void, Never>?
    @State private var showScorePanel: Bool = false
    @State private var showClosestToCenter: Bool = false
    @State private var showMenu: Bool = false
    @State private var isManualFinish: Bool = false
    @State private var undoButtonVisible: Bool = false
    @State private var undoHideTimer: Timer? = nil
    @State private var toastMessage: String? = nil
    @State private var scoreboardLayout: String = "horizontal"
    @State private var restState: WatchRestState?
    @State private var confirmation: WatchScoreboardConfirmation?
    @State private var suppressTapAfterLongPress = false

    private var redScore: Int { store.state.leftArrowSum }
    private var blueScore: Int { store.state.rightArrowSum }
    private var redSets: Int { store.state.leftSetPoints }
    private var blueSets: Int { store.state.rightSetPoints }
    /// `true` = red/left engine slot currently shooting.
    private var currentShooter: Bool { store.state.currentShooterIsLeft }
    private var arrowsRedThisSet: Int { store.state.arrowsLeftThisSet }
    private var arrowsBlueThisSet: Int { store.state.arrowsRightThisSet }
    private var pendingSetNumber: Int { store.state.pendingSetNumber }
    private var leftName: String { store.state.leftName }
    private var rightName: String { store.state.rightName }
    private var matchStartTime: Date { store.startedAt }

    init(
        initialState: ArcheryMatchState? = nil,
        linkedSessionId: UUID? = nil,
        resumeBundle: WatchArcherySessionStore.ResumeBundle? = nil,
        resumedStartTime: Date? = nil,
        resumedRestState: WatchRestState? = nil,
        resumedActionLog: WatchScoreActionLog? = nil
    ) {
        self.linkedSessionId = linkedSessionId
        _store = State(initialValue: WatchArcherySessionStore(
            initialState: initialState,
            resumeBundle: resumeBundle,
            resumedStartTime: resumedStartTime,
            resumedActionLog: resumedActionLog
        ))
        _restState = State(initialValue: resumedRestState)
    }

    private var isMatchFinished: Bool { matchState.finished }
    private var winner: MatchSide? { matchState.winnerSide }

    private var scoringLocked: Bool {
        linkedSessionId != nil && !linkService.canEditLinkedMatch
    }

    var body: some View {
        ZStack {
            mainBoard
            if showScorePanel { scorePanelOverlay }
            if setEnding { setEndOverlay }
            if showClosestToCenter { closestToCenterOverlay }
            if isMatchFinished { stoppedOverlay }
            if let restState, !scoringLocked {
                WatchRestOverlay(
                    state: restState,
                    onContinue: {
                        self.restState = nil
                        persistResumeSession()
                    },
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
            if matchState.setCompletionPending, !matchState.finished, restState == nil, !scoringLocked {
                endSetFromPending()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = WatchPreferences.shared.scoreboardLayout
        }
        .onChange(of: scoringLocked) { _, locked in
            if locked {
                restState = nil
                cancelSetEnd()
            } else if matchState.setCompletionPending, !matchState.finished {
                endSetFromPending()
            }
        }
        .onChange(of: linkService.latestSnapshot, initial: true) { previous, update in
            guard let linkedSessionId, let update, update.sessionId == linkedSessionId,
                  update.matchGeneration == linkService.activeHandle?.matchGeneration,
                  let remote = update.snapshot.archeryState else { return }
            let acceptsScore = linkService.incomingSnapshot != nil
            if acceptsScore, update.beginsMatch(after: previous) {
                undoHideTimer?.invalidate()
                undoHideTimer = nil
                undoButtonVisible = false
                store = WatchArcherySessionStore(initialState: remote, resumedStartTime: Date())
            }
            let historyChanged = store.mergeRemoteActions(update.detailedActions, removing: update.removedActionIDs)
            guard acceptsScore, store.applyAuthoritativeState(
                remote, revision: update.revision, matchGeneration: update.matchGeneration
            ) else {
                if historyChanged { persistResumeSession() }
                return
            }
            applyRemote(remote)
        }
        .onChange(of: store.state) { _, _ in
            persistResumeSession()
        }
        .onDisappear {
            cancelSetEnd()
            undoHideTimer?.invalidate()
            if isMatchFinished {
                finalizeArcheryFinish()
            }
            persistResumeSession()
        }
        .watchScoreboardGestures(
            suppressTapAfterLongPress: $suppressTapAfterLongPress,
            enabled: !showScorePanel && !setEnding && !showClosestToCenter
                && !isMatchFinished && !showMenu && restState == nil && confirmation == nil,
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
        .opacity(isMatchFinished && winner != nil && winner != (isRed ? .left : .right) ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            let isCurrent = (isRed && currentShooter) || (!isRed && !currentShooter)
            if !isCurrent || suppressTapAfterLongPress || scoringLocked || isMatchFinished || setEnding
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
            winner: .side(winner),
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
        guard case .accepted(let session, let events) = store.apply(.recordArrow(side: nil, value: value)) else {
            return
        }
        updateMatchPresentation(session.state)
        WatchHaptics.shared.play(.score)
        publishLinked()
        for event in events {
            switch event {
            case .closestToCenterRequired, .setReady:
                endSetFromPending()
            default:
                break
            }
        }
    }

    private var matchState: ArcheryMatchState { store.state }

    private func updateMatchPresentation(_ state: ArcheryMatchState) {
        showClosestToCenter = state.closestToCenterPending
    }

    private func endSetFromPending() {
        cancelSetEnd()
        setEnding = true
        setEndTask = Task {
            do {
                try await Task.sleep(for: .seconds(setEndDelay))
            } catch {
                return
            }
            guard !scoringLocked, matchState.setCompletionPending else {
                setEnding = false
                return
            }
            if matchState.closestToCenterPending && redScore == 0 && blueScore == 0 {
                repeatShootOff()
                return
            }
            applySetEnd()
        }
    }

    private func cancelSetEnd() {
        setEndTask?.cancel()
        setEndTask = nil
        setEnding = false
    }

    private func applySetEnd() {
        if matchState.closestToCenterPending {
            setEnding = false
            showClosestToCenter = true
            return
        }
        guard case .accepted(let session, _) = store.apply(
            .completeSet(closestToCenterWinner: nil), recordHistory: false, recordsNonUndoableActions: true
        ) else {
            setEnding = false
            return
        }
        updateMatchPresentation(session.state)
        finishAfterReducer(session.state)
    }

    private func applyClosestToCenter(redWins: Bool) {
        guard !scoringLocked else { return }
        guard case .accepted(let session, _) = store.apply(
            .completeSet(closestToCenterWinner: redWins ? .left : .right),
            recordHistory: false, recordsNonUndoableActions: true
        ) else { return }
        cancelSetEnd()
        updateMatchPresentation(session.state)
        finishAfterReducer(session.state)
    }

    private func repeatShootOff() {
        guard !scoringLocked,
              case .accepted(let session, _) = store.apply(
                  .repeatShootOff, recordHistory: false, recordsNonUndoableActions: true
              ) else { return }
        cancelSetEnd()
        updateMatchPresentation(session.state)
        publishLinked()
    }

    private func finishAfterReducer(_ state: ArcheryMatchState) {
        if state.finished {
            isManualFinish = false
            showUndoButton()
            publishLinked()
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
        undoHideTimer?.invalidate()
        undoHideTimer = nil
        undoButtonVisible = false
        showClosestToCenter = store.state.closestToCenterPending
        cancelSetEnd()
        restState = nil
        isManualFinish = false
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
        guard case .accepted(let session, _) = store.apply(.finish) else { return }
        cancelSetEnd()
        updateMatchPresentation(session.state)
        showUndoButton()
        isManualFinish = true
        WatchHaptics.shared.play(.finish)
        publishLinked()
    }

    private func resetMatch() {
        guard !scoringLocked, !isMatchFinished || finalizeArcheryFinish() else { return }
        resumeStore.clear()
        undoHideTimer?.invalidate()
        undoHideTimer = nil
        let timestamp = Date()
        let freshState = ArcheryMatchReducer().reduce(
            state: store.state, intent: .reset,
            at: WatchArcherySessionStore.epochMilliseconds(timestamp)
        ).state
        store = WatchArcherySessionStore(initialState: freshState, resumedStartTime: timestamp)
        updateMatchPresentation(freshState)
        cancelSetEnd()
        showScorePanel = false
        showClosestToCenter = false
        showMenu = false
        restState = nil
        isManualFinish = false
        undoButtonVisible = false
        if linkedSessionId != nil {
            linkService.startNextMatch(
                snapshot: .archery(freshState),
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
            if store.savedRecordID != nil { resumeStore.clear() }
            return
        }
        let context = linkedSessionId == nil ? nil : linkService.resumeContext
        if let linkedSessionId, context?.handle.sessionId != linkedSessionId { return }
        guard redScore + blueScore + redSets + blueSets > 0 || store.canUndo else {
            resumeStore.clear()
            return
        }
        store.persistResumeSession(
            into: resumeStore, link: context,
            payload: .archery(bundle: store.resumeBundle(), restState: restState)
        )
    }

    private func showToast(_ text: String) {
        toastMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            toastMessage = nil
        }
    }

    @discardableResult
    private func publishLinked(commitFinish: Bool = false) -> Bool {
        guard linkedSessionId != nil, linkService.canEditLinkedMatch else { return false }
        let snapshot = store.snapshot
        linkService.publishSnapshot(snapshot, detailedActions: store.actionLog.detailedActions)
        if snapshot.isFinished, commitFinish {
            return linkService.publishMatchFinished(
                snapshot: snapshot,
                recordId: matchRecordID,
                winnerSide: winner,
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
        guard isMatchFinished, store.savedRecordID == nil, !scoringLocked else { return true }
        undoButtonVisible = false
        let saved = linkedSessionId != nil
            ? publishLinked(commitFinish: true)
            : saveMatchRecord()
        guard saved else {
            showRecordSaveFailure = true
            return false
        }
        if linkedSessionId != nil { store.markRecordSaved(matchRecordID) }
        resumeStore.clear()
        return true
    }

    private func applyRemote(_ state: ArcheryMatchState) {
        cancelSetEnd()
        updateMatchPresentation(state)
        showScorePanel = false
        confirmation = nil
        restState = nil
        if !state.finished {
            isManualFinish = false
            if state.setCompletionPending, !scoringLocked {
                endSetFromPending()
            }
        }
    }

    private var matchRecordID: String {
        let prefix = linkedSessionId == nil ? "w_" : "w_archery_"
        return prefix + store.machine.currentSession.sessionId.uuidString
    }

    private func saveMatchRecord() -> Bool {
        store.saveFinishedRecord(
            into: resumeStore,
            gameType: .archeryDual,
            recordID: matchRecordID,
            endTime: Date(),
            winnerSide: winner
        )
    }
}
