import PersistenceCore
import RecordCore
import ScoreCore
import SwiftUI
import UIKit

enum GuandanLocalScoreboardAction: Equatable {
    case settleRound(side: GuandanSide, step: Int)
    case adjustRank(side: GuandanSide, delta: Int)
    case undo
    case none
}

func guandanLogicalSide(onScreen screenSide: MatchSide) -> GuandanSide {
    // Guandan never swaps screen sides; red/team0 is always the left (stable) logical identity.
    TeamScreenLayout(sidesSwapped: false).engineSide(onScreen: screenSide) == .left
        ? .red
        : .blue
}

func guandanLocalScoreboardAction(
    for intent: LocalScoreboardIntent
) -> GuandanLocalScoreboardAction {
    switch intent {
    case .addLeft:
        .settleRound(side: guandanLogicalSide(onScreen: .left), step: 1)
    case .addRight:
        .settleRound(side: guandanLogicalSide(onScreen: .right), step: 1)
    case .subtractLeft:
        .adjustRank(side: guandanLogicalSide(onScreen: .left), delta: -1)
    case .subtractRight:
        .adjustRank(side: guandanLogicalSide(onScreen: .right), delta: -1)
    case .undo:
        .undo
    case .exchangeSides:
        .none
    case .requestSnapshot:
        .none
    }
}

func guandanLocalDisplayState(
    state: GuandanMatchState,
    typography: ScoreboardTypographyPreference,
    themeID: String
) -> LocalScoreboardDisplayState {
    let leftSide = guandanLogicalSide(onScreen: .left)
    let rightSide = guandanLogicalSide(onScreen: .right)
    var compact = LocalScoreboardDisplayState(
        gameID: GameType.guandan.canonicalScoreboardIdentifier,
        title: "",
        leftName: leftSide == .red ? state.redTeam.name : state.blueTeam.name,
        rightName: rightSide == .red ? state.redTeam.name : state.blueTeam.name,
        leftScore: state.displayRank(for: leftSide),
        rightScore: state.displayRank(for: rightSide),
        leftDetail: nil,
        rightDetail: nil,
        themeID: themeID,
        fontID: typography.font.rawValue,
        scoreMultiplier: typography.scoreMultiplier,
        nameMultiplier: typography.nameMultiplier,
        secondaryMultiplier: typography.secondaryMultiplier,
        finished: state.phase == .finished,
        revision: 0
    )
    var sportState: [String: ScoreboardDisplayValue] = [
        "team0ScreenSide": .string("left"),
        "guandanRedRank": .string(state.displayRank(for: .red)),
        "guandanBlueRank": .string(state.displayRank(for: .blue)),
        "guandanLeftAFailCount": .integer(state.aFailCount(for: .red)),
        "guandanRightAFailCount": .integer(state.aFailCount(for: .blue)),
        "guandanTripleAEnabled": .boolean(state.aStageMode == .tripleA)
    ]
    if let banker = state.aStageTeam ?? state.lastRoundWinner {
        sportState["guandanBankerTeam"] = .string(banker == .red ? "team_0" : "team_1")
    }
    compact.externalState = ScoreboardDisplayState.enriched(
        compact: compact,
        layoutKind: .boardCard,
        sportState: sportState
    )
    return compact
}

struct GuandanResumeState: Codable, Equatable {
    var schemaVersion: Int
    let state: GuandanMatchState
    let undoHistory: [GuandanMatchState]
    let intentTimeline: [String]
    let detailedActions: [DetailedScoreAction]
    let actionCount: Int
    let undoTimeline: [GuandanUndoTimelineCheckpoint]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case state
        case undoHistory
        case intentTimeline
        case detailedActions
        case actionCount
        case undoTimeline
    }

    init(
        schemaVersion: Int = 1,
        state: GuandanMatchState,
        undoHistory: [GuandanMatchState],
        intentTimeline: [String],
        detailedActions: [DetailedScoreAction] = [],
        actionCount: Int,
        undoTimeline: [GuandanUndoTimelineCheckpoint] = []
    ) {
        self.schemaVersion = schemaVersion
        self.state = state
        self.undoHistory = undoHistory
        self.intentTimeline = intentTimeline
        self.detailedActions = detailedActions
        self.actionCount = actionCount
        self.undoTimeline = undoTimeline
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        state = try container.decode(GuandanMatchState.self, forKey: .state)
        undoHistory = try container.decodeIfPresent([GuandanMatchState].self, forKey: .undoHistory) ?? []
        intentTimeline = try container.decodeIfPresent([String].self, forKey: .intentTimeline) ?? []
        detailedActions = try container.decodeIfPresent([DetailedScoreAction].self, forKey: .detailedActions) ?? []
        actionCount = try container.decodeIfPresent(Int.self, forKey: .actionCount) ?? undoHistory.count
        undoTimeline = try container.decodeIfPresent([GuandanUndoTimelineCheckpoint].self, forKey: .undoTimeline) ?? []
    }
}

