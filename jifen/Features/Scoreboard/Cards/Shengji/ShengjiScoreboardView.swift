import LinkCore
import OSLog
import RecordCore
import ScoreCore
import SessionCore
import SwiftUI
import UIKit

func shengjiDetailedAction(
    for intent: ShengjiTierIntent,
    resultingState state: ShengjiTierState,
    epochMilliseconds: Int64,
    roundNumber: Int
) -> DetailedScoreAction {
    func recordTeam(_ side: MatchSide?) -> RecordTeam? {
        guard let side else { return nil }
        return side == .left ? .team1 : .team2
    }
    let scores = [state.leftIndex, state.rightIndex]

    switch intent {
    case .addLevels(let side, let delta):
        return .init(type: .scoreChanged, epochMilliseconds: epochMilliseconds, team: recordTeam(side), scores: scores, scoreChange: delta, operationCode: "shengji_levels_added")
    case .subtractLevels(let side, let delta):
        return .init(type: .scoreChanged, epochMilliseconds: epochMilliseconds, team: recordTeam(side), scores: scores, scoreChange: -delta, operationCode: "shengji_levels_subtracted")
    case .claimDealer(let side):
        return .init(type: .stateChanged, epochMilliseconds: epochMilliseconds, team: recordTeam(side), scores: scores, operationCode: "shengji_dealer_claimed")
    case .resolveRound(let winner, let delta):
        let team = recordTeam(winner)
        return .init(type: .roundFinished, epochMilliseconds: epochMilliseconds, team: team, scores: scores, roundNumber: roundNumber, scoreChange: delta, winner: team, operationCode: "shengji_round_finished")
    case .adminCorrect:
        return .init(type: .stateChanged, epochMilliseconds: epochMilliseconds, scores: scores, operationCode: "shengji_admin_corrected")
    case .exchangeSides:
        return .init(type: .sideChanged, epochMilliseconds: epochMilliseconds, scores: scores, operationCode: "shengji_sides_exchanged")
    case .reset:
        return .init(type: .reset, epochMilliseconds: epochMilliseconds, scores: scores, operationCode: "shengji_reset")
    case .finish:
        return .init(type: .matchFinished, epochMilliseconds: epochMilliseconds, scores: scores, winner: recordTeam(state.winnerSide), operationCode: "shengji_match_finished")
    }
}

