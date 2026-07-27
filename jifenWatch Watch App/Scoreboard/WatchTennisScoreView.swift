import LinkCore
import Observation
import PersistenceCore
import RecordCore
import ScoreCore
import SessionCore
import SwiftUI

@MainActor
@Observable
private final class WatchTennisSessionStore {
    typealias ResumeBundle = ScoreSessionResumeBundle<TennisMatchState, TennisMatchEvent, TennisMatchIntent>

    private let core: ScoreSessionCore<TennisMatchReducer>
    private let archiveRepository = SessionArchiveRepository()
    private(set) var state: TennisMatchState
    private(set) var actionLog: WatchScoreActionLog
    var onStateChanged: ((TennisMatchState, [TennisMatchEvent]) -> Void)?

    init(
        gameType: GameType,
        rules: TennisRuleSet,
        initialState: TennisMatchState? = nil,
        resumeBundle: ResumeBundle? = nil,
        resumedActionLog: WatchScoreActionLog? = nil,
        startedAt: Date = Date()
    ) {
        let defaults = WatchDefaultTeamNames.resolve()
        let initial = resumeBundle?.currentSession.state ?? initialState ?? TennisMatchState(
            leftName: defaults.left,
            rightName: defaults.right,
            rules: rules
        )
        if let resumeBundle {
            core = ScoreSessionCore(
                resumeBundle: resumeBundle,
                reducer: TennisMatchReducer(),
                shouldFinish: { _, state in state.finished }
            )
        } else {
            let session = ScoreSession<TennisMatchState, TennisMatchEvent>(
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
                reducer: TennisMatchReducer(),
                shouldFinish: { _, state in state.finished }
            )
        }
        state = initial
        actionLog = resumedActionLog ?? WatchScoreActionLog(startedAt: startedAt)
    }

    func score(_ side: MatchSide) {
        send(.pointWon(side))
    }

    func send(_ intent: TennisMatchIntent) {
        Task { [weak self, core] in
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            guard let self else { return }
            self.actionLog.beginUndoableMutation()
            guard case .accepted(let session, let events) = await core.dispatch(actorId: "watch", intent: intent, at: now) else {
                self.actionLog.rejectUndoableMutation()
                return
            }
            self.state = session.state
            if case .reset = intent {
                self.actionLog.reset(at: Date(timeIntervalSince1970: TimeInterval(now) / 1_000))
            } else {
                self.actionLog.append(contentsOf: WatchScoreActionProjector.tennis(
                    intent: intent,
                    events: events,
                    state: session.state,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(now) / 1_000)
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
            self.actionLog.undo(
                at: Date(),
                team1Score: session.state.leftPoints,
                team2Score: session.state.rightPoints,
                team1SetScore: session.state.leftSets,
                team2SetScore: session.state.rightSets
            )
            try? await self.archiveRepository.save(session, source: .watchLocal)
            self.onStateChanged?(session.state, [])
        }
    }

    func replaceDisplayedState(_ state: TennisMatchState) {
        self.state = state
    }

    func mergeRemoteActions(_ actions: [DetailedScoreAction]) {
        actionLog.merge(detailedActions: actions)
    }

    func resumeBundle() async -> ResumeBundle {
        await core.resumeBundle()
    }
}

struct WatchTennisScoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchLinkService.self) private var linkService
    @Environment(WatchResumeSessionStore.self) private var resumeStore

    let maxSets: Int
    let linkedSessionId: UUID?
    let isDoubles: Bool
    @State private var store: WatchTennisSessionStore
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
    @State private var completedSetPresentation: WatchTennisCompletedSetPresentation?
    @State private var completedScoreTask: Task<Void, Never>?

