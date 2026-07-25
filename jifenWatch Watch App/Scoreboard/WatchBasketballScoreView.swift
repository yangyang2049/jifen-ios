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

    init(
        gameMode: BasketballGameMode,
        initialState: BasketballMatchState? = nil,
        resumeBundle: ResumeBundle? = nil
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
    }

    func send(_ intent: BasketballMatchIntent, recordsUndo: Bool = true) {
        Task { [weak self, core] in
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            let result = if recordsUndo {
                await core.dispatch(actorId: "watch", intent: intent, at: now)
            } else {
                await core.dispatchNonUndoable(actorId: "watch", intent: intent, at: now)
            }
            guard case .accepted(let session, _) = result, let self else { return }
            self.state = session.state
        }
    }

    func undo() {
        Task { [weak self, core] in
            guard await core.undo(actorId: "watch"), let self else { return }
            self.state = await core.snapshot().state
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

    init(
        gameMode: BasketballGameMode,
        initialState: BasketballMatchState? = nil,
        linkedSessionId: UUID? = nil,
        resumeBundle: ScoreSessionResumeBundle<
            BasketballMatchState,
            BasketballMatchEvent,
            BasketballMatchIntent
        >? = nil,
        resumedStartTime: Date? = nil
    ) {
        self.gameMode = gameMode
        self.linkedSessionId = linkedSessionId
        _store = State(initialValue: WatchBasketballSessionStore(
            gameMode: gameMode,
            initialState: initialState,
            resumeBundle: resumeBundle
        ))
        _matchStartTime = State(initialValue: resumedStartTime ?? Date())
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
            if showFinishedOverlay {
                WatchFinishedOverlay(
                    title: NSLocalizedString("watch_match_finished", value: "比赛结束", comment: ""),
                    scoreText: "\(store.state.leftScore) : \(store.state.rightScore)",
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
        .sheet(
            isPresented: Binding(
                get: { selectedSide != nil },
                set: { isPresented in
                    if !isPresented {
                        selectedSide = nil
                    }
                }
            )
        ) {
            if let selectedSide {
                scoreSheet(for: selectedSide)
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
            store.replaceDisplayedState(state)
            if state.finished {
                showFinishedOverlay = true
                finishUndoAvailable = false
            }
        }
        .onChange(of: store.state) { oldState, newState in
            if linkedSessionId != nil, linkService.isController {
                linkService.publishSnapshot(.basketball(newState))
            }
            if !oldState.finished, newState.finished {
                beginBasketballFinish()
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
            onUndo: { store.undo() },
            onExit: exitBasketball
        )
    }

    private func side(_ screenSide: MatchSide, height: CGFloat) -> some View {
        let logicalSide = TeamScreenLayout(sidesSwapped: store.state.sidesSwapped).engineSide(onScreen: screenSide)
        let isLeft = logicalSide == .left
        let score = isLeft ? store.state.leftScore : store.state.rightScore
        let fouls = isLeft ? store.state.leftFouls : store.state.rightFouls
        let timeouts = isLeft ? store.state.leftTimeouts : store.state.rightTimeouts
        let name = isLeft ? store.state.leftName : store.state.rightName

        return VStack(spacing: 2) {
            Text(name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text("\(score)")
                .font(.system(size: 58, weight: .bold, design: .rounded))
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

    private func scoreSheet(for side: MatchSide) -> some View {
        VStack(spacing: 10) {
            Text(side == .left ? store.state.leftName : store.state.rightName)
                .font(.headline)
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
            Button(NSLocalizedString("watch_bball_cancel", value: "取消", comment: ""), role: .cancel) { selectedSide = nil }
        }
        .padding()
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
        !isFollowingPhone && !showMenu && selectedSide == nil && confirmation == nil
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
        showFinishedOverlay = true
        finishUndoAvailable = true
        finishTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                finishUndoAvailable = false
                finalizeBasketball()
            }
        }
    }

    private func finalizeBasketball() {
        guard store.state.finished, !didPublishFinish else { return }
        resumeStore.clear()
        if linkedSessionId != nil, linkService.isController {
            linkService.publishMatchFinished(
                snapshot: .basketball(store.state),
                recordId: "w_\(UUID().uuidString)",
                winnerSide: store.state.leftScore == store.state.rightScore
                    ? nil
                    : (store.state.leftScore > store.state.rightScore ? .left : .right),
                manualEnd: manualFinishRequested,
                startTime: matchStartTime,
                endTime: Date(),
                totalScoreChanges: max(1, store.state.leftScore + store.state.rightScore)
            )
        }
        didPublishFinish = true
    }

    private func undoFinishedBasketball() {
        guard finishUndoAvailable else { return }
        finishTask?.cancel()
        store.undo()
        showFinishedOverlay = false
        finishUndoAvailable = false
        didPublishFinish = false
        manualFinishRequested = false
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
            link: linkService.resumeContext
        ))
    }
}
