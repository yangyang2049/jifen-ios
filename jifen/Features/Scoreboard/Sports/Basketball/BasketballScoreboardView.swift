import SwiftUI
import ScoreCore
import UIKit

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
    @State private var appearance = ScoreboardAppearanceSnapshot.current()
    @State private var showDisplaySettings = false
    @State private var showLocalSync = false
    @State private var previousIdleTimerDisabled: Bool?
    @State private var chromeVisible = true
    @State private var immersiveGeneration = 0

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
        let ruleSet: BasketballRuleSet = initialSetup?.basketballRuleSet == "nba" ? .nba : .fiba
        _store = State(initialValue: BasketballSessionStore(
            leftName: leftName,
            rightName: rightName,
            gameMode: gameMode,
            ruleSet: ruleSet
        ))
        _watchSessionId = State(initialValue: initialSetup?.linkedWatchSessionId)
    }

    var body: some View {
        GeometryReader { proxy in
            let centerW = ScoreboardLayoutMetrics.basketballCenterWidth(screenWidth: proxy.size.width)
            let sideW = (proxy.size.width - centerW) / 2
            HStack(spacing: 0) {
                BasketballTeamPanel(
                    name: displayName(for: .left),
                    score: displayScore(for: .left),
                    fouls: displayFouls(for: .left),
                    timeouts: displayTimeouts(for: .left),
                    foulDisplayLimit: BasketballMatchEngine.foulDisplayLimit(store.state),
                    bonusThreshold: BasketballMatchEngine.bonusThreshold(store.state),
                    doubleBonusThreshold: BasketballMatchEngine.doubleBonusThreshold(store.state),
                    color: logicalSide(forScreen: .left) == .left ? Color(hex: "C62828") : Color(hex: "007AFF"),
                    isLeftSide: true,
                    scoreboardFont: appearance.font,
                    scoreMultiplier: scoreMultiplier,
                    panelHeight: proxy.size.height,
                    points: BasketballMatchEngine.scoringButtons(store.state),
                    onScore: { store.send(.addPoints(side: logicalSide(forScreen: .left), points: $0)) },
                    onFoul: { store.send(.addFoul(side: logicalSide(forScreen: .left))) },
                    onRemoveFoul: { store.send(.removeFoul(side: logicalSide(forScreen: .left))) },
                    onTimeout: { store.send(.useTimeout(side: logicalSide(forScreen: .left))) }
                )
                .frame(width: sideW)

                BasketballCenterPanel(
                    state: store.state,
                    onBack: back,
                    showsBackButton: showBackButton,
                    onToggleClock: { store.send(.setClockRunning(!store.state.gameRunning)) },
                    onResetGameClock: { store.send(.resetGameClock) },
                    onResetShotClock: { store.send(.resetShotClock(seconds: $0)) },
                    onAdvancePeriod: { store.send(.advanceToNextPeriod) },
                    onEnterOvertime: { store.send(.enterOvertime) },
                    onSelectPeriod: { store.send(.selectPeriod($0)) },
                    onUndo: store.undo,
                    onFinish: { store.send(.finish) },
                    onSwap: { store.send(.exchangeSides) },
                    onLaunchOnWatch: { watchSessionId = watchLinkService.startOnWatch(state: store.state) },
                    onDisplaySettings: { showDisplaySettings = true },
                    onLocalSync: { showLocalSync = true },
                    showsChrome: shouldShowChrome
                )
                .frame(width: centerW)

                BasketballTeamPanel(
                    name: displayName(for: .right),
                    score: displayScore(for: .right),
                    fouls: displayFouls(for: .right),
                    timeouts: displayTimeouts(for: .right),
                    foulDisplayLimit: BasketballMatchEngine.foulDisplayLimit(store.state),
                    bonusThreshold: BasketballMatchEngine.bonusThreshold(store.state),
                    doubleBonusThreshold: BasketballMatchEngine.doubleBonusThreshold(store.state),
                    color: logicalSide(forScreen: .right) == .left ? Color(hex: "C62828") : Color(hex: "007AFF"),
                    isLeftSide: false,
                    scoreboardFont: appearance.font,
                    scoreMultiplier: scoreMultiplier,
                    panelHeight: proxy.size.height,
                    points: BasketballMatchEngine.scoringButtons(store.state),
                    onScore: { store.send(.addPoints(side: logicalSide(forScreen: .right), points: $0)) },
                    onFoul: { store.send(.addFoul(side: logicalSide(forScreen: .right))) },
                    onRemoveFoul: { store.send(.removeFoul(side: logicalSide(forScreen: .right))) },
                    onTimeout: { store.send(.useTimeout(side: logicalSide(forScreen: .right))) }
                )
                .frame(width: sideW)
            }
            .background(Color.black)
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .simultaneousGesture(TapGesture().onEnded { revealImmersiveChrome() })
        .onAppear {
            onSetupConsumed?()
            store.startClock()
            appearance = .current()
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            registerScoreboardSync()
            revealImmersiveChrome()
        }
        .onChange(of: store.state) { _, state in
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
            if let watchSessionId { watchLinkService.syncWatch(sessionId: watchSessionId, state: state) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scoreboardPreferencesDidChange)) { _ in
            appearance = .current()
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            revealImmersiveChrome()
        }
        .onDisappear {
            LocalScoreboardSyncCoordinator.shared.unregisterHost()
            if let previousIdleTimerDisabled { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled }
            if let watchSessionId {
                watchLinkService.endWatchSession(watchSessionId)
            }
            store.stopClock()
            store.persistSnapshot()
        }
        .sheet(isPresented: $showDisplaySettings) {
            ScoreboardDisplaySettingsView(gameType: appGameType)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showLocalSync, onDismiss: registerScoreboardSync) { LocalSyncView() }
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

    private var appGameType: GameType {
        store.state.gameMode == .threeXThree ? .threeBasketball : .basketball
    }

    private var scoreMultiplier: CGFloat {
        CGFloat(PreferencesManager.shared.fontSizeMultipliers(for: appGameType)[ScoreboardFontMetric.score.rawValue] ?? 1)
    }

    private var shouldShowChrome: Bool {
        !appearance.immersiveMode || chromeVisible || showDisplaySettings || showLocalSync
    }

    private func revealImmersiveChrome() {
        chromeVisible = true
        immersiveGeneration += 1
        guard appearance.immersiveMode, !showDisplaySettings, !showLocalSync else { return }
        let generation = immersiveGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard generation == immersiveGeneration,
                  appearance.immersiveMode,
                  !showDisplaySettings,
                  !showLocalSync else { return }
            chromeVisible = false
        }
    }

    private func registerScoreboardSync() {
        LocalScoreboardSyncCoordinator.shared.registerHost(
            snapshot: {
                LocalScoreboardDisplayState(
                    gameID: appGameType.canonicalScoreboardIdentifier,
                    title: appGameType.displayName,
                    leftName: displayName(for: .left),
                    rightName: displayName(for: .right),
                    leftScore: "\(displayScore(for: .left))",
                    rightScore: "\(displayScore(for: .right))",
                    leftDetail: "\(displayFouls(for: .left)) 犯规 · \(displayTimeouts(for: .left)) 暂停",
                    rightDetail: "\(displayFouls(for: .right)) 犯规 · \(displayTimeouts(for: .right)) 暂停",
                    themeID: appearance.theme.rawValue,
                    fontID: appearance.font.rawValue,
                    finished: store.state.finished,
                    revision: 0
                )
            },
            handleIntent: { intent in
                switch intent {
                case .addLeft: store.send(.addPoints(side: logicalSide(forScreen: .left), points: 1))
                case .addRight: store.send(.addPoints(side: logicalSide(forScreen: .right), points: 1))
                case .subtractLeft, .subtractRight, .undo: store.undo()
                case .exchangeSides: store.send(.exchangeSides)
                case .requestSnapshot: break
                }
            }
        )
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
    let foulDisplayLimit: Int
    let bonusThreshold: Int
    let doubleBonusThreshold: Int
    let color: Color
    let isLeftSide: Bool
    let scoreboardFont: ScoreboardFont
    let scoreMultiplier: CGFloat
    let panelHeight: CGFloat
    let points: [Int]
    let onScore: (Int) -> Void
    let onFoul: () -> Void
    let onRemoveFoul: () -> Void
    let onTimeout: () -> Void

    private let bonusYellow = Color(hex: "FACC15")

    private var scoreSize: CGFloat {
        ScoreboardLayoutMetrics.mainScoreFontSize(halfViewportHeight: panelHeight) * scoreMultiplier
    }

    private var foulBonusLabel: String? {
        if doubleBonusThreshold > 0, fouls >= doubleBonusThreshold { return "DBL" }
        if fouls >= bonusThreshold { return "BONUS" }
        return nil
    }

    var body: some View {
        ZStack {
            color

            Text("\(score)")
                .font(scoreboardFont.swiftUIFont(size: scoreSize))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .padding(.horizontal, 58)

            VStack {
                Text(name)
                    .font(.system(size: ScoreboardLayoutMetrics.defaultTeamNameFontSize, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, ScoreboardLayoutMetrics.nameTopPadding(panelHeight: panelHeight))
                    .padding(.horizontal, 8)
                Spacer()
            }

            HStack {
                if isLeftSide {
                    scoreButtons
                        .padding(.leading, 32)
                    Spacer()
                } else {
                    Spacer()
                    scoreButtons
                        .padding(.trailing, 32)
                }
            }

            GeometryReader { geo in
                foulRow
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.84)
            }

            VStack {
                Spacer()
                HStack {
                    if isLeftSide { Spacer() }
                    Button(action: onTimeout) {
                        Text("暂停 \(timeouts)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .padding(isLeftSide ? .trailing : .leading, 12)
                    .padding(.bottom, 12)
                    if !isLeftSide { Spacer() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scoreButtons: some View {
        VStack(spacing: 10) {
            ForEach(points, id: \.self) { point in
                Button(action: { onScore(point) }) {
                    Text("+\(point)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var foulRow: some View {
        HStack(spacing: 8) {
            Text("犯规 \(fouls)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            HStack(spacing: 4) {
                ForEach(0..<foulDisplayLimit, id: \.self) { index in
                    Circle()
                        .fill(index < fouls ? Color.white : Color.white.opacity(0.25))
                        .frame(width: 8, height: 8)
                }
            }

            if let label = foulBonusLabel {
                Text(label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(bonusYellow)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onFoul)
        .onLongPressGesture(minimumDuration: 0.35, perform: onRemoveFoul)
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
    let onEnterOvertime: () -> Void
    let onSelectPeriod: (Int) -> Void
    let onUndo: () -> Void
    let onFinish: () -> Void
    let onSwap: () -> Void
    let onLaunchOnWatch: () -> Void
    let onDisplaySettings: () -> Void
    let onLocalSync: () -> Void
    let showsChrome: Bool

    @State private var showPeriodPicker = false
    @State private var shotClockBlinkPhase = false

    private let centerBG = Color(hex: "111827")
    private let actionBlue = Color(hex: "2563EB")
    private let overtimePurple = Color(hex: "7C3AED")
    private let shotYellow = Color(hex: "FACC15")
    private let shotExpired = Color(hex: "EF4444")

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                upperZone
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(2)

                lowerZone
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
            }
            .frame(maxHeight: .infinity)
            .background(centerBG)

            if showPeriodPicker {
                periodPickerOverlay
            }
        }
    }

    private var upperZone: some View {
        VStack(spacing: 10) {
            if showsChrome {
                HStack(spacing: 8) {
                    if showsBackButton {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .foregroundStyle(.white)
                        }
                    }
                    Spacer()
                    Button(action: onLaunchOnWatch) {
                        Image(systemName: "applewatch").foregroundStyle(.white)
                    }
                    Button(action: onSwap) {
                        Image(systemName: "arrow.left.arrow.right").foregroundStyle(.white)
                    }
                    Button(action: onDisplaySettings) {
                        Text("Aa").font(.headline).foregroundStyle(.white)
                    }
                    Button(action: onLocalSync) {
                        Image(systemName: "rectangle.connected.to.line.below").foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.top, 8)
            }

            if state.gameMode == .fiveVFive {
                Button {
                    showPeriodPicker.toggle()
                } label: {
                    Text(periodTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            } else {
                Text(periodTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Button(action: onResetGameClock) {
                Text(clockText(state.gameTimeSeconds))
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button(action: onToggleClock) {
                Image(systemName: state.gameRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 88, height: 88)
                    .background(Circle().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)

            if state.canAdvancePeriod && !state.isOvertime {
                periodActionButton(title: "下一节", color: actionBlue, action: onAdvancePeriod)
            }
            if state.canAdvancePeriod && state.isOvertime {
                periodActionButton(title: "再加时", color: overtimePurple, action: onAdvancePeriod)
            }
            if shouldShowEnterOvertime {
                periodActionButton(title: "进入加时", color: overtimePurple, action: onEnterOvertime)
            }

            Spacer(minLength: 0)
        }
    }

    private var lowerZone: some View {
        VStack(spacing: 8) {
            Text("\(state.shotTimeSeconds)″")
                .font(.system(size: 30, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(state.shotTimeSeconds <= 0 ? shotExpired : shotYellow)
                .opacity(state.shotTimeSeconds <= 0 ? (shotClockBlinkPhase ? 1 : 0.25) : 1)
                .animation(
                    state.shotTimeSeconds <= 0
                        ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                        : .default,
                    value: shotClockBlinkPhase
                )
                .onAppear { shotClockBlinkPhase = true }
                .onChange(of: state.shotTimeSeconds) { _, seconds in
                    if seconds <= 0 { shotClockBlinkPhase.toggle() }
                }

            HStack(spacing: 6) {
                ForEach(shotOptions, id: \.self) { seconds in
                    Button("\(seconds)") { onResetShotClock(seconds) }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.12)))
                        .buttonStyle(.plain)
                }
            }

            if showsChrome {
                HStack(spacing: 16) {
                    Button(action: onUndo) {
                        Image(systemName: "arrow.uturn.backward").foregroundStyle(.white)
                    }
                    Button(action: onFinish) {
                        Image(systemName: "flag.checkered").foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .font(.title3)
                .padding(.bottom, 10)
            }
        }
    }

    private var periodPickerOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { showPeriodPicker = false }

            VStack(spacing: 10) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(1...4, id: \.self) { period in
                        Button("Q\(period)") {
                            onSelectPeriod(period)
                            showPeriodPicker = false
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(state.currentPeriod == period && !state.isOvertime ? .white : .white.opacity(0.85))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(state.currentPeriod == period && !state.isOvertime ? actionBlue : Color.white.opacity(0.12))
                        )
                        .buttonStyle(.plain)
                    }
                }

                Button("OT") {
                    onEnterOvertime()
                    showPeriodPicker = false
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(state.isOvertime ? .white : .white.opacity(0.85))
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(state.isOvertime ? overtimePurple : Color.white.opacity(0.12))
                )
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(centerBG))
            .padding(.horizontal, 8)
        }
    }

    private func periodActionButton(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 92, height: 38)
                .background(RoundedRectangle(cornerRadius: 8).fill(color))
        }
        .buttonStyle(.plain)
    }

    private var shouldShowEnterOvertime: Bool {
        state.gameMode == .fiveVFive
            && !state.isOvertime
            && state.currentPeriod >= 4
            && state.gameTimeSeconds == 0
            && state.leftScore == state.rightScore
            && !state.finished
    }

    private var periodTitle: String {
        if state.isOvertime { return "OT" }
        return state.gameMode == .threeXThree ? "3x3" : "Q\(state.currentPeriod)"
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
