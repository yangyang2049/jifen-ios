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
    private let core: ScoreSessionCore<TennisMatchReducer>
    private let archiveRepository = SessionArchiveRepository()
    private(set) var state: TennisMatchState
    var onStateChanged: ((TennisMatchState) -> Void)?

    init(gameType: GameType, rules: TennisRuleSet, initialState: TennisMatchState? = nil) {
        let defaults = WatchDefaultTeamNames.resolve()
        let initial = initialState ?? TennisMatchState(
            leftName: defaults.left,
            rightName: defaults.right,
            rules: rules
        )
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
        core = ScoreSessionCore(seedSession: session, reducer: TennisMatchReducer(), shouldFinish: { _, state in state.finished })
        state = initial
    }

    func score(_ side: MatchSide) {
        send(.pointWon(side))
    }

    func send(_ intent: TennisMatchIntent) {
        Task { [weak self, core] in
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            guard case .accepted(let session, _) = await core.dispatch(actorId: "watch", intent: intent, at: now),
                  let self else { return }
            self.state = session.state
            try? await self.archiveRepository.save(session, source: .watchLocal)
            self.onStateChanged?(session.state)
        }
    }

    func undo() {
        Task { [weak self, core] in
            guard await core.undo(actorId: "watch"), let self else { return }
            let session = await core.snapshot()
            self.state = session.state
            try? await self.archiveRepository.save(session, source: .watchLocal)
            self.onStateChanged?(session.state)
        }
    }

    func replaceDisplayedState(_ state: TennisMatchState) {
        self.state = state
    }
}

