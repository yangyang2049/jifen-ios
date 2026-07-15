import SwiftUI
import ScoreCore

struct BasketballScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PhoneWatchLinkService.self) private var watchLinkService

    var showBackButton: Bool = true
    var onNavigationBack: (() -> Void)? = nil
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil

    @State private var store: BasketballSessionStore
    @State private var watchSessionId: UUID?

    init(
        showBackButton: Bool = true,
        onNavigationBack: (() -> Void)? = nil,
        initialSetup: SportsSetupResult? = nil,
        initialRecordId: String? = nil,
        onSetupConsumed: (() -> Void)? = nil
    ) {
        self.showBackButton = showBackButton
        self.onNavigationBack = onNavigationBack
        self.initialSetup = initialSetup
        self.initialRecordId = initialRecordId
        self.onSetupConsumed = onSetupConsumed

        let leftName = initialSetup?.team1Name.isEmpty == false
            ? initialSetup!.team1Name
            : NSLocalizedString("team_home", value: "主队", comment: "Home team")
        let rightName = initialSetup?.team2Name.isEmpty == false
            ? initialSetup!.team2Name
            : NSLocalizedString("team_away", value: "客队", comment: "Away team")
        let gameMode: BasketballGameMode = initialSetup?.basketballMode == "three_x_three" ? .threeXThree : .fiveVFive
        _store = State(initialValue: BasketballSessionStore(leftName: leftName, rightName: rightName, gameMode: gameMode))
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                BasketballTeamPanel(
                    name: displayName(for: .left),
                    score: displayScore(for: .left),
                    fouls: displayFouls(for: .left),
                    timeouts: displayTimeouts(for: .left),
                    color: Color(red: 0.85, green: 0.22, blue: 0.2),
                    points: BasketballMatchEngine.scoringButtons(store.state),
                    onScore: { store.send(.addPoints(side: logicalSide(forScreen: .left), points: $0)) },
                    onFoul: { store.send(.addFoul(side: logicalSide(forScreen: .left))) },
                    onTimeout: { store.send(.useTimeout(side: logicalSide(forScreen: .left))) }
                )
                .frame(width: proxy.size.width * 0.37)

                BasketballCenterPanel(
                    state: store.state,
                    onBack: back,
                    showsBackButton: showBackButton,
                    onToggleClock: { store.send(.setClockRunning(!store.state.gameRunning)) },
                    onResetGameClock: { store.send(.resetGameClock) },
                    onResetShotClock: { store.send(.resetShotClock(seconds: $0)) },
                    onAdvancePeriod: { store.send(.advanceToNextPeriod) },
                    onUndo: store.undo,
                    onFinish: { store.send(.finish) },
                    onSwap: { store.send(.exchangeSides) },
                    onLaunchOnWatch: { watchSessionId = watchLinkService.startOnWatch(state: store.state) }
                )
                .frame(width: proxy.size.width * 0.26)

                BasketballTeamPanel(
                    name: displayName(for: .right),
                    score: displayScore(for: .right),
                    fouls: displayFouls(for: .right),
                    timeouts: displayTimeouts(for: .right),
                    color: Color(red: 0.13, green: 0.37, blue: 0.82),
                    points: BasketballMatchEngine.scoringButtons(store.state),
                    onScore: { store.send(.addPoints(side: logicalSide(forScreen: .right), points: $0)) },
                    onFoul: { store.send(.addFoul(side: logicalSide(forScreen: .right))) },
                    onTimeout: { store.send(.useTimeout(side: logicalSide(forScreen: .right))) }
                )
                .frame(width: proxy.size.width * 0.37)
            }
            .background(Theme.backgroundColor)
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .onAppear {
            onSetupConsumed?()
            store.startClock()
        }
        .onChange(of: store.state) { _, state in
            guard let watchSessionId else { return }
            watchLinkService.syncWatch(sessionId: watchSessionId, state: state)
        }
        .onDisappear {
            if let watchSessionId {
                watchLinkService.endWatchSession(watchSessionId)
            }
            store.stopClock()
            store.persistSnapshot()
        }
    }

    private func displayName(for side: MatchSide) -> String {
        logicalSide(forScreen: side) == .left ? store.state.leftName : store.state.rightName
    }

    private func displayScore(for side: MatchSide) -> Int {
        logicalSide(forScreen: side) == .left ? store.state.leftScore : store.state.rightScore
    }

    private func displayFouls(for side: MatchSide) -> Int {
        logicalSide(forScreen: side) == .left ? store.state.leftFouls : store.state.rightFouls
    }

    private func displayTimeouts(for side: MatchSide) -> Int {
        logicalSide(forScreen: side) == .left ? store.state.leftTimeouts : store.state.rightTimeouts
    }

    private func logicalSide(forScreen side: MatchSide) -> MatchSide {
        store.state.sidesSwapped ? side.opposite : side
    }

    private func back() {
        if let onNavigationBack {
            onNavigationBack()
        } else {
            dismiss()
        }
    }
}

