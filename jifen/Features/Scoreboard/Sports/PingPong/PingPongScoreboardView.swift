import ScoreCore
import SwiftUI

struct PingPongScoreboardView: View {
    @Environment(\.dismiss) private var dismiss

    var showBackButton: Bool = true
    var onNavigationBack: (() -> Void)? = nil
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil

    @State private var store: RallySessionStore

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
            : NSLocalizedString("red_team", value: "红方", comment: "Red team")
        let rightName = initialSetup?.team2Name.isEmpty == false
            ? initialSetup!.team2Name
            : NSLocalizedString("blue_team", value: "蓝方", comment: "Blue team")
        let maxSets = initialSetup?.maxSets ?? 5
        _store = State(initialValue: RallySessionStore(
            leftName: leftName,
            rightName: rightName,
            gameType: .pingpong,
            rules: .pingPong(maxSets: maxSets)
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
        .onAppear { onSetupConsumed?() }
        .onDisappear { store.persistSnapshot() }
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

    private func back() {
        if let onNavigationBack {
            onNavigationBack()
        } else {
            dismiss()
        }
    }
}

#Preview {
    PingPongScoreboardView()
        .previewInterfaceOrientation(.landscapeLeft)
}