struct ShengjiScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    let initialSetup: SportsSetupResult?
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)?
    var onNavigationBack: (() -> Void)?
    @State private var state: ShengjiTierState
    @State private var history: [ShengjiTierState] = []
    @State private var actionLog: [String] = []
    @State private var detailedActions: [DetailedScoreAction] = []
    @State private var actionCount = 0
    @State private var startedAt: Date
    @State private var recordID: String
    @State private var leftName: String
    @State private var rightName: String
    @State private var showFinishedRecordDetail = false
    @State private var scoreboardEditing = false
    @State private var showGameOverDialog = false
    @State private var showPersistenceError = false
    @State private var typographyPreference = PreferencesManager.shared.scoreboardTypography(
        for: ScoreboardStyleID(gameType: .shengji)
    )
    private let reducer = ShengjiTierReducer()
    private let levels = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]

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

        let defaults = DefaultParticipantNames.resolve(for: .shengji)
        var left = initialSetup?.team1Name.nonEmpty ?? defaults.left
        var right = initialSetup?.team2Name.nonEmpty ?? defaults.right
        var initial = ShengjiTierState()
        var start = Date()
        var id = ScoreboardRecordIdentity.next(prefix: GameType.shengji.canonicalScoreboardIdentifier)
        var actions = 0
        var restoredHistory: [ShengjiTierState] = []
        var restoredActionLog: [String] = []
        var restoredDetailedActions: [DetailedScoreAction] = []

        if let initialResumeSessionId,
           let resume = ReducerScoreboardRecordPersistence.loadResume(recordId: initialResumeSessionId, as: ShengjiTierState.self) {
            initial = resume.state
            start = resume.record.startTime
            id = resume.record.id
            restoredHistory = Array(resume.undoStates.suffix(80))
            restoredActionLog = resume.intentTimeline
            restoredDetailedActions = resume.detailedActions
            actions = max(max(resume.record.totalScoreChanges, restoredHistory.count), 1)
            left = resume.record.team1Name
            right = resume.record.team2Name
        }

        _state = State(initialValue: initial)
        _history = State(initialValue: restoredHistory)
        _actionLog = State(initialValue: restoredActionLog)
        _detailedActions = State(initialValue: restoredDetailedActions)
        _showGameOverDialog = State(initialValue: initial.finished)
        _startedAt = State(initialValue: start)
        _recordID = State(initialValue: id)
        _actionCount = State(initialValue: actions)
        _leftName = State(initialValue: left)
        _rightName = State(initialValue: right)
    }

    var body: some View {
        shengjiContent
        .fullScreenCover(isPresented: $showFinishedRecordDetail) {
            finishedRecordDetailPage
        }
        .onAppear { onSetupConsumed?(); registerSync() }
        .onChange(of: state) { _, _ in LocalScoreboardSyncCoordinator.shared.publishSnapshot() }
        .onDisappear { LocalScoreboardSyncCoordinator.shared.unregisterHost(); saveRecord() }
        .alert(
            NSLocalizedString("save_failed", value: "保存失败", comment: ""),
            isPresented: $showPersistenceError
        ) {
            Button(NSLocalizedString("confirm", value: "确定", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("scoreboard_save_failed", value: "保存失败，请稍后重试", comment: ""))
        }
    }

    private var shengjiContent: some View {
        ZStack {
            shengjiScaffold

            if showGameOverDialog {
                let winnerName: String = switch state.winnerSide {
                case .left: leftName
                case .right: rightName
                case nil: ""
                }
                let winnerIndices: Set<Int> = switch state.winnerSide {
                case .left: [0]
                case .right: [1]
                case nil: []
                }
                GameOverDialog(
                    winnerName: winnerName,
                    gameType: .shengji,
                    resultText: "\(level(state.leftIndex)) - \(level(state.rightIndex))",
                    leftName: leftName,
                    rightName: rightName,
                    leftScoreText: level(state.leftIndex),
                    rightScoreText: level(state.rightIndex),
                    winnerIndices: winnerIndices,
                    onNewGame: {
                        startNewMatch()
                    },
                    onRecords: {
                        saveRecord()
                        showFinishedRecordDetail = true
                    },
                    onShare: {
                        ScoreboardShareSupport.present(text: "\(leftName) \(level(state.leftIndex)) - \(level(state.rightIndex)) \(rightName)")
                    },
                    onExit: exit
                )
            }
        }
    }

    private var finishedRecordDetailPage: some View {
        NavigationStack {
            ScoreboardRecordDetailPage(recordId: recordID)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ModalCloseButton { showFinishedRecordDetail = false }
                    }
                }
        }
    }

    private var shengjiScaffold: some View {
        TwoSideScoreboardScaffold(
            gameType: .shengji,
            leftName: shengjiName(onScreen: .left),
            rightName: shengjiName(onScreen: .right),
            leftScore: level(shengjiValue(onScreen: .left, left: state.leftIndex, right: state.rightIndex)),
            rightScore: level(shengjiValue(onScreen: .right, left: state.leftIndex, right: state.rightIndex)),
            leftDetail: nil,
            rightDetail: nil,
            finished: state.finished,
            onLeftTap: {},
            onRightTap: {},
            onUndo: undo,
            onReset: resetMatch,
            onExchange: { send(.exchangeSides) },
            onBack: exit,
            showEndGame: true,
            onEndGame: finishMatch,
            onEditCommit: applyEdit,
            onEditAdjust: { isLeft, delta in
                let side = shengjiLogicalSide(onScreen: isLeft ? .left : .right)
                if delta < 0 {
                    send(.subtractLevels(side: side, delta: abs(delta)))
                } else {
                    send(.addLevels(side: side, delta: delta))
                }
            },
            seamOverlay: state.dealer == nil ? nil : {
                AnyView(
                    GeometryReader { geo in
                        let indicatorSize = ScoreboardLayoutMetrics.serveIndicatorSize(
                            halfViewportSize: CGSize(width: geo.size.width / 2, height: geo.size.height)
                        )
                        CenterLineServeIndicator(
                            isLeftServing: state.dealer == shengjiLogicalSide(onScreen: .left),
                            triangleSize: indicatorSize,
                            color: ScoreboardTheme.serverIndicatorColor
                        )
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                    .allowsHitTesting(false)
                )
            },
            panelAccessory: { isLeft in
                AnyView(shengjiPanelActions(side: shengjiLogicalSide(onScreen: isLeft ? .left : .right)))
            },
            onEditModeChange: { scoreboardEditing = $0 },
            onTypographyChange: { preference in
                typographyPreference = preference
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()
            },
            sidesSwapped: state.sidesSwapped
        ) { _, _ in
            EmptyView()
        }
    }

    private var shengjiScreenLayout: TeamScreenLayout {
        TeamScreenLayout(sidesSwapped: state.sidesSwapped)
    }

    private func shengjiLogicalSide(onScreen screen: MatchSide) -> MatchSide {
        shengjiScreenLayout.engineSide(onScreen: screen)
    }

    private func shengjiName(onScreen screen: MatchSide) -> String {
        shengjiLogicalSide(onScreen: screen) == .left ? leftName : rightName
    }

    private func shengjiValue(onScreen screen: MatchSide, left: Int, right: Int) -> Int {
        shengjiLogicalSide(onScreen: screen) == .left ? left : right
    }

    @ViewBuilder
    private func shengjiPanelActions(side: MatchSide) -> some View {
        if state.dealer == nil {
            scoreboardCardActionButton(
                NSLocalizedString("shengji_claim_dealer", value: "抢庄", comment: ""),
                width: Theme.usesPadLayout ? 104 : 88
            ) {
                send(.claimDealer(side))
            }
            .accessibilityIdentifier(side == .left ? "ui_test_shengji_left_banker" : "ui_test_shengji_right_banker")
        } else if !state.finished {
            HStack(spacing: 12) {
                if state.dealer != side {
                    scoreboardCardActionButton(
                        NSLocalizedString("shengji_take_dealer", value: "上台", comment: ""),
                        width: Theme.usesPadLayout ? 96 : 80
                    ) {
                        send(.resolveRound(winner: side, delta: 0))
                    }
                }
                ForEach([1, 2, 3], id: \.self) { step in
                    scoreboardCardActionButton("+\(step)") {
                        send(.resolveRound(winner: side, delta: step))
                    }
                }
            }
        }
    }

    private func level(_ index: Int) -> String { levels[min(max(0, index), levels.count - 1)] }
    private func send(_ intent: ShengjiTierIntent) {
        let timestamp = ReducerScoreboardRecordPersistence.nowMilliseconds()
        let result = reducer.reduce(state: state, intent: intent, at: timestamp)
        guard result.accepted else { return }
        history.append(state)
        if history.count > 80 { history.removeFirst(history.count - 80) }
        let wasFinished = state.finished
        state = result.state
        actionCount += 1
        actionLog.append(ReducerScoreboardRecordPersistence.snapshot(code: String(describing: intent), scores: [state.leftIndex, state.rightIndex]))
        appendDetailedAction(shengjiDetailedAction(
            for: intent,
            resultingState: state,
            epochMilliseconds: timestamp,
            roundNumber: nextDetailedRoundNumber
        ))
        if state.finished, !wasFinished {
            showGameOverDialog = true
        }
    }
    private func undo() -> Bool {
        guard let previous = history.popLast() else { return false }
        state = previous
        actionCount = max(0, actionCount - 1)
        actionLog.append(ReducerScoreboardRecordPersistence.snapshot(code: "undo", scores: [state.leftIndex, state.rightIndex]))
        appendDetailedAction(DetailedScoreAction(
            type: .undo,
            epochMilliseconds: ReducerScoreboardRecordPersistence.nowMilliseconds(),
            scores: [state.leftIndex, state.rightIndex],
            operationCode: "shengji_undo"
        ))
        showGameOverDialog = state.finished
        return true
    }
    private func resetMatch() {
        send(.reset)
        showGameOverDialog = false
    }
    private func startNewMatch() {
        saveRecord()
        state = ShengjiTierState(maxTierIndex: state.maxTierIndex)
        history.removeAll()
        actionLog.removeAll()
        detailedActions.removeAll()
        actionCount = 0
        startedAt = Date()
        recordID = ScoreboardRecordIdentity.next(prefix: GameType.shengji.canonicalScoreboardIdentifier)
        showGameOverDialog = false
    }
    private func finishMatch() {
        send(.finish)
    }
    private func applyEdit(left: String, right: String, leftScore: String, rightScore: String) {
        let previousState = state
        let previousLeftName = leftName
        let previousRightName = rightName
        let screenLeftIndex = levels.firstIndex(of: leftScore.uppercased())
            ?? shengjiValue(onScreen: .left, left: state.leftIndex, right: state.rightIndex)
        let screenRightIndex = levels.firstIndex(of: rightScore.uppercased())
            ?? shengjiValue(onScreen: .right, left: state.leftIndex, right: state.rightIndex)
        let leftIdentityOnScreenLeft = shengjiLogicalSide(onScreen: .left) == .left
        let nextLeftIndex = leftIdentityOnScreenLeft ? screenLeftIndex : screenRightIndex
        let nextRightIndex = leftIdentityOnScreenLeft ? screenRightIndex : screenLeftIndex
        let result = reducer.reduce(
            state: state,
            intent: .adminCorrect(left: nextLeftIndex, right: nextRightIndex),
            at: ReducerScoreboardRecordPersistence.nowMilliseconds()
        )
        guard result.accepted else { return }
        let next = result.state

        let screenLeftName = left.isEmpty ? shengjiName(onScreen: .left) : left
        let screenRightName = right.isEmpty ? shengjiName(onScreen: .right) : right
        let nextLeftName = leftIdentityOnScreenLeft ? screenLeftName : screenRightName
        let nextRightName = leftIdentityOnScreenLeft ? screenRightName : screenLeftName
        let stateChanged = next != previousState
        let namesChanged = nextLeftName != previousLeftName || nextRightName != previousRightName
        guard stateChanged || namesChanged else { return }

        if stateChanged {
            history.append(previousState)
            if history.count > 80 { history.removeFirst(history.count - 80) }
        }
        state = next
        leftName = nextLeftName
        rightName = nextRightName
        actionCount += 1
        actionLog.append(ReducerScoreboardRecordPersistence.snapshot(
            code: "adminCorrect",
            scores: [state.leftIndex, state.rightIndex]
        ))
        appendDetailedAction(shengjiDetailedAction(
            for: .adminCorrect(left: nextLeftIndex, right: nextRightIndex),
            resultingState: state,
            epochMilliseconds: ReducerScoreboardRecordPersistence.nowMilliseconds(),
            roundNumber: nextDetailedRoundNumber
        ))
    }
    private func exit() { saveRecord(); onNavigationBack?(); dismiss() }
    private func registerSync() {
        LocalScoreboardSyncCoordinator.shared.registerHost(snapshot: syncSnapshot) { intent in
            guard LocalScoreboardMutationPolicy.allowsMutation(
                isEditing: scoreboardEditing,
                finished: state.finished,
                scoringLocked: false
            ) else { return }
            switch intent {
            case .addLeft:
                let side = shengjiLogicalSide(onScreen: .left)
                if state.dealer == nil { send(.claimDealer(side)) }
                else { send(.resolveRound(winner: side, delta: 1)) }
            case .addRight:
                let side = shengjiLogicalSide(onScreen: .right)
                if state.dealer == nil { send(.claimDealer(side)) }
                else { send(.resolveRound(winner: side, delta: 1)) }
            case .subtractLeft: send(.subtractLevels(side: shengjiLogicalSide(onScreen: .left), delta: 1))
            case .subtractRight: send(.subtractLevels(side: shengjiLogicalSide(onScreen: .right), delta: 1))
            case .undo: _ = undo()
            case .exchangeSides: send(.exchangeSides)
            default: break
            }
        }
    }
    private func syncSnapshot() -> LocalScoreboardDisplayState {
        return .init(
            gameID: GameType.shengji.canonicalScoreboardIdentifier,
            title: GameType.shengji.displayName,
            leftName: shengjiName(onScreen: .left),
            rightName: shengjiName(onScreen: .right),
            leftScore: level(shengjiValue(onScreen: .left, left: state.leftIndex, right: state.rightIndex)),
            rightScore: level(shengjiValue(onScreen: .right, left: state.leftIndex, right: state.rightIndex)),
            leftDetail: nil,
            rightDetail: nil,
            themeID: ScoreboardAppearanceSnapshot.current().theme.rawValue,
            fontID: typographyPreference.font.rawValue,
            scoreMultiplier: typographyPreference.scoreMultiplier,
            nameMultiplier: typographyPreference.nameMultiplier,
            secondaryMultiplier: typographyPreference.secondaryMultiplier,
            finished: state.finished,
            revision: 0
        )
    }
    @discardableResult
    private func saveRecord() -> Bool {
        let success = ReducerScoreboardRecordPersistence.saveRecord(
            id: recordID, gameType: .shengji, startedAt: startedAt,
            leftName: leftName, rightName: rightName,
            left: state.leftIndex, right: state.rightIndex,
            actionCount: actionCount,
            actions: actionLog,
            detailedActions: detailedActions,
            undoStates: Array(history.suffix(80)),
            finished: state.finished,
            snapshot: state
        )
        if !success { showPersistenceError = true }
        return success
    }

    private var nextDetailedRoundNumber: Int {
        (detailedActions.compactMap(\.roundNumber).max() ?? 0) + 1
    }

    private func appendDetailedAction(_ action: DetailedScoreAction) {
        if detailedActions.isEmpty {
            switch action.type {
            case .matchStarted:
                break
            default:
                detailedActions.append(DetailedScoreAction(
                    type: .matchStarted,
                    epochMilliseconds: Int64(startedAt.timeIntervalSince1970 * 1_000),
                    scores: [0, 0],
                    operationCode: "shengji_match_started"
                ))
            }
        }
        detailedActions.append(action)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