private struct BasketballTeamPanel: View {
    let name: String
    let score: Int
    let fouls: Int
    let timeouts: Int
    let color: Color
    let points: [Int]
    let onScore: (Int) -> Void
    let onFoul: () -> Void
    let onTimeout: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(name)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(score)")
                .font(.system(size: 112, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            HStack(spacing: 8) {
                ForEach(points, id: \.self) { point in
                    Button("+\(point)") { onScore(point) }
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.22))
                }
            }
            HStack(spacing: 12) {
                Button("犯规 \(fouls)") { onFoul() }
                Button("暂停 \(timeouts)") { onTimeout() }
            }
            .font(.caption.weight(.medium))
            .buttonStyle(.bordered)
            .tint(.white.opacity(0.75))
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color)
    }
}

private struct BasketballCenterPanel: View {
    let state: BasketballMatchState
    let onBack: () -> Void
    let showsBackButton: Bool
    let onToggleClock: () -> Void
    let onResetGameClock: () -> Void
    let onResetShotClock: (Int) -> Void
    let onAdvancePeriod: () -> Void
    let onUndo: () -> Void
    let onFinish: () -> Void
    let onSwap: () -> Void
    let onLaunchOnWatch: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                if showsBackButton {
                    Button(action: onBack) { Image(systemName: "chevron.left") }
                }
                Spacer()
                Text(periodTitle)
                    .font(.headline.monospacedDigit())
                Spacer()
                Button(action: onLaunchOnWatch) {
                    Image(systemName: "applewatch")
                }
                .help("在手表打开计分板")
                Button(action: onSwap) { Image(systemName: "arrow.left.arrow.right") }
            }
            .buttonStyle(.borderless)

            Button(action: onResetGameClock) {
                Text(clockText(state.gameTimeSeconds))
                    .font(.system(size: 38, weight: .bold, design: .monospaced))
                    .monospacedDigit()
            }
            .buttonStyle(.plain)

            Text("进攻 \(state.shotTimeSeconds)")
                .font(.title3.monospacedDigit())
                .foregroundStyle(Theme.accentColor)

            HStack(spacing: 6) {
                ForEach(shotOptions, id: \.self) { seconds in
                    Button("\(seconds)") { onResetShotClock(seconds) }
                        .buttonStyle(.bordered)
                }
            }

            Button(action: onToggleClock) {
                Image(systemName: state.gameRunning ? "pause.fill" : "play.fill")
                    .frame(width: 42, height: 28)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accentColor)

            if state.canAdvancePeriod {
                Button("下一节", action: onAdvancePeriod)
                    .buttonStyle(.bordered)
            }

            Spacer(minLength: 0)
            HStack(spacing: 14) {
                Button(action: onUndo) { Image(systemName: "arrow.uturn.backward") }
                Button(action: onFinish) { Image(systemName: "flag.checkered") }
            }
            .buttonStyle(.borderless)
            .font(.title3)
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(12)
        .frame(maxHeight: .infinity)
        .background(Theme.cardBackground)
    }

    private var periodTitle: String {
        if state.isOvertime { return "加时" }
        return state.gameMode == .threeXThree ? "3x3" : "第 \(state.currentPeriod) 节"
    }

    private var shotOptions: [Int] {
        state.gameMode == .threeXThree ? [12] : [14, 24]
    }

    private func clockText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct BasketballScoreboardView_Previews: PreviewProvider {
    static var previews: some View {
        BasketballScoreboardView()
            .previewInterfaceOrientation(.landscapeLeft)
    }
}