struct GuandanUndoTimelineCheckpoint: Codable, Equatable {
    let actionLogCount: Int
    let detailedActionsCount: Int
    let actionCount: Int
}

func guandanPresentationStartedState(
    _ state: GuandanMatchState,
    at epochMilliseconds: Int64
) -> GuandanMatchState {
    guard state.phase == .notStarted else { return state }
    return GuandanSessionReducer().reduce(
        state: state,
        intent: .startMatch,
        at: epochMilliseconds
    ).state
}

/// One visible +1/+2/+3 operation is one atomic user transition even when a
/// legacy snapshot is still `notStarted`. This prevents an undo-to-notStarted
/// state from trapping the board in reducer no-ops.
func guandanRoundStateAfterTap(
    state: GuandanMatchState,
    winner: GuandanSide,
    step: Int,
    at epochMilliseconds: Int64
) -> GuandanMatchState? {
    let reducer = GuandanSessionReducer()
    var working = guandanPresentationStartedState(state, at: epochMilliseconds)
    guard working.phase != .finished else { return nil }
    if working.phase == .roundResult, working.roundWinner != winner {
        working = reducer.reduce(
            state: working,
            intent: .cancelRoundResult,
            at: epochMilliseconds
        ).state
    }
    if working.phase != .roundResult {
        guard working.phase == .playing else { return nil }
        let begun = reducer.reduce(
            state: working,
            intent: .beginRoundResult(winner: winner),
            at: epochMilliseconds
        )
        guard begun.accepted, begun.state.phase == .roundResult else { return nil }
        working = begun.state
    }
    let settled = reducer.reduce(
        state: working,
        intent: .applyRoundSettlement(step: step),
        at: epochMilliseconds
    )
    guard settled.accepted, settled.state != state else { return nil }
    return settled.state
}