struct WatchTennisScoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchLinkService.self) private var linkService

    let maxSets: Int
    let linkedSessionId: UUID?
    let isDoubles: Bool
    @State private var store: WatchTennisSessionStore
    @State private var showMenu = false
    @State private var matchStartTime = Date()
    @State private var didTransferFinishedRecord = false
    @State private var scoreboardLayout: String = "horizontal"
    @State private var setBreakToast: String?
    @State private var lastObservedSets: (Int, Int) = (0, 0)

    init(
        maxSets: Int,
        initialState: TennisMatchState? = nil,
        linkedSessionId: UUID? = nil,
        isDoubles: Bool = false
    ) {
        self.maxSets = maxSets
        self.linkedSessionId = linkedSessionId
        self.isDoubles = isDoubles
        let rules = TennisRuleSet(maxSets: maxSets)
        let gameType: GameType = isDoubles ? .tennisDoubles : .tennis
        _store = State(initialValue: WatchTennisSessionStore(
            gameType: gameType,
            rules: initialState?.rules ?? rules,
            initialState: initialState
        ))
    }

    private var scoringLocked: Bool {
        linkedSessionId != nil && linkService.isFollower
    }

    private var isHorizontal: Bool { scoreboardLayout == "horizontal" }

    var body: some View {
        ZStack {
            mainBoard
            if showMenu { menuOverlay }
            if let setBreakToast {
                Text(setBreakToast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.82))
                    .clipShape(Capsule())
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .disabled(scoringLocked)
        .onAppear {
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
            lastObservedSets = (store.state.leftSets, store.state.rightSets)
            matchStartTime = Date()
            store.onStateChanged = { [linkService] state in
                if linkedSessionId != nil {
                    guard linkService.isController else { return }
                    linkService.publishSnapshot(.tennis(state))
                    if state.finished {
                        let leftWinnerScore = state.rules.setScoringMode == .tiebreakOnly
                            ? state.leftPoints
                            : state.leftSets
                        let rightWinnerScore = state.rules.setScoringMode == .tiebreakOnly
                            ? state.rightPoints
                            : state.rightSets
                        let winner: MatchSide? = leftWinnerScore == rightWinnerScore
                            ? nil
                            : (leftWinnerScore > rightWinnerScore ? .left : .right)
                        linkService.publishMatchFinished(
                            snapshot: .tennis(state),
                            recordId: "w_\(UUID().uuidString)",
                            winnerSide: winner,
                            manualEnd: false,
                            startTime: matchStartTime,
                            endTime: Date(),
                            totalScoreChanges: max(1, state.leftPoints + state.rightPoints + state.leftGames + state.rightGames)
                        )
                    }
                    return
                }
                if state.finished {
                    transferLocalFinishedRecordIfNeeded(state)
                }
            }
        }
        .onChange(of: store.state.leftSets) { _, _ in handlePossibleSetBreak() }
        .onChange(of: store.state.rightSets) { _, _ in handlePossibleSetBreak() }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
        }
        .onChange(of: linkService.latestSnapshot) { _, update in
            guard let linkedSessionId, let update, update.sessionId == linkedSessionId,
                  let state = update.snapshot.tennisState else { return }
            store.replaceDisplayedState(state)
        }
    }

    private var mainBoard: some View {
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
        .gesture(boardGesture)
    }

    private func side(_ screenSide: MatchSide, size: CGSize) -> some View {
        let logical = TeamScreenLayout(sidesSwapped: store.state.sidesSwapped).engineSide(onScreen: screenSide)
        let isLeftTeam = logical == .left
        let name = isLeftTeam
            ? store.state.doublesTeamDisplayName(for: .left)
            : store.state.doublesTeamDisplayName(for: .right)
        let pointText = store.state.scoreDisplay(for: logical)
        let sets = isLeftTeam ? store.state.leftSets : store.state.rightSets
        let games = isLeftTeam ? store.state.leftGames : store.state.rightGames
        let isServing = store.state.servingSide == logical
        let showMeta = store.state.rules.setScoringMode != .tiebreakOnly
        let mainScoreFont: CGFloat = isHorizontal ? 48 : 52

        return ZStack {
            Text(pointText)
                .font(.system(size: mainScoreFont, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.28))
                .clipShape(Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, isHorizontal ? 28 : 8)

            if showMeta {
                VStack(spacing: 2) {
                    Text("\(sets)")
                        .font(.system(size: 18, weight: .semibold))
                    Text("\(games)")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.7))
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: isHorizontal ? .bottom : .leading
                )
                .padding(.bottom, isHorizontal ? 24 : 0)
                .padding(.leading, isHorizontal ? 0 : 14)
            }

            if isServing {
                servingIndicator(screenSide: screenSide)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(isLeftTeam ? Color(hex: 0xE53935) : Color(hex: 0x1E88E5))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !scoringLocked else { return }
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
        WatchServerIndicator(direction: direction, size: 14, color: WatchTheme.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(.top, alignment == .top ? 0 : 8)
            .padding(.bottom, alignment == .bottom ? 0 : 8)
            .padding(.leading, alignment == .leading ? 0 : 8)
            .padding(.trailing, alignment == .trailing ? 0 : 8)
            .allowsHitTesting(false)
    }

    private var boardGesture: some Gesture {
        DragGesture(minimumDistance: 25)
            .onEnded { value in
                guard !scoringLocked else { return }
                if value.translation.width > 45 {
                    if linkedSessionId != nil { linkService.leaveSession() }
                    dismiss()
                } else if value.translation.height > 35 {
                    store.undo()
                } else if value.translation.height < -35 {
                    showMenu = true
                }
            }
    }

    private var menuOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { showMenu = false }

            VStack(spacing: WatchLayout.isCompactScreen ? 6 : 8) {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: WatchLayout.isCompactScreen ? 6 : 8
                ) {
                    WatchMenuGridButton(
                        title: NSLocalizedString("menu_undo", value: "撤销", comment: ""),
                        systemImage: "arrow.uturn.backward"
                    ) {
                        store.undo()
                        showMenu = false
                    }
                    WatchMenuGridButton(
                        title: NSLocalizedString("watch_menu_end_match", value: "结束比赛", comment: ""),
                        systemImage: "flag.checkered",
                        background: WatchTheme.dangerRed
                    ) {
                        store.send(.finish)
                        showMenu = false
                    }
                    WatchMenuGridButton(
                        title: NSLocalizedString("watch_menu_restart", value: "重新开始", comment: ""),
                        systemImage: "arrow.counterclockwise"
                    ) {
                        store.send(.reset)
                        showMenu = false
                    }
                }

                WatchMenuCloseButton {
                    showMenu = false
                }
            }
            .padding(WatchLayout.isCompactScreen ? 8 : 12)
            .background(WatchTheme.overlayCard)
            .clipShape(RoundedRectangle(
                cornerRadius: WatchLayout.isCompactScreen ? 12 : 16,
                style: .continuous
            ))
            .padding(.horizontal, WatchLayout.isCompactScreen ? 12 : 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func normalizedLayout(_ raw: String) -> String {
        raw == "vertical" ? "vertical" : "horizontal"
    }

    private func handlePossibleSetBreak() {
        let current = (store.state.leftSets, store.state.rightSets)
        defer { lastObservedSets = current }
        guard WatchPreferences.shared.setBreakEnabled else { return }
        guard !store.state.finished else { return }
        guard current != lastObservedSets else { return }
        guard current.0 + current.1 > lastObservedSets.0 + lastObservedSets.1 else { return }
        setBreakToast = NSLocalizedString("watch_set_break_toast", value: "局间休息", comment: "")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if setBreakToast != nil { setBreakToast = nil }
        }
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
            actions: [],
            totalScoreChanges: max(1, state.leftPoints + state.rightPoints),
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
