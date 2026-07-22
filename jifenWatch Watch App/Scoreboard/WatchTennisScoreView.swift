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
        let initial = initialState ?? TennisMatchState(
            leftName: NSLocalizedString("watch_team_red", value: "红方", comment: ""),
            rightName: NSLocalizedString("watch_team_blue", value: "蓝方", comment: ""),
            rules: rules
        )
        let session = ScoreSession<TennisMatchState, TennisMatchEvent>(
            gameType: gameType,
            ruleFamily: .s1,
            reducerType: ScoreboardKernelRegistry.descriptor(for: gameType).reducerType,
            state: initial,
            participants: [
                .init(id: "left", name: initial.leftName, role: "team"),
                .init(id: "right", name: initial.rightName, role: "team")
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

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let height = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
                VStack(spacing: 0) {
                    side(.left, height: height / 2)
                    side(.right, height: height / 2)
                }
                .offset(x: -proxy.safeAreaInsets.leading, y: -proxy.safeAreaInsets.top)
            }
            .ignoresSafeArea()
            .gesture(boardGesture)

            VStack(spacing: 2) {
                if store.state.rules.setScoringMode == .tiebreakOnly {
                    Text(store.state.rules.tieBreakPoints == 10 ? "抢十" : "抢七")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                } else {
                    Text("\(store.state.leftSets)-\(store.state.rightSets)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("\(store.state.leftGames):\(store.state.rightGames)")
                        .font(.caption2)
                }
                if linkedSessionId != nil {
                    Text(linkService.isController ? "手表主控" : "跟随手机")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(WatchTheme.accent)
                }
            }
            .padding(8)
            .background(Color.black.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if showMenu {
                VStack(spacing: 8) {
                    Button("交换两侧") { store.send(.exchangeSides); showMenu = false }
                    Button("结束比赛") { store.send(.finish); showMenu = false }
                    Button("重置", role: .destructive) { store.send(.reset); showMenu = false }
                    Button("关闭") { showMenu = false }
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .background(Color.black.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .disabled(scoringLocked)
        .onAppear {
            store.onStateChanged = { [linkService] state in
                guard linkedSessionId != nil, linkService.isController else { return }
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
                        manualEnd: false
                    )
                }
            }
        }
        .onChange(of: linkService.latestSnapshot) { _, update in
            guard let linkedSessionId, let update, update.sessionId == linkedSessionId,
                  let state = update.snapshot.tennisState else { return }
            store.replaceDisplayedState(state)
        }
    }

    private func side(_ screenSide: MatchSide, height: CGFloat) -> some View {
        let logical = store.state.sidesSwapped ? screenSide.opposite : screenSide
        let isLeft = logical == .left
        return VStack {
            Text(isLeft ? store.state.leftName : store.state.rightName)
                .font(.caption.weight(.semibold))
            Text(store.state.scoreDisplay(for: logical))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background(isLeft ? Color(hex: 0xE53935) : Color(hex: 0x1E88E5))
        .onTapGesture {
            guard !scoringLocked else { return }
            store.score(logical)
        }
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
}
