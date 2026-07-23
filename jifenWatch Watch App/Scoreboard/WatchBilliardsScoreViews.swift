import LinkCore
import ScoreCore
import SwiftUI

/// Compact dual-side board for eight-ball / snooker-style rack or frame scoring on Watch.
struct WatchEightBallScoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchLinkService.self) private var linkService

    let linkedSessionId: UUID?
    let leftName: String
    let rightName: String
    @State private var state: EightBallState
    @State private var showMenu = false
    @State private var matchStartTime = Date()
    @State private var didSaveFinishedRecord = false
    @State private var scoreboardLayout: String = "horizontal"
    @State private var undoStack: [EightBallState] = []

    init(
        initialState: EightBallState? = nil,
        linkedSessionId: UUID? = nil,
        leftName: String? = nil,
        rightName: String? = nil
    ) {
        let defaults = WatchDefaultTeamNames.resolve()
        self.linkedSessionId = linkedSessionId
        self.leftName = leftName ?? defaults.left
        self.rightName = rightName ?? defaults.right
        _state = State(initialValue: initialState ?? .initial())
    }

    private var scoringLocked: Bool { linkedSessionId != nil && linkService.isFollower }
    private var isHorizontal: Bool { scoreboardLayout == "horizontal" }

    var body: some View {
        ZStack {
            dualBoard(
                leftLabel: "\(state.leftPoints)",
                rightLabel: "\(state.rightPoints)",
                halfMeta: String(
                    format: NSLocalizedString("watch_eight_ball_target_format", value: "抢 %d", comment: ""),
                    state.targetPoints
                ),
                onLeft: { addRack(.left) },
                onRight: { addRack(.right) }
            )
            if showMenu { menuOverlay }
        }
        .onAppear {
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
            matchStartTime = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
        }
        .onChange(of: linkService.latestSnapshot) { _, update in
            guard let linkedSessionId, let update, update.sessionId == linkedSessionId,
                  let remote = update.snapshot.eightBallState else { return }
            state = remote
            undoStack.removeAll()
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
                        undo()
                        showMenu = false
                    }
                    WatchMenuGridButton(
                        title: NSLocalizedString("watch_menu_end_match", value: "结束比赛", comment: ""),
                        systemImage: "flag.checkered",
                        background: WatchTheme.dangerRed
                    ) {
                        finishMatch(manual: true)
                        showMenu = false
                    }
                    WatchMenuGridButton(
                        title: NSLocalizedString("watch_menu_restart", value: "重新开始", comment: ""),
                        systemImage: "arrow.counterclockwise"
                    ) {
                        restartMatch()
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

    private func addRack(_ side: MatchSide) {
        guard !scoringLocked, !state.finished else { return }
        let result = EightBallReducer().reduce(state: state, intent: .addRack(side), at: nowMs())
        guard result.accepted else { return }
        undoStack.append(state)
        state = result.state
        if state.finished {
            finishMatch(manual: false)
        } else {
            publish(manualEnd: false)
        }
    }

    private func finishMatch(manual: Bool) {
        if manual, !state.finished {
            state.finished = true
        }
        publish(manualEnd: manual)
        saveLocalRecordIfNeeded()
    }

    private func publish(manualEnd: Bool) {
        guard linkedSessionId != nil, linkService.isController else { return }
        linkService.publishSnapshot(.eightBall(state))
        if state.finished {
            linkService.publishMatchFinished(
                snapshot: .eightBall(state),
                recordId: "w_\(UUID().uuidString)",
                winnerSide: state.leftPoints == state.rightPoints
                    ? nil
                    : (state.leftPoints > state.rightPoints ? .left : .right),
                manualEnd: manualEnd,
                startTime: matchStartTime,
                endTime: Date(),
                totalScoreChanges: max(1, state.leftPoints + state.rightPoints)
            )
        }
    }

    private func saveLocalRecordIfNeeded() {
        guard linkedSessionId == nil, !didSaveFinishedRecord else { return }
        guard state.finished || state.leftPoints + state.rightPoints > 0 else { return }
        didSaveFinishedRecord = true
        let end = Date()
        let winnerName: String? = {
            if state.leftPoints == state.rightPoints { return nil }
            return state.leftPoints > state.rightPoints ? leftName : rightName
        }()
        let record = WatchScoreboardRecord(
            id: "w_\(UUID().uuidString)",
            gameType: .eightBall,
            startTime: matchStartTime,
            endTime: end,
            duration: end.timeIntervalSince(matchStartTime),
            team1Name: leftName,
            team2Name: rightName,
            team1FinalScore: state.leftPoints,
            team2FinalScore: state.rightPoints,
            team1SetScore: state.leftPoints,
            team2SetScore: state.rightPoints,
            winner: winnerName,
            actions: [],
            totalScoreChanges: max(1, state.leftPoints + state.rightPoints),
            projectConfiguration: [
                "targetRacks": String(state.targetPoints),
                "handicapRacks": String(state.handicapRacks),
                "handicapBeneficiary": state.handicapBeneficiary?.rawValue ?? "none"
            ]
        )
        WatchRecordManager.shared.saveRecord(record)
    }

    @ViewBuilder
    private func dualBoard(
        leftLabel: String,
        rightLabel: String,
        halfMeta: String,
        onLeft: @escaping () -> Void,
        onRight: @escaping () -> Void
    ) -> some View {
        Group {
            if isHorizontal {
                HStack(spacing: 0) {
                    scoreHalf(leftLabel, meta: halfMeta, color: Color(hex: 0xE53935), action: onLeft)
                    scoreHalf(rightLabel, meta: halfMeta, color: Color(hex: 0x1E88E5), action: onRight)
                }
            } else {
                VStack(spacing: 0) {
                    scoreHalf(leftLabel, meta: halfMeta, color: Color(hex: 0xE53935), action: onLeft)
                    scoreHalf(rightLabel, meta: halfMeta, color: Color(hex: 0x1E88E5), action: onRight)
                }
            }
        }
        .ignoresSafeArea()
        .disabled(scoringLocked)
        .gesture(boardGesture)
    }

    private var boardGesture: some Gesture {
        DragGesture(minimumDistance: 25, coordinateSpace: .local)
            .onEnded { value in
                guard !scoringLocked else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                if dx > 45, abs(dy) < 45 {
                    if linkedSessionId != nil { linkService.leaveSession() }
                    else { saveLocalRecordIfNeeded() }
                    dismiss()
                } else if dy > 35 {
                    undo()
                } else if dy < -35 {
                    showMenu = true
                }
            }
    }

    private func scoreHalf(_ text: String, meta: String, color: Color, action: @escaping () -> Void) -> some View {
        ZStack {
            Text(text)
                .font(.system(size: isHorizontal ? 56 : 62, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(meta)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, isHorizontal ? 22 : 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    private func normalizedLayout(_ raw: String) -> String {
        raw == "vertical" ? "vertical" : "horizontal"
    }

    private func undo() {
        guard !scoringLocked, let previous = undoStack.popLast() else { return }
        state = previous
        publish(manualEnd: false)
    }

    private func restartMatch() {
        guard !scoringLocked else { return }
        let result = EightBallReducer().reduce(state: state, intent: .reset, at: nowMs())
        guard result.accepted else { return }
        undoStack.append(state)
        state = result.state
        didSaveFinishedRecord = false
        matchStartTime = Date()
        publish(manualEnd: false)
    }

    private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }
}

struct WatchNineBallScoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchLinkService.self) private var linkService

    let linkedSessionId: UUID?
    @State private var state: NineBallChaseState
    @State private var showMenu = false
    @State private var matchStartTime = Date()
    @State private var didSaveFinishedRecord = false
    @State private var scoreboardLayout: String = "horizontal"
    @State private var undoStack: [NineBallChaseState] = []

    private static let playerColors: [Color] = [
        Color(hex: 0xE53935),
        Color(hex: 0x1E88E5),
        Color(hex: 0x43A047),
        Color(hex: 0x8E24AA)
    ]

    init(initialState: NineBallChaseState? = nil, linkedSessionId: UUID? = nil) {
        self.linkedSessionId = linkedSessionId
        _state = State(initialValue: initialState ?? .initial())
    }

    private var scoringLocked: Bool { linkedSessionId != nil && linkService.isFollower }
    private var isHorizontal: Bool { scoreboardLayout == "horizontal" }

    var body: some View {
        ZStack {
            playerLayout
            if showMenu { menuOverlay }
        }
        .disabled(scoringLocked)
        .onAppear {
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
            matchStartTime = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
        }
        .gesture(boardGesture)
        .onChange(of: linkService.latestSnapshot) { _, update in
            guard let linkedSessionId, let update, update.sessionId == linkedSessionId,
                  let remote = update.snapshot.nineBallState else { return }
            state = remote
            undoStack.removeAll()
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
                        undo()
                        showMenu = false
                    }
                    WatchMenuGridButton(
                        title: NSLocalizedString("watch_menu_end_match", value: "结束比赛", comment: ""),
                        systemImage: "flag.checkered",
                        background: WatchTheme.dangerRed
                    ) {
                        finishMatch()
                        showMenu = false
                    }
                    WatchMenuGridButton(
                        title: NSLocalizedString("watch_menu_restart", value: "重新开始", comment: ""),
                        systemImage: "arrow.counterclockwise"
                    ) {
                        restartMatch()
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

    private var boardGesture: some Gesture {
        DragGesture(minimumDistance: 25, coordinateSpace: .local)
            .onEnded { value in
                guard !scoringLocked else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                if dx > 45, abs(dy) < 45 {
                    if linkedSessionId != nil { linkService.leaveSession() }
                    else { saveLocalRecordIfNeeded() }
                    dismiss()
                } else if dy > 35 {
                    undo()
                } else if dy < -35 {
                    showMenu = true
                }
            }
    }

    @ViewBuilder
    private var playerLayout: some View {
        switch state.playerCount {
        case 3:
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { index in
                    playerZone(index)
                }
            }
            .ignoresSafeArea()
        case 4:
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    playerZone(0)
                    playerZone(1)
                }
                HStack(spacing: 0) {
                    playerZone(2)
                    playerZone(3)
                }
            }
            .ignoresSafeArea()
        default:
            Group {
                if isHorizontal {
                    HStack(spacing: 0) {
                        playerZone(0)
                        playerZone(1)
                    }
                } else {
                    VStack(spacing: 0) {
                        playerZone(0)
                        playerZone(1)
                    }
                }
            }
            .ignoresSafeArea()
        }
    }

    private func playerZone(_ index: Int) -> some View {
        let scoreFont: CGFloat = state.playerCount == 4 ? 34 : (state.playerCount == 3 ? 40 : 56)
        let nameFont: CGFloat = state.playerCount > 2 ? 11 : 13
        return VStack(spacing: state.playerCount > 2 ? 4 : 6) {
            Text(displayName(at: index))
                .font(.system(size: nameFont, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(playerPoints(at: index))")
                .font(.system(size: scoreFont, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .offset(y: state.playerCount == 4 && index == 1 ? 18 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(index < Self.playerColors.count ? Self.playerColors[index] : .gray)
        .contentShape(Rectangle())
        .onTapGesture {
            apply(.deltaTotal(player: index, delta: 1))
        }
    }

    private func displayName(at index: Int) -> String {
        let fallback = String.localizedStringWithFormat(
            NSLocalizedString("multi_score_player_default_format", value: "玩家 %d", comment: ""),
            index + 1
        )
        return state.resolvedName(at: index, fallback: fallback)
    }

    private func apply(_ intent: NineBallChaseIntent) {
        guard !scoringLocked else { return }
        let result = NineBallChaseReducer().reduce(state: state, intent: intent, at: nowMs())
        guard result.accepted else { return }
        undoStack.append(state)
        state = result.state
        publish()
        if state.finished {
            saveLocalRecordIfNeeded()
        }
    }

    private func finishMatch() {
        guard !state.finished else {
            saveLocalRecordIfNeeded()
            return
        }
        state.finished = true
        publish()
        if linkedSessionId != nil, linkService.isController {
            linkService.publishMatchFinished(
                snapshot: .nineBall(state),
                recordId: "w_\(UUID().uuidString)",
                winnerSide: winnerSide(),
                manualEnd: true,
                startTime: matchStartTime,
                endTime: Date(),
                totalScoreChanges: max(1, (0..<state.playerCount).reduce(0) { $0 + playerPoints(at: $1) })
            )
        }
        saveLocalRecordIfNeeded()
    }

    private func publish() {
        guard linkedSessionId != nil, linkService.isController else { return }
        linkService.publishSnapshot(.nineBall(state))
    }

    private func winnerSide() -> MatchSide? {
        guard state.playerCount <= 2 else { return nil }
        let left = playerPoints(at: 0)
        let right = playerPoints(at: 1)
        if left == right { return nil }
        return left > right ? .left : .right
    }

    private func saveLocalRecordIfNeeded() {
        guard linkedSessionId == nil, !didSaveFinishedRecord else { return }
        let total = (0..<state.playerCount).reduce(0) { $0 + playerPoints(at: $1) }
        guard state.finished || total > 0 else { return }
        didSaveFinishedRecord = true
        let end = Date()
        let leftName = displayName(at: 0)
        let rightName = state.playerCount > 1 ? displayName(at: 1) : WatchDefaultTeamNames.resolve().right
        let leftScore = playerPoints(at: 0)
        let rightScore = state.playerCount > 1 ? playerPoints(at: 1) : 0
        let winnerName: String? = {
            if state.playerCount > 2 {
                let best = (0..<state.playerCount).max(by: { playerPoints(at: $0) < playerPoints(at: $1) })
                return best.map { displayName(at: $0) }
            }
            if leftScore == rightScore { return nil }
            return leftScore > rightScore ? leftName : rightName
        }()
        let record = WatchScoreboardRecord(
            id: "w_\(UUID().uuidString)",
            gameType: .nineBall,
            startTime: matchStartTime,
            endTime: end,
            duration: end.timeIntervalSince(matchStartTime),
            team1Name: leftName,
            team2Name: rightName,
            team1FinalScore: leftScore,
            team2FinalScore: rightScore,
            team1SetScore: leftScore,
            team2SetScore: rightScore,
            winner: winnerName,
            actions: [],
            totalScoreChanges: max(1, total),
            participants: (0..<state.playerCount).map {
                WatchRecordParticipant(name: displayName(at: $0), score: playerPoints(at: $0))
            },
            projectConfiguration: ["playerCount": String(state.playerCount)]
        )
        WatchRecordManager.shared.saveRecord(record)
    }

    private func normalizedLayout(_ raw: String) -> String {
        raw == "vertical" ? "vertical" : "horizontal"
    }

    private func undo() {
        guard !scoringLocked, let previous = undoStack.popLast() else { return }
        state = previous
        publish()
    }

    private func restartMatch() {
        guard !scoringLocked else { return }
        let result = NineBallChaseReducer().reduce(state: state, intent: .resetScores, at: nowMs())
        guard result.accepted else { return }
        undoStack.append(state)
        state = result.state
        didSaveFinishedRecord = false
        matchStartTime = Date()
        publish()
    }

    private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }

    private func playerPoints(at index: Int) -> Int {
        guard state.playerPoints.indices.contains(index) else { return 0 }
        return state.playerPoints[index]
    }
}

struct WatchSnookerScoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchLinkService.self) private var linkService

    let linkedSessionId: UUID?
    let leftName: String
    let rightName: String
    @State private var state: SnookerState
    @State private var showMenu = false
    @State private var matchStartTime = Date()
    @State private var didSaveFinishedRecord = false
    @State private var scoreboardLayout: String = "horizontal"
    @State private var undoStack: [SnookerState] = []

    init(
        initialState: SnookerState? = nil,
        linkedSessionId: UUID? = nil,
        leftName: String? = nil,
        rightName: String? = nil
    ) {
        let defaults = WatchDefaultTeamNames.resolve()
        self.linkedSessionId = linkedSessionId
        self.leftName = leftName ?? defaults.left
        self.rightName = rightName ?? defaults.right
        _state = State(initialValue: initialState ?? SnookerState.initial())
    }

    private var scoringLocked: Bool { linkedSessionId != nil && linkService.isFollower }
    private var isHorizontal: Bool { scoreboardLayout == "horizontal" }

    var body: some View {
        ZStack {
            Group {
                if isHorizontal {
                    HStack(spacing: 0) {
                        scoreHalf(.left)
                        scoreHalf(.right)
                    }
                } else {
                    VStack(spacing: 0) {
                        scoreHalf(.left)
                        scoreHalf(.right)
                    }
                }
            }
            .ignoresSafeArea()
            if showMenu { menuOverlay }
        }
        .disabled(scoringLocked)
        .onAppear {
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
            matchStartTime = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = normalizedLayout(WatchPreferences.shared.scoreboardLayout)
        }
        .gesture(boardGesture)
        .onChange(of: linkService.latestSnapshot) { _, update in
            guard let linkedSessionId, let update, update.sessionId == linkedSessionId,
                  let remote = update.snapshot.snookerState else { return }
            state = remote
            undoStack.removeAll()
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
                        undo()
                        showMenu = false
                    }
                    WatchMenuGridButton(
                        title: NSLocalizedString("watch_menu_end_match", value: "结束比赛", comment: ""),
                        systemImage: "flag.checkered",
                        background: WatchTheme.dangerRed
                    ) {
                        finishMatch()
                        showMenu = false
                    }
                    WatchMenuGridButton(
                        title: NSLocalizedString("watch_menu_restart", value: "重新开始", comment: ""),
                        systemImage: "arrow.counterclockwise"
                    ) {
                        restartMatch()
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

    private var boardGesture: some Gesture {
        DragGesture(minimumDistance: 25, coordinateSpace: .local)
            .onEnded { value in
                guard !scoringLocked else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                if dx > 45, abs(dy) < 45 {
                    if linkedSessionId != nil { linkService.leaveSession() }
                    else { saveLocalRecordIfNeeded() }
                    dismiss()
                } else if dy > 35 {
                    undo()
                } else if dy < -35 {
                    showMenu = true
                }
            }
    }

    private func scoreHalf(_ side: MatchSide) -> some View {
        let isLeft = side == .left
        let score = isLeft ? state.leftScore : state.rightScore
        let frames = isLeft ? state.leftFrames : state.rightFrames
        let color = isLeft ? Color(hex: 0xE53935) : Color(hex: 0x1E88E5)
        return ZStack {
            Text("\(score)")
                .font(.system(size: isHorizontal ? 56 : 62, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(String(
                format: NSLocalizedString("watch_snooker_frames_format", value: "局 %d", comment: ""),
                frames
            ))
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, isHorizontal ? 22 : 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color)
        .contentShape(Rectangle())
        .onTapGesture {
            apply(.potBallAsSide(side: side, points: 1))
        }
    }

    private func apply(_ intent: SnookerIntent) {
        guard !scoringLocked else { return }
        let result = SnookerReducer().reduce(state: state, intent: intent, at: nowMs())
        guard result.accepted else { return }
        undoStack.append(state)
        state = result.state
        publish()
        if state.finished {
            saveLocalRecordIfNeeded()
        }
    }

    private func finishMatch() {
        let result = SnookerReducer().reduce(state: state, intent: .finishMatch, at: nowMs())
        state = result.state
        publish()
        if state.finished {
            if linkedSessionId != nil, linkService.isController {
                linkService.publishMatchFinished(
                    snapshot: .snooker(state),
                    recordId: "w_\(UUID().uuidString)",
                    winnerSide: state.leftFrames == state.rightFrames
                        ? nil
                        : (state.leftFrames > state.rightFrames ? .left : .right),
                    manualEnd: true,
                    startTime: matchStartTime,
                    endTime: Date(),
                    totalScoreChanges: max(1, state.leftScore + state.rightScore)
                )
            }
            saveLocalRecordIfNeeded()
        }
    }

    private func publish() {
        guard linkedSessionId != nil, linkService.isController else { return }
        linkService.publishSnapshot(.snooker(state))
    }

    private func saveLocalRecordIfNeeded() {
        guard linkedSessionId == nil, !didSaveFinishedRecord else { return }
        guard state.finished || state.leftScore + state.rightScore + state.leftFrames + state.rightFrames > 0 else { return }
        didSaveFinishedRecord = true
        let end = Date()
        let winnerName: String? = {
            if state.leftFrames != state.rightFrames {
                return state.leftFrames > state.rightFrames ? leftName : rightName
            }
            if state.leftScore == state.rightScore { return nil }
            return state.leftScore > state.rightScore ? leftName : rightName
        }()
        let record = WatchScoreboardRecord(
            id: "w_\(UUID().uuidString)",
            gameType: .snooker,
            startTime: matchStartTime,
            endTime: end,
            duration: end.timeIntervalSince(matchStartTime),
            team1Name: leftName,
            team2Name: rightName,
            team1FinalScore: state.leftScore,
            team2FinalScore: state.rightScore,
            team1SetScore: state.leftFrames,
            team2SetScore: state.rightFrames,
            winner: winnerName,
            actions: [],
            totalScoreChanges: max(1, state.leftScore + state.rightScore),
            projectConfiguration: ["maxFrames": String(state.maxFrames)]
        )
        WatchRecordManager.shared.saveRecord(record)
    }

    private func normalizedLayout(_ raw: String) -> String {
        raw == "vertical" ? "vertical" : "horizontal"
    }

    private func undo() {
        guard !scoringLocked, let previous = undoStack.popLast() else { return }
        state = previous
        publish()
    }

    private func restartMatch() {
        guard !scoringLocked else { return }
        undoStack.append(state)
        state = .initial(striker: state.firstBreaker, maxFrames: state.maxFrames)
        didSaveFinishedRecord = false
        matchStartTime = Date()
        publish()
    }

    private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }
}
