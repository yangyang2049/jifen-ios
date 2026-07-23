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
    private let core: ScoreSessionCore<RallyMatchReducer>
    private let archiveRepository: SessionArchiveRepository

    private(set) var state: RallyMatchState

    init(gameType: GameType, rules: RallyRuleSet, initialState: RallyMatchState? = nil) {
        let defaults = WatchDefaultTeamNames.resolve()
        let initial = initialState ?? RallyMatchEngine.initial(
            leftName: defaults.left,
            rightName: defaults.right,
            rules: rules
        )
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
        core = ScoreSessionCore(seedSession: session, reducer: RallyMatchReducer(), shouldFinish: { _, state in state.finished })
        archiveRepository = SessionArchiveRepository()
        state = initial
    }

    func score(_ side: MatchSide) {
        send(.pointWon(side))
    }

    func send(_ intent: RallyMatchIntent) {
        Task { [weak self, core] in
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            guard case .accepted(let session, _) = await core.dispatch(actorId: "watch", intent: intent, at: now), let self else { return }
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

    var onStateChanged: ((RallyMatchState) -> Void)?

    func persist() {
        Task { [core, archiveRepository] in
            let session = await core.snapshot()
            try? await archiveRepository.save(session, source: .watchLocal)
        }
    }

    func replaceDisplayedState(_ state: RallyMatchState) {
        self.state = state
    }
}

struct WatchRallyScoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchLinkService.self) private var linkService

    let gameType: GameType
    let rules: RallyRuleSet
    let linkedSessionId: UUID?
    @State private var store: WatchRallySessionStore
    @State private var showMenu = false
    @State private var matchStartTime = Date()
    @State private var didTransferFinishedRecord = false
    @State private var scoreboardLayout: String = "horizontal"
    @State private var setBreakToast: String?
    @State private var lastObservedSets: (Int, Int) = (0, 0)

    init(
        gameType: GameType,
        rules: RallyRuleSet,
        initialState: RallyMatchState? = nil,
        linkedSessionId: UUID? = nil
    ) {
        self.gameType = gameType
        self.rules = rules
        self.linkedSessionId = linkedSessionId
        _store = State(initialValue: WatchRallySessionStore(gameType: gameType, rules: rules, initialState: initialState))
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
                    linkService.publishSnapshot(.rally(state))
                    if state.finished {
                        let winner: MatchSide? = state.leftSets == state.rightSets
                            ? nil
                            : (state.leftSets > state.rightSets ? .left : .right)
                        linkService.publishMatchFinished(
                            snapshot: .rally(state),
                            recordId: "w_\(UUID().uuidString)",
                            winnerSide: winner,
                            manualEnd: false,
                            startTime: matchStartTime,
                            endTime: Date(),
                            totalScoreChanges: max(1, state.leftPoints + state.rightPoints)
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
            guard let linkedSessionId,
                  let update,
                  update.sessionId == linkedSessionId else { return }
            guard let state = update.snapshot.rallyState else { return }
            store.replaceDisplayedState(state)
        }
        .onDisappear {
            if !scoringLocked {
                store.persist()
            }
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
        let layout = TeamScreenLayout(sidesSwapped: store.state.sidesSwapped)
        let logicalSide = layout.engineSide(onScreen: screenSide)
        let isLeftTeam = logicalSide == .left
        let name = isLeftTeam ? store.state.leftName : store.state.rightName
        let points = isLeftTeam ? store.state.leftPoints : store.state.rightPoints
        let sets = isLeftTeam ? store.state.leftSets : store.state.rightSets
        let isServing = store.state.servingSide == logicalSide
        let showSets = store.state.leftSets + store.state.rightSets > 0 || store.state.currentSet > 1
        let mainScoreFont: CGFloat = isHorizontal ? 64 : 62

        return ZStack {
            // Main point score (Harmony-style: no helper caption).
            Text("\(points)")
                .font(.system(size: mainScoreFont, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            // Team name
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.28))
                .clipShape(Capsule())
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
                servingIndicator(screenSide: screenSide, isLeftTeam: isLeftTeam)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(isLeftTeam ? Color(hex: 0xE53935) : Color(hex: 0x1E88E5))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !scoringLocked else { return }
            store.score(logicalSide)
        }
    }

    @ViewBuilder
    private func servingIndicator(screenSide: MatchSide, isLeftTeam: Bool) -> some View {
        let direction: WatchServerIndicatorDirection = {
            if isHorizontal {
                return screenSide == .left ? .right : .left
            }
            return isLeftTeam ? .bottom : .top
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
        DragGesture(minimumDistance: 25, coordinateSpace: .local)
            .onEnded { value in
                guard !scoringLocked else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                if dx > 45, abs(dy) < 45 {
                    if linkedSessionId != nil {
                        linkService.leaveSession()
                    }
                    dismiss()
                } else if dy > 35 {
                    store.undo()
                } else if dy < -35 {
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
                    menuGridButton(
                        title: NSLocalizedString("menu_undo", value: "撤销", comment: ""),
                        systemImage: "arrow.uturn.backward",
                        background: WatchTheme.card
                    ) {
                        store.undo()
                        showMenu = false
                    }

                    menuGridButton(
                        title: NSLocalizedString("watch_menu_end_match", value: "结束比赛", comment: ""),
                        systemImage: "flag.checkered",
                        background: WatchTheme.dangerRed
                    ) {
                        store.send(.finish)
                        showMenu = false
                    }

                    menuGridButton(
                        title: NSLocalizedString("watch_menu_restart", value: "重新开始", comment: ""),
                        systemImage: "arrow.counterclockwise",
                        background: WatchTheme.card
                    ) {
                        store.send(.reset)
                        showMenu = false
                    }
                }

                Button {
                    showMenu = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: WatchLayout.isCompactScreen ? 20 : 24))
                        .foregroundStyle(WatchTheme.secondaryText)
                        .frame(
                            width: WatchLayout.isCompactScreen ? 32 : 38,
                            height: WatchLayout.isCompactScreen ? 32 : 38
                        )
                }
                .buttonStyle(.plain)
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

    private func menuGridButton(
        title: String,
        systemImage: String,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(
                        size: WatchLayout.isCompactScreen ? 18 : 21,
                        weight: .medium
                    ))
                Text(title)
                    .font(.system(
                        size: WatchLayout.isCompactScreen ? 10 : 11,
                        weight: .medium
                    ))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .frame(height: WatchLayout.isCompactScreen ? 48 : 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(background)
        .clipShape(RoundedRectangle(
            cornerRadius: WatchLayout.isCompactScreen ? 10 : 12,
            style: .continuous
        ))
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
            actions: [],
            totalScoreChanges: max(1, state.leftPoints + state.rightPoints),
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
