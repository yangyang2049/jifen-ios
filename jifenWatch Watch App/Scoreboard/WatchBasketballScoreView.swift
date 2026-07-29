import Observation
import LinkCore
import PersistenceCore
import RecordCore
import ScoreCore
import SessionCore
import SwiftUI

@MainActor
@Observable
private final class WatchBasketballSessionStore {
    typealias ResumeBundle = ScoreSessionResumeBundle<
        BasketballMatchState,
        BasketballMatchEvent,
        BasketballMatchIntent
    >

    private let core: ScoreSessionCore<BasketballMatchReducer>
    private let snapshotStore: AtomicJSONFileStore<ScoreSession<BasketballMatchState, BasketballMatchEvent>>
    private let archiveIndex: SessionArchiveIndex
    private var clockTask: Task<Void, Never>?

    private(set) var state: BasketballMatchState
    private(set) var actionLog: WatchScoreActionLog

    init(
        gameMode: BasketballGameMode,
        initialState: BasketballMatchState? = nil,
        resumeBundle: ResumeBundle? = nil,
        resumedActionLog: WatchScoreActionLog? = nil,
        startedAt: Date = Date()
    ) {
        let initial = resumeBundle?.currentSession.state ?? initialState ?? BasketballMatchEngine.initial(
            leftName: NSLocalizedString("watch_team_red", value: "红方", comment: "Red"),
            rightName: NSLocalizedString("watch_team_blue", value: "蓝方", comment: "Blue"),
            gameMode: gameMode
        )
        let session = resumeBundle?.currentSession ?? ScoreSession<BasketballMatchState, BasketballMatchEvent>(
            gameType: gameMode == .threeXThree ? .threeBasketball : .basketball,
            ruleFamily: .s2,
            reducerType: "basketball/v1",
            state: initial,
            participants: [
                .init(id: TeamID.team0.rawValue, name: initial.leftName, role: "team"),
                .init(id: TeamID.team1.rawValue, name: initial.rightName, role: "team")
            ]
        )
        if let resumeBundle {
            self.core = ScoreSessionCore(
                resumeBundle: resumeBundle,
                reducer: BasketballMatchReducer(),
                shouldFinish: { _, state in state.finished }
            )
        } else {
            self.core = ScoreSessionCore(
                seedSession: session,
                reducer: BasketballMatchReducer(),
                shouldFinish: { _, state in state.finished }
            )
        }
        self.snapshotStore = AtomicJSONFileStore(fileURL: Self.snapshotURL(for: session.sessionId))
        self.archiveIndex = SessionArchiveIndex(fileURL: Self.archiveIndexURL())
        self.state = initial
        self.actionLog = resumedActionLog ?? WatchScoreActionLog(startedAt: startedAt)
    }

    func send(_ intent: BasketballMatchIntent, recordsUndo: Bool = true) {
        Task { [weak self, core] in
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            guard let self else { return }
            if recordsUndo { self.actionLog.beginUndoableMutation() }
            let result = if recordsUndo {
                await core.dispatch(actorId: "watch", intent: intent, at: now)
            } else {
                await core.dispatchNonUndoable(actorId: "watch", intent: intent, at: now)
            }
            guard case .accepted(let session, _) = result else {
                if recordsUndo { self.actionLog.rejectUndoableMutation() }
                return
            }
            self.state = session.state
            guard recordsUndo else { return }
            let timestamp = Date(timeIntervalSince1970: TimeInterval(now) / 1_000)
            if case .reset = intent {
                self.actionLog.reset(at: timestamp)
            } else {
                self.actionLog.append(contentsOf: WatchScoreActionProjector.basketball(
                    intent: intent,
                    state: session.state,
                    timestamp: timestamp
                ))
            }
        }
    }

    func undo(onSuccess: @escaping () -> Void = {}) {
        Task { [weak self, core] in
            guard await core.undo(actorId: "watch"), let self else { return }
            let state = await core.snapshot().state
            self.state = state
            self.actionLog.undo(
                at: Date(),
                team1Score: state.leftScore,
                team2Score: state.rightScore
            )
            onSuccess()
        }
    }

    func startClock() {
        guard clockTask == nil else { return }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.send(.tickClock, recordsUndo: false)
            }
        }
    }

    func stopClock() {
        clockTask?.cancel()
        clockTask = nil
    }

    func stopClockAndPersist() {
        stopClock()
        Task { [core, snapshotStore, archiveIndex] in
            let session = await core.snapshot()
            try? await snapshotStore.save(session)
            try? await archiveIndex.upsert(.init(
                sessionId: session.sessionId,
                gameType: session.gameType,
                source: .watchLocal,
                snapshotPath: "watch-sessions/\(session.sessionId.uuidString).json",
                participants: session.participants,
                status: session.status,
                updatedAtEpochMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
            ))
        }
    }

    func replaceDisplayedState(_ state: BasketballMatchState) {
        self.state = state
    }

    func mergeRemoteActions(_ actions: [DetailedScoreAction]) {
        actionLog.merge(detailedActions: actions)
    }

    func resumeBundle() async -> ResumeBundle {
        await core.resumeBundle()
    }

    private static func snapshotURL(for sessionId: UUID) -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jifen-v2/watch-sessions", isDirectory: true)
        return directory.appendingPathComponent("\(sessionId.uuidString).json")
    }

    private static func archiveIndexURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jifen-v2/session-index.json")
    }
}

