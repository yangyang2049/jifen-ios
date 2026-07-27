import Observation
import LinkCore
import PersistenceCore
import RecordCore
import ScoreCore
import SessionCore
import SwiftUI

@MainActor
@Observable
private final class WatchRallySessionStore {
    typealias ResumeBundle = ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>

    private let core: ScoreSessionCore<RallyMatchReducer>
    private let archiveRepository: SessionArchiveRepository

    private(set) var state: RallyMatchState
    private(set) var actionLog: WatchScoreActionLog

    init(
        gameType: GameType,
        rules: RallyRuleSet,
        initialState: RallyMatchState? = nil,
        resumeBundle: ResumeBundle? = nil,
        resumedActionLog: WatchScoreActionLog? = nil,
        startedAt: Date = Date()
    ) {
        let defaults = WatchDefaultTeamNames.resolve()
        let initial = resumeBundle?.currentSession.state ?? initialState ?? RallyMatchEngine.initial(
            leftName: defaults.left,
            rightName: defaults.right,
            rules: rules
        )
        if let resumeBundle {
            core = ScoreSessionCore(
                resumeBundle: resumeBundle,
                reducer: RallyMatchReducer(),
                shouldFinish: { _, state in state.finished }
            )
        } else {
            let session = ScoreSession<RallyMatchState, RallyMatchEvent>(
                gameType: gameType,
                ruleFamily: .s1,
                reducerType: ScoreboardKernelRegistry.descriptor(for: gameType).reducerType,
                state: initial,
                participants: [
                    .init(id: TeamID.team0.rawValue, name: initial.leftName, role: "team"),
                    .init(id: TeamID.team1.rawValue, name: initial.rightName, role: "team")
                ]
            )
            core = ScoreSessionCore(
                seedSession: session,
                reducer: RallyMatchReducer(),
                shouldFinish: { _, state in state.finished }
            )
        }
        archiveRepository = SessionArchiveRepository()
        state = initial
        actionLog = WatchScoreActionLog(startedAt: startedAt, resumed: resumedActionLog)
    }

    func score(_ side: MatchSide) {
        send(.pointWon(side))
    }

    func send(_ intent: RallyMatchIntent) {
        Task { [weak self, core] in
            let timestamp = Date()
            let now = Int64(timestamp.timeIntervalSince1970 * 1_000)
            guard let self else { return }
            self.actionLog.beginUndoableMutation()
            guard case .accepted(let session, let events) = await core.dispatch(actorId: "watch", intent: intent, at: now) else {
                self.actionLog.rejectUndoableMutation()
                return
            }
            self.state = session.state
            if case .reset = intent {
                self.actionLog.reset(at: timestamp)
            } else {
                self.actionLog.append(contentsOf: WatchScoreActionProjector.rally(
                    intent: intent,
                    events: events,
                    state: session.state,
                    timestamp: timestamp
                ))
            }
            try? await self.archiveRepository.save(session, source: .watchLocal)
            self.onStateChanged?(session.state, events)
        }
    }

    func undo() {
        Task { [weak self, core] in
            guard await core.undo(actorId: "watch"), let self else { return }
            let session = await core.snapshot()
            self.state = session.state
            _ = self.actionLog.undo(
                team1Score: session.state.leftPoints,
                team2Score: session.state.rightPoints,
                team1SetScore: session.state.leftSets,
                team2SetScore: session.state.rightSets
            )
            try? await self.archiveRepository.save(session, source: .watchLocal)
            self.onStateChanged?(session.state, [])
        }
    }

    var onStateChanged: ((RallyMatchState, [RallyMatchEvent]) -> Void)?

    func persist() {
        Task { [core, archiveRepository] in
            let session = await core.snapshot()
            try? await archiveRepository.save(session, source: .watchLocal)
        }
    }

    func replaceDisplayedState(_ state: RallyMatchState) {
        self.state = state
    }

