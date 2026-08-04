import LinkCore
import Observation
import RecordCore
import ScoreCore
import SessionCore
import SwiftUI

@MainActor
@Observable
private final class WatchTennisSessionStore {
    typealias ResumeBundle = ScoreSessionResumeBundle<TennisMatchState, TennisMatchEvent, TennisMatchIntent>

    private let core: ScoreSessionCore<TennisMatchReducer>
    private(set) var state: TennisMatchState
    private(set) var actionLog: WatchScoreActionLog
    private var lastAppliedRemoteRevision: UInt64?
    var onStateChanged: ((TennisMatchState, [TennisMatchEvent]) -> Void)?

    init(
        gameType: GameType,
        rules: TennisRuleSet,
        initialState: TennisMatchState? = nil,
        resumeBundle: ResumeBundle? = nil,
        resumedActionLog: WatchScoreActionLog? = nil,
        startedAt: Date = Date()
    ) {
        let defaults = WatchDefaultTeamNames.resolve(for: gameType)
        // Priority: a resumeBundle only ever arrives from the explicit resume
        // flow (every fresh-launch path clears activeResumeSession first), so
        // it wins. Otherwise initialState (fresh phone Setup snapshot or local
        // setup) must be used as-is — never fall back to any historical state,
        // mirroring HarmonyOS, which discards the persisted session on every
        // non-resume scoreboard launch. Engine core and displayed state must
        // always come from the same source.
        let initial: TennisMatchState
        if let resumeBundle {
            core = ScoreSessionCore(
                resumeBundle: resumeBundle,
                reducer: TennisMatchReducer(),
                shouldFinish: { _, state in state.finished }
            )
            initial = resumeBundle.currentSession.state
        } else if let initialState {
            let session = ScoreSession<TennisMatchState, TennisMatchEvent>(
                gameType: gameType,
                ruleFamily: .s1,
                reducerType: ScoreboardKernelRegistry.descriptor(for: gameType).reducerType,
                state: initialState,
                participants: [
                    .init(id: TeamID.team0.rawValue, name: initialState.leftName, role: "team"),
                    .init(id: TeamID.team1.rawValue, name: initialState.rightName, role: "team")
                ]
            )
            core = ScoreSessionCore(
                seedSession: session,
                reducer: TennisMatchReducer(),
                shouldFinish: { _, state in state.finished }
            )
            initial = initialState
        } else {
            let fallback = TennisMatchState(
                leftName: defaults.left,
                rightName: defaults.right,
                rules: rules
            )
            let session = ScoreSession<TennisMatchState, TennisMatchEvent>(
                gameType: gameType,
                ruleFamily: .s1,
                reducerType: ScoreboardKernelRegistry.descriptor(for: gameType).reducerType,
                state: fallback,
                participants: [
                    .init(id: TeamID.team0.rawValue, name: fallback.leftName, role: "team"),
                    .init(id: TeamID.team1.rawValue, name: fallback.rightName, role: "team")
                ]
            )
            core = ScoreSessionCore(
                seedSession: session,
                reducer: TennisMatchReducer(),
                shouldFinish: { _, state in state.finished }
            )
            initial = fallback
        }
        state = initial
        actionLog = resumedActionLog ?? WatchScoreActionLog(startedAt: startedAt)
        if initial.rules.setScoringMode == .tiebreakOnly {
            actionLog.omitSecondaryScores()
        }
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
                if session.state.rules.setScoringMode == .tiebreakOnly {
                    self.actionLog.omitSecondaryScores()
                }
            } else {
                self.actionLog.append(contentsOf: WatchScoreActionProjector.tennis(
                    intent: intent,
                    events: events,
                    state: session.state,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(now) / 1_000)
                ))
            }
            self.onStateChanged?(session.state, events)
        }
    }

    func undo(onSuccess: @escaping () -> Void = {}) {
        Task { [weak self, core] in
            guard await core.undo(actorId: "watch"), let self else { return }
            let session = await core.snapshot()
            self.state = session.state
            self.actionLog.undo(
                at: Date(),
                team1Score: session.state.leftPoints,
                team2Score: session.state.rightPoints,
                team1SetScore: session.state.rules.setScoringMode == .tiebreakOnly
                    ? nil
                    : session.state.leftSets,
                team2SetScore: session.state.rules.setScoringMode == .tiebreakOnly
                    ? nil
                    : session.state.rightSets
            )
            self.onStateChanged?(session.state, [])
            onSuccess()
        }
    }

    @discardableResult
    func applyAuthoritativeState(
        _ state: TennisMatchState,
        detailedActions: [DetailedScoreAction],
        revision: UInt64
    ) async -> Bool {
        if let lastAppliedRemoteRevision, revision <= lastAppliedRemoteRevision {
            return false
        }
        lastAppliedRemoteRevision = revision
        let session = await core.rebase(
            to: state,
            status: state.finished ? .finished : .live
        )
        guard lastAppliedRemoteRevision == revision else { return false }
        self.state = session.state
        actionLog.merge(detailedActions: detailedActions)
        if session.state.rules.setScoringMode == .tiebreakOnly {
            actionLog.omitSecondaryScores()
        }
        return true
    }

    func mergeRemoteActions(_ actions: [DetailedScoreAction]) {
        actionLog.merge(detailedActions: actions)
        if state.rules.setScoringMode == .tiebreakOnly {
            actionLog.omitSecondaryScores()
        }
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
    @State private var scoreEventToast: WatchScoreEventToastState?
    @State private var scoreEventToastTask: Task<Void, Never>?
    @State private var undoToastToken: UUID?

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
                VStack {
                    Text(store.state.rules.tieBreakPoints == 10
                        ? NSLocalizedString("watch_tiebreak_indicator_10", value: "抢十", comment: "")
                        : NSLocalizedString("watch_tiebreak_indicator_7", value: "抢七", comment: ""))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color(white: 0.32))
                        .clipShape(Capsule())
                    Spacer()
                }
                .padding(.top, 8)
            }
            if showSideExchangeToast {
                WatchSideExchangeToast()
            }
            if let scoreEventToast {
                WatchScoreEventToast(state: scoreEventToast)
                    .transition(.opacity)
            }
            if showMenu {
                WatchScoreboardMenuOverlay(
                    onDismiss: { showMenu = false },
                    onUndo: {
                        guard !scoringLocked else { return }
                        undoScoreboard()
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
                    },
                    onReclaim: scoringLocked ? {
                        linkService.requestReclaim()
                        showMenu = false
                    } : nil
                )
            }
            if let restState {
                WatchRestOverlay(
                    state: restState,
                    onContinue: { self.restState = nil },
                    onUndo: {
                        guard !scoringLocked else { return }
                        let triggerID = restState.triggerID
                        self.restState = nil
                        restTriggers.release(triggerID)
                        undoScoreboard()
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
            Task {
                guard await store.applyAuthoritativeState(
                    state,
                    detailedActions: update.detailedActions,
                    revision: update.revision
                ) else { return }
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
        }
        .onChange(of: linkService.pendingReclaimAcceptance) { _, pending in
            guard let linkedSessionId,
                  let pending,
                  pending.sessionId == linkedSessionId,
                  let state = pending.snapshot.tennisState else { return }
            Task {
                guard await store.applyAuthoritativeState(
                    state,
                    detailedActions: pending.detailedActions,
                    revision: pending.revision
                ) else { return }
                linkService.completeReclaimAcceptance(messageId: pending.messageId)
            }
        }
        .onDisappear {
            finishTask?.cancel()
            sideExchangeTask?.cancel()
            completedScoreTask?.cancel()
            scoreEventToastTask?.cancel()
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
            onUndo: {
                guard !scoringLocked else { return }
                undoScoreboard()
            },
            onExit: exitBoard
        )
        .watchUndoToast(token: $undoToastToken)
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
                screenSide: .left,
                logicalSide: layout.engineSide(onScreen: .left),
                names: names,
                serverSlot: serverSlot
            ),
            right: tennisDoublesHalf(
                screenSide: .right,
                logicalSide: layout.engineSide(onScreen: .right),
                names: names,
                serverSlot: serverSlot
            )
        )
    }

    private func tennisDoublesHalf(
        screenSide: MatchSide,
        logicalSide: MatchSide,
        names: [String],
        serverSlot: Int
    ) -> WatchDoublesHalfModel {
        let isLeft = logicalSide == .left
        var topIndex = isLeft ? 0 : 1
        var bottomIndex = isLeft ? 2 : 3
        if screenSide == .right {
            swap(&topIndex, &bottomIndex)
        }
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
                .font(WatchScoreTypography.primaryScore(size: mainScoreFont))
                .monospacedDigit()
                .foregroundStyle(.white)

            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, isHorizontal ? 28 : 8)
                .offset(y: WatchLayout.scoreboardNameVerticalOffset)

            if isHorizontal {
                if hasSets {
                    tennisSetDots(count: sets, vertical: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 62)
                }
                if hasGames {
                    Text("\(games)")
                        .font(WatchScoreTypography.secondaryScore(size: 20))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.78))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 40)
                        .offset(y: WatchLayout.scoreboardMetaVerticalOffset)
                }
            } else if hasSets || hasGames {
                HStack {
                    Group {
                        if hasGames {
                            Text("\(games)")
                                .font(WatchScoreTypography.secondaryScore(size: 24))
                                .monospacedDigit()
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
                .offset(y: WatchLayout.scoreboardMetaVerticalOffset)
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
            .offset(y: WatchLayout.serverIndicatorVerticalOffset(isHorizontal: isHorizontal))
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
        TennisDoublesServing.currentServerSlot(in: state)
            ?? (state.servingSide == .left ? 0 : 1)
    }

    private func handle(events: [TennisMatchEvent], state: TennisMatchState) {
        if let completed = WatchTennisCompletedSetPresentation.resolve(
            events: events,
            currentSidesSwapped: state.sidesSwapped
        ) {
            beginCompletedSetPresentation(completed, state: state)
            return
        }
        let sideExchangeRequested = events.contains { event in
            if case .sidesExchanged = event { return true }
            if case .sidesExchangeReminder = event { return true }
            return false
        }
        var handledGameCompletion = false
        for event in events {
            switch event {
            case .setCompleted(_, let setNumber, _, _, _, _):
                guard !state.finished else { continue }
                beginBetweenSetRest(setNumber: setNumber)
            case .gameCompleted(let winner, let leftGames, let rightGames, _):
                guard !WatchPreferences.shared.setBreakEnabled else { continue }
                handledGameCompletion = true
                showCompletedGameToast(
                    winner: winner,
                    leftGames: leftGames,
                    rightGames: rightGames,
                    state: state,
                    followWithSideExchange: sideExchangeRequested
                )
            case .sidesExchanged, .sidesExchangeReminder:
                if !handledGameCompletion {
                    showSideExchange()
                }
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
        sideExchangeTask?.cancel()
        scoreEventToastTask?.cancel()
        restState = nil
        showSideExchangeToast = false
        scoreEventToast = nil
        scoreEventToastTask = nil
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
                if WatchPreferences.shared.setBreakEnabled {
                    beginBetweenSetRest(setNumber: presentation.setNumber)
                    if restState == nil, didExchangeSides {
                        showSideExchange()
                    }
                } else {
                    showCompletedSetToast(
                        presentation,
                        state: state,
                        followWithSideExchange: didExchangeSides
                    )
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

    private func showCompletedGameToast(
        winner: MatchSide,
        leftGames: Int,
        rightGames: Int,
        state: TennisMatchState,
        followWithSideExchange: Bool
    ) {
        showScoreEventToast(
            WatchScoreEventToastState(
                title: String.localizedStringWithFormat(
                    NSLocalizedString(
                        "watch_score_event_tennis_game_title",
                        value: "第%d局结束",
                        comment: ""
                    ),
                    leftGames + rightGames
                ),
                detail: String.localizedStringWithFormat(
                    NSLocalizedString(
                        "watch_score_event_tennis_game_detail",
                        value: "%@胜 · 局分 %d:%d",
                        comment: ""
                    ),
                    state.doublesTeamDisplayName(for: winner),
                    leftGames,
                    rightGames
                )
            ),
            followWithSideExchange: followWithSideExchange
        )
    }

    private func showCompletedSetToast(
        _ presentation: WatchTennisCompletedSetPresentation,
        state: TennisMatchState,
        followWithSideExchange: Bool
    ) {
        let winner: MatchSide = presentation.leftGames > presentation.rightGames ? .left : .right
        showScoreEventToast(
            WatchScoreEventToastState(
                title: String.localizedStringWithFormat(
                    NSLocalizedString(
                        "watch_score_event_tennis_set_title",
                        value: "第%d盘结束",
                        comment: ""
                    ),
                    presentation.setNumber
                ),
                detail: String.localizedStringWithFormat(
                    NSLocalizedString(
                        "watch_score_event_tennis_set_detail",
                        value: "%@胜 %d:%d · 盘分 %d:%d",
                        comment: ""
                    ),
                    state.doublesTeamDisplayName(for: winner),
                    presentation.leftGames,
                    presentation.rightGames,
                    presentation.leftSets,
                    presentation.rightSets
                )
            ),
            followWithSideExchange: followWithSideExchange
        )
    }

    private func showSideExchange() {
        scoreEventToastTask?.cancel()
        scoreEventToastTask = nil
        scoreEventToast = nil
        sideExchangeTask?.cancel()
        showSideExchangeToast = true
        sideExchangeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            showSideExchangeToast = false
        }
    }

    private func showScoreEventToast(
        _ toast: WatchScoreEventToastState,
        followWithSideExchange: Bool
    ) {
        sideExchangeTask?.cancel()
        showSideExchangeToast = false
        scoreEventToastTask?.cancel()
        scoreEventToast = toast
        scoreEventToastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            scoreEventToast = nil
            scoreEventToastTask = nil
            if followWithSideExchange {
                showSideExchange()
            }
        }
    }

    private func beginProvisionalFinish() {
        guard !showFinishedOverlay else { return }
        sideExchangeTask?.cancel()
        scoreEventToastTask?.cancel()
        restState = nil
        showMenu = false
        showSideExchangeToast = false
        scoreEventToast = nil
        scoreEventToastTask = nil
        showFinishedOverlay = true
        finishUndoAvailable = !scoringLocked
        didFinalizeFinish = false
        finishTask?.cancel()
        guard !scoringLocked else { return }
        finishTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(WatchTiming.finishedUndoCountdown))
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
        guard finishUndoAvailable, !scoringLocked else { return }
        completedScoreTask?.cancel()
        completedScoreTask = nil
        completedSetPresentation = nil
        finishTask?.cancel()
        showFinishedOverlay = false
        finishUndoAvailable = false
        didFinalizeFinish = false
        undoScoreboard()
    }

    private func undoScoreboard() {
        store.undo {
            undoToastToken = UUID()
        }
    }

    private func playAgain() {
        guard !scoringLocked else { return }
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
        scoreEventToastTask?.cancel()
        completedScoreTask?.cancel()
        completedScoreTask = nil
        completedSetPresentation = nil
        showSideExchangeToast = false
        scoreEventToast = nil
        startFreshMatch()
    }

    private func finishAndExit() {
        finalizeFinish()
        exitBoard()
    }

    private func confirm(_ value: WatchScoreboardConfirmation) {
        guard !scoringLocked else {
            confirmation = nil
            return
        }
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
            scoreEventToastTask?.cancel()
            completedScoreTask?.cancel()
            completedScoreTask = nil
            completedSetPresentation = nil
            showSideExchangeToast = false
            scoreEventToast = nil
            startFreshMatch()
        }
    }

    private func startFreshMatch() {
        let timestamp = Date()
        let result = TennisMatchReducer().reduce(
            state: store.state,
            intent: .reset,
            at: Int64(timestamp.timeIntervalSince1970 * 1_000)
        )
        guard result.accepted else { return }
        let freshStore = WatchTennisSessionStore(
            gameType: isDoubles ? .tennisDoubles : .tennis,
            rules: store.state.rules,
            initialState: result.state,
            startedAt: timestamp
        )
        freshStore.onStateChanged = { [linkService] state, events in
            if linkedSessionId != nil {
                guard linkService.isController else { return }
                linkService.publishSnapshot(
                    .tennis(state),
                    detailedActions: freshStore.actionLog.detailedActions
                )
            }
            handle(events: events, state: state)
            Task { await persistResumeSession() }
        }
        store = freshStore
        matchStartTime = timestamp
        if linkedSessionId != nil {
            linkService.startNextMatch(
                snapshot: .tennis(result.state),
                participantNames: result.state.doublesPlayerNames
                    ?? [result.state.leftName, result.state.rightName]
            )
        }
    }

    private func exitBoard() {
        if linkedSessionId != nil {
            linkService.exitScoreboardToHome()
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
                "scoreCoreGameType": (isDoubles ? GameType.tennisDoubles : .tennis).rawValue,
                "isSingles": String(state.doublesPlayerNames == nil),
                "maxSets": String(state.rules.maxSets),
                "tieBreakPoints": String(state.rules.tieBreakPoints),
                "setScoringMode": state.rules.setScoringMode.rawValue,
                "usesNoAdScoring": String(state.rules.usesNoAdScoring),
                "isDoubles": String(state.doublesPlayerNames != nil)
            ]
        )
        WatchRecordManager.shared.saveRecord(record)
    }
}
