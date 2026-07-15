import Observation
import PersistenceCore
import ScoreCore
import SessionCore
import SwiftUI

@MainActor
@Observable
private final class WatchBasketballSessionStore {
    private let core: ScoreSessionCore<BasketballMatchReducer>
    private let snapshotStore: AtomicJSONFileStore<ScoreSession<BasketballMatchState, BasketballMatchEvent>>
    private var clockTask: Task<Void, Never>?

    private(set) var state: BasketballMatchState

    init(gameMode: BasketballGameMode) {
        let initial = BasketballMatchEngine.initial(
            leftName: NSLocalizedString("watch_team_red", value: "红方", comment: "Red"),
            rightName: NSLocalizedString("watch_team_blue", value: "蓝方", comment: "Blue"),
            gameMode: gameMode
        )
        let session = ScoreSession<BasketballMatchState, BasketballMatchEvent>(
            gameType: gameMode == .threeXThree ? .threeBasketball : .basketball,
            ruleFamily: .s2,
            reducerType: "basketball/v1",
            state: initial,
            participants: [
                .init(id: "left", name: initial.leftName, role: "team"),
                .init(id: "right", name: initial.rightName, role: "team")
            ]
        )
        self.core = ScoreSessionCore(
            seedSession: session,
            reducer: BasketballMatchReducer(),
            shouldFinish: { _, state in state.finished }
        )
        self.snapshotStore = AtomicJSONFileStore(fileURL: Self.snapshotURL(for: session.sessionId))
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

    func stopClockAndPersist() {
        clockTask?.cancel()
        clockTask = nil
        Task { [core, snapshotStore] in
            let session = await core.snapshot()
            try? await snapshotStore.save(session)
        }
    }

    private static func snapshotURL(for sessionId: UUID) -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jifen-v2/watch-sessions", isDirectory: true)
        return directory.appendingPathComponent("\(sessionId.uuidString).json")
    }
}

struct WatchBasketballScoreView: View {
    @Environment(\.dismiss) private var dismiss

    let gameMode: BasketballGameMode
    @State private var store: WatchBasketballSessionStore
    @State private var selectedSide: MatchSide?
    @State private var showMenu = false

    init(gameMode: BasketballGameMode) {
        self.gameMode = gameMode
        _store = State(initialValue: WatchBasketballSessionStore(gameMode: gameMode))
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
                menuOverlay
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
        .onAppear { store.startClock() }
        .onDisappear { store.stopClockAndPersist() }
    }

    private func side(_ screenSide: MatchSide, height: CGFloat) -> some View {
        let logicalSide = store.state.sidesSwapped ? screenSide.opposite : screenSide
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
            Text("犯规 \(fouls)  暂停 \(timeouts)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background(isLeft ? Color(hex: 0xE53935) : Color(hex: 0x1E88E5))
        .contentShape(Rectangle())
        .onTapGesture { selectedSide = logicalSide }
    }

    private var boardGesture: some Gesture {
        DragGesture(minimumDistance: 25, coordinateSpace: .local)
            .onEnded { value in
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
            Button("犯规 +1") {
                store.send(.addFoul(side: side))
                selectedSide = nil
            }
            Button("暂停") {
                store.send(.useTimeout(side: side))
                selectedSide = nil
            }
            Button("取消", role: .cancel) { selectedSide = nil }
        }
        .padding()
    }

    private var menuOverlay: some View {
        VStack(spacing: 10) {
            HStack {
                ForEach(shotClockOptions, id: \.self) { seconds in
                    Button("\(seconds)") { store.send(.resetShotClock(seconds: seconds)) }
                }
            }
            Button("交换两侧") { store.send(.exchangeSides) }
            Button("结束比赛") { store.send(.finish) }
            Button("关闭") { showMenu = false }
        }
        .buttonStyle(.borderedProminent)
        .padding()
        .background(Color.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var periodTitle: String {
        if store.state.isOvertime { return "加时" }
        return gameMode == .threeXThree ? "3x3" : "第 \(store.state.currentPeriod) 节"
    }

    private var shotClockOptions: [Int] {
        gameMode == .threeXThree ? [12] : [14, 24]
    }

    private func clockText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
