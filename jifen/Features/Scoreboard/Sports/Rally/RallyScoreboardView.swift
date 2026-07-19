import ScoreCore
import SwiftUI
import UIKit

struct RallyScoreboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PhoneWatchLinkService.self) private var watchLinkService

    let gameType: ScoreCore.GameType
    let showBackButton: Bool
    let onNavigationBack: (() -> Void)?
    let onPresented: () -> Void
    @State private var voiceAnnouncementEnabled: Bool
    @State private var store: RallySessionStore
    @State private var watchSessionId: UUID?
    @State private var finishConfirmationDeadline: Date?
    @State private var settleConfirmationDeadline: Date?
    @State private var toastMessage: String?
    @State private var appearance = ScoreboardAppearanceSnapshot.current()
    @State private var showDisplaySettings = false
    @State private var showLocalSync = false
    @State private var showMenu = false
    @State private var previousIdleTimerDisabled: Bool?
    @State private var chromeVisible = true
    @State private var immersiveGeneration = 0
    @State private var exitConfirmDeadline: Date?
    @State private var isEditMode = false
    @State private var editLeftName = ""
    @State private var editRightName = ""
    @State private var editDoublesNames: [String] = Array(repeating: "", count: 4)
    @State private var pendingDoublesFlash: PendingDoublesFlash?
    @State private var flashSlots: Set<Int> = []
    @State private var flashActive = false
    @State private var flashTask: Task<Void, Never>?
    @State private var showGameFinishedOverlay = false
    @State private var recordId: String
    @State private var gameStartTime: Date
    @State private var draftSaveGeneration = 0
    @State private var actions: [String]

    init(
        leftName: String,
        rightName: String,
        gameType: ScoreCore.GameType,
        rules: RallyRuleSet,
        participants: [SessionParticipant]? = nil,
        openingServer: MatchSide = .left,
        voiceAnnouncementEnabled: Bool = false,
        initialWatchSessionId: UUID? = nil,
        initialRecordId: String? = nil,
        showBackButton: Bool = true,
        onNavigationBack: (() -> Void)? = nil,
        onPresented: @escaping () -> Void = {}
    ) {
        self.showBackButton = showBackButton
        self.onNavigationBack = onNavigationBack
        self.onPresented = onPresented
        _watchSessionId = State(initialValue: initialWatchSessionId)

        if let initialRecordId,
           let draft = Self.loadDraft(recordId: initialRecordId) {
            self.gameType = draft.coreGameType ?? gameType
            _store = State(initialValue: RallySessionStore(
                gameType: draft.coreGameType ?? gameType,
                state: draft.state,
                participants: participants
            ))
            _recordId = State(initialValue: initialRecordId)
            _gameStartTime = State(initialValue: draft.startTime)
            _actions = State(initialValue: draft.actions)
            _voiceAnnouncementEnabled = State(initialValue: draft.voiceAnnouncementEnabled)
            _showGameFinishedOverlay = State(initialValue: draft.state.finished)
        } else {
            self.gameType = gameType
            _store = State(initialValue: RallySessionStore(
                leftName: leftName,
                rightName: rightName,
                gameType: gameType,
                rules: rules,
                participants: participants,
                openingServer: openingServer
            ))
            _recordId = State(initialValue: initialRecordId ?? "rally_\(UUID().uuidString)")
            _gameStartTime = State(initialValue: Date())
            _actions = State(initialValue: [])
            _voiceAnnouncementEnabled = State(initialValue: voiceAnnouncementEnabled)
        }
    }

    private var isDoubles: Bool { store.state.doubles != nil }
    private var palette: ScoreboardPalette { appearance.theme.palette }

    /// 桌上足球无发球模型（对齐鸿蒙/安卓）。
    private var showsServeIndicator: Bool {
        switch gameType {
        case .foosball, .foosballDoubles: return false
        default: return true
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let halfH = proxy.size.height
            ZStack {
                palette.background.ignoresSafeArea()

                HStack(spacing: 0) {
                    if isDoubles {
                        doublesHalf(screenSide: .left, size: CGSize(width: proxy.size.width / 2, height: halfH))
                        doublesHalf(screenSide: .right, size: CGSize(width: proxy.size.width / 2, height: halfH))
                    } else {
                        singlesHalf(screenSide: .left, size: CGSize(width: proxy.size.width / 2, height: halfH))
                        singlesHalf(screenSide: .right, size: CGSize(width: proxy.size.width / 2, height: halfH))
                    }
                }

                if !isEditMode && showsServeIndicator {
                    serveIndicatorOverlay(size: proxy.size)
                }

                if shouldShowChrome {
                    chromeOverlay
                }

                if appearance.immersiveMode && !chromeVisible && !isEditMode {
                    ImmersiveCornerRevealZones(onReveal: revealImmersiveChrome)
                }

                MenuDialog(
                    isVisible: showMenu,
                    onClose: { showMenu = false },
                    onMenuItemClick: handleMenuAction,
                    showEndGame: true,
                    items: menuItems
                )

                if showGameFinishedOverlay {
                    GameFinishedOverlay(winnerName: finishedWinnerName)
                }

                if let toastMessage {
                    VStack {
                        Spacer()
                        ToastView(message: toastMessage)
                            .padding(.bottom, 40)
                    }
                    .transition(.opacity.combined(with: .scale))
                    .allowsHitTesting(false)
                }
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .lockOrientation(.landscape)
        .simultaneousGesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    guard !isEditMode else { return }
                    if value.translation.height < -50 && abs(value.translation.width) < 50 {
                        showMenu.toggle()
                        revealImmersiveChrome()
                    }
                }
        )
        .onAppear {
            onPresented()
            appearance = .current()
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            registerScoreboardSync()
            revealImmersiveChrome()
            if store.state.finished {
                showGameFinishedOverlay = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scoreboardPreferencesDidChange)) { _ in
            appearance = .current()
            UIApplication.shared.isIdleTimerDisabled = appearance.keepScreenOn
            revealImmersiveChrome()
        }
        .onChange(of: store.state) { previous, state in
            if voiceAnnouncementEnabled,
               previous.leftPoints != state.leftPoints || previous.rightPoints != state.rightPoints {
                ScoreVoiceAnnouncer.shared.announce(left: state.leftPoints, right: state.rightPoints)
            }
            if pendingDoublesFlash != nil,
               previous.leftPoints != state.leftPoints || previous.rightPoints != state.rightPoints {
                processPendingDoublesFlash()
            }
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
            if let watchSessionId {
                watchLinkService.syncWatch(sessionId: watchSessionId, gameType: gameType, state: state)
            }
            if state.finished {
                showGameFinishedOverlay = true
            }
            scheduleDraftPersist(finished: state.finished)
        }
        .onChange(of: showMenu) { _, _ in updateImmersiveForBlocking() }
        .onChange(of: showDisplaySettings) { _, _ in updateImmersiveForBlocking() }
        .onChange(of: showLocalSync) { _, _ in updateImmersiveForBlocking() }
        .onChange(of: isEditMode) { _, editing in
            if editing {
                syncEditNamesFromState()
            } else {
                commitSinglesNamesIfNeeded()
            }
            updateImmersiveForBlocking()
        }
        .onDisappear {
            flashTask?.cancel()
            LocalScoreboardSyncCoordinator.shared.unregisterHost()
            if let previousIdleTimerDisabled { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled }
            if let watchSessionId {
                watchLinkService.endWatchSession(watchSessionId)
            }
            store.persistSnapshot()
            persistRecord(finished: store.state.finished)
        }
        .sheet(isPresented: $showDisplaySettings) {
            ScoreboardDisplaySettingsView(gameType: appGameType)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showLocalSync, onDismiss: registerScoreboardSync) {
            LocalSyncView()
        }
    }

    // MARK: - Singles

    private func singlesHalf(screenSide: MatchSide, size: CGSize) -> some View {
        let side = logicalSide(forScreen: screenSide)
        let isLeft = side == .left
        let color = isLeft ? palette.left : palette.right

        return ZStack {
            color
            if isEditMode {
                singlesEditContent(side: side, size: size)
            } else {
                singlesPlayContent(side: side, size: size)
            }
        }
        .foregroundStyle(palette.foreground)
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEditMode, !store.state.finished else { return }
            handlePointWon(side)
        }
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    guard !isEditMode else { return }
                    if value.translation.width < -50 && abs(value.translation.height) < 50 {
                        store.undo {
                            scheduleDraftPersist(finished: store.state.finished)
                        }
                        showToast(NSLocalizedString("undone", value: "已撤销", comment: ""))
                    } else if value.translation.height > 50 && abs(value.translation.width) < 50 {
                        guard !store.state.finished else { return }
                        let points = side == .left ? store.state.leftPoints : store.state.rightPoints
                        guard points > 0 else { return }
                        dispatch(.adjustPoints(side: side, delta: -1))
                    }
                }
        )
    }

    private func singlesPlayContent(side: MatchSide, size: CGSize) -> some View {
        let isLeft = side == .left
        let name = isLeft ? store.state.leftName : store.state.rightName
        let score = isLeft ? store.state.leftPoints : store.state.rightPoints
        let sets = isLeft ? store.state.leftSets : store.state.rightSets
        let mainSize = ScoreboardLayoutMetrics.mainScoreFontSize(halfViewportHeight: size.height) * scoreMultiplier
        let setSize = ScoreboardLayoutMetrics.setScoreFontSize(halfViewportHeight: size.height) * secondaryMultiplier
        let nameSize = ScoreboardLayoutMetrics.teamNameFontSize(halfViewportHeight: size.height) * nameMultiplier
        let nameToMain = ScoreboardLayoutMetrics.nameToMainSpacing(halfViewportHeight: size.height)
        let mainToSet = ScoreboardLayoutMetrics.mainToSetSpacing(halfViewportHeight: size.height)

        return VStack(spacing: 0) {
            Text(name)
                .font(.system(size: nameSize, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 8)
            Spacer().frame(height: nameToMain)
            Text("\(score)")
                .font(appearance.font.swiftUIFont(size: mainSize))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Spacer().frame(height: mainToSet)
            Text("\(sets)")
                .font(appearance.font.swiftUIFont(size: setSize))
                .monospacedDigit()
                .foregroundStyle(palette.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func singlesEditContent(side: MatchSide, size: CGSize) -> some View {
        let isLeft = side == .left
        let score = isLeft ? store.state.leftPoints : store.state.rightPoints
        let sets = isLeft ? store.state.leftSets : store.state.rightSets
        let mainSize = ScoreboardLayoutMetrics.mainScoreFontSize(halfViewportHeight: size.height) * scoreMultiplier * 0.7
        let setSize = ScoreboardLayoutMetrics.setScoreFontSize(halfViewportHeight: size.height) * secondaryMultiplier
        let nameSize = ScoreboardLayoutMetrics.teamNameFontSize(halfViewportHeight: size.height) * nameMultiplier
        let nameToMain = ScoreboardLayoutMetrics.nameToMainSpacing(halfViewportHeight: size.height)
        let mainToSet = ScoreboardLayoutMetrics.mainToSetSpacing(halfViewportHeight: size.height)

        return VStack(spacing: 0) {
            TextField(
                NSLocalizedString("team_name", value: "队名", comment: ""),
                text: isLeft ? $editLeftName : $editRightName
            )
            .font(.system(size: nameSize, weight: .bold))
            .multilineTextAlignment(.center)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
            .padding(.horizontal, 16)
            .onChange(of: isLeft ? editLeftName : editRightName) { _, _ in
                commitSinglesNamesIfNeeded()
            }

            Spacer().frame(height: nameToMain)

            editAdjustRow(
                value: score,
                fontSize: mainSize,
                useSecondaryColor: false,
                canDecrement: score > 0,
                onDecrement: { store.send(.adjustPoints(side: side, delta: -1)) },
                onIncrement: { store.send(.adjustPoints(side: side, delta: 1)) }
            )

            Spacer().frame(height: mainToSet)

            editAdjustRow(
                value: sets,
                fontSize: setSize,
                useSecondaryColor: true,
                canDecrement: sets > 0,
                onDecrement: { store.send(.adjustSets(side: side, delta: -1)) },
                onIncrement: { store.send(.adjustSets(side: side, delta: 1)) }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, ScoreboardLayoutMetrics.nameTopPadding(panelHeight: size.height, isEditMode: true))
    }

    // MARK: - Doubles

    private func doublesHalf(screenSide: MatchSide, size: CGSize) -> some View {
        let side = logicalSide(forScreen: screenSide)
        let isLeft = side == .left
        let color = isLeft ? palette.left : palette.right
        let rowH = size.height / 3
        let (topName, bottomName) = doublesCornerNames(screenSide: screenSide)
        let topSlot = doublesTopSlot(screenSide: screenSide)
        let bottomSlot = doublesBottomSlot(screenSide: screenSide)

        return ZStack {
            color
            VStack(spacing: 0) {
                doublesNameCell(
                    name: topName,
                    slot: topSlot,
                    fontSize: doublesNameFontSize(panelHeight: size.height),
                    height: rowH
                )
                if isEditMode {
                    doublesEditScoreRow(screenSide: screenSide, side: side, height: rowH, panelHeight: size.height)
                } else {
                    doublesPlayScoreRow(screenSide: screenSide, side: side, height: rowH, panelHeight: size.height)
                }
                doublesNameCell(
                    name: bottomName,
                    slot: bottomSlot,
                    fontSize: doublesNameFontSize(panelHeight: size.height),
                    height: rowH
                )
            }
        }
        .foregroundStyle(palette.foreground)
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEditMode, !store.state.finished else { return }
            handlePointWon(side)
        }
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    guard !isEditMode else { return }
                    if value.translation.width < -50 && abs(value.translation.height) < 50 {
                        store.undo {
                            scheduleDraftPersist(finished: store.state.finished)
                        }
                        showToast(NSLocalizedString("undone", value: "已撤销", comment: ""))
                    } else if value.translation.height > 50 && abs(value.translation.width) < 50 {
                        guard !store.state.finished else { return }
                        let points = side == .left ? store.state.leftPoints : store.state.rightPoints
                        guard points > 0 else { return }
                        dispatch(.adjustPoints(side: side, delta: -1))
                    }
                }
        )
    }

    private func doublesPlayScoreRow(screenSide: MatchSide, side: MatchSide, height: CGFloat, panelHeight: CGFloat) -> some View {
        let isLeft = side == .left
        let score = isLeft ? store.state.leftPoints : store.state.rightPoints
        let sets = isLeft ? store.state.leftSets : store.state.rightSets
        let mainSize = ScoreboardLayoutMetrics.mainScoreFontSize(halfViewportHeight: panelHeight) * scoreMultiplier * 0.85
        let setSize = ScoreboardLayoutMetrics.setScoreFontSize(halfViewportHeight: panelHeight) * secondaryMultiplier

        return HStack(spacing: 8) {
            if screenSide == .left {
                Text("\(score)")
                    .font(appearance.font.swiftUIFont(size: mainSize))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("\(sets)")
                    .font(appearance.font.swiftUIFont(size: setSize))
                    .monospacedDigit()
                    .foregroundStyle(palette.secondary)
            } else {
                Text("\(sets)")
                    .font(appearance.font.swiftUIFont(size: setSize))
                    .monospacedDigit()
                    .foregroundStyle(palette.secondary)
                Text("\(score)")
                    .font(appearance.font.swiftUIFont(size: mainSize))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private func doublesEditScoreRow(screenSide: MatchSide, side: MatchSide, height: CGFloat, panelHeight: CGFloat) -> some View {
        let isLeft = side == .left
        let score = isLeft ? store.state.leftPoints : store.state.rightPoints
        let sets = isLeft ? store.state.leftSets : store.state.rightSets
        let mainSize = ScoreboardLayoutMetrics.mainScoreFontSize(halfViewportHeight: panelHeight) * scoreMultiplier * 0.7
        let setSize = ScoreboardLayoutMetrics.setScoreFontSize(halfViewportHeight: panelHeight) * secondaryMultiplier

        return VStack(spacing: 8) {
            editAdjustRow(
                value: score,
                fontSize: mainSize,
                useSecondaryColor: false,
                canDecrement: score > 0,
                onDecrement: { store.send(.adjustPoints(side: side, delta: -1)) },
                onIncrement: { store.send(.adjustPoints(side: side, delta: 1)) }
            )
            editAdjustRow(
                value: sets,
                fontSize: setSize,
                useSecondaryColor: true,
                canDecrement: sets > 0,
                onDecrement: { store.send(.adjustSets(side: side, delta: -1)) },
                onIncrement: { store.send(.adjustSets(side: side, delta: 1)) }
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private func doublesNameCell(name: String, slot: Int, fontSize: CGFloat, height: CGFloat) -> some View {
        let doubles = store.state.doubles
        let isServer = doubles?.serverSlotIndex == slot
        let isReceiver = doubles?.receiverSlotIndex == slot
        let nameColor: Color = {
            if isServer { return palette.foreground }
            if isReceiver { return palette.secondary }
            return palette.foreground.opacity(0.85)
        }()
        let showFlash = flashSlots.contains(slot) && flashActive
        let flashColor = Color(red: 1, green: 215 / 255, blue: 0).opacity(0.45)

        return ZStack {
            if showFlash {
                flashColor
            }
            if isEditMode {
                TextField(
                    NSLocalizedString("multi_score_player_default", value: "玩家", comment: ""),
                    text: Binding(
                        get: {
                            guard editDoublesNames.indices.contains(slot) else { return name }
                            return editDoublesNames[slot]
                        },
                        set: { newValue in
                            guard editDoublesNames.indices.contains(slot) else { return }
                            editDoublesNames[slot] = newValue
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                store.send(.setDoublesPlayerName(slot: slot, name: trimmed))
                            }
                        }
                    )
                )
                .font(.system(size: fontSize, weight: .bold))
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
            } else {
                Text(name)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(nameColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private func doublesNameFontSize(panelHeight: CGFloat) -> CGFloat {
        (ScoreboardLayoutMetrics.isPad ? 28 : 22) * nameMultiplier
    }

    private func doublesTopSlot(screenSide: MatchSide) -> Int {
        let side = logicalSide(forScreen: screenSide)
        return side == .left ? 0 : 1
    }

    private func doublesBottomSlot(screenSide: MatchSide) -> Int {
        let side = logicalSide(forScreen: screenSide)
        return side == .left ? 2 : 3
    }

    private func doublesCornerNames(screenSide: MatchSide) -> (String, String) {
        guard let doubles = store.state.doubles else { return ("", "") }
        var top = doubles.playerName(at: doublesTopSlot(screenSide: screenSide)) ?? ""
        var bottom = doubles.playerName(at: doublesBottomSlot(screenSide: screenSide)) ?? ""
        if !isEditMode, let swapped = doubles.pickleballPartnersSwapped {
            let logical = logicalSide(forScreen: screenSide)
            let partnersSwapped = logical == .left ? swapped.team0 : swapped.team1
            if partnersSwapped {
                swap(&top, &bottom)
            }
        }
        return (top, bottom)
    }

    // MARK: - Edit helpers

    private func editAdjustRow(
        value: Int,
        fontSize: CGFloat,
        useSecondaryColor: Bool,
        canDecrement: Bool,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            editCircleButton(systemName: "minus", enabled: canDecrement, action: onDecrement)
            Text("\(value)")
                .font(appearance.font.swiftUIFont(size: fontSize))
                .monospacedDigit()
                .foregroundStyle(useSecondaryColor ? palette.secondary : palette.foreground)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            editCircleButton(systemName: "plus", enabled: true, action: onIncrement)
        }
    }

    private func editCircleButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(enabled ? palette.foreground.opacity(0.75) : palette.foreground.opacity(0.3))
                .frame(width: 50, height: 50)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
    }

    private func syncEditNamesFromState() {
        editLeftName = store.state.leftName
        editRightName = store.state.rightName
        if let doubles = store.state.doubles {
            editDoublesNames = (0..<4).map { doubles.playerName(at: $0) ?? "" }
        }
    }

    private func commitSinglesNamesIfNeeded() {
        let left = editLeftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = editRightName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty, !right.isEmpty else { return }
        if left != store.state.leftName || right != store.state.rightName {
            store.send(.setNames(left: left, right: right))
        }
    }

    // MARK: - Doubles flash

    private struct PendingDoublesFlash {
        let scoringSide: MatchSide
        let prevServingSide: MatchSide
    }

    private func handlePointWon(_ side: MatchSide) {
        if isDoubles {
            pendingDoublesFlash = PendingDoublesFlash(
                scoringSide: side,
                prevServingSide: store.state.servingSide
            )
        }
        dispatch(.pointWon(side))
        revealImmersiveChrome()
    }

    private func processPendingDoublesFlash() {
        guard let pending = pendingDoublesFlash else { return }
        pendingDoublesFlash = nil

        let slots: Set<Int>
        if pending.scoringSide == pending.prevServingSide {
            slots = pending.scoringSide == .left ? [0, 2] : [1, 3]
        } else if let newSlot = store.state.doubles?.serverSlotIndex {
            slots = [newSlot]
        } else {
            return
        }
        runDoublesFlash(slots: slots)
    }

    private func runDoublesFlash(slots: Set<Int>) {
        flashTask?.cancel()
        flashTask = Task { @MainActor in
            flashSlots = slots
            flashActive = false
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            for step in 0..<4 {
                flashActive = step.isMultiple(of: 2)
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
            }
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            flashActive = false
            flashSlots = []
        }
    }

    // MARK: - Serve indicator

    @ViewBuilder
    private func serveIndicatorOverlay(size: CGSize) -> some View {
        let servingIsLeftScreen: Bool = {
            let serving = store.state.servingSide
            let leftLogical = logicalSide(forScreen: .left)
            return serving == leftLogical
        }()

        if isDoubles, let doubles = store.state.doubles {
            let serverSlot = doubles.serverSlotIndex
            let isTopRow = serverSlot == 0 || serverSlot == 1
            let yFrac: CGFloat = isTopRow ? (1.0 / 6.0) : (5.0 / 6.0)
            ZStack {
                CenterLineServeIndicator(isLeftServing: servingIsLeftScreen, triangleSize: 36)
                if let serverNumber = doubles.pickleballServerNumber {
                    Text("\(serverNumber)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.foreground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.35)))
                        .offset(y: isTopRow ? 28 : -28)
                }
            }
            .position(x: size.width / 2, y: size.height * yFrac)
            .allowsHitTesting(false)
        } else {
            CenterLineServeIndicator(isLeftServing: servingIsLeftScreen, triangleSize: 36)
                .position(x: size.width / 2, y: size.height / 2)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Chrome

    private var chromeOverlay: some View {
        ZStack {
            VStack {
                HStack(spacing: 8) {
                    Spacer()
                    chromeButton(systemName: "textformat.size") {
                        showDisplaySettings = true
                    }
                    chromeButton(
                        systemName: isEditMode ? "checkmark" : "pencil",
                        background: isEditMode ? Color(hex: "00C853") : Color.black.opacity(0.25)
                    ) {
                        if isEditMode {
                            commitSinglesNamesIfNeeded()
                        }
                        isEditMode.toggle()
                        VibrationManager.shared.vibrateMedium()
                    }
                }
                Spacer()
            }
            .padding(.trailing, ScoreboardConstants.buttonPadding)
            .padding(.top, ScoreboardConstants.buttonPadding)

            if !isEditMode {
                VStack {
                    Spacer()
                    HStack {
                        if showBackButton {
                            chromeButton(systemName: "chevron.left", action: requestBack)
                                .padding(.leading, ScoreboardConstants.buttonPadding)
                                .padding(.bottom, ScoreboardConstants.buttonPadding)
                        }
                        Spacer()
                        chromeButton(systemName: "line.3.horizontal") {
                            showMenu = true
                        }
                        .padding(.trailing, ScoreboardConstants.buttonPadding)
                        .padding(.bottom, ScoreboardConstants.buttonPadding)
                    }
                }
            }
        }
        .allowsHitTesting(true)
    }

    private func chromeButton(
        systemName: String,
        background: Color = Color.black.opacity(0.25),
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            action()
            revealImmersiveChrome()
        }) {
            Image(systemName: systemName)
                .font(.system(size: ScoreboardConstants.buttonIconSize))
                .foregroundColor(.white)
                .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                .background(Circle().fill(background))
        }
        .buttonStyle(.plain)
    }

    private var menuItems: [ScoreboardMenuItem] {
        var extras: [ScoreboardMenuItem] = []
        if supportsWatchLaunch {
            extras.append(
                ScoreboardMenuItem(
                    title: NSLocalizedString("open_on_watch", value: "在手表打开", comment: ""),
                    action: "watch",
                    group: .tools,
                    icon: "applewatch"
                )
            )
        }
        extras.append(
            ScoreboardMenuItem(
                title: voiceAnnouncementEnabled
                    ? NSLocalizedString("voice_announcement_on", value: "语音：开", comment: "")
                    : NSLocalizedString("voice_announcement_off", value: "语音：关", comment: ""),
                action: "voiceAnnouncement",
                group: .tools,
                icon: voiceAnnouncementEnabled ? "speaker.wave.2" : "speaker.slash",
                keepDialogOpen: true
            )
        )
        return ScoreboardMenuItemBuilder.defaultItems(
            showEndGame: true,
            showExchangeSide: true,
            showLocalSync: true,
            showWhistle: true,
            showScreenshot: true,
            showDisplaySettings: true,
            showSettleMatch: gameType == .foosball || gameType == .foosballDoubles,
            settleConfirming: settleConfirmationDeadline.map { Date() <= $0 } == true,
            extraItems: extras
        )
    }

    private func handleMenuAction(_ action: String) {
        switch action {
        case "undo":
            store.undo {
                scheduleDraftPersist(finished: store.state.finished)
            }
            showToast(NSLocalizedString("undone", value: "已撤销", comment: ""))
        case "exchangeSide":
            dispatch(.exchangeSides)
        case "reset":
            showGameFinishedOverlay = false
            dispatch(.reset)
        case "endGame":
            finishMatch()
        case "settleMatch":
            settleMatch()
        case "displaySettings":
            showDisplaySettings = true
        case "localSync":
            showLocalSync = true
        case "watch":
            watchSessionId = watchLinkService.startOnWatch(gameType: gameType, state: store.state)
        case "voiceAnnouncement":
            voiceAnnouncementEnabled.toggle()
            scheduleDraftPersist(finished: store.state.finished)
        default:
            break
        }
    }

    // MARK: - Multipliers / chrome state

    private var scoreMultiplier: CGFloat {
        CGFloat(PreferencesManager.shared.fontSizeMultipliers(for: appGameType)[ScoreboardFontMetric.score.rawValue] ?? 1)
    }

    private var nameMultiplier: CGFloat {
        CGFloat(PreferencesManager.shared.fontSizeMultipliers(for: appGameType)[ScoreboardFontMetric.name.rawValue] ?? 1)
    }

    private var secondaryMultiplier: CGFloat {
        CGFloat(PreferencesManager.shared.fontSizeMultipliers(for: appGameType)[ScoreboardFontMetric.secondary.rawValue] ?? 1)
    }

    private var shouldShowChrome: Bool {
        !appearance.immersiveMode || chromeVisible || isEditMode || showDisplaySettings || showLocalSync || showMenu
    }

    private func revealImmersiveChrome() {
        chromeVisible = true
        immersiveGeneration += 1
        guard appearance.immersiveMode, !isEditMode, !showDisplaySettings, !showLocalSync, !showMenu else { return }
        let generation = immersiveGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard generation == immersiveGeneration,
                  appearance.immersiveMode,
                  !isEditMode,
                  !showDisplaySettings,
                  !showLocalSync,
                  !showMenu else { return }
            chromeVisible = false
        }
    }

    private func updateImmersiveForBlocking() {
        if showMenu || showDisplaySettings || showLocalSync || isEditMode || !appearance.immersiveMode {
            immersiveGeneration += 1
            chromeVisible = true
        } else {
            revealImmersiveChrome()
        }
    }

    private var appGameType: GameType {
        switch gameType {
        case .pingpong, .pingpongDoubles: .pingpong
        case .badminton, .badmintonDoubles: .badminton
        case .tennis, .tennisDoubles: .tennis
        case .pickleball, .pickleballDoubles: .pickleball
        case .volleyball: .volleyball
        case .airVolleyball: .airVolleyball
        case .beachVolleyball: .beachVolleyball
        case .foosball, .foosballDoubles: .foosball
        default: .simpleScore
        }
    }

    private func registerScoreboardSync() {
        LocalScoreboardSyncCoordinator.shared.registerHost(
            snapshot: {
                let leftSide = logicalSide(forScreen: .left)
                let rightSide = logicalSide(forScreen: .right)
                return LocalScoreboardDisplayState(
                    gameID: appGameType.canonicalScoreboardIdentifier,
                    title: appGameType.displayName,
                    leftName: leftSide == .left ? store.state.leftName : store.state.rightName,
                    rightName: rightSide == .left ? store.state.leftName : store.state.rightName,
                    leftScore: "\(leftSide == .left ? store.state.leftPoints : store.state.rightPoints)",
                    rightScore: "\(rightSide == .left ? store.state.leftPoints : store.state.rightPoints)",
                    leftDetail: String(format: NSLocalizedString("sync_sets_format", value: "%d 局", comment: ""), leftSide == .left ? store.state.leftSets : store.state.rightSets),
                    rightDetail: String(format: NSLocalizedString("sync_sets_format", value: "%d 局", comment: ""), rightSide == .left ? store.state.leftSets : store.state.rightSets),
                    themeID: appearance.theme.rawValue,
                    fontID: appearance.font.rawValue,
                    finished: store.state.finished,
                    revision: 0
                )
            },
            handleIntent: { intent in
                switch intent {
                case .addLeft: dispatch(.pointWon(logicalSide(forScreen: .left)))
                case .addRight: dispatch(.pointWon(logicalSide(forScreen: .right)))
                case .subtractLeft:
                    let side = logicalSide(forScreen: .left)
                    guard store.state.leftPoints > 0, !store.state.finished else { return }
                    dispatch(.adjustPoints(side: side, delta: -1))
                case .subtractRight:
                    let side = logicalSide(forScreen: .right)
                    guard store.state.rightPoints > 0, !store.state.finished else { return }
                    dispatch(.adjustPoints(side: side, delta: -1))
                case .undo:
                    store.undo {
                        scheduleDraftPersist(finished: store.state.finished)
                    }
                case .exchangeSides: dispatch(.exchangeSides)
                case .requestSnapshot: break
                }
            }
        )
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

    private func requestBack() {
        let now = Date()
        if exitConfirmDeadline.map({ now <= $0 }) != true {
            exitConfirmDeadline = now.addingTimeInterval(2)
            showToast(NSLocalizedString("press_again_to_exit", value: "再按一次退出", comment: ""))
            return
        }
        back()
    }

    private func back() {
        if let onNavigationBack {
            onNavigationBack()
        } else {
            dismiss()
        }
    }

    private func finishMatch() {
        let now = Date()
        let requiresConfirmation = store.state.rules.matchCompletionMode == .playAll
            && !store.state.rules.isMatchFinished(
                leftSets: store.state.leftSets,
                rightSets: store.state.rightSets
            )
        if requiresConfirmation, finishConfirmationDeadline.map({ now <= $0 }) != true {
            finishConfirmationDeadline = now.addingTimeInterval(2)
            showToast(NSLocalizedString(
                "match_completion_finish_confirmation",
                value: "尚未打满，2 秒内再次点击结束比赛。",
                comment: ""
            ))
            return
        }
        finishConfirmationDeadline = nil
        dispatch(.finish)
    }

    private func settleMatch() {
        let now = Date()
        guard settleConfirmationDeadline.map({ now <= $0 }) == true else {
            settleConfirmationDeadline = now.addingTimeInterval(2)
            showToast(NSLocalizedString("click_again_to_settle_match", value: "再按一次结算", comment: ""))
            return
        }
        settleConfirmationDeadline = nil
        finishMatch()
        showMenu = false
    }

    private func dispatch(_ intent: RallyMatchIntent) {
        store.send(intent) { events in
            handleEvents(events)
        }
    }

    private func handleEvents(_ events: [RallyMatchEvent]) {
        var setToast: String?
        var sideToast: String?
        var matchFinished = false

        for event in events {
            let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
            switch event {
            case .setCompleted(let winner, let setNumber, let leftPoints, let rightPoints, let leftSets, let rightSets):
                actions.append("\(timestamp)|set|\(winner.rawValue)|\(setNumber)|\(leftPoints):\(rightPoints)|\(leftSets):\(rightSets)")
                let winnerName = winner == .left ? store.state.leftName : store.state.rightName
                setToast = String(
                    format: NSLocalizedString("set_ended_winner", value: "第%d局结束，%@获胜，比分 %d-%d", comment: ""),
                    setNumber,
                    winnerName,
                    leftPoints,
                    rightPoints
                )
            case .sidesExchanged:
                actions.append("\(timestamp)|exchangeSides")
                sideToast = NSLocalizedString("change_sides", value: "换边", comment: "")
            case .sidesExchangeReminder:
                actions.append("\(timestamp)|sideChangeReminder")
                sideToast = NSLocalizedString("please_change_sides_manually", value: "请手动换边", comment: "")
            case .matchFinished(let winner):
                actions.append("\(timestamp)|finish|\(winner?.rawValue ?? "draw")")
                matchFinished = true
            case .pointScored(let side, let leftPoints, let rightPoints):
                actions.append("\(timestamp)|point|\(side.rawValue)|\(leftPoints):\(rightPoints)")
            case .matchReset:
                actions.append("\(timestamp)|reset")
            }
        }

        if let setToast {
            showToast(setToast)
            if let sideToast {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
                    showToast(sideToast)
                }
            }
        } else if let sideToast {
            showToast(sideToast)
        }

        if matchFinished {
            showGameFinishedOverlay = true
            persistRecord(finished: true)
        }
    }

    private var finishedWinnerName: String {
        if store.state.leftSets == store.state.rightSets { return "" }
        return store.state.leftSets > store.state.rightSets ? store.state.leftName : store.state.rightName
    }

    private var hasMatchProgress: Bool {
        store.state.leftPoints > 0
            || store.state.rightPoints > 0
            || store.state.leftSets > 0
            || store.state.rightSets > 0
            || store.state.finished
    }

    private func scheduleDraftPersist(finished: Bool) {
        guard finished || hasMatchProgress else { return }
        draftSaveGeneration += 1
        let generation = draftSaveGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard generation == draftSaveGeneration else { return }
            persistRecord(finished: finished)
        }
    }

    private func persistRecord(finished: Bool) {
        guard finished || hasMatchProgress else { return }
        guard let snapshot = try? JSONEncoder().encode(store.state) else { return }
        let endTime = Date()
        let winner: String?
        if finished {
            if store.state.leftSets > store.state.rightSets {
                winner = "left"
            } else if store.state.rightSets > store.state.leftSets {
                winner = "right"
            } else {
                winner = nil
            }
        } else {
            winner = nil
        }

        let record = ScoreboardRecord(
            id: recordId,
            gameType: appGameType,
            startTime: gameStartTime,
            endTime: finished ? endTime : nil,
            duration: endTime.timeIntervalSince(gameStartTime),
            team1Name: store.state.leftName,
            team2Name: store.state.rightName,
            team1FinalScore: store.state.leftSets,
            team2FinalScore: store.state.rightSets,
            team1SetScore: store.state.leftSets,
            team2SetScore: store.state.rightSets,
            winner: winner,
            actions: actions,
            totalScoreChanges: store.state.leftPoints + store.state.rightPoints + store.state.leftSets + store.state.rightSets,
            extraData: {
                var data: [String: AnyCodable] = [
                    "coreGameType": AnyCodable(gameType.rawValue),
                    "maxSets": AnyCodable(store.state.rules.maxSets),
                    "pointsPerSet": AnyCodable(store.state.rules.pointsToWinSet),
                    "matchCompletionMode": AnyCodable(store.state.rules.matchCompletionMode.rawValue),
                    "autoChangeSides": AnyCodable(store.state.rules.autoChangeSides),
                    "servingSide": AnyCodable(store.state.openingServerSide.rawValue),
                    "voiceAnnouncement": AnyCodable(voiceAnnouncementEnabled),
                    "currentSet": AnyCodable(store.state.currentSet),
                    "currentLeftScore": AnyCodable(store.state.leftPoints),
                    "currentRightScore": AnyCodable(store.state.rightPoints),
                    "sidesSwapped": AnyCodable(store.state.sidesSwapped),
                    "winByTwo": AnyCodable(store.state.rules.finalSetWinByTwo ?? store.state.rules.winByTwo)
                ]
                if let scoreCap = store.state.rules.finalSetPointCap {
                    data["scoreCap"] = AnyCodable(scoreCap)
                }
                data["isSingles"] = AnyCodable(store.state.doubles == nil)
                if let doubles = store.state.doubles {
                    let names = doubles.playerNames
                    data["playerNames"] = AnyCodable(names)
                    data["players"] = AnyCodable(names.map { ["name": $0] })
                    if names.indices.contains(3) {
                        data["team1Player1Name"] = AnyCodable(names[0])
                        data["team2Player1Name"] = AnyCodable(names[1])
                        data["team1Player2Name"] = AnyCodable(names[2])
                        data["team2Player2Name"] = AnyCodable(names[3])
                    }
                }
                return data
            }(),
            stateSnapshot: snapshot,
            status: finished ? .finished : .draft
        )

        do {
            try ScoreboardRecordManager.shared.saveScoreboardRecord(record)
            ScoreboardRecordsViewModel.shared.refreshRecords()
        } catch {
            #if DEBUG
            print("[RallyScoreboardView] Failed to save record: \(error)")
            #endif
        }
    }

    private struct DraftLoad {
        let state: RallyMatchState
        let startTime: Date
        let coreGameType: ScoreCore.GameType?
        let actions: [String]
        let voiceAnnouncementEnabled: Bool
    }

    private static func loadDraft(recordId: String) -> DraftLoad? {
        guard let record = ScoreboardRecordManager.shared.getRecordById(recordId),
              record.status == .draft,
              let data = record.stateSnapshot,
              let state = try? JSONDecoder().decode(RallyMatchState.self, from: data) else {
            return nil
        }
        let coreRaw = record.extraData?["coreGameType"]?.value as? String
        let coreGameType = coreRaw.flatMap { ScoreCore.GameType(rawValue: $0) }
        let voiceAnnouncementEnabled = record.extraData?["voiceAnnouncement"]?.value as? Bool ?? false
        return DraftLoad(
            state: state,
            startTime: record.startTime,
            coreGameType: coreGameType,
            actions: record.actions,
            voiceAnnouncementEnabled: voiceAnnouncementEnabled
        )
    }

    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }
}
