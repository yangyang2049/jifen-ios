import ScoreCore
import SwiftUI

struct RallyScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PhoneWatchLinkService.self) private var watchLinkService

    let gameType: ScoreCore.GameType
    let showBackButton: Bool
    let onNavigationBack: (() -> Void)?
    let onPresented: () -> Void
    @State private var store: RallySessionStore
    @State private var watchSessionId: UUID?

    init(
        leftName: String,
        rightName: String,
        gameType: ScoreCore.GameType,
        rules: RallyRuleSet,
        participants: [SessionParticipant]? = nil,
        showBackButton: Bool = true,
        onNavigationBack: (() -> Void)? = nil,
        onPresented: @escaping () -> Void = {}
    ) {
        self.gameType = gameType
        self.showBackButton = showBackButton
        self.onNavigationBack = onNavigationBack
        self.onPresented = onPresented
        _store = State(initialValue: RallySessionStore(
            leftName: leftName,
            rightName: rightName,
            gameType: gameType,
            rules: rules,
            participants: participants
        ))
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                teamPanel(screenSide: .left, color: Color(red: 0.85, green: 0.22, blue: 0.2))
                    .frame(width: proxy.size.width * 0.4)
                centerPanel
                    .frame(width: proxy.size.width * 0.2)
                teamPanel(screenSide: .right, color: Color(red: 0.13, green: 0.37, blue: 0.82))
                    .frame(width: proxy.size.width * 0.4)
            }
            .background(Theme.backgroundColor)
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .onAppear(perform: onPresented)
        .onChange(of: store.state) { _, state in
            guard let watchSessionId else { return }
            watchLinkService.syncWatch(sessionId: watchSessionId, gameType: gameType, state: state)
        }
        .onDisappear {
            if let watchSessionId {
                watchLinkService.endWatchSession(watchSessionId)
            }
            store.persistSnapshot()
        }
    }

    private func teamPanel(screenSide: MatchSide, color: Color) -> some View {
        let side = logicalSide(forScreen: screenSide)
        let isLeft = side == .left
        let name = isLeft ? store.state.leftName : store.state.rightName
        let score = isLeft ? store.state.leftPoints : store.state.rightPoints
        return VStack(spacing: 12) {
            Text(name)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(score)")
                .font(.system(size: 128, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
            Button(action: { store.send(.pointWon(side)) }) {
                Text("+1")
                    .font(.title2.weight(.bold))
                    .frame(minWidth: 76, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.22))
            .disabled(store.state.finished)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color)
    }

    private var centerPanel: some View {
        VStack(spacing: 14) {
            HStack {
                if showBackButton {
                    Button(action: back) { Image(systemName: "chevron.left") }
                }
                Spacer()
                if supportsWatchLaunch {
                    Button(action: {
                        watchSessionId = watchLinkService.startOnWatch(gameType: gameType, state: store.state)
                    }) {
                        Image(systemName: "applewatch")
                    }
                    .help("在手表打开计分板")
                }
                Button(action: { store.send(.exchangeSides) }) { Image(systemName: "arrow.left.arrow.right") }
            }
            .buttonStyle(.borderless)

            Text("第 \(store.state.currentSet) 局")
                .font(.headline)
            Text("\(store.state.leftSets) : \(store.state.rightSets)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
            Image(systemName: store.state.servingSide == .left ? "arrow.left.circle.fill" : "arrow.right.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.accentColor)

            Spacer(minLength: 0)
            HStack(spacing: 16) {
                Button(action: store.undo) { Image(systemName: "arrow.uturn.backward") }
                Button(action: { store.send(.finish) }) { Image(systemName: "flag.checkered") }
                Button(action: { store.send(.reset) }) { Image(systemName: "arrow.counterclockwise") }
            }
            .buttonStyle(.borderless)
            .font(.title3)
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(12)
        .frame(maxHeight: .infinity)
        .background(Theme.cardBackground)
    }

    private func logicalSide(forScreen side: MatchSide) -> MatchSide {
        store.state.sidesSwapped ? side.opposite : side
    }

    private var supportsWatchLaunch: Bool {
        switch gameType {
        case .pingpong, .pingpongDoubles, .badminton, .badmintonDoubles, .pickleball, .pickleballDoubles:
            true
        default:
            false
        }
    }

    private func back() {
        if let onNavigationBack {
            onNavigationBack()
        } else {
            dismiss()
        }
    }
}