func guandanDetailedActions(
    for intent: GuandanSessionIntent,
    previousState: GuandanMatchState,
    resultingState state: GuandanMatchState,
    epochMilliseconds: Int64,
    roundNumber: Int
) -> [DetailedScoreAction] {
    func recordTeam(_ side: GuandanSide?) -> RecordTeam? {
        guard let side else { return nil }
        return side == .red ? .team1 : .team2
    }
    func rank(for side: GuandanSide, in state: GuandanMatchState) -> String {
        side == .red ? state.redTeam.currentRank : state.blueTeam.currentRank
    }
    func rankIndex(_ rank: String) -> Int {
        max(0, guandanRankOrder.firstIndex(of: rank) ?? 0)
    }
    let scores = [
        GuandanMatchState.rankDisplayScore(state.redTeam.currentRank),
        GuandanMatchState.rankDisplayScore(state.blueTeam.currentRank)
    ]

    switch intent {
    case .startMatch:
        return [.init(type: .matchStarted, epochMilliseconds: epochMilliseconds, scores: scores, operationCode: "guandan_match_started")]
    case .applyRoundSettlement(let step):
        let winnerSide = state.lastRoundWinner ?? previousState.roundWinner
        let winner = recordTeam(winnerSide)
        let actualDelta: Int = winnerSide.map { side in
            let beforeRank = rank(for: side, in: previousState)
            let afterRank = rank(for: side, in: state)
            let rankDelta = rankIndex(afterRank) - rankIndex(beforeRank)
            return rankDelta == 0 ? step : rankDelta
        } ?? step
        var actions = [DetailedScoreAction(
            type: .roundFinished,
            epochMilliseconds: epochMilliseconds,
            team: winner,
            scores: scores,
            roundNumber: roundNumber,
            scoreChange: actualDelta,
            winner: winner,
            operationCode: "guandan_upgrade"
        )]

        if let passSide = previousState.aStageTeam {
            let passTeam = recordTeam(passSide)
            let passSucceeded = passSide == winnerSide && {
                switch previousState.passACondition {
                case .doubleUp: return step == 3
                case .notLast: return step == 2 || step == 3
                }
            }()
            if passSucceeded {
                actions.append(.init(
                    type: .stateChanged,
                    epochMilliseconds: epochMilliseconds,
                    team: passTeam,
                    scores: scores,
                    roundNumber: roundNumber,
                    operationCode: "gd_pass_a_ok"
                ))
            } else if previousState.aStageMode == .singleA {
                actions.append(.init(
                    type: .stateChanged,
                    epochMilliseconds: epochMilliseconds,
                    team: passTeam,
                    scores: scores,
                    roundNumber: roundNumber,
                    operationCode: "gd_pass_a_fail"
                ))
            } else {
                let failAttempt = previousState.aFailCount(for: passSide) + 1
                actions.append(.init(
                    type: .stateChanged,
                    epochMilliseconds: epochMilliseconds,
                    team: passTeam,
                    scores: scores,
                    roundNumber: roundNumber,
                    scoreChange: failAttempt,
                    operationCode: "gd_pass_a_fail_triple"
                ))
                if failAttempt >= 3 {
                    actions.append(.init(
                        type: .stateChanged,
                        epochMilliseconds: epochMilliseconds,
                        team: passTeam,
                        scores: scores,
                        roundNumber: roundNumber,
                        operationCode: "gd_triple_a_fallback",
                        operationPayload: previousState.tripleAFallbackRank
                    ))
                }
            }
        }
        return actions
    case .recordPassA(let success):
        guard let passSide = previousState.aStageTeam else {
            return [.init(type: .stateChanged, epochMilliseconds: epochMilliseconds, scores: scores, roundNumber: roundNumber, operationCode: "guandan_pass_a_unavailable")]
        }
        let passTeam = recordTeam(passSide)
        let operationCode: String
        let scoreChange: Int?
        let operationPayload: String?
        if success {
            operationCode = "gd_pass_a_ok"
            scoreChange = nil
            operationPayload = nil
        } else if previousState.aStageMode == .singleA {
            operationCode = "gd_pass_a_fail"
            scoreChange = nil
            operationPayload = nil
        } else if previousState.aFailCount(for: passSide) < 2 {
            operationCode = "gd_pass_a_fail_triple"
            scoreChange = state.aFailCount(for: passSide)
            operationPayload = nil
        } else {
            operationCode = "gd_triple_a_fallback"
            scoreChange = nil
            operationPayload = rank(for: passSide, in: state)
        }
        return [.init(
            type: .roundFinished,
            epochMilliseconds: epochMilliseconds,
            team: passTeam,
            scores: scores,
            roundNumber: roundNumber,
            scoreChange: scoreChange,
            winner: success ? passTeam : nil,
            operationCode: operationCode,
            operationPayload: operationPayload
        )]
    case .adjustRank(let side, let delta):
        return [.init(type: .scoreChanged, epochMilliseconds: epochMilliseconds, team: recordTeam(side), scores: scores, scoreChange: delta, operationCode: "guandan_rank_adjusted")]
    case .beginRoundResult(let winner):
        return [.init(type: .stateChanged, epochMilliseconds: epochMilliseconds, team: recordTeam(winner), scores: scores, operationCode: "guandan_round_winner_selected")]
    case .cancelRoundResult:
        return [.init(type: .stateChanged, epochMilliseconds: epochMilliseconds, scores: scores, operationCode: "guandan_round_result_cancelled")]
    case .reset:
        return [.init(type: .reset, epochMilliseconds: epochMilliseconds, scores: scores, operationCode: "guandan_reset")]
    case .finish:
        let winner = recordTeam(state.finalWinner)
        return [.init(type: .matchFinished, epochMilliseconds: epochMilliseconds, scores: scores, winner: winner, operationCode: "guandan_match_finished")]
    case .adminCorrect:
        return [.init(type: .stateChanged, epochMilliseconds: epochMilliseconds, scores: scores, operationCode: "guandan_admin_corrected")]
    case .setRedTeamName:
        return [.init(type: .stateChanged, epochMilliseconds: epochMilliseconds, team: .team1, scores: scores, operationCode: "guandan_red_name_changed")]
    case .setBlueTeamName:
        return [.init(type: .stateChanged, epochMilliseconds: epochMilliseconds, team: .team2, scores: scores, operationCode: "guandan_blue_name_changed")]
    }
}

func guandanDetailedAction(
    for intent: GuandanSessionIntent,
    previousState: GuandanMatchState,
    resultingState state: GuandanMatchState,
    epochMilliseconds: Int64,
    roundNumber: Int
) -> DetailedScoreAction {
    guandanDetailedActions(
        for: intent,
        previousState: previousState,
        resultingState: state,
        epochMilliseconds: epochMilliseconds,
        roundNumber: roundNumber
    )[0]
}