    init(
        maxSets: Int,
        initialState: TennisMatchState? = nil,
        linkedSessionId: UUID? = nil,
        isDoubles: Bool = false,
        resumeBundle: ScoreSessionResumeBundle<TennisMatchState, TennisMatchEvent, TennisMatchIntent>? = nil,
        resumedStartTime: Date? = nil,
        resumedRestState: WatchRestState? = nil,
        resumedActionLog: WatchScoreActionLog? = nil
    ) {
        self.maxSets = maxSets
        self.linkedSessionId = linkedSessionId
        self.isDoubles = isDoubles
        let rules = TennisRuleSet(maxSets: maxSets)
        let gameType: GameType = isDoubles ? .tennisDoubles : .tennis
        let startedAt = resumedStartTime ?? Date()
        _store = State(initialValue: WatchTennisSessionStore(
            gameType: gameType,
            rules: initialState?.rules ?? rules,
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
            if store.state.isTieBreak && !showMenu && restState == nil && !showFinishedOverlay {
                Text(NSLocalizedString("watch_tiebreak_indicator", value: "抢七", comment: ""))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.yellow)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Capsule())
            }
            if showSideExchangeToast {
                WatchSideExchangeToast()
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
                            score: String(store.state.rules.setScoringMode == .tiebreakOnly
                                ? store.state.leftPoints
                                : store.state.leftSets)
                        ),
                        WatchFinishedScoreItem(
                            name: store.state.rightName,
                            score: String(store.state.rules.setScoringMode == .tiebreakOnly
                                ? store.state.rightPoints
                                : store.state.rightSets)
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
            if !isDoubles {
                scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
            }
            store.onStateChanged = { [linkService] state, events in
                if linkedSessionId != nil {
                    guard linkService.isController else { return }
                    linkService.publishSnapshot(.tennis(state), detailedActions: store.actionLog.detailedActions)
                }
                handle(events: events, state: state)
                Task { await persistResumeSession() }
            }
            if store.state.finished { beginProvisionalFinish() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            guard !isDoubles else { return }
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
        }
        .onChange(of: linkService.latestSnapshot) { _, update in
            guard let linkedSessionId, let update, update.sessionId == linkedSessionId,
                  let state = update.snapshot.tennisState else { return }
            store.mergeRemoteActions(update.detailedActions)
            store.replaceDisplayedState(state)
            if state.finished {
                beginAutomaticFinishPresentation()
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
            if store.state.finished { finalizeFinish() }
            Task { await persistResumeSession() }
        }
    }

    private var mainBoard: some View {
        Group {
            if isDoubles, store.state.doublesPlayerNames != nil {
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
        let names = store.state.doublesPlayerNames ?? [
            store.state.leftName,
            store.state.rightName,
            store.state.leftName,
            store.state.rightName
        ]
        let layout = TeamScreenLayout(sidesSwapped: presentedSidesSwapped)
        let serverSlot = tennisDoublesServerSlot(state: store.state)
        return WatchDoublesBoard(
            left: tennisDoublesHalf(
                logicalSide: layout.engineSide(onScreen: .left),
                names: names,
                serverSlot: serverSlot
            ),
            right: tennisDoublesHalf(
                logicalSide: layout.engineSide(onScreen: .right),
                names: names,
                serverSlot: serverSlot
            )
        )
    }

    private func tennisDoublesHalf(
        logicalSide: MatchSide,
        names: [String],
        serverSlot: Int
    ) -> WatchDoublesHalfModel {
        let isLeft = logicalSide == .left
        let topIndex = isLeft ? 0 : 1
        let bottomIndex = isLeft ? 2 : 3
        let hasGames = store.state.rules.setScoringMode != .tiebreakOnly
            && presentedGamesTotal > 0
        let hasSets = store.state.rules.setScoringMode != .tiebreakOnly
            && presentedSetsTotal > 0
        let servingPosition: WatchDoublesHalfModel.PlayerPosition? = {
            guard completedSetPresentation == nil,
                  store.state.servingSide == logicalSide else { return nil }
            return serverSlot == bottomIndex ? .bottom : .top
        }()
        return WatchDoublesHalfModel(
            topName: names.indices.contains(topIndex) ? names[topIndex] : "",
            bottomName: names.indices.contains(bottomIndex) ? names[bottomIndex] : "",
            score: store.state.scoreDisplay(for: logicalSide),
            primaryMeta: hasGames
                ? "\(presentedGames(for: logicalSide))"
                : nil,
            secondaryMeta: hasSets
                ? "\(presentedSets(for: logicalSide))"
                : nil,
            color: isLeft ? Color(hex: 0xD93A34) : Color(hex: 0x1F78D1),
            servingPosition: servingPosition,
            onTap: {
                guard interactionsEnabled, !suppressTapAfterLongPress else { return }
                store.score(logicalSide)
            }
        )
    }

    private func side(_ screenSide: MatchSide, size: CGSize) -> some View {
        let logical = TeamScreenLayout(sidesSwapped: presentedSidesSwapped).engineSide(onScreen: screenSide)
        let isLeftTeam = logical == .left
        let name = isLeftTeam
            ? store.state.doublesTeamDisplayName(for: .left)
            : store.state.doublesTeamDisplayName(for: .right)
        let pointText = store.state.scoreDisplay(for: logical)
        let sets = presentedSets(for: logical)
        let games = presentedGames(for: logical)
        let isServing = completedSetPresentation == nil && store.state.servingSide == logical
        let showMeta = store.state.rules.setScoringMode != .tiebreakOnly
        let hasSets = showMeta && presentedSetsTotal > 0
        let hasGames = showMeta && presentedGamesTotal > 0
        let mainScoreFont = WatchScoreTypography.adaptiveFontSize(
            baseSize: isHorizontal ? 48 : 52,
            scoreText: pointText,
            minimumSize: 34,
            availableWidth: size.width,
            horizontalPadding: 12
        )

        return ZStack {
            Text(pointText)
                .font(.system(size: mainScoreFont, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, isHorizontal ? 28 : 8)

            if isHorizontal {
                if hasSets {
                    tennisSetDots(count: sets, vertical: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 62)
                }
                if hasGames {
                    Text("\(games)")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 40)
                }
            } else if hasSets || hasGames {
                HStack {
                    Group {
                        if hasGames {
                            Text("\(games)")
                                .font(.system(size: 24, weight: .medium))
                        } else {
                            Color.clear.frame(width: 24, height: 24)
                        }
                    }
                    Spacer()
                    if hasSets {
                        tennisSetDots(count: sets, vertical: true)
                    } else {
                        Color.clear.frame(width: 24, height: 24)
                    }
                }
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 40)
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
            store.score(logical)
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

    @ViewBuilder
    private func tennisSetDots(count: Int, vertical: Bool) -> some View {
        if vertical {
            VStack(spacing: 3) {
                ForEach(0..<count, id: \.self) { _ in
                    Circle()
                        .fill(Color.white.opacity(0.65))
                        .frame(width: 10, height: 10)
                }
            }
        } else {
            HStack(spacing: 4) {
                ForEach(0..<count, id: \.self) { _ in
                    Circle()
                        .fill(Color.white.opacity(0.65))
                        .frame(width: 8, height: 8)
                }
            }
        }
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
        if store.state.rules.setScoringMode == .tiebreakOnly {
            return "\(store.state.leftPoints) : \(store.state.rightPoints)"
        }
        return "\(store.state.leftSets) - \(store.state.rightSets)"
    }

    private var winnerText: String? {
        let left = store.state.rules.setScoringMode == .tiebreakOnly
            ? store.state.leftPoints
            : store.state.leftSets
        let right = store.state.rules.setScoringMode == .tiebreakOnly
            ? store.state.rightPoints
            : store.state.rightSets
        guard left != right else { return nil }
        let name = left > right ? store.state.leftName : store.state.rightName
        return String(
            format: NSLocalizedString("watch_winner_format", value: "%@ 获胜", comment: ""),
            name
        )
    }

    private func tennisDoublesServerSlot(state: TennisMatchState) -> Int {
        WatchTennisDoublesServing.serverSlot(
            firstServer: state.firstServerInSet,
            completedGames: state.leftGames + state.rightGames,
            isTieBreak: state.isTieBreak,
            tieBreakPointsPlayed: state.leftPoints + state.rightPoints
        )
    }

    private func handle(events: [TennisMatchEvent], state: TennisMatchState) {
        if let completed = WatchTennisCompletedSetPresentation.resolve(
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
            case .matchFinished:
                if manualFinishRequested {
                    beginProvisionalFinish()
                } else {
                    beginAutomaticFinishPresentation()
                }
            default:
                break
            }
        }
        if state.finished, !showFinishedOverlay, completedScoreTask == nil {
            manualFinishRequested ? beginProvisionalFinish() : beginAutomaticFinishPresentation()
        }
    }

    private var presentedSidesSwapped: Bool {
        completedSetPresentation?.sidesSwapped ?? store.state.sidesSwapped
    }

    private var presentedGamesTotal: Int {
        if let completedSetPresentation {
            return completedSetPresentation.leftGames + completedSetPresentation.rightGames
        }
        return store.state.leftGames + store.state.rightGames
    }

    private var presentedSetsTotal: Int {
        if let completedSetPresentation {
            return completedSetPresentation.leftSets + completedSetPresentation.rightSets
        }
        return store.state.leftSets + store.state.rightSets
    }

    private func presentedGames(for side: MatchSide) -> Int {
        if let completedSetPresentation {
            return side == .left
                ? completedSetPresentation.leftGames
                : completedSetPresentation.rightGames
        }
        return side == .left ? store.state.leftGames : store.state.rightGames
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
        _ presentation: WatchTennisCompletedSetPresentation,
        state: TennisMatchState
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

    private func beginAutomaticFinishPresentation() {
        guard completedScoreTask == nil, !showFinishedOverlay else { return }
        completedScoreTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(WatchTiming.completedScoreVisibility))
            guard !Task.isCancelled else { return }
            completedScoreTask = nil
            beginProvisionalFinish()
        }
    }

    private func beginBetweenSetRest(setNumber: Int) {
        guard !scoringLocked, WatchPreferences.shared.setBreakEnabled else { return }
        let triggerID = "tennis-set-\(setNumber)"
        guard restTriggers.consume(triggerID) else { return }
        restState = WatchRestState(
            kind: .betweenSets,
            title: NSLocalizedString("watch_rest_between_sets", value: "局间休息", comment: ""),
            durationSeconds: 120,
            triggerID: triggerID
        )
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
            let left = store.state.rules.setScoringMode == .tiebreakOnly
                ? store.state.leftPoints
                : store.state.leftSets
            let right = store.state.rules.setScoringMode == .tiebreakOnly
                ? store.state.rightPoints
                : store.state.rightSets
            let winner: MatchSide? = left == right ? nil : (left > right ? .left : .right)
            linkService.publishMatchFinished(
                snapshot: .tennis(store.state),
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
                || state.leftGames != 0 || state.rightGames != 0
                || state.leftSets != 0 || state.rightSets != 0 else {
            resumeStore.clear()
            return
        }
        let bundle = await store.resumeBundle()
        resumeStore.save(WatchResumeSession(
            startedAt: matchStartTime,
            scoreLine: scoreLine,
            emoji: "🎾",
            payload: .tennis(
                isDoubles: isDoubles,
                bundle: bundle,
                restState: restState
            ),
            actionLog: store.actionLog,
            link: linkService.resumeContext
        ))
    }

    private func transferLocalFinishedRecordIfNeeded(_ state: TennisMatchState) {
        guard !didTransferFinishedRecord else { return }
        didTransferFinishedRecord = true
        let end = Date()
        let leftScore = state.rules.setScoringMode == .tiebreakOnly ? state.leftPoints : state.leftSets
        let rightScore = state.rules.setScoringMode == .tiebreakOnly ? state.rightPoints : state.rightSets
        let winnerName: String? = {
            if leftScore == rightScore { return nil }
            return leftScore > rightScore ? state.leftName : state.rightName
        }()
        let record = WatchScoreboardRecord(
            id: "w_\(UUID().uuidString)",
            gameType: .tennis,
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
            participants: state.doublesPlayerNames?.map {
                WatchRecordParticipant(name: $0, score: 0)
            },
            projectConfiguration: [
                "maxSets": String(state.rules.maxSets),
                "usesNoAdScoring": String(state.rules.usesNoAdScoring),
                "isDoubles": String(state.doublesPlayerNames != nil)
            ]
        )
        WatchRecordManager.shared.saveRecord(record)
    }
}
