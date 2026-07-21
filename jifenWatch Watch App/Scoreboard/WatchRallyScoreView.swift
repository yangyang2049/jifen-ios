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
        let initial = initialState ?? RallyMatchEngine.initial(
            leftName: NSLocalizedString("watch_team_red", value: "红方", comment: "Red"),
            rightName: NSLocalizedString("watch_team_blue", value: "蓝方", comment: "Blue"),
            rules: rules
        )
        let session = ScoreSession<RallyMatchState, RallyMatchEvent>(
            gameType: gameType,
            ruleFamily: .s1,
            reducerType: ScoreboardKernelRegistry.descriptor(for: gameType).reducerType,
            state: initial,
            participants: [
                .init(id: "left", name: initial.leftName, role: "team"),
                .init(id: "right", name: initial.rightName, role: "team")
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
        }
    }

    func undo() {
        Task { [weak self, core] in
            guard await core.undo(actorId: "watch"), let self else { return }
            let session = await core.snapshot()
            self.state = session.state
            try? await self.archiveRepository.save(session, source: .watchLocal)
        }
    }

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
            .gesture(boardGesture)

            VStack(spacing: 1) {
                Text("第 \(store.state.currentSet) 局")
                    .font(.caption2.weight(.bold))
                Text("\(store.state.leftSets) : \(store.state.rightSets)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Image(systemName: store.state.servingSide == .left ? "arrow.up.left" : "arrow.down.right")
                    .font(.caption2)
                    .foregroundStyle(WatchTheme.accent)
                if let serverName = store.state.doubles?.serverName {
                    Label(serverName, systemImage: "arrow.up.circle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(7)
            .background(Color.black.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if showMenu { menuOverlay }
        }
        .ignoresSafeArea()
        .disabled(isFollowingPhone)
        .onChange(of: linkService.latestSnapshot) { _, update in
            guard let linkedSessionId,
                  let update,
                  update.sessionId == linkedSessionId else { return }
            guard let state = update.snapshot.rallyState else { return }
            store.replaceDisplayedState(state)
        }
        .onDisappear {
            if !isFollowingPhone {
                store.persist()
            }
        }
    }

    private func side(_ screenSide: MatchSide, height: CGFloat) -> some View {
        let logicalSide = store.state.sidesSwapped ? screenSide.opposite : screenSide
        let isLeft = logicalSide == .left
        let name = isLeft ? store.state.leftName : store.state.rightName
        let points = isLeft ? store.state.leftPoints : store.state.rightPoints

        return VStack(spacing: 2) {
            Text(name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text("\(points)")
                .font(.system(size: 62, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(store.state.finished ? "比赛结束" : "点按得分")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background(isLeft ? Color(hex: 0xE53935) : Color(hex: 0x1E88E5))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isFollowingPhone else { return }
            store.score(logicalSide)
        }
    }

    private var boardGesture: some Gesture {
        DragGesture(minimumDistance: 25, coordinateSpace: .local)
            .onEnded { value in
                guard !isFollowingPhone else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                if dx > 45, abs(dy) < 45 {
                    dismiss()
                } else if dy > 35 {
                    store.undo()
                } else if dy < -35 {
                    showMenu = true
                }
            }
    }

    private var menuOverlay: some View {
        VStack(spacing: 10) {
            Button("交换两侧") { store.send(.exchangeSides); showMenu = false }
            Button("结束比赛") { store.send(.finish); showMenu = false }
            Button("重新开始", role: .destructive) { store.send(.reset); showMenu = false }
            Button("关闭") { showMenu = false }
        }
        .buttonStyle(.borderedProminent)
        .padding()
        .background(Color.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var isFollowingPhone: Bool {
        linkedSessionId != nil
    }
}