struct GuandanScoreboardView: View {
    var initialSetup: SportsSetupResult? = nil
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scoreboardMatchClockSession) private var matchClockSession
    @State private var state: GuandanMatchState
    @State private var history: [GuandanMatchState] = []
    @State private var historyTimeline: [GuandanUndoTimelineCheckpoint] = []
    @State private var actionLog: [String] = []
    @State private var detailedActions: [DetailedScoreAction] = []
    @State private var actionCount = 0
    @State private var gameStartAt: Date
    @State private var recordID: String
    @State private var showGameOverDialog = false
    @State private var showFinishedRecordDetail = false
    @State private var pendingEditWrapSide: GuandanSide?
    @State private var scoreboardEditing = false
    @State private var typographyPreference = PreferencesManager.shared.scoreboardTypography(
        for: ScoreboardStyleID(gameType: .guandan)
    )

    private let reducer = GuandanSessionReducer()

    init(
        initialSetup: SportsSetupResult? = nil,
        initialResumeSessionId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil,
        onNavigationBack: (() -> Void)? = nil
    ) {
        self.initialSetup = initialSetup
        self.initialResumeSessionId = initialResumeSessionId
        self.onSetupConsumed = onSetupConsumed
        self.onNavigationBack = onNavigationBack

        let defaults = DefaultParticipantNames.resolve(for: .guandan)
        let red = initialSetup?.team1Name.nonEmpty ?? defaults.left
        let blue = initialSetup?.team2Name.nonEmpty ?? defaults.right
        let tripleA = initialSetup?.guandanTripleA ?? PreferencesManager.shared.guandanSetupTripleA
        let passRaw = initialSetup?.guandanPassACondition ?? PreferencesManager.shared.guandanSetupPassACondition
        let pass: GuandanPassACondition = passRaw == "double_up" ? .doubleUp : .notLast
        let fallback = initialSetup?.guandanTripleAFallbackRank
            ?? PreferencesManager.shared.guandanSetupTripleAFallbackRank

        var initial = GuandanMatchState.initial(
            redName: red,
            blueName: blue,
            aStageMode: tripleA ? .tripleA : .singleA,
            passACondition: pass,
            tripleAFallbackRank: fallback
        )
        var start = Date()
        var id = ScoreboardRecordIdentity.next(prefix: GameType.guandan.canonicalScoreboardIdentifier)
        var actions = 0
        var showFinished = false
        var restoredActions: [String] = []
        var restoredDetailedActions: [DetailedScoreAction] = []
        var restoredHistory: [GuandanMatchState] = []
        var restoredHistoryTimeline: [GuandanUndoTimelineCheckpoint] = []

        if let initialResumeSessionId,
           let record = ManualResumeSessionStore.load(recordID: initialResumeSessionId),
           let data = record.stateSnapshot {
            if let resume = try? JSONDecoder().decode(GuandanResumeState.self, from: data) {
                initial = resume.state
                restoredHistory = Array(resume.undoHistory.suffix(80))
                restoredHistoryTimeline = Array(resume.undoTimeline.suffix(80))
                restoredActions = resume.intentTimeline.isEmpty ? record.actions : resume.intentTimeline
                restoredDetailedActions = resume.detailedActions.isEmpty
                    ? (record.detailedActions ?? [])
                    : resume.detailedActions
                actions = max(max(record.totalScoreChanges, resume.actionCount), restoredHistory.count)
                start = record.startTime
                id = record.id
                showFinished = initial.phase == .finished
            } else if let restored = try? JSONDecoder().decode(GuandanMatchState.self, from: data) {
                initial = restored
                restoredActions = record.actions
                restoredDetailedActions = record.detailedActions ?? []
                actions = max(record.totalScoreChanges, 1)
                start = record.startTime
                id = record.id
                showFinished = initial.phase == .finished
            }
        }

        if restoredHistoryTimeline.count != restoredHistory.count {
            let historyCount = restoredHistory.count
            restoredHistoryTimeline = restoredHistory.indices.map { index in
                let distance = historyCount - index
                return GuandanUndoTimelineCheckpoint(
                    actionLogCount: max(0, restoredActions.count - distance),
                    detailedActionsCount: max(0, restoredDetailedActions.count - distance),
                    actionCount: max(0, actions - distance)
                )
            }
        }

        _state = State(initialValue: initial)
        _history = State(initialValue: restoredHistory)
        _historyTimeline = State(initialValue: restoredHistoryTimeline)
        _gameStartAt = State(initialValue: start)
        _recordID = State(initialValue: id)
        _actionCount = State(initialValue: actions)
        _showGameOverDialog = State(initialValue: showFinished)
        _actionLog = State(initialValue: restoredActions)
        _detailedActions = State(initialValue: restoredDetailedActions)
        _pendingEditWrapSide = State(initialValue: nil)
    }

    var body: some View {
        ZStack {
            TwoSideScoreboardScaffold(
                gameType: .guandan,
                leftName: guandanName(onScreen: .left),
                rightName: guandanName(onScreen: .right),
                leftScore: state.displayRank(for: guandanSide(onScreen: .left)),
                rightScore: state.displayRank(for: guandanSide(onScreen: .right)),
                leftDetail: nil,
                rightDetail: nil,
                finished: state.phase == .finished,
                onLeftTap: {},
                onRightTap: {},
                onUndo: undo,
                onReset: resetMatch,
                // Android 3.0/3.1 does not expose a local exchange-side action
                // for Guandan. Logical red/blue identity therefore stays fixed.
                onExchange: nil,
                onBack: {
                    saveRecord()
                    onNavigationBack?()
                    dismiss()
                },
                showEndGame: true,
                onEndGame: finishMatch,
                onEditCommit: applyEdit,
                onEditAdjust: { isLeft, delta in
                    adjustRankInEditMode(side: guandanSide(onScreen: isLeft ? .left : .right), delta: delta)
                },
                onPanelSwipe: { isLeft, delta in
                    let side = guandanSide(onScreen: isLeft ? .left : .right)
                    if delta > 0 {
                        applyGuandanRound(side: side, step: 1)
                    } else {
                        send(.adjustRank(side: side, delta: -1))
                    }
                },
                extraMenuItems: guandanMatchClockMenuItems,
                onMenuAction: { action in
                    guard action == "toggleMatchTime" else { return }
                    toggleMatchClockVisibility()
                },
                seamOverlay: state.lastRoundWinner == nil ? nil : { indicatorColor in
                    AnyView(
                        GeometryReader { geo in
                            let indicatorSize = ScoreboardLayoutMetrics.serveIndicatorSize(
                                halfViewportSize: CGSize(width: geo.size.width / 2, height: geo.size.height)
                            )
                            CenterLineServeIndicator(
                                isLeftServing: state.lastRoundWinner == guandanSide(onScreen: .left),
                                triangleSize: indicatorSize,
                                color: indicatorColor
                            )
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        }
                        .allowsHitTesting(false)
                    )
                },
                panelAccessory: { isLeft in
                    AnyView(guandanPanelActions(side: guandanSide(onScreen: isLeft ? .left : .right), isLeftScreen: isLeft))
                },
                onEditModeChange: { scoreboardEditing = $0 },
                onTypographyChange: { preference in
                    typographyPreference = preference
                    LocalScoreboardSyncCoordinator.shared.publishSnapshot()
                },
                sidesSwapped: false,
                center: { _, _ in
                    EmptyView()
                }
            )

            if showGameOverDialog {
                let winnerName: String = switch state.finalWinner {
                case .red: state.redTeam.name
                case .blue: state.blueTeam.name
                case nil: ""
                }
                let winnerIndices: Set<Int> = switch state.finalWinner {
                case .red: [0]
                case .blue: [1]
                case nil: []
                }
                GameOverDialog(
                    winnerName: winnerName,
                    gameType: .guandan,
                    leftName: state.redTeam.name,
                    rightName: state.blueTeam.name,
                    leftScoreText: state.displayRank(for: .red),
                    rightScoreText: state.displayRank(for: .blue),
                    winnerIndices: winnerIndices,
                    onNewGame: {
                        startNewMatch()
                    },
                    onRecords: {
                        saveRecord()
                        showFinishedRecordDetail = true
                    },
                    onShare: {
                        ScoreboardShareSupport.present(
                            text: "\(state.redTeam.name) \(state.displayRank(for: .red)) - \(state.displayRank(for: .blue)) \(state.blueTeam.name)"
                        )
                    },
                    onExit: {
                        saveRecord()
                        onNavigationBack?()
                        dismiss()
                    }
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showGameOverDialog)
        .cloudSyncSharingEntryOverlay()
        .fullScreenCover(isPresented: $showFinishedRecordDetail) {
            NavigationStack {
                ScoreboardRecordDetailPage(recordId: recordID)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            ModalCloseButton { showFinishedRecordDetail = false }
                        }
                    }
            }
        }
        .onAppear {
            if state.phase == .notStarted {
                // Opening the page is lifecycle setup, not an undoable scoring
                // action. Android starts the state machine on the first round
                // settlement and never enables Undo on an untouched board.
                state = guandanPresentationStartedState(
                    state,
                    at: Int64(Date().timeIntervalSince1970 * 1_000)
                )
            }
            onSetupConsumed?()
            registerSync()
            bindMatchClock()
        }
        .onChange(of: state) { _, _ in
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
        }
        .onChange(of: state.phase) { _, phase in
            if phase == .finished {
                showGameOverDialog = true
            }
        }
        .onChange(of: matchClockSession?.isVisible) { _, _ in saveRecord() }
        .onDisappear {
            LocalScoreboardSyncCoordinator.shared.unregisterHost()
            saveRecord()
        }
        .alert(
            NSLocalizedString("guandan_edit_level_wrap_confirm_title", value: "级牌回到 2？", comment: ""),
            isPresented: Binding(
                get: { pendingEditWrapSide != nil },
                set: { if !$0 { pendingEditWrapSide = nil } }
            )
        ) {
            Button(NSLocalizedString("cancel", value: "取消", comment: ""), role: .cancel) {
                pendingEditWrapSide = nil
            }
            Button(NSLocalizedString("confirm", value: "确认", comment: ""), role: .destructive) {
                guard let side = pendingEditWrapSide else { return }
                pendingEditWrapSide = nil
                send(.adjustRank(side: side, delta: 1))
            }
        } message: {
            Text(NSLocalizedString(
                "guandan_edit_level_wrap_confirm_message",
                value: "继续增加会将该队级牌重置为 2。",
                comment: ""
            ))
        }
    }

    private func guandanSide(onScreen screen: MatchSide) -> GuandanSide {
        guandanLogicalSide(onScreen: screen)
    }

    private func guandanName(onScreen screen: MatchSide) -> String {
        guandanSide(onScreen: screen) == .red ? state.redTeam.name : state.blueTeam.name
    }

    @ViewBuilder
    private func guandanPanelActions(side: GuandanSide, isLeftScreen: Bool) -> some View {
        if state.phase != .finished {
            HStack(spacing: Theme.usesPadLayout ? 24 : 20) {
                ForEach([1, 2, 3], id: \.self) { step in
                    scoreboardCardActionButton("+\(step)") {
                        applyGuandanRound(side: side, step: step)
                    }
                    .accessibilityIdentifier("guandan_round_\(side.rawValue)_plus_\(step)")
                }
            }
            // 用户反馈：按钮贴近底部两角的返回/菜单按钮易误触。
            // 整排向屏幕中心平移（offset 不影响上下布局，仅水平移动含点击区域）。
            .offset(x: isLeftScreen
                ? (Theme.usesPadLayout ? 40 : 32)
                : (Theme.usesPadLayout ? -40 : -32)
            )
        }
    }

    private func applyGuandanRound(side: GuandanSide, step: Int) {
        guard state.phase != .finished else { return }
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
        let before = state
        guard let settled = guandanRoundStateAfterTap(
            state: state,
            winner: side,
            step: step,
            at: timestamp
        ) else { return }
        pushUndoSnapshot(before)
        state = settled
        actionCount += 1
        appendSnapshot("round_\(side.rawValue)_plus_\(step)")
        appendDetailedAction(
            for: .applyRoundSettlement(step: step),
            previousState: before,
            epochMilliseconds: timestamp
        )
        VibrationManager.shared.vibrateMedium()
        if state.phase == .finished {
            showGameOverDialog = true
        }
        saveRecord()
    }

    private func adjustRankInEditMode(side: GuandanSide, delta: Int) {
        guard delta != 0 else { return }
        if delta > 0, shouldConfirmRankWrap(side: side, delta: delta) {
            pendingEditWrapSide = side
            return
        }
        send(.adjustRank(side: side, delta: delta))
    }

    private func shouldConfirmRankWrap(side: GuandanSide, delta: Int) -> Bool {
        guard delta > 0 else { return false }
        let rank = side == .red ? state.redTeam.currentRank : state.blueTeam.currentRank
        let maxRankIndex = guandanRankOrder.count - 1
        let rankIndex = max(0, guandanRankOrder.firstIndex(of: rank) ?? 0)
        let currentDisplayIndex: Int
        if state.aStageMode == .tripleA, rankIndex == maxRankIndex {
            currentDisplayIndex = maxRankIndex + min(max(state.aFailCount(for: side), 0), 2)
        } else {
            currentDisplayIndex = rankIndex
        }
        let maxDisplayIndex = state.aStageMode == .tripleA ? maxRankIndex + 2 : maxRankIndex
        return currentDisplayIndex + delta > maxDisplayIndex
    }

    private func send(_ intent: GuandanSessionIntent) {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
        let previous = state
        let result = reducer.reduce(state: state, intent: intent, at: timestamp)
        guard result.accepted else { return }
        pushUndoSnapshot(state)
        state = result.state
        actionCount += 1
        appendSnapshot(String(describing: intent))
        appendDetailedAction(for: intent, previousState: previous, epochMilliseconds: timestamp)
        VibrationManager.shared.vibrateMedium()
        if state.phase == .finished {
            showGameOverDialog = true
        }
        saveRecord()
    }

    private func undo() -> Bool {
        guard let previous = history.popLast() else { return false }
        let timeline = historyTimeline.popLast()
        state = previous
        actionLog = Array(actionLog.prefix(timeline?.actionLogCount ?? max(0, actionLog.count - 1)))
        detailedActions = Array(detailedActions.prefix(timeline?.detailedActionsCount ?? max(0, detailedActions.count - 1)))
        actionCount = timeline?.actionCount ?? max(0, actionCount - 1)
        showGameOverDialog = state.phase == .finished
        saveRecord()
        return true
    }

    private func resetMatch() {
        let previousRecordID = recordID
        let reset = reducer.reduce(
            state: state,
            intent: .reset,
            at: Int64(Date().timeIntervalSince1970 * 1_000)
        )
        guard reset.accepted else { return }
        state = reset.state
        history.removeAll()
        historyTimeline.removeAll()
        actionLog.removeAll()
        detailedActions.removeAll()
        actionCount = 0
        gameStartAt = Date()
        recordID = ScoreboardRecordIdentity.next(prefix: GameType.guandan.canonicalScoreboardIdentifier)
        pendingEditWrapSide = nil
        showGameOverDialog = false
        matchClockSession?.reset(startedAt: gameStartAt)
        saveRecord()

        if let oldSessionID = ManualResumeSessionStore.sessionID(for: previousRecordID) {
            Task {
                try? await ResumeSessionRepository().remove(sessionId: oldSessionID)
            }
        }
    }

    private func startNewMatch() {
        saveRecord()
        let reset = reducer.reduce(
            state: state,
            intent: .reset,
            at: Int64(Date().timeIntervalSince1970 * 1_000)
        )
        guard reset.accepted else { return }
        state = reset.state
        history.removeAll()
        historyTimeline.removeAll()
        actionLog.removeAll()
        detailedActions.removeAll()
        actionCount = 0
        gameStartAt = Date()
        recordID = ScoreboardRecordIdentity.next(prefix: GameType.guandan.canonicalScoreboardIdentifier)
        matchClockSession?.reset(startedAt: gameStartAt)
        pendingEditWrapSide = nil
        showGameOverDialog = false
        LocalScoreboardSyncCoordinator.shared.publishSnapshot()
    }

    private func bindMatchClock() {
        guard let matchClockSession else { return }
        var visible = initialSetup?.showMatchTime ?? matchClockSession.isVisible
        if let recordId = initialResumeSessionId,
           let record = ManualResumeSessionStore.load(recordID: recordId),
           let restored = scoreboardBool(
               record.projectConfiguration?["showMatchTime"]
                   ?? record.extraData?["showMatchTime"]
           ) {
            visible = restored
        }
        matchClockSession.bind(startedAt: gameStartAt, isVisible: visible)
    }

    /// 对齐安卓 GuandanScoreboardScreen 的 toggleMatchTime 菜单项。
    private var guandanMatchClockMenuItems: [ScoreboardMenuItem] {
        let visible = matchClockSession?.isVisible
            ?? PreferencesManager.shared.scoreboardMatchTimeVisible(for: .guandan)
        return [
            ScoreboardMenuItem(
                title: visible
                    ? NSLocalizedString("hide_match_time", value: "隐藏时间", comment: "")
                    : NSLocalizedString("show_match_time", value: "显示时间", comment: ""),
                action: "toggleMatchTime",
                group: .tools,
                icon: "clock",
                keepDialogOpen: true
            )
        ]
    }

    private func toggleMatchClockVisibility() {
        guard let session = matchClockSession else { return }
        session.isVisible.toggle()
        PreferencesManager.shared.setScoreboardMatchTimeVisible(session.isVisible, for: .guandan)
    }

    private func finishMatch() {
        send(.finish)
    }

    private func applyEdit(left: String, right: String, leftScore: String, rightScore: String) {
        let previous = state
        // Rank buttons mutate the reducer immediately while the scaffold keeps
        // the edit-session text it captured on entry. Commit names together
        // with the reducer's current ranks so leaving edit mode cannot roll a
        // rank adjustment back to that stale text.
        let screenLeftRank = state.displayRank(for: guandanSide(onScreen: .left))
            .uppercased().replacingOccurrences(of: "A1", with: "A")
            .replacingOccurrences(of: "A2", with: "A")
            .replacingOccurrences(of: "A3", with: "A")
        let screenRightRank = state.displayRank(for: guandanSide(onScreen: .right))
            .uppercased().replacingOccurrences(of: "A1", with: "A")
            .replacingOccurrences(of: "A2", with: "A")
            .replacingOccurrences(of: "A3", with: "A")
        let leftIsRed = guandanSide(onScreen: .left) == .red
        let redName = leftIsRed ? left : right
        let blueName = leftIsRed ? right : left
        let redRank = leftIsRed ? screenLeftRank : screenRightRank
        let blueRank = leftIsRed ? screenRightRank : screenLeftRank
        let result = reducer.reduce(
            state: state,
            intent: .adminCorrect(redName: redName, blueName: blueName, redRank: redRank, blueRank: blueRank),
            at: Int64(Date().timeIntervalSince1970 * 1_000)
        )
        guard result.accepted, result.state != previous else { return }
        pushUndoSnapshot(previous)
        state = result.state
        actionCount += 1
        appendSnapshot("adminCorrect")
        appendDetailedAction(
            for: .adminCorrect(redName: redName, blueName: blueName, redRank: redRank, blueRank: blueRank),
            previousState: previous,
            epochMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
        )
        showGameOverDialog = false
        saveRecord()
    }

    private func registerSync() {
        LocalScoreboardSyncCoordinator.shared.registerHost(snapshot: syncSnapshot) { intent in
            guard LocalScoreboardMutationPolicy.allowsMutation(
                isEditing: scoreboardEditing,
                finished: state.phase == .finished,
                scoringLocked: false
            ) else { return }

            switch guandanLocalScoreboardAction(for: intent) {
            case .settleRound(let side, let step):
                applyGuandanRound(side: side, step: step)
            case .adjustRank(let side, let delta):
                send(.adjustRank(side: side, delta: delta))
            case .undo:
                _ = undo()
            case .none:
                break
            }
        }
    }

    private func syncSnapshot() -> LocalScoreboardDisplayState {
        guandanLocalDisplayState(
            state: state,
            typography: typographyPreference,
            themeID: ScoreboardAppearanceSnapshot.current().theme.rawValue
        )
    }

    private func saveRecord() {
        guard actionCount > 0 || state.phase != .notStarted else { return }
        let end = Date()
        let winnerIdentity: ScoreboardWinnerIdentity? = state.finalWinner.map {
            .team($0 == .red ? .team0 : .team1)
        }
        let snapshotData: Data
        do {
            snapshotData = try JSONEncoder().encode(GuandanResumeState(
                state: state,
                undoHistory: Array(history.suffix(80)),
                intentTimeline: actionLog,
                detailedActions: detailedActions,
                actionCount: actionCount,
                undoTimeline: historyTimeline
            ))
        } catch {
            ScoreboardPersistenceFailureReporter.report(error, context: "Failed to encode guandan record \(recordID)")
            return
        }
        let finished = state.phase == .finished
        let record = ScoreboardRecord(
            id: recordID,
            gameType: .guandan,
            startTime: gameStartAt,
            endTime: end,
            duration: end.timeIntervalSince(gameStartAt),
            team1Name: state.redTeam.name,
            team2Name: state.blueTeam.name,
            team1FinalScore: GuandanMatchState.rankDisplayScore(state.redTeam.currentRank),
            team2FinalScore: GuandanMatchState.rankDisplayScore(state.blueTeam.currentRank),
            winner: winnerIdentity?.legacyToken,
            winnerIdentity: winnerIdentity,
            actions: actionLog,
            detailedActions: detailedActions,
            setResults: ScoreboardRecordActionAdapter.setResults(from: detailedActions),
            totalScoreChanges: max(actionCount, history.count),
            extraData: [
                "schemaVersion": AnyCodable(3),
                "guandanTripleAEnabled": AnyCodable(state.aStageMode == .tripleA),
                "guandanPassACondition": AnyCodable(state.passACondition.rawValue),
                "guandanTripleAFallbackRank": AnyCodable(state.tripleAFallbackRank),
                "guandanPhase": AnyCodable(state.projectedPhaseName),
                "guandanRedRank": AnyCodable(state.redTeam.currentRank),
                "guandanBlueRank": AnyCodable(state.blueTeam.currentRank),
                "guandanIsInAStage": AnyCodable(state.isInAStage),
                "guandanRoundWinner": AnyCodable(state.lastRoundWinner?.rawValue),
                "guandanAStageTeam": AnyCodable(state.aStageTeam?.rawValue),
                "guandanFinalWinner": AnyCodable(state.finalWinner?.rawValue),
                "guandanRedAFailCount": AnyCodable(state.aFailCount(for: .red)),
                "guandanBlueAFailCount": AnyCodable(state.aFailCount(for: .blue)),
                "showMatchTime": AnyCodable(matchClockSession?.isVisible ?? false)
            ],
            projectConfiguration: [
                ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(ScoreCore.GameType.guandan.rawValue),
                "showMatchTime": AnyCodable(matchClockSession?.isVisible ?? false)
            ],
            stateSnapshot: snapshotData,
            status: .finished
        )
        do {
            try ScoreboardLifecyclePersistence.save(record, finished: finished)
        } catch {
            ScoreboardPersistenceFailureReporter.report(error, context: "Failed to save guandan record \(recordID)")
        }
    }

    private func appendSnapshot(_ code: String) {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
        let scores = guandanDetailedScores
        let safeCode = ReducerScoreboardRecordPersistence.normalizedOperationCode(code)
        actionLog.append("\(timestamp)|snapshot|\(safeCode)|\(scores.map(String.init).joined(separator: ","))|")
    }

    private func pushUndoSnapshot(_ snapshot: GuandanMatchState) {
        history.append(snapshot)
        historyTimeline.append(.init(
            actionLogCount: actionLog.count,
            detailedActionsCount: detailedActions.count,
            actionCount: actionCount
        ))
        if history.count > 80 {
            history.removeFirst(history.count - 80)
            historyTimeline.removeFirst(max(0, historyTimeline.count - 80))
        }
    }

    private var guandanDetailedScores: [Int] {
        [
            GuandanMatchState.rankDisplayScore(state.redTeam.currentRank),
            GuandanMatchState.rankDisplayScore(state.blueTeam.currentRank)
        ]
    }

    private var nextDetailedRoundNumber: Int {
        (detailedActions.compactMap(\.roundNumber).max() ?? 0) + 1
    }

    private func appendDetailedAction(
        for intent: GuandanSessionIntent,
        previousState: GuandanMatchState,
        epochMilliseconds: Int64
    ) {
        let roundNumber = nextDetailedRoundNumber
        let actions = guandanDetailedActions(
            for: intent,
            previousState: previousState,
            resultingState: state,
            epochMilliseconds: epochMilliseconds,
            roundNumber: roundNumber
        )
        for action in actions {
            appendDetailedAction(action)
        }
    }

    private func appendDetailedAction(_ action: DetailedScoreAction) {
        if detailedActions.isEmpty {
            switch action.type {
            case .matchStarted:
                break
            default:
                detailedActions.append(DetailedScoreAction(
                    type: .matchStarted,
                    epochMilliseconds: Int64(gameStartAt.timeIntervalSince1970 * 1_000),
                    scores: guandanDetailedScores,
                    operationCode: "guandan_match_started"
                ))
            }
        }
        detailedActions.append(action)
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    GuandanScoreboardView()
}
