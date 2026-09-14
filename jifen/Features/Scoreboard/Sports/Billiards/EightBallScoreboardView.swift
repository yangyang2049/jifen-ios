import OSLog
import RecordCore
import ScoreCore
import SessionCore
import SwiftUI
import UIKit

struct EightBallScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    let initialSetup: SportsSetupResult?
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)?
    var onNavigationBack: (() -> Void)?

    @State private var sessionStore: BilliardsSessionStore<EightBallReducer>
    @State private var actionLog: [String] = []
    @State private var detailedActions: [DetailedScoreAction] = []
    @State private var actionCount = 0
    @State private var startedAt: Date
    @State private var recordID: String
    @State private var leftName: String
    @State private var rightName: String
    @State private var showGameOverDialog = false
    @State private var showFinishedRecordDetail = false
    @State private var showPersistenceError = false
    @State private var manualFinishRequested = false
    @State private var isStartingNewMatch = false
    @State private var scoreboardEditing = false
    @State private var overflowToastMessage: String?
    @State private var typographyPreference = PreferencesManager.shared.scoreboardTypography(
        for: ScoreboardStyleID(gameType: .eightBall)
    )

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

        let defaults = DefaultParticipantNames.resolve(for: .eightBall)
        var left = initialSetup?.team1Name.nonEmpty ?? defaults.left
        var right = initialSetup?.team2Name.nonEmpty ?? defaults.right
        let target: Int
        let handicap: Int
        let beneficiary: MatchSide?
        if case let .some(.eightBall(targetRacks, handicapRacks, projectedBeneficiary)) = initialSetup?.billiardsConfiguration(for: .eightBall) {
            target = targetRacks
            handicap = handicapRacks
            beneficiary = projectedBeneficiary
        } else {
            target = 9
            handicap = 0
            beneficiary = nil
        }
        var initial = EightBallState.initial(
            targetPoints: target,
            handicapRacks: handicap,
            handicapBeneficiary: beneficiary
        )
        var start = Date()
        var id = UUID().uuidString
        var actions = 0
        var restoredHistory: [EightBallState] = []
        var restoredActionLog: [String] = []
        var restoredDetailedActions: [DetailedScoreAction] = []
        var showFinished = false
        var resumeBundle: BilliardsSessionStore<EightBallReducer>.ResumeBundle?

        if let initialResumeSessionId,
           let sessionId = UUID(uuidString: initialResumeSessionId),
           let bundle = BilliardsSessionStore<EightBallReducer>.decodeResumeBundle(sessionId: sessionId) {
            resumeBundle = bundle
            initial = bundle.currentSession.state
            start = bundle.currentSession.metadata.extras["startedAtEpochMilliseconds"]
                .flatMap(Int64.init)
                .map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) } ?? start
            id = bundle.currentSession.metadata.extras["recordID"] ?? initialResumeSessionId
            let recordContext = ScoreSessionRecordContext.decode(bundle.auxiliaryPayload)
            restoredActionLog = recordContext?.actionLog ?? []
            restoredDetailedActions = recordContext?.detailedActions ?? []
            actions = recordContext?.actionCount ?? bundle.timeline.count
            restoredHistory = bundle.undoFrames.map(\.session.state)
            if bundle.currentSession.participants.count >= 2 {
                left = bundle.currentSession.participants[0].name
                right = bundle.currentSession.participants[1].name
            }
            showFinished = initial.finished
        }

        let store = resumeBundle.map {
            BilliardsSessionStore(resumeBundle: $0, reducer: EightBallReducer())
        } ?? BilliardsSessionStore(
            gameType: .eightBall,
            state: initial,
            reducer: EightBallReducer(),
            participants: [
                .init(id: TeamID.team0.rawValue, name: left, role: "team"),
                .init(id: TeamID.team1.rawValue, name: right, role: "team")
            ],
            startedAt: start,
            recordID: id,
            restoredUndoStates: restoredHistory
        )
        _sessionStore = State(initialValue: store)
        _startedAt = State(initialValue: start)
        _recordID = State(initialValue: id)
        _actionCount = State(initialValue: actions)
        _actionLog = State(initialValue: restoredActionLog)
        _detailedActions = State(initialValue: restoredDetailedActions)
        _leftName = State(initialValue: left)
        _rightName = State(initialValue: right)
        _showGameOverDialog = State(initialValue: showFinished)
    }

    private var state: EightBallState { sessionStore.state }

    private var scoringLocked: Bool {
        false
    }

    var body: some View {
        eightBallContent
        .fullScreenCover(isPresented: $showFinishedRecordDetail) {
            finishedRecordDetailPage
        }
        .onAppear {
            onSetupConsumed?()
            registerSync()

        }
        .onChange(of: state.finished) { _, finished in
            if finished {
                showGameOverDialog = true

            }
        }
        .onChange(of: state) { _, newState in
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()

        }
        .onChange(of: sessionStore.persistenceFailureSignal) { _, signal in
            if signal > 0 { showPersistenceError = true }
        }

        .onDisappear {
            LocalScoreboardSyncCoordinator.shared.unregisterHost()

            sessionStore.flush {
                _ = saveRecord()
            }
        }
        .alert(
            NSLocalizedString("save_failed", value: "保存失败", comment: ""),
            isPresented: $showPersistenceError
        ) {
            Button(NSLocalizedString("confirm", value: "确定", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("scoreboard_save_failed", value: "保存失败，请稍后重试", comment: ""))
        }
    }

    private var eightBallContent: some View {
        ZStack {
            eightBallScaffold

            if showGameOverDialog {
                GameOverDialog(
                    winnerName: finishedWinnerName,
                    gameType: .eightBall,
                    leftName: leftName,
                    rightName: rightName,
                    leftScore: state.leftPoints,
                    rightScore: state.rightPoints,
                    newGameLabel: nil,
                    newGameDisabled: scoringLocked || isStartingNewMatch,
                    onNewGame: {
                        startNewMatch()
                    },
                    onRecords: {
                        if !scoringLocked, !saveRecord() { return }
                        showFinishedRecordDetail = true
                    },
                    onShare: {
                        ScoreboardShareSupport.present(text: "\(leftName) \(state.leftPoints) - \(state.rightPoints) \(rightName)")
                    },
                    onExit: exit
                )
            }

            if let overflowToastMessage {
                VStack {
                    Spacer()
                    ToastView(message: overflowToastMessage)
                        .padding(.bottom, 72)
                }
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showGameOverDialog)
        .animation(.easeInOut(duration: 0.2), value: overflowToastMessage)
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

    private var eightBallScaffold: some View {
        TwoSideScoreboardScaffold(
            gameType: .eightBall,
            leftName: displayName(onScreen: .left),
            rightName: displayName(onScreen: .right),
            leftScore: "\(logical(.left))",
            rightScore: "\(logical(.right))",
            leftDetail: nil,
            rightDetail: nil,
            finished: state.finished,
            onLeftTap: {

                send(.addRack(screenSide(.left)))
            },
            onRightTap: {

                send(.addRack(screenSide(.right)))
            },
            onUndo: { scoringLocked ? false : undo() },
            onReset: { guard !scoringLocked else { return }; send(.reset) },
            onExchange: { guard !scoringLocked else { return }; send(.exchangeSides) },
            onBack: exit,
            showEndGame: true,
            onEndGame: { guard !scoringLocked else { return }; markFinished() },
            onEditCommit: { left, right, leftScore, rightScore in
                guard !scoringLocked else { return }
                applyEditNames(left: left, right: right)
            },
            nameType: ScoreboardCommonNamePolicy.nameType(for: .eightBall),
            editingEnabled: !scoringLocked,
            scoringEnabled: !scoringLocked,
            onEditAdjust: { isLeft, delta in
                guard !scoringLocked else { return }
                adjustScore(onScreen: isLeft ? .left : .right, delta: delta)
            },
            onPanelSwipe: { isLeft, delta in
                // 对齐安卓上滑加分/下滑减分（scoreboardPanelSwipeGestures）。
                guard !scoringLocked, !state.finished else { return }
                if delta > 0 {
                    send(.addRack(screenSide(isLeft ? .left : .right)))
                } else {
                    adjustScore(onScreen: isLeft ? .left : .right, delta: -1)
                }
            },
            onDoubleTapSubtract: { isLeft in
                // 对齐安卓 subtractRack：终局后不再减；减分下限由 canAdjustRacks 守住（含让杆）。

                guard !state.finished else { return }
                adjustScore(onScreen: isLeft ? .left : .right, delta: -1)
            },
            extraMenuItems: [],
            onMenuAction: { _ in },
            panelAccessory: { isLeft in
                AnyView(
                    Group {
                        if state.handicapRacks > 0, state.handicapBeneficiary == screenSide(isLeft ? .left : .right) {
                            Text("+\(state.handicapRacks)")
                                .font(typographyPreference.font.swiftUIFont(
                                    size: 28,
                                    weight: .bold
                                ))
                                .foregroundStyle(ScoreboardAppearanceSnapshot.current().theme.palette.foreground.opacity(0.6))
                                .accessibilityIdentifier(isLeft ? "eight_ball_left_handicap" : "eight_ball_right_handicap")
                        }
                    }
                )
            },
            topCenter: { preference, containerSize, _ in
                AnyView(eightBallTargetPill(preference: preference, containerSize: containerSize))
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



    private func showToastMessage(_ message: String) {
        overflowToastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if overflowToastMessage == message {
                overflowToastMessage = nil
            }
        }
    }



    private var finishedWinnerName: String {
        if state.leftPoints > state.rightPoints { return leftName }
        if state.rightPoints > state.leftPoints { return rightName }
        return ""
    }

    private func eightBallTargetPill(
        preference: ScoreboardTypographyPreference,
        containerSize: CGSize
    ) -> some View {
        let fontSize = twoSideSecondarySize(
            text: "\(state.targetPoints)",
            preference: preference,
            containerSize: containerSize,
            baseScale: 0.32
        )
        return HStack(spacing: 8) {
            Text("\(state.targetPoints)")
                .accessibilityIdentifier("eight_ball_target")
        }
            .font(preference.font.swiftUIFont(size: fontSize, weight: .bold))
            .foregroundStyle(.white)
            .frame(minWidth: 132, minHeight: max(34, fontSize * 1.6))
            .background(Capsule().fill(Color.black.opacity(0.4)))
    }

    private func twoSideSecondarySize(
        text: String,
        preference: ScoreboardTypographyPreference,
        containerSize: CGSize,
        baseScale: CGFloat
    ) -> CGFloat {
        ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .twoSide,
                containerSize: CGSize(
                    width: max(132, min(320, containerSize.width * 0.32)),
                    height: containerSize.height
                ),
                nameText: "",
                scoreText: "",
                secondaryText: text,
                preference: preference,
                horizontalPadding: 12,
                secondaryBaseScale: baseScale,
                isLargeScreen: Theme.usesPadLayout
            )
        ).secondaryFontSize
    }

    private func logical(_ screen: MatchSide) -> Int {
        let side = screenSide(screen)
        return side == .left ? state.leftPoints : state.rightPoints
    }
    private func screenSide(_ screen: MatchSide) -> MatchSide {
        TeamScreenLayout(sidesSwapped: state.sidesSwapped).engineSide(onScreen: screen)
    }
    private func displayName(onScreen screen: MatchSide) -> String {
        screenSide(screen) == .left ? leftName : rightName
    }
    private func send(_ intent: EightBallIntent) {
        guard !scoringLocked else { return }
        sessionStore.send(
            intent,
            completion: { _, next, _ in
                projectAcceptedEightBallIntent(intent, next: next)
            },
            afterFinalized: { _, next, _ in
                if next.finished { _ = saveRecord() }
            }
        )
    }

    private func projectAcceptedEightBallIntent(_ intent: EightBallIntent, next: EightBallState) {
        actionCount += 1
        actionLog.append(ReducerScoreboardRecordPersistence.snapshot(
            code: String(describing: intent),
            scores: [next.leftPoints, next.rightPoints]
        ))
        appendEightBallAction(intent)
        persistRecordContext()
        if next.finished {
            if case .finishMatch = intent {} else { manualFinishRequested = false }
            showGameOverDialog = true
        }
    }
    private func markFinished() {
        guard !scoringLocked, !state.finished else { return }
        manualFinishRequested = true
        send(.finishMatch)
    }
    private func applyEditNames(left: String, right: String) {
        guard !scoringLocked else { return }
        let screenEdits: [(MatchSide, String)] = [(.left, left), (.right, right)]
        for (screen, name) in screenEdits where !name.isEmpty {
            if screenSide(screen) == .left {
                leftName = name
            } else {
                rightName = name
            }
        }
        sessionStore.updateParticipants([
            .init(id: TeamID.team0.rawValue, name: leftName, role: "team"),
            .init(id: TeamID.team1.rawValue, name: rightName, role: "team")
        ])
        actionCount += 1
        actionLog.append(ReducerScoreboardRecordPersistence.snapshot(code: "edit_names", scores: [state.leftPoints, state.rightPoints]))
        detailedActions.append(DetailedScoreAction(
            type: .stateChanged,
            epochMilliseconds: ReducerScoreboardRecordPersistence.nowMilliseconds(),
            scores: [state.leftPoints, state.rightPoints],
            operationCode: "eight_ball_edit_names"
        ))
        persistRecordContext()
    }

    private func adjustScore(onScreen screen: MatchSide, delta: Int) {
        let side = screenSide(screen)
        guard state.canAdjustRacks(side: side, delta: delta) else {
            if delta > 0 {
                showOverflowToast(NSLocalizedString("scoreboard_set_score_overflow", value: "局分超限", comment: ""))
            }
            return
        }
        sessionStore.sendDerived(
            { current in
                let authoritativeSide = TeamScreenLayout(sidesSwapped: current.sidesSwapped)
                    .engineSide(onScreen: screen)
                guard current.canAdjustRacks(side: authoritativeSide, delta: delta) else { return nil }
                let left = current.leftPoints + (authoritativeSide == .left ? delta : 0)
                let right = current.rightPoints + (authoritativeSide == .right ? delta : 0)
                return .adminAdjust(left: left, right: right)
            },
            completion: { intent, _, next, _ in
                projectAcceptedEightBallIntent(intent, next: next)
            },
            afterFinalized: { _, _, next, _ in
                if next.finished { _ = saveRecord() }
            }
        )
        showGameOverDialog = false
    }

    private func showOverflowToast(_ message: String) {
        overflowToastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if overflowToastMessage == message { overflowToastMessage = nil }
        }
    }
    private func undo() -> Bool {
        guard !scoringLocked else { return false }
        return sessionStore.undo { success, restored in
            guard success else { return }
            actionLog = sessionStore.recordContext.actionLog
            detailedActions = sessionStore.recordContext.detailedActions
            actionCount = sessionStore.recordContext.actionCount
            showGameOverDialog = restored.finished
        }
    }

    private func appendEightBallAction(_ intent: EightBallIntent) {
        let type: DetailedScoreActionType
        let team: RecordTeam?
        let code: String
        let gameNumber: Int?
        switch intent {
        case .addRack(let side):
            type = .scoreChanged
            team = side == .left ? .team1 : .team2
            code = "eight_ball_rack"
            gameNumber = max(1, state.leftPoints + state.rightPoints)
        case .applyPot(let side, let ball):
            type = .scoreChanged
            team = side == .left ? .team1 : .team2
            code = "eight_ball_pot_\(ball)"
            gameNumber = nil
        case .adminAdjust:
            type = .stateChanged; team = nil; code = "eight_ball_edit"; gameNumber = nil
        case .exchangeSides:
            type = .sideChanged; team = nil; code = "exchange_side"; gameNumber = nil
        case .reset:
            type = .reset; team = nil; code = "reset"; gameNumber = nil
        case .finishMatch:
            type = .matchFinished; team = nil; code = "finish"; gameNumber = nil
        }
        detailedActions.append(DetailedScoreAction(
            type: type,
            epochMilliseconds: ReducerScoreboardRecordPersistence.nowMilliseconds(),
            team: team,
            scores: [state.leftPoints, state.rightPoints],
            gameNumber: gameNumber,
            operationCode: code
        ))
    }

    private func persistRecordContext() {
        sessionStore.updateRecordContext(
            actionLog: actionLog,
            detailedActions: detailedActions,
            actionCount: actionCount
        )
    }
    private func exit() {
        OrientationLock.shared.unlock()

        sessionStore.flush {
            _ = saveRecord()
            onNavigationBack?()
            dismiss()
        }
    }
    private func registerSync() {
        LocalScoreboardSyncCoordinator.shared.registerHost(snapshot: syncSnapshot) { intent in
            guard LocalScoreboardMutationPolicy.allowsMutation(
                isEditing: scoreboardEditing,
                finished: state.finished,
                scoringLocked: scoringLocked
            ) else { return }
            switch intent {
            case .addLeft: send(.addRack(screenSide(.left)))
            case .addRight: send(.addRack(screenSide(.right)))
            case .subtractLeft, .subtractRight, .undo: _ = undo()
            case .exchangeSides: send(.exchangeSides)
            case .requestSnapshot: break
            }
        }
    }









    private func startNewMatch() {
        guard !scoringLocked, !isStartingNewMatch else { return }
        isStartingNewMatch = true
        let finishedStore = sessionStore
        finishedStore.persistSnapshot { persisted in
            guard persisted, saveRecord() else {
                isStartingNewMatch = false
                return
            }
            let newStartedAt = Date()
            let newRecordID = UUID().uuidString
            let freshState = EightBallState.initial(
                targetPoints: state.targetPoints,
                handicapRacks: state.handicapRacks,
                handicapBeneficiary: state.handicapBeneficiary
            )
            let freshStore = BilliardsSessionStore(
                gameType: .eightBall,
                state: freshState,
                reducer: EightBallReducer(),
                participants: [
                    .init(id: TeamID.team0.rawValue, name: leftName, role: "team"),
                    .init(id: TeamID.team1.rawValue, name: rightName, role: "team")
                ],
                startedAt: newStartedAt,
                recordID: newRecordID
            )
            freshStore.persistSnapshot { freshSaved in
                isStartingNewMatch = false
                guard freshSaved else { return }
                sessionStore = freshStore
                startedAt = newStartedAt
                recordID = newRecordID
                actionCount = 0
                actionLog.removeAll()
                detailedActions.removeAll()
                manualFinishRequested = false
                scoreboardEditing = false
                showGameOverDialog = false
                LocalScoreboardSyncCoordinator.shared.publishSnapshot()

            }
        }
    }
    private func syncSnapshot() -> LocalScoreboardDisplayState {
        var snapshot = LocalScoreboardDisplayState(
            gameID: GameType.eightBall.canonicalScoreboardIdentifier, title: "",
              leftName: displayName(onScreen: .left), rightName: displayName(onScreen: .right),
              leftScore: "\(logical(.left))", rightScore: "\(logical(.right))",
              leftDetail: nil, rightDetail: nil,
              themeID: ScoreboardAppearanceSnapshot.current().theme.rawValue,
              fontID: typographyPreference.font.rawValue,
              scoreMultiplier: typographyPreference.scoreMultiplier,
              nameMultiplier: typographyPreference.nameMultiplier,
              secondaryMultiplier: typographyPreference.secondaryMultiplier,
              finished: state.finished, revision: 0)
        // 显示端顶部目标数/让局信息（对齐安卓 eight_ball sportState 键）。
        snapshot.externalState = ScoreboardDisplayState.enriched(
            compact: snapshot,
            layoutKind: .twoSide,
            sportState: [
                "team0ScreenSide": .string(state.sidesSwapped ? "right" : "left"),
                "eightBallTargetRacks": .integer(state.targetPoints),
                "eightBallHandicapRacks": .integer(state.handicapRacks),
                "eightBallHandicapBeneficiary": .string(
                    state.handicapBeneficiary == .left ? "team_0" : (state.handicapBeneficiary == .right ? "team_1" : "none")
                )
            ]
        )
        return snapshot
    }
    @discardableResult
    private func saveRecord() -> Bool {
        if state.finished, sessionStore.hasCommittedFinishedRecord {
            return true
        }
        let success = ReducerScoreboardRecordPersistence.saveRecord(
            id: recordID, gameType: .eightBall, startedAt: startedAt,
            leftName: leftName, rightName: rightName,
            left: state.leftPoints, right: state.rightPoints,
            actionCount: actionCount, actions: actionLog, detailedActions: detailedActions, undoStates: sessionStore.undoStates, finished: state.finished, snapshot: state,
            sessionSnapshotData: sessionStore.encodedResumeBundle,
            projectConfiguration: [
                "maxSets": state.targetPoints,
                "eightBallHandicapRacks": state.handicapRacks,
                "eightBallHandicapBeneficiary": state.handicapBeneficiary == .left ? "team1" : (state.handicapBeneficiary == .right ? "team2" : "none")
            ],
            finishedSessionId: sessionStore.sessionId,
            finishedCommitCoordinator: sessionStore.finishedCommitCoordinator,
            replaceCommittedFinishedRecord: sessionStore.shouldReplaceCommittedFinishedRecord
        )
        if success, state.finished, actionCount > 0 {
            sessionStore.markFinishedRecordCommitted()
        }
        if !success { showPersistenceError = true }
        return success
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