struct WatchBasketballScoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchLinkService.self) private var linkService
    @Environment(WatchResumeSessionStore.self) private var resumeStore

    let gameMode: BasketballGameMode
    let linkedSessionId: UUID?
    @State private var store: WatchBasketballSessionStore
    @State private var selectedSide: MatchSide?
    @State private var showMenu = false
    @State private var confirmation: WatchScoreboardConfirmation?
    @State private var showFinishedOverlay = false
    @State private var finishUndoAvailable = false
    @State private var finishTask: Task<Void, Never>?
    @State private var didPublishFinish = false
    @State private var matchStartTime = Date()
    @State private var suppressTapAfterLongPress = false
    @State private var manualFinishRequested = false
    @State private var undoToastToken: UUID?

    init(
        gameMode: BasketballGameMode,
        initialState: BasketballMatchState? = nil,
        linkedSessionId: UUID? = nil,
        resumeBundle: ScoreSessionResumeBundle<
            BasketballMatchState,
            BasketballMatchEvent,
            BasketballMatchIntent
        >? = nil,
        resumedStartTime: Date? = nil,
        resumedActionLog: WatchScoreActionLog? = nil
    ) {
        self.gameMode = gameMode
        self.linkedSessionId = linkedSessionId
        let startedAt = resumedStartTime ?? Date()
        _store = State(initialValue: WatchBasketballSessionStore(
            gameMode: gameMode,
            initialState: initialState,
            resumeBundle: resumeBundle,
            resumedActionLog: resumedActionLog,
            startedAt: startedAt
        ))
        _matchStartTime = State(initialValue: startedAt)
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let width = proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing
                let height = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
                VStack(spacing: 0) {
                    side(.left, height: height / 2)
                    side(.right, height: height / 2)
                }
                .frame(width: width, height: height)
                .offset(x: -proxy.safeAreaInsets.leading, y: -proxy.safeAreaInsets.top)
            }
            .ignoresSafeArea()
            .disabled(!interactionsEnabled)

            VStack(spacing: 3) {
                Text(periodTitle)
                    .font(.caption2.weight(.bold))
                Text(clockText(store.state.gameTimeSeconds))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                Text("\(store.state.shotTimeSeconds)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(WatchTheme.accent)
                Button {
                    store.send(.setClockRunning(!store.state.gameRunning))
                } label: {
                    Image(systemName: store.state.gameRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.accent)
            }
            .padding(8)
            .background(Color.black.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if let selectedSide {
                scoreOverlay(for: selectedSide)
            }
            if showMenu {
                WatchScoreboardMenuOverlay(
                    onDismiss: { showMenu = false },
                    onUndo: {
                        undoScoreboard()
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
            if showFinishedOverlay {
                WatchFinishedOverlay(
                    title: NSLocalizedString("watch_match_finished", value: "比赛结束", comment: ""),
                    scoreItems: [
                        WatchFinishedScoreItem(name: store.state.leftName, score: String(store.state.leftScore)),
                        WatchFinishedScoreItem(name: store.state.rightName, score: String(store.state.rightScore))
                    ],
                    winnerText: basketballWinnerText,
                    undoAvailable: finishUndoAvailable,
                    onUndo: undoFinishedBasketball,
                    onPlayAgain: restartBasketball,
                    onExit: {
                        finalizeBasketball()
                        exitBasketball()
                    }
                )
            }
            if let confirmation {
                WatchConfirmationOverlay(
                    confirmation: confirmation,
                    onCancel: { self.confirmation = nil },
                    onConfirm: { confirmBasketball(confirmation) }
                )
            }
        }
        .ignoresSafeArea()
        .disabled(isFollowingPhone)
        .onAppear {
            if !isFollowingPhone {
                store.startClock()
            }
        }
        .onChange(of: linkService.latestSnapshot) { _, update in
            guard let linkedSessionId,
                  let update,
                  update.sessionId == linkedSessionId else { return }
            guard let state = update.snapshot.basketballState else { return }
            guard state.gameMode == gameMode else { return }
            store.mergeRemoteActions(update.detailedActions)
            store.replaceDisplayedState(state)
            if state.finished {
                beginRemoteBasketballFinishPresentation()
            } else {
                finishTask?.cancel()
                showFinishedOverlay = false
                finishUndoAvailable = false
                didPublishFinish = false
            }
        }
        .onChange(of: store.state) { oldState, newState in
            if linkedSessionId != nil, linkService.isController {
                linkService.publishSnapshot(.basketball(newState), detailedActions: store.actionLog.detailedActions)
            }
            if !oldState.finished, newState.finished {
                if isFollowingPhone {
                    beginRemoteBasketballFinishPresentation()
                } else {
                    beginBasketballFinish()
                }
            }
            Task { await persistResumeSession() }
        }
        .onDisappear {
            finishTask?.cancel()
            if store.state.finished { finalizeBasketball() }
            Task { await persistResumeSession() }
            if isFollowingPhone {
                store.stopClock()
            } else {
                store.stopClockAndPersist()
            }
        }
        .watchScoreboardGestures(
            suppressTapAfterLongPress: $suppressTapAfterLongPress,
            enabled: interactionsEnabled,
            onMenu: { showMenu = true },
            onUndo: undoScoreboard,
            onExit: exitBasketball
        )
        .watchUndoToast(token: $undoToastToken)
    }

    private func side(_ screenSide: MatchSide, height: CGFloat) -> some View {
        let logicalSide = TeamScreenLayout(sidesSwapped: store.state.sidesSwapped).engineSide(onScreen: screenSide)
        let isLeft = logicalSide == .left
        let score = isLeft ? store.state.leftScore : store.state.rightScore
        let fouls = isLeft ? store.state.leftFouls : store.state.rightFouls
        let timeouts = isLeft ? store.state.leftTimeouts : store.state.rightTimeouts
        let name = isLeft ? store.state.leftName : store.state.rightName
        let scoreText = "\(score)"
        let scoreFont = WatchScoreTypography.adaptiveFontSize(
            baseSize: 58,
            scoreText: scoreText,
            minimumSize: 40
        )

        return VStack(spacing: 2) {
            Text(name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(scoreText)
                .font(WatchScoreTypography.primaryScore(size: scoreFont))
                .monospacedDigit()
            Text(String(format: NSLocalizedString("watch_bball_fouls_timeouts_format", value: "犯规 %d  暂停 %d", comment: ""), fouls, timeouts))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background(isLeft ? Color(hex: 0xE53935) : Color(hex: 0x1E88E5))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isFollowingPhone, !suppressTapAfterLongPress else { return }
            selectedSide = logicalSide
        }
    }

    private func scoreOverlay(for side: MatchSide) -> some View {
        ZStack {
            Color.black.opacity(0.84)
                .ignoresSafeArea()
                .onTapGesture { selectedSide = nil }
            ScrollView {
                VStack(spacing: WatchLayout.isCompactScreen ? 7 : 10) {
                    Text(side == .left ? store.state.leftName : store.state.rightName)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    HStack {
                        ForEach(BasketballMatchEngine.scoringButtons(store.state), id: \.self) { points in
                            Button("+\(points)") {
                                store.send(.addPoints(side: side, points: points))
                                selectedSide = nil
                            }
                        }
                    }
                    Button(NSLocalizedString("watch_bball_foul_plus", value: "犯规 +1", comment: "")) {
                        store.send(.addFoul(side: side))
                        selectedSide = nil
                    }
                    Button(NSLocalizedString("watch_bball_timeout", value: "暂停", comment: "")) {
                        store.send(.useTimeout(side: side))
                        selectedSide = nil
                    }
                    HStack {
                        ForEach(shotClockOptions, id: \.self) { seconds in
                            Button("\(seconds)s") {
                                store.send(.resetShotClock(seconds: seconds))
                                selectedSide = nil
                            }
                        }
                    }
                    Button(NSLocalizedString("watch_bball_cancel", value: "取消", comment: ""), role: .cancel) {
                        selectedSide = nil
                    }
                }
                .padding(.horizontal, WatchLayout.isCompactScreen ? 8 : 12)
                .padding(.vertical, WatchLayout.isCompactScreen ? 10 : 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WatchTheme.overlayCard)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private var periodTitle: String {
        if store.state.isOvertime {
            return NSLocalizedString("watch_bball_overtime", value: "加时", comment: "")
        }
        return gameMode == .threeXThree
            ? "3x3"
            : String(format: NSLocalizedString("watch_bball_period_format", value: "第 %d 节", comment: ""), store.state.currentPeriod)
    }

    private var isFollowingPhone: Bool {
        linkedSessionId != nil && linkService.isFollower
    }

    private var shotClockOptions: [Int] {
        gameMode == .threeXThree ? [12] : [14, 24]
    }

    private func clockText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var interactionsEnabled: Bool {
        !isFollowingPhone && !store.state.finished && !showMenu && selectedSide == nil && confirmation == nil
            && !showFinishedOverlay
    }

    private var basketballWinnerText: String? {
        guard store.state.leftScore != store.state.rightScore else { return nil }
        let winner = store.state.leftScore > store.state.rightScore
            ? store.state.leftName
            : store.state.rightName
        return String.localizedStringWithFormat(
            NSLocalizedString("watch_winner_format", value: "%@ 获胜", comment: ""),
            winner
        )
    }

    private func confirmBasketball(_ value: WatchScoreboardConfirmation) {
        confirmation = nil
        switch value {
        case .finish:
            manualFinishRequested = true
            store.send(.finish)
        case .reset:
            restartBasketball()
        }
    }

    private func beginBasketballFinish() {
        finishTask?.cancel()
        finishUndoAvailable = true
        showFinishedOverlay = manualFinishRequested
        finishTask = Task { @MainActor in
            if !manualFinishRequested {
                try? await Task.sleep(for: .seconds(WatchTiming.completedScoreVisibility))
                guard !Task.isCancelled else { return }
                showFinishedOverlay = true
            }
            try? await Task.sleep(for: .seconds(WatchTiming.finishedUndoCountdown))
            guard !Task.isCancelled else { return }
            finishUndoAvailable = false
            finalizeBasketball()
        }
    }

    private func beginRemoteBasketballFinishPresentation() {
        finishTask?.cancel()
        showFinishedOverlay = false
        finishUndoAvailable = false
        finishTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(WatchTiming.completedScoreVisibility))
            guard !Task.isCancelled else { return }
            showFinishedOverlay = true
        }
    }

    private func finalizeBasketball() {
        guard store.state.finished, !didPublishFinish else { return }
        resumeStore.clear()
        let recordId = "w_\(UUID().uuidString)"
        let endTime = Date()
        if linkedSessionId != nil {
            // A follower receives the authoritative finished record from the
            // phone. Only the Watch controller owns the linked result.
            guard linkService.isController else {
                didPublishFinish = true
                return
            }
            // Keep a durable Watch-side fallback even if the link disappears
            // before the terminal message is acknowledged. The linked terminal
            // message owns phone ingestion, so do not enqueue a duplicate
            // standalone-record transfer here.
            saveLocalBasketballRecord(
                id: recordId,
                endTime: endTime,
                transferToPhone: false
            )
            linkService.publishMatchFinished(
                snapshot: .basketball(store.state),
                recordId: recordId,
                winnerSide: store.state.leftScore == store.state.rightScore
                    ? nil
                    : (store.state.leftScore > store.state.rightScore ? .left : .right),
                manualEnd: manualFinishRequested,
                startTime: matchStartTime,
                endTime: endTime,
                totalScoreChanges: store.actionLog.scoreChangeCount,
                detailedActions: store.actionLog.detailedActions,
                participantNames: [store.state.leftName, store.state.rightName]
            )
        } else {
            saveLocalBasketballRecord(
                id: recordId,
                endTime: endTime,
                transferToPhone: true
            )
        }
        didPublishFinish = true
    }

    private func saveLocalBasketballRecord(
        id: String,
        endTime: Date,
        transferToPhone: Bool
    ) {
        let record = WatchBasketballRecordFactory.make(
            id: id,
            state: store.state,
            startTime: matchStartTime,
            endTime: endTime,
            actionLog: store.actionLog,
            manualEnd: manualFinishRequested
        )
        WatchRecordManager.shared.saveRecord(record, transferToPhone: transferToPhone)
    }

    private func undoFinishedBasketball() {
        guard finishUndoAvailable else { return }
        finishTask?.cancel()
        undoScoreboard()
        showFinishedOverlay = false
        finishUndoAvailable = false
        didPublishFinish = false
        manualFinishRequested = false
    }

    private func undoScoreboard() {
        store.undo {
            undoToastToken = UUID()
        }
    }

    private func restartBasketball() {
        finishTask?.cancel()
        store.send(.reset)
        showFinishedOverlay = false
        finishUndoAvailable = false
        didPublishFinish = false
        manualFinishRequested = false
        matchStartTime = Date()
        resumeStore.clear()
    }

    private func exitBasketball() {
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
        let initial = BasketballMatchEngine.initial(
            leftName: state.leftName,
            rightName: state.rightName,
            gameMode: gameMode
        )
        guard !state.finished, state != initial else {
            resumeStore.clear()
            return
        }
        let bundle = await store.resumeBundle()
        resumeStore.save(WatchResumeSession(
            startedAt: matchStartTime,
            scoreLine: "\(state.leftScore) : \(state.rightScore)",
            emoji: "🏀",
            payload: .basketball(gameMode: gameMode, bundle: bundle),
            actionLog: store.actionLog,
            link: linkService.resumeContext
        ))
    }
}