    func mergeRemoteActions(_ actions: [DetailedScoreAction]) {
        actionLog.merge(detailedActions: actions)
    }

    func resumeBundle() async -> ResumeBundle {
        await core.resumeBundle()
    }
}

struct WatchRallyScoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchLinkService.self) private var linkService
    @Environment(WatchResumeSessionStore.self) private var resumeStore

    let gameType: GameType
    let rules: RallyRuleSet
    let linkedSessionId: UUID?
    @State private var store: WatchRallySessionStore
    @State private var showMenu = false
    @State private var matchStartTime = Date()
    @State private var didTransferFinishedRecord = false
    @State private var scoreboardLayout: String = "horizontal"
    @State private var restState: WatchRestState?
    @State private var showSideExchangeToast = false
    @State private var confirmation: WatchScoreboardConfirmation?
    @State private var showFinishedOverlay = false
    @State private var finishUndoAvailable = false
    @State private var didFinalizeFinish = false
    @State private var finishTask: Task<Void, Never>?
    @State private var suppressTapAfterLongPress = false
    @State private var manualFinishRequested = false
    @State private var restTriggers = WatchRestTriggerRegistry()
    @State private var sideExchangeTask: Task<Void, Never>?
    @State private var completedSetPresentation: WatchRallyCompletedSetPresentation?
    @State private var completedScoreTask: Task<Void, Never>?

    init(
        gameType: GameType,
        rules: RallyRuleSet,
        initialState: RallyMatchState? = nil,
        linkedSessionId: UUID? = nil,
        resumeBundle: ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>? = nil,
        resumedStartTime: Date? = nil,
        resumedRestState: WatchRestState? = nil,
        resumedActionLog: WatchScoreActionLog? = nil
    ) {
        self.gameType = gameType
        self.rules = rules
        self.linkedSessionId = linkedSessionId
        let startedAt = resumedStartTime ?? Date()
        _store = State(initialValue: WatchRallySessionStore(
            gameType: gameType,
            rules: rules,
            initialState: initialState,
            resumeBundle: resumeBundle,
            resumedActionLog: resumedActionLog,
            startedAt: startedAt
        ))
        _matchStartTime = State(initialValue: startedAt)
        _restState = State(initialValue: resumedRestState)
    }

    private var scoringLocked: Bool {
        linkedSessionId != nil && linkService.isFollower
    }

    private var isHorizontal: Bool { scoreboardLayout == "horizontal" }

    var body: some View {
        ZStack {
            mainBoard
            if showSideExchangeToast {
                WatchSideExchangeToast()
                    .transition(.opacity)
            }
            if showMenu {
                WatchScoreboardMenuOverlay(
                    onDismiss: { showMenu = false },
                    onUndo: {
                        store.undo()
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
            if let restState {
                WatchRestOverlay(
                    state: restState,
                    onContinue: { self.restState = nil },
                    onUndo: {
                        let triggerID = restState.triggerID
                        self.restState = nil
                        restTriggers.release(triggerID)
                        store.undo()
                    }
                )
            }
            if showFinishedOverlay {
                WatchFinishedOverlay(
                    title: NSLocalizedString("watch_match_finished", value: "比赛结束", comment: ""),
                    scoreItems: [
                        WatchFinishedScoreItem(
                            name: store.state.leftName,
                            score: String(store.state.leftSets + store.state.rightSets > 0
                                ? store.state.leftSets
                                : store.state.leftPoints)
                        ),
                        WatchFinishedScoreItem(
                            name: store.state.rightName,
                            score: String(store.state.leftSets + store.state.rightSets > 0
                                ? store.state.rightSets
                                : store.state.rightPoints)
                        )
                    ],
                    winnerText: winnerText,
                    undoAvailable: finishUndoAvailable,
                    onUndo: undoFinish,
                    onPlayAgain: playAgain,
                    onExit: finishAndExit
                )
            }
            if let confirmation {
                WatchConfirmationOverlay(
                    confirmation: confirmation,
                    onCancel: { self.confirmation = nil },
                    onConfirm: { confirm(confirmation) }
                )
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if store.state.doubles == nil {
                scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
            }
            store.onStateChanged = { [linkService] state, events in
                if linkedSessionId != nil {
                    guard linkService.isController else { return }
                    linkService.publishSnapshot(.rally(state), detailedActions: store.actionLog.detailedActions)
                }
                handle(events: events, state: state)
                Task { await persistResumeSession() }
            }
            if store.state.finished {
                beginProvisionalFinish()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            guard store.state.doubles == nil else { return }
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
        }
        .onChange(of: linkService.latestSnapshot) { _, update in
            guard let linkedSessionId,
                  let update,
                  update.sessionId == linkedSessionId else { return }
            guard let state = update.snapshot.rallyState else { return }
            store.mergeRemoteActions(update.detailedActions)
            store.replaceDisplayedState(state)
            if state.finished {
                beginRemoteFinishPresentation()
            } else {
                completedScoreTask?.cancel()
                completedScoreTask = nil
                completedSetPresentation = nil
                finishTask?.cancel()
                showFinishedOverlay = false
                finishUndoAvailable = false
                didFinalizeFinish = false
            }
        }
        .onDisappear {
            finishTask?.cancel()
            sideExchangeTask?.cancel()
            completedScoreTask?.cancel()
            if store.state.finished {
                finalizeFinish()
            }
            if !scoringLocked {
                store.persist()
            }
            Task { await persistResumeSession() }
        }
    }

    private var mainBoard: some View {
        Group {
            if store.state.doubles != nil {
                doublesBoard
            } else {
                GeometryReader { proxy in
                    let width = proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing
                    let height = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
                    Group {
                        if isHorizontal {
                            HStack(spacing: 0) {
                                side(.left, size: CGSize(width: width / 2, height: height))
                                side(.right, size: CGSize(width: width / 2, height: height))
                            }
                            .frame(width: width, height: height)
                        } else {
                            VStack(spacing: 0) {
                                side(.left, size: CGSize(width: width, height: height / 2))
                                side(.right, size: CGSize(width: width, height: height / 2))
                            }
                            .frame(width: width, height: height)
                        }
                    }
                    .offset(x: -proxy.safeAreaInsets.leading, y: -proxy.safeAreaInsets.top)
                }
                .ignoresSafeArea()
            }
        }
        .watchScoreboardGestures(
            suppressTapAfterLongPress: $suppressTapAfterLongPress,
            enabled: interactionsEnabled,
            onMenu: { showMenu = true },
            onUndo: { store.undo() },
            onExit: exitBoard
        )
    }

    private var doublesBoard: some View {
        let doubles = store.state.doubles
        let names = doubles?.playerNames ?? [
            store.state.leftName,
            store.state.rightName,
            store.state.leftName,
            store.state.rightName
        ]
        let layout = TeamScreenLayout(sidesSwapped: presentedSidesSwapped)
        let leftLogical = layout.engineSide(onScreen: .left)
        let rightLogical = layout.engineSide(onScreen: .right)
        return WatchDoublesBoard(
            left: doublesHalf(
                screenSide: .left,
                logicalSide: leftLogical,
                names: names
            ),
            right: doublesHalf(
                screenSide: .right,
                logicalSide: rightLogical,
                names: names
            )
        )
    }

    private func doublesHalf(
        screenSide: MatchSide,
        logicalSide: MatchSide,
        names: [String]
    ) -> WatchDoublesHalfModel {
        let isLeft = logicalSide == .left
        let fallbackTopIndex = isLeft ? 0 : 1
        let fallbackBottomIndex = isLeft ? 2 : 3
        let display = store.state.doubles.map {
            WatchDoublesDisplayState.resolve(
                doubles: $0,
                logicalSide: logicalSide,
                screenSide: screenSide
            )
        }
        let topIndex = display?.topPlayerIndex ?? fallbackTopIndex
        let bottomIndex = display?.bottomPlayerIndex ?? fallbackBottomIndex
        let points = presentedPoints(for: logicalSide)
        let sets = presentedSets(for: logicalSide)
        let showSets = store.state.leftSets + store.state.rightSets > 0 || store.state.currentSet > 1
        let servingPosition: WatchDoublesHalfModel.PlayerPosition? = {
            guard completedSetPresentation == nil,
                  store.state.servingSide == logicalSide,
                  let serverIsTop = display?.serverIsTop else { return nil }
            return serverIsTop ? .top : .bottom
        }()
        return WatchDoublesHalfModel(
            topName: names.indices.contains(topIndex) ? names[topIndex] : "",
            bottomName: names.indices.contains(bottomIndex) ? names[bottomIndex] : "",
            score: "\(points)",
            primaryMeta: showSets ? "\(sets)" : nil,
            secondaryMeta: nil,
            color: isLeft ? Color(hex: 0xD93A34) : Color(hex: 0x1F78D1),
            servingPosition: servingPosition,
            onTap: {
                guard interactionsEnabled, !suppressTapAfterLongPress else { return }
                store.score(logicalSide)
            }
        )
    }

    private func side(_ screenSide: MatchSide, size: CGSize) -> some View {
        let layout = TeamScreenLayout(sidesSwapped: presentedSidesSwapped)
        let logicalSide = layout.engineSide(onScreen: screenSide)
        let isLeftTeam = logicalSide == .left
        let name = isLeftTeam ? store.state.leftName : store.state.rightName
        let points = presentedPoints(for: logicalSide)
        let sets = presentedSets(for: logicalSide)
        let isServing = completedSetPresentation == nil && store.state.servingSide == logicalSide
        let showSets = store.state.leftSets + store.state.rightSets > 0 || store.state.currentSet > 1
        let scoreText = "\(points)"
        let mainScoreFont = WatchScoreTypography.adaptiveFontSize(
            baseSize: isHorizontal ? 64 : 62,
            scoreText: scoreText,
            minimumSize: 42,
            availableWidth: size.width,
            horizontalPadding: 12
        )

        return ZStack {
            // Main point score (Harmony-style: no helper caption).
            Text(scoreText)
                .font(.system(size: mainScoreFont, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            // Team name
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isHorizontal ? .top : .top)
                .padding(.top, isHorizontal ? 28 : 8)

            // Set score on each half (no floating center card).
            if showSets {
                Text("\(sets)")
                    .font(.system(size: isHorizontal ? 20 : 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: isHorizontal ? .bottom : .leading
                    )
                    .padding(.bottom, isHorizontal ? 28 : 0)
                    .padding(.leading, isHorizontal ? 0 : 16)
            }

            if isServing {
                servingIndicator(screenSide: screenSide)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(isLeftTeam ? Color(hex: 0xE53935) : Color(hex: 0x1E88E5))
        .contentShape(Rectangle())
        .onTapGesture {
            guard interactionsEnabled, !suppressTapAfterLongPress else { return }
            store.score(logicalSide)
        }
    }

    @ViewBuilder
    private func servingIndicator(screenSide: MatchSide) -> some View {
        let direction: WatchServerIndicatorDirection = {
            if isHorizontal {
                return screenSide == .left ? .right : .left
            }
            return screenSide == .left ? .bottom : .top
        }()
        let alignment: Alignment = {
            if isHorizontal {
                return screenSide == .left ? .leading : .trailing
            }
            return screenSide == .left ? .top : .bottom
        }()
        WatchServerIndicator(
            direction: direction,
            size: WatchLayout.serverIndicatorSize,
            color: WatchTheme.accent
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(.vertical, isHorizontal ? 6 : 0)
            .padding(.horizontal, isHorizontal ? 0 : 6)
            .allowsHitTesting(false)
    }

    private func normalizedLayout(_ raw: String) -> String {
        raw == "vertical" ? "vertical" : "horizontal"
    }

    private var interactionsEnabled: Bool {
        !scoringLocked
            && !store.state.finished
            && completedSetPresentation == nil
            && restState == nil
            && !showFinishedOverlay
            && confirmation == nil
            && !showMenu
    }

    private var scoreLine: String {
        if store.state.leftSets + store.state.rightSets > 0 {
            return "\(store.state.leftSets) - \(store.state.rightSets)"
        }
        return "\(store.state.leftPoints) : \(store.state.rightPoints)"
    }

    private var winnerText: String? {
        guard store.state.leftSets != store.state.rightSets else { return nil }
        let name = store.state.leftSets > store.state.rightSets
            ? store.state.leftName
            : store.state.rightName
        return String(
            format: NSLocalizedString("watch_winner_format", value: "%@ 获胜", comment: ""),
            name
        )
    }

    private func handle(events: [RallyMatchEvent], state: RallyMatchState) {
        reconcileBadmintonMidGameRestTrigger(for: state)
        if let completed = WatchRallyCompletedSetPresentation.resolve(
            events: events,
            currentSidesSwapped: state.sidesSwapped
        ) {
            beginCompletedSetPresentation(completed, state: state)
            return
        }
        for event in events {
            switch event {
            case .setCompleted(_, let setNumber, _, _, _, _):
                guard !state.finished else { continue }
                beginBetweenSetRest(setNumber: setNumber)
            case .sidesExchanged, .sidesExchangeReminder:
                showSideExchange()
            case .pointScored:
                beginBadmintonMidGameRestIfNeeded(state)
            case .matchFinished:
                beginProvisionalFinish()
            default:
                break
            }
        }
        if state.finished {
            beginProvisionalFinish()
        }
    }

    private var presentedSidesSwapped: Bool {
        completedSetPresentation?.sidesSwapped ?? store.state.sidesSwapped
    }

    private func presentedPoints(for side: MatchSide) -> Int {
        if let completedSetPresentation {
            return side == .left
                ? completedSetPresentation.leftPoints
                : completedSetPresentation.rightPoints
        }
        return side == .left ? store.state.leftPoints : store.state.rightPoints
    }

    private func presentedSets(for side: MatchSide) -> Int {
        if let completedSetPresentation {
            return side == .left
                ? completedSetPresentation.leftSets
                : completedSetPresentation.rightSets
        }
        return side == .left ? store.state.leftSets : store.state.rightSets
    }

    private func beginCompletedSetPresentation(
        _ presentation: WatchRallyCompletedSetPresentation,
        state: RallyMatchState
    ) {
        completedScoreTask?.cancel()
        restState = nil
        showSideExchangeToast = false
        completedSetPresentation = presentation
        completedScoreTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(WatchTiming.completedScoreVisibility))
            guard !Task.isCancelled else { return }
            let didExchangeSides = presentation.sidesSwapped != state.sidesSwapped
            completedSetPresentation = nil
            completedScoreTask = nil
            if state.finished {
                beginProvisionalFinish()
            } else {
                beginBetweenSetRest(setNumber: presentation.setNumber)
                if restState == nil, didExchangeSides {
                    showSideExchange()
                }
            }
        }
    }

    private func beginRemoteFinishPresentation() {
        guard completedScoreTask == nil, !showFinishedOverlay else { return }
        completedScoreTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(WatchTiming.completedScoreVisibility))
            guard !Task.isCancelled else { return }
            completedScoreTask = nil
            beginProvisionalFinish()
        }
    }

    private func beginBetweenSetRest(setNumber: Int) {
        guard !scoringLocked,
              WatchPreferences.shared.setBreakEnabled,
              let duration = WatchRestPolicy.betweenSetDuration(for: gameType) else { return }
        let triggerID = "set-\(setNumber)"
        guard restTriggers.consume(triggerID) else { return }
        restState = WatchRestState(
            kind: .betweenSets,
            title: NSLocalizedString("watch_rest_between_sets", value: "局间休息", comment: ""),
            durationSeconds: duration,
            triggerID: triggerID
        )
    }

    private func beginBadmintonMidGameRestIfNeeded(_ state: RallyMatchState) {
        guard !scoringLocked,
              WatchPreferences.shared.setBreakEnabled,
              gameType == .badminton || gameType == .badmintonDoubles else { return }
        let point = WatchRestPolicy.badmintonMidGamePoint(
            pointsToWinSet: state.rules.pointsToWinSet
        )
        guard max(state.leftPoints, state.rightPoints) == point else { return }
        let triggerID = badmintonMidGameTriggerID(setNumber: state.currentSet, point: point)
        guard restTriggers.consume(triggerID) else { return }
        restState = WatchRestState(
            kind: .midGame,
            title: NSLocalizedString("watch_mid_game_rest", value: "局中休息", comment: ""),
            durationSeconds: 60,
            triggerID: triggerID
        )
    }

    private func reconcileBadmintonMidGameRestTrigger(for state: RallyMatchState) {
        guard gameType == .badminton || gameType == .badmintonDoubles else { return }
        let point = WatchRestPolicy.badmintonMidGamePoint(
            pointsToWinSet: state.rules.pointsToWinSet
        )
        guard max(state.leftPoints, state.rightPoints) < point else { return }
        restTriggers.release(
            badmintonMidGameTriggerID(setNumber: state.currentSet, point: point)
        )
    }

    private func badmintonMidGameTriggerID(setNumber: Int, point: Int) -> String {
        "set-\(setNumber)-point-\(point)"
    }

    private func showSideExchange() {
        sideExchangeTask?.cancel()
        showSideExchangeToast = true
        sideExchangeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            showSideExchangeToast = false
        }
    }

    private func beginProvisionalFinish() {
        guard !showFinishedOverlay else { return }
        restState = nil
        showMenu = false
        showFinishedOverlay = true
        finishUndoAvailable = !scoringLocked
        didFinalizeFinish = false
        finishTask?.cancel()
        guard !scoringLocked else { return }
        finishTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(WatchTiming.undoCountdown))
            guard !Task.isCancelled else { return }
            finishUndoAvailable = false
            finalizeFinish()
        }
    }

    private func finalizeFinish() {
        guard store.state.finished, !didFinalizeFinish else { return }
        resumeStore.clear()
        didFinalizeFinish = true
        if linkedSessionId != nil {
            guard linkService.isController else { return }
            let winner: MatchSide? = store.state.leftSets == store.state.rightSets
                ? nil
                : (store.state.leftSets > store.state.rightSets ? .left : .right)
            linkService.publishMatchFinished(
                snapshot: .rally(store.state),
                recordId: "w_\(UUID().uuidString)",
                winnerSide: winner,
                manualEnd: manualFinishRequested,
                startTime: matchStartTime,
                endTime: Date(),
                totalScoreChanges: store.actionLog.scoreChangeCount,
                detailedActions: store.actionLog.detailedActions
            )
        } else {
            transferLocalFinishedRecordIfNeeded(store.state)
        }
    }

    private func undoFinish() {
        guard finishUndoAvailable else { return }
        completedScoreTask?.cancel()
        completedScoreTask = nil
        completedSetPresentation = nil
        finishTask?.cancel()
        showFinishedOverlay = false
        finishUndoAvailable = false
        didFinalizeFinish = false
        store.undo()
    }

    private func playAgain() {
        resumeStore.clear()
        finalizeFinish()
        finishTask?.cancel()
        showFinishedOverlay = false
        finishUndoAvailable = false
        didTransferFinishedRecord = false
        didFinalizeFinish = false
        manualFinishRequested = false
        restTriggers.reset()
        sideExchangeTask?.cancel()
        completedScoreTask?.cancel()
        completedScoreTask = nil
        completedSetPresentation = nil
        showSideExchangeToast = false
        matchStartTime = Date()
        store.send(.reset)
    }

    private func finishAndExit() {
        finalizeFinish()
        exitBoard()
    }

    private func confirm(_ value: WatchScoreboardConfirmation) {
        confirmation = nil
        switch value {
        case .finish:
            manualFinishRequested = true
            store.send(.finish)
        case .reset:
            resumeStore.clear()
            finishTask?.cancel()
            showFinishedOverlay = false
            restState = nil
            didTransferFinishedRecord = false
            didFinalizeFinish = false
            manualFinishRequested = false
            restTriggers.reset()
            sideExchangeTask?.cancel()
            completedScoreTask?.cancel()
            completedScoreTask = nil
            completedSetPresentation = nil
            showSideExchangeToast = false
            matchStartTime = Date()
            store.send(.reset)
        }
    }

    private func exitBoard() {
        if linkedSessionId != nil {
            if store.state.finished {
                linkService.leaveSession()
            } else {
                linkService.exitScoreboardToHome()
            }
        }
        dismiss()
    }

    private func persistResumeSession() async {
        let state = store.state
        guard !state.finished,
              state.leftPoints != 0 || state.rightPoints != 0
                || state.leftSets != 0 || state.rightSets != 0 else {
            resumeStore.clear()
            return
        }
        let bundle = await store.resumeBundle()
        resumeStore.save(WatchResumeSession(
            startedAt: matchStartTime,
            scoreLine: scoreLine,
            emoji: resumeEmoji,
            payload: .rally(
                gameType: gameType,
                bundle: bundle,
                restState: restState
            ),
            actionLog: store.actionLog,
            link: linkService.resumeContext
        ))
    }

    private var resumeEmoji: String {
        switch gameType {
        case .badminton, .badmintonDoubles: return "🏸"
        case .pingpong, .pingpongDoubles: return "🏓"
        case .pickleball, .pickleballDoubles: return "🏓"
        default: return "🏆"
        }
    }

    private func transferLocalFinishedRecordIfNeeded(_ state: RallyMatchState) {
        guard !didTransferFinishedRecord else { return }
        didTransferFinishedRecord = true
        let end = Date()
        let winnerName: String? = {
            if state.leftSets == state.rightSets { return nil }
            return state.leftSets > state.rightSets ? state.leftName : state.rightName
        }()
        let record = WatchScoreboardRecord(
            id: "w_\(UUID().uuidString)",
            gameType: watchGameType(for: gameType),
            startTime: matchStartTime,
            endTime: end,
            duration: end.timeIntervalSince(matchStartTime),
            team1Name: state.leftName,
            team2Name: state.rightName,
            team1FinalScore: state.leftPoints,
            team2FinalScore: state.rightPoints,
            team1SetScore: state.leftSets,
            team2SetScore: state.rightSets,
            winner: winnerName,
            actions: store.actionLog.actions,
            totalScoreChanges: store.actionLog.scoreChangeCount,
            participants: state.doubles?.playerNames.map {
                WatchRecordParticipant(name: $0, score: 0)
            },
            projectConfiguration: [
                "maxSets": String(state.rules.maxSets),
                "pointsPerSet": String(state.rules.pointsToWinSet),
                "rallyScoring": String(state.rules.useRallyScoring),
                "isDoubles": String(state.doubles != nil)
            ]
        )
        WatchRecordManager.shared.saveRecord(record)
    }

    private func watchGameType(for type: GameType) -> WatchGameType {
        switch type {
        case .pingpong, .pingpongDoubles: return .pingpong
        case .badminton, .badmintonDoubles: return .badminton
        case .pickleball, .pickleballDoubles: return .pickleball
        default: return .badminton
        }
    }
}
