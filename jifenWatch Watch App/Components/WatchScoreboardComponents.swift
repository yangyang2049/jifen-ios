import ScoreCore
import SwiftUI

private struct WatchScoreboardAlwaysOnModifier: ViewModifier {
    @AppStorage(WatchPreferences.scoreboardKeepScreenOnKey) private var keepScreenOn = true
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    func body(content: Content) -> some View {
        content
            .overlay {
                if !keepScreenOn && isLuminanceReduced {
                    Color.black
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { }
                        .accessibilityHidden(true)
                }
            }
    }
}

extension View {
    func watchScoreboardAlwaysOn() -> some View {
        modifier(WatchScoreboardAlwaysOnModifier())
    }
}

enum WatchScoreboardConfirmation: String, Identifiable {
    case finish
    case reset

    var id: String { rawValue }
}

struct WatchRestState: Codable, Equatable {
    enum Kind: String, Codable, Equatable {
        case midGame
        case betweenSets
        case archerySet
    }

    let kind: Kind
    let title: String
    let durationSeconds: Int
    let startedAt: Date
    let triggerID: String
    let countUp: Bool?

    init(
        kind: Kind,
        title: String,
        durationSeconds: Int,
        startedAt: Date = Date(),
        triggerID: String,
        countUp: Bool? = nil
    ) {
        self.kind = kind
        self.title = title
        self.durationSeconds = max(0, durationSeconds)
        self.startedAt = startedAt
        self.triggerID = triggerID
        self.countUp = countUp
    }

    func remainingSeconds(at date: Date = Date()) -> Int {
        max(0, durationSeconds - elapsedSeconds(at: date))
    }

    func elapsedSeconds(at date: Date) -> Int {
        Int(max(0, date.timeIntervalSince(startedAt)).rounded(.down))
    }

    func officialBreakState(for gameType: GameType) -> OfficialBreakState? {
        let sport: OfficialBreakSport
        switch gameType {
        case .badminton, .badmintonDoubles:
            sport = .badminton
        case .pingpong, .pingpongDoubles:
            sport = .pingpong
        case .pickleball, .pickleballDoubles:
            sport = .pickleball
        case .shuttlecock:
            sport = .shuttlecock
        case .squash:
            sport = .squash
        case .tennis, .tennisDoubles:
            sport = .tennis
        default:
            return nil
        }

        let breakKind: OfficialBreakKind
        let afterAction: OfficialBreakAfterAction
        switch kind {
        case .midGame:
            breakKind = .midGame
            afterAction = .none
        case .betweenSets:
            breakKind = sport == .tennis ? .setBreak : .gameBreak
            afterAction = .advanceAndExchange
        case .archerySet:
            return nil
        }

        return OfficialBreakState(
            sport: sport,
            kind: breakKind,
            durationSeconds: durationSeconds,
            source: .official,
            afterAction: afterAction,
            nowMilliseconds: Int64(startedAt.timeIntervalSince1970 * 1_000)
        )
    }

    static func fromOfficialBreak(
        _ state: OfficialBreakState?,
        now: Date = Date()
    ) -> WatchRestState? {
        guard let state, state.isRunning else { return nil }
        let startedAt: Date
        if state.startedWallClockMilliseconds > 0 {
            startedAt = Date(
                timeIntervalSince1970: TimeInterval(state.startedWallClockMilliseconds) / 1_000
            )
        } else {
            let elapsed = max(0, state.durationSeconds - state.remainingSeconds)
            startedAt = now.addingTimeInterval(-TimeInterval(elapsed))
        }
        let kind: Kind
        let title: String
        switch state.kind {
        case .midGame:
            kind = .midGame
            title = NSLocalizedString("watch_mid_game_rest", value: "局中休息", comment: "")
        case .gameBreak, .setBreak:
            kind = .betweenSets
            title = NSLocalizedString("watch_rest_between_sets", value: "局间休息", comment: "")
        case .changeover:
            kind = .midGame
            title = NSLocalizedString("watch_side_exchange", value: "交换场地", comment: "")
        case .timeout:
            kind = .midGame
            title = state.title ?? NSLocalizedString("watch_official_timeout", value: "暂停", comment: "")
        case .medical:
            kind = .midGame
            title = state.title ?? NSLocalizedString("watch_medical_break", value: "医疗中断", comment: "")
        }
        return WatchRestState(
            kind: kind,
            title: title,
            durationSeconds: max(0, state.durationSeconds),
            startedAt: startedAt,
            triggerID: "remote-\(state.kind.rawValue)-\(state.startedWallClockMilliseconds)",
            countUp: state.countUp ? true : nil
        )
    }
}

enum WatchRestPolicy {
    static func betweenSetDuration(for gameType: GameType) -> Int? {
        switch gameType {
        case .pingpong, .pingpongDoubles, .foosball, .foosballDoubles:
            return 60
        case .badminton, .badmintonDoubles,
             .shuttlecock, .squash,
             .pickleball, .pickleballDoubles,
             .tennis, .tennisDoubles:
            return 120
        default:
            return nil
        }
    }

    static func badmintonMidGamePoint(pointsToWinSet: Int) -> Int {
        max(1, (max(1, pointsToWinSet) + 1) / 2)
    }
}

struct WatchRallyCompletedSetPresentation: Equatable {
    let setNumber: Int
    let leftPoints: Int
    let rightPoints: Int
    let leftSets: Int
    let rightSets: Int
    let sidesSwapped: Bool

    static func resolve(
        events: [RallyMatchEvent],
        currentSidesSwapped: Bool
    ) -> Self? {
        guard let completed = events.reversed().compactMap({ event -> Self? in
            guard case let .setCompleted(
                _, setNumber, leftPoints, rightPoints, leftSets, rightSets
            ) = event else { return nil }
            return Self(
                setNumber: setNumber,
                leftPoints: leftPoints,
                rightPoints: rightPoints,
                leftSets: leftSets,
                rightSets: rightSets,
                sidesSwapped: currentSidesSwapped
            )
        }).first else { return nil }

        let exchangedAfterSet = events.contains { event in
            if case .sidesExchanged = event { return true }
            return false
        }
        guard exchangedAfterSet else { return completed }
        return Self(
            setNumber: completed.setNumber,
            leftPoints: completed.leftPoints,
            rightPoints: completed.rightPoints,
            leftSets: completed.leftSets,
            rightSets: completed.rightSets,
            sidesSwapped: !currentSidesSwapped
        )
    }
}

struct WatchTennisCompletedSetPresentation: Equatable {
    let setNumber: Int
    let leftGames: Int
    let rightGames: Int
    let leftSets: Int
    let rightSets: Int
    let sidesSwapped: Bool

    static func resolve(
        events: [TennisMatchEvent],
        currentSidesSwapped: Bool
    ) -> Self? {
        guard let completed = events.reversed().compactMap({ event -> Self? in
            guard case let .setCompleted(
                _, setNumber, leftGames, rightGames, leftSets, rightSets
            ) = event else { return nil }
            return Self(
                setNumber: setNumber,
                leftGames: leftGames,
                rightGames: rightGames,
                leftSets: leftSets,
                rightSets: rightSets,
                sidesSwapped: currentSidesSwapped
            )
        }).first else { return nil }

        let exchangedAfterSet = events.contains { event in
            if case .sidesExchanged = event { return true }
            return false
        }
        guard exchangedAfterSet else { return completed }
        return Self(
            setNumber: completed.setNumber,
            leftGames: completed.leftGames,
            rightGames: completed.rightGames,
            leftSets: completed.leftSets,
            rightSets: completed.rightSets,
            sidesSwapped: !currentSidesSwapped
        )
    }
}

struct WatchRestTriggerRegistry: Equatable {
    private(set) var consumedTriggerIDs: Set<String> = []

    mutating func consume(_ triggerID: String) -> Bool {
        consumedTriggerIDs.insert(triggerID).inserted
    }

    mutating func release(_ triggerID: String) {
        consumedTriggerIDs.remove(triggerID)
    }

    mutating func reset() {
        consumedTriggerIDs.removeAll()
    }
}

enum WatchTennisDoublesServing {
    static func serverSlot(
        firstServer: MatchSide,
        completedGames: Int,
        isTieBreak: Bool,
        tieBreakPointsPlayed: Int
    ) -> Int {
        TennisDoublesServing.serverSlot(
            firstServerSlot: firstServer == .left ? 0 : 1,
            completedGames: completedGames,
            isTieBreak: isTieBreak,
            tieBreakPointsPlayed: tieBreakPointsPlayed
        )
    }
}

/// Sport-specific menu entry rendered as a full-width row above "结束比赛".
struct WatchMenuExtraAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var assetImage: String? = nil
    var background: Color = WatchTheme.card
    let action: () -> Void
}

/// Full-bleed watchOS overlay container.
/// Uses `GeometryReader` + safe-area offset so overlays cover 100% of the watch
/// display (no bottom black band) and never push the underlying scoreboard ZStack.
struct WatchFullScreenOverlay<Content: View>: View {
    let scrim: Color
    var onBackgroundTap: (() -> Void)? = nil
    @ViewBuilder let content: (_ fullSize: CGSize, _ safeAreaInsets: EdgeInsets) -> Content

    var body: some View {
        GeometryReader { proxy in
            let fullWidth = proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing
            let fullHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            ZStack {
                if let onBackgroundTap {
                    scrim
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onBackgroundTap)
                } else {
                    scrim
                }
                content(CGSize(width: fullWidth, height: fullHeight), proxy.safeAreaInsets)
                    .frame(width: fullWidth, height: fullHeight)
            }
            .frame(width: fullWidth, height: fullHeight)
            .offset(x: -proxy.safeAreaInsets.leading, y: -proxy.safeAreaInsets.top)
        }
        .ignoresSafeArea()
    }
}

struct WatchScoreboardMenuOverlay: View {
    let onDismiss: () -> Void
    let onUndo: () -> Void
    let onFinish: () -> Void
    let onReset: () -> Void
    var onReclaim: (() -> Void)? = nil
    var extraActions: [WatchMenuExtraAction] = []

    var body: some View {
        let compact = WatchLayout.isCompactScreen
        let gridSpacing: CGFloat = compact ? 5 : 6
        let needsScroll = extraActions.count > 1 || (onReclaim != nil && !extraActions.isEmpty)
        let menuContent = VStack(spacing: compact ? 5 : 6) {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: gridSpacing
            ) {
                WatchMenuGridButton(
                    title: NSLocalizedString("menu_undo", value: "撤销", comment: ""),
                    systemImage: "arrow.uturn.backward",
                    action: onUndo
                )
                WatchMenuGridButton(
                    title: NSLocalizedString("watch_menu_restart", value: "重新开始", comment: ""),
                    systemImage: "arrow.counterclockwise",
                    action: onReset
                )
                if extraActions.count == 1, let onlyExtra = extraActions.first {
                    WatchMenuGridButton(
                        title: onlyExtra.title,
                        systemImage: onlyExtra.systemImage,
                        assetImage: onlyExtra.assetImage,
                        background: onlyExtra.background,
                        action: onlyExtra.action
                    )
                    WatchMenuGridButton(
                        title: NSLocalizedString("watch_menu_end_match", value: "结束比赛", comment: ""),
                        systemImage: "flag.checkered",
                        background: WatchTheme.dangerRed,
                        action: onFinish
                    )
                }
            }

            if extraActions.count != 1 {
                ForEach(extraActions) { extra in
                    WatchMenuGridButton(
                        title: extra.title,
                        systemImage: extra.systemImage,
                        assetImage: extra.assetImage,
                        background: extra.background,
                        action: extra.action
                    )
                }

                WatchMenuGridButton(
                    title: NSLocalizedString("watch_menu_end_match", value: "结束比赛", comment: ""),
                    systemImage: "flag.checkered",
                    background: WatchTheme.dangerRed,
                    action: onFinish
                )
            }

            if let onReclaim {
                WatchMenuGridButton(
                    title: NSLocalizedString("linked_score_watch_reclaim", value: "手表接管", comment: ""),
                    systemImage: "applewatch.radiowaves.left.and.right",
                    background: WatchTheme.successGreen,
                    action: onReclaim
                )
            }
        }
        return WatchFullScreenOverlay(
            scrim: WatchTheme.panelScrim,
            onBackgroundTap: onDismiss
        ) { _, _ in
            VStack(spacing: compact ? 6 : 8) {
                if needsScroll {
                    ScrollView {
                        menuContent
                            .padding(.top, compact ? 28 : 36)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    Spacer(minLength: compact ? 28 : 38)
                    menuContent
                }

                WatchMenuCloseButton(action: onDismiss)
            }
            .padding(.horizontal, compact ? 14 : 20)
            .padding(.bottom, compact ? 8 : 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

struct WatchConfirmationOverlay: View {
    let confirmation: WatchScoreboardConfirmation
    var titleOverride: String?
    var messageOverride: String?
    var backdropOpacity: Double? = nil
    var cardOpacity: Double? = nil
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var resolvedBackdropOpacity: Double {
        backdropOpacity ?? (confirmation == .finish ? 0.40 : 0.72)
    }

    private var resolvedCardOpacity: Double {
        cardOpacity ?? (confirmation == .finish ? 0.62 : 1.0)
    }

    private var title: String {
        if let titleOverride { return titleOverride }
        return switch confirmation {
        case .finish:
            NSLocalizedString("watch_finish_confirm_title", value: "结束比赛？", comment: "")
        case .reset:
            NSLocalizedString("watch_reset_confirm_title", value: "重新开始？", comment: "")
        }
    }

    private var message: String {
        if let messageOverride { return messageOverride }
        return switch confirmation {
        case .finish:
            NSLocalizedString("watch_finish_confirm_message", value: "将结束并保存本场比赛。", comment: "")
        case .reset:
            NSLocalizedString("watch_reset_confirm_message", value: "当前比分将被清空。", comment: "")
        }
    }

    var body: some View {
        let compact = WatchLayout.isCompactScreen
        let combinedScrimOpacity = 1 - (1 - resolvedBackdropOpacity) * (1 - resolvedCardOpacity)
        WatchFullScreenOverlay(scrim: Color.black.opacity(combinedScrimOpacity)) { _, _ in
            VStack(spacing: compact ? 8 : 10) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                HStack(spacing: compact ? 20 : 24) {
                    confirmationIconButton(
                        systemImage: "xmark",
                        background: Color(hex: 0x636366),
                        accessibilityLabel: NSLocalizedString("cancel", value: "取消", comment: ""),
                        action: onCancel
                    )
                    confirmationIconButton(
                        systemImage: "checkmark",
                        background: WatchTheme.dangerRed,
                        accessibilityLabel: NSLocalizedString("confirm", value: "确认", comment: ""),
                        action: onConfirm
                    )
                }
                .padding(.top, compact ? 8 : 12)
            }
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.top, compact ? 18 : 24)
            .padding(.bottom, compact ? 8 : 12)
        }
    }

    private func confirmationIconButton(
        systemImage: String,
        background: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(
                    size: WatchLayout.isCompactScreen ? 17 : 19,
                    weight: .bold
                ))
                .foregroundStyle(.white)
                .frame(
                    width: WatchLayout.isCompactScreen ? 42 : 46,
                    height: WatchLayout.isCompactScreen ? 42 : 46
                )
                .background(background)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct WatchRestOverlay: View {
    let state: WatchRestState
    var isReadOnly: Bool = false
    let onContinue: () -> Void
    let onUndo: () -> Void

    var body: some View {
        let compact = WatchLayout.isCompactScreen
        WatchFullScreenOverlay(scrim: Color.black.opacity(0.76)) { _, _ in
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let remaining = state.remainingSeconds(at: context.date)
                let elapsed = state.elapsedSeconds(at: context.date)
                VStack(spacing: compact ? 7 : 10) {
                    Text(state.title)
                        .font(.system(size: compact ? 16 : 19, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)
                    Text(Self.timeText(state.countUp == true ? elapsed : remaining))
                        .font(.system(size: compact ? 30 : 36, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(WatchTheme.timerAccent)
                    if !isReadOnly {
                        VStack(spacing: compact ? 6 : 8) {
                            restActionButton(
                                title: remaining == 0 && state.countUp != true
                                    ? NSLocalizedString("watch_continue_match", value: "继续比赛", comment: "")
                                    : NSLocalizedString("watch_continue", value: "继续", comment: ""),
                                background: WatchTheme.accent,
                                action: onContinue
                            )
                            if state.countUp != true {
                                restActionButton(
                                    title: NSLocalizedString("menu_undo", value: "撤销", comment: ""),
                                    background: WatchTheme.card,
                                    action: onUndo
                                )
                            }
                        }
                        .padding(.top, compact ? 2 : 4)
                    }
                }
                .padding(.horizontal, compact ? 10 : 16)
                .padding(.top, compact ? 26 : 34)
                .padding(.bottom, compact ? 10 : 14)
            }
        }
    }

    private func restActionButton(
        title: String,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        let compact = WatchLayout.isCompactScreen
        return Button(action: action) {
            Text(title)
                .font(.system(size: compact ? 14 : 15, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity)
                .frame(height: compact ? 36 : 40)
                .background(background)
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(width: WatchLayout.overlayActionButtonWidth)
    }

    static func timeText(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        return String(format: "%02d:%02d", safe / 60, safe % 60)
    }
}

struct WatchFinishedScoreItem {
    let names: [String]
    let score: Int

    init(name: String, score: Int, doublesNames: [String]? = nil, side: MatchSide = .left) {
        self.score = score
        guard let doublesNames, doublesNames.count == 4 else {
            names = [name]
            return
        }
        // Doubles slots are ordered left A, right A, left B, right B.
        let firstSlot = side == .left ? 0 : 1
        let players = [doublesNames[firstSlot], doublesNames[firstSlot + 2]]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        names = players.isEmpty ? [name] : players
    }
}

struct WatchUndoCountdownStroke: View {
    let deadline: Date
    let duration: TimeInterval

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let remaining = Self.remainingFraction(
                deadline: deadline,
                now: context.date,
                duration: duration
            )
            ZStack {
                Capsule()
                    .stroke(Color.white.opacity(0.18), lineWidth: 2)
                Capsule()
                    .trim(from: 0, to: remaining)
                    .stroke(
                        WatchTheme.timerAccent,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func remainingFraction(
        deadline: Date,
        now: Date,
        duration: TimeInterval
    ) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, deadline.timeIntervalSince(now) / duration))
    }
}

struct WatchFinishedOverlay: View {
    enum Winner {
        case highestScore
        case side(MatchSide?)
    }

    let title: String
    let scoreItems: [WatchFinishedScoreItem]
    var winner: Winner = .highestScore
    let undoAvailable: Bool
    var canPlayAgain = true
    let onUndo: () -> Void
    let onPlayAgain: () -> Void
    let onExit: () -> Void
    @State private var undoDeadline: Date = .distantPast

    private static let actionHeight: CGFloat = 44
    private static let gold = Color(hex: 0xFFD285)
    private static let teamAccents = [
        WatchTheme.teamRed, WatchTheme.teamBlue, Color(hex: 0x81DB99), Color(hex: 0xD5A4FF)
    ]

    var body: some View {
        WatchFullScreenOverlay(scrim: WatchTheme.background) { size, safeArea in
            let compact = WatchLayout.isNarrowScreen(width: size.width)
            VStack(spacing: compact ? 6 : 9) {
                ViewThatFits(in: .vertical) {
                    summary(compact: compact, dense: false)
                    summary(compact: compact, dense: true)
                    ScrollView {
                        summary(compact: compact, dense: true)
                    }
                }
                .frame(maxHeight: .infinity)
                actions(compact: compact)
            }
            .padding(.horizontal, compact ? 12 : 18)
            .padding(.top, max(safeArea.top, compact ? 30 : 36))
            .padding(.bottom, max(safeArea.bottom, compact ? 14 : 18))
        }
        .onAppear {
            resetUndoDeadlineIfNeeded()
        }
        .onChange(of: undoAvailable) { _, isAvailable in
            if isAvailable {
                resetUndoDeadlineIfNeeded()
            }
        }
    }

    private var winningIndex: Int? {
        switch winner {
        case .highestScore:
            guard let best = scoreItems.map(\.score).max() else { return nil }
            let leaders = scoreItems.indices.filter { scoreItems[$0].score == best }
            return leaders.count == 1 ? leaders.first : nil
        case .side(let side):
            return side.map { $0 == .left ? 0 : 1 }
        }
    }

    private func summary(compact: Bool, dense: Bool) -> some View {
        let winner = winningIndex
        return VStack(alignment: .leading, spacing: dense ? 4 : (compact ? 5 : 7)) {
            Text(title)
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0xBFC0C9))
                .padding(.leading, 7)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("watch_finished_title")

            VStack(spacing: 0) {
                ForEach(scoreItems.indices, id: \.self) { index in
                    if index > 0 {
                        Rectangle()
                            .fill(.white.opacity(0.16))
                            .frame(height: 1)
                            .accessibilityHidden(true)
                    }
                    scoreRow(index: index, isWinner: index == winner, compact: compact, dense: dense)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scoreRow(index: Int, isWinner: Bool, compact: Bool, dense: Bool) -> some View {
        let item = scoreItems[index]
        let accent = Self.teamAccents[index % Self.teamAccents.count]
        let shortNames = item.names.allSatisfy { $0.count <= 4 }
        let manyPlayers = scoreItems.count > 2
        let nameSize: CGFloat = dense && compact ? 9 : (manyPlayers ? 10 : (compact ? 11 : 12))
        let scoreSize: CGFloat = manyPlayers ? 16 : (compact ? 23 : 28)
        return HStack(spacing: 5) {
            VStack(alignment: .leading, spacing: dense ? 0 : 1) {
                ForEach(item.names.indices, id: \.self) { nameIndex in
                    let name = item.names[nameIndex]
                    Text(name)
                        .font(.system(size: nameSize, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xE1E1E8))
                        .lineLimit(compact ? 1 : 2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(Text(verbatim: name))
                        .accessibilityIdentifier("watch_finished_name_\(index)_\(nameIndex)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 7)
            .padding(.trailing, 35)
            .overlay(alignment: .trailing) {
                if isWinner {
                    winnerStamp
                        .frame(width: 33)
                        .padding(.trailing, shortNames ? 12 : 1)
                }
            }

            Text(String(item.score))
                .font(WatchScoreTypography.primaryScore(size: scoreSize))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(width: compact ? 32 : 40, alignment: .trailing)
                .accessibilityIdentifier("watch_finished_score_\(index)")
        }
        .padding(.vertical, dense || manyPlayers ? 0 : (compact ? 3 : 5))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(accent)
                .frame(width: 2)
                .padding(.vertical, 3)
                .accessibilityHidden(true)
        }
    }

    private var winnerStamp: some View {
        Text(NSLocalizedString("watch_finished_win_badge", value: "胜", comment: "Short winner stamp"))
            .font(.system(size: 9, weight: .heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(Self.gold)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color(hex: 0x221A0E), in: RoundedRectangle(cornerRadius: 2))
            .overlay(alignment: .top) {
                Rectangle().fill(Self.gold).frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Self.gold).frame(height: 1)
            }
            .rotationEffect(.degrees(-5))
            .accessibilityLabel(NSLocalizedString("watch_finished_winner", value: "胜方", comment: "Winner stamp accessibility label"))
            .accessibilityIdentifier("watch_finished_winner_badge")
            .allowsHitTesting(false)
    }

    private func actions(compact: Bool) -> some View {
        HStack(spacing: 6) {
            Button(action: onExit) {
                Image(systemName: "house")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Self.actionHeight, height: Self.actionHeight)
                    .background(WatchTheme.card, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("watch_finished_home", value: "返回首页", comment: "Leave the finished match and return home"))
            .accessibilityIdentifier("watch_finished_home")

            if undoAvailable && canPlayAgain {
                finishedActionButton(
                    title: NSLocalizedString("menu_undo", value: "撤销", comment: ""),
                    compact: compact,
                    background: WatchTheme.card,
                    countdownDeadline: undoDeadline,
                    action: onUndo
                )
            } else if canPlayAgain {
                finishedActionButton(
                    title: NSLocalizedString("watch_play_again", value: "再来一场", comment: ""),
                    compact: compact,
                    background: Color(hex: 0x008336),
                    action: onPlayAgain
                )
            }
        }
    }

    private func finishedActionButton(
        title: String,
        compact: Bool,
        background: Color,
        countdownDeadline: Date? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: compact ? 13 : 15, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity)
                .frame(height: Self.actionHeight)
                .background(background, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .overlay {
            if let countdownDeadline {
                WatchUndoCountdownStroke(
                    deadline: countdownDeadline,
                    duration: WatchTiming.finishedUndoCountdown
                )
                .padding(1)
            }
        }
    }

    private func resetUndoDeadlineIfNeeded() {
        guard undoAvailable else { return }
        undoDeadline = Date().addingTimeInterval(WatchTiming.finishedUndoCountdown)
    }
}

struct WatchSideExchangeToast: View {
    var body: some View {
        Text(NSLocalizedString("watch_side_exchange", value: "交换场地", comment: ""))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(WatchTheme.successGreen.opacity(0.72))
            .clipShape(Capsule())
    }
}

struct WatchScoreEventToastState: Equatable {
    let title: String
    let detail: String
}

struct WatchScoreEventToast: View {
    let state: WatchScoreEventToastState

    var body: some View {
        VStack(spacing: 3) {
            Text(state.title)
                .font(.system(size: 14, weight: .semibold))
            Text(state.detail)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 10)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

struct WatchDoublesHalfModel {
    enum PlayerPosition {
        case top
        case bottom
    }

    let topName: String
    let bottomName: String
    let score: String
    let primaryMeta: String?
    let secondaryMeta: String?
    let color: Color
    let servingPosition: PlayerPosition?
    let onTap: () -> Void
}

struct WatchDoublesDisplayState: Equatable {
    let topPlayerIndex: Int
    let bottomPlayerIndex: Int
    let serverIsTop: Bool?

    static func resolve(
        doubles: RallyDoublesState,
        logicalSide: MatchSide,
        screenSide: MatchSide
    ) -> WatchDoublesDisplayState {
        let resolved = RallyDoublesDisplayState.resolve(
            doubles: doubles,
            logicalSide: logicalSide,
            screenSide: screenSide
        )
        return WatchDoublesDisplayState(
            topPlayerIndex: resolved.topPlayerIndex,
            bottomPlayerIndex: resolved.bottomPlayerIndex,
            serverIsTop: resolved.serverIsTop
        )
    }
}

/// Gives a stacked score its own space below the name, including on small watches.
struct WatchScoreboardFace<Name: View, Score: View>: View {
    let isHorizontal: Bool
    var topInset: CGFloat = 12
    var bottomInset: CGFloat = 0
    @ViewBuilder let name: () -> Name
    @ViewBuilder let score: () -> Score

    var body: some View {
        if isHorizontal {
            ZStack {
                score()
                name()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, WatchLayout.scoreboardTopNameInset)
            }
        } else {
            VStack(spacing: 0) {
                name()
                    .layoutPriority(1)
                score()
                    .frame(maxHeight: .infinity)
            }
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
        }
    }
}

struct WatchDoublesBoard: View {
    let left: WatchDoublesHalfModel
    let right: WatchDoublesHalfModel

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing
            let height = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            HStack(spacing: 0) {
                half(left, size: .init(width: width / 2, height: height), isFirst: true)
                half(right, size: .init(width: width / 2, height: height), isFirst: false)
            }
            .frame(width: width, height: height)
            .offset(x: -proxy.safeAreaInsets.leading, y: -proxy.safeAreaInsets.top)
        }
        .ignoresSafeArea()
    }

    private func half(
        _ model: WatchDoublesHalfModel,
        size: CGSize,
        isFirst: Bool
    ) -> some View {
        ZStack {
            scoreRow(model, isFirst: isFirst)

            playerName(model.topName, alignment: .top)
                .padding(.top, WatchLayout.isCompactScreen ? 24 : 32)
                .offset(y: WatchLayout.scoreboardNameVerticalOffset)
            playerName(model.bottomName, alignment: .bottom)
                .padding(.bottom, WatchLayout.isCompactScreen ? 24 : 32)

            if let servingPosition = model.servingPosition {
                WatchServerIndicator(
                    direction: isFirst ? .left : .right,
                    size: WatchLayout.serverIndicatorSize,
                    color: WatchTheme.accent
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: servingAlignment(
                        servingPosition,
                        isFirst: isFirst
                    )
                )
                .padding(.vertical, WatchLayout.isCompactScreen ? 24 : 32)
                .offset(y: servingPosition == .top ? WatchLayout.scoreboardNameVerticalOffset : 0)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(model.color)
        .contentShape(Rectangle())
        .onTapGesture(perform: model.onTap)
    }

    private func scoreRow(
        _ model: WatchDoublesHalfModel,
        isFirst: Bool
    ) -> some View {
        let hasInnerScore = model.primaryMeta != nil || model.secondaryMeta != nil
        let outerPadding: CGFloat = WatchLayout.isCompactScreen ? 3 : 4
        let centerInset: CGFloat = 4
        return HStack(spacing: 2) {
            if !hasInnerScore {
                mainScore(model.score)
                    .frame(maxWidth: .infinity)
            } else if isFirst {
                mainScore(model.score)
                    .frame(maxWidth: .infinity)
                innerScore(primary: model.primaryMeta, secondary: model.secondaryMeta)
            } else {
                innerScore(primary: model.primaryMeta, secondary: model.secondaryMeta)
                mainScore(model.score)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.leading, isFirst ? outerPadding : centerInset)
        .padding(.trailing, isFirst ? centerInset : outerPadding)
    }

    private func mainScore(_ score: String) -> some View {
        let baseSize: CGFloat = WatchLayout.isCompactScreen ? 42 : 52
        let scoreFont = WatchScoreTypography.adaptiveFontSize(
            baseSize: baseSize,
            scoreText: score,
            minimumSize: 28
        )
        return Text(score)
            .font(WatchScoreTypography.primaryScore(size: scoreFont))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
    }

    @ViewBuilder
    private func innerScore(primary: String?, secondary: String?) -> some View {
        if primary != nil || secondary != nil {
            let compact = WatchLayout.isCompactScreen
            let badgeWidth: CGFloat = compact ? 21 : 23
            let badgeHeight: CGFloat = compact ? 19 : 21
            let columnWidth: CGFloat = secondary == nil
                ? (compact ? 17 : 19)
                : badgeWidth
            VStack(alignment: .center, spacing: 2) {
                if let primary {
                    Text(primary)
                        .font(WatchScoreTypography.secondaryScore(
                            size: secondary == nil
                                ? (compact ? 22 : 24)
                                : (compact ? 18 : 20)
                        ))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let secondary {
                    Text(secondary)
                        .font(WatchScoreTypography.secondaryScore(size: compact ? 12 : 13))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(minWidth: badgeWidth, minHeight: badgeHeight)
                        .background(
                            Color.black.opacity(0.18),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
            }
            .frame(width: columnWidth, alignment: .center)
        }
    }

    private func playerName(_ name: String, alignment: Alignment) -> some View {
        Text(name)
            .font(.system(size: WatchLayout.isCompactScreen ? 12 : 15, weight: .medium))
            .foregroundStyle(.white.opacity(0.82))
            .lineLimit(2)
            .minimumScaleFactor(0.65)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(.horizontal, 4)
    }

    private func servingAlignment(
        _ position: WatchDoublesHalfModel.PlayerPosition,
        isFirst: Bool
    ) -> Alignment {
        switch (isFirst, position) {
        case (true, .top): .topTrailing
        case (true, .bottom): .bottomTrailing
        case (false, .top): .topLeading
        case (false, .bottom): .bottomLeading
        }
    }
}

struct WatchScoreboardGestureModifier: ViewModifier {
    @Binding var suppressTapAfterLongPress: Bool
    let enabled: Bool
    let onMenu: () -> Void
    let onUndo: () -> Void
    let onExit: () -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                LongPressGesture(minimumDuration: WatchTiming.longPressThreshold)
                    .onEnded { _ in
                        guard enabled else { return }
                        suppressTapAfterLongPress = true
                        WatchHaptics.shared.play(.strong)
                        onMenu()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            suppressTapAfterLongPress = false
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        guard enabled else { return }
                        let dx = value.translation.width
                        let dy = value.translation.height
                        if dx > 55, abs(dy) < 50 {
                            onExit()
                        } else if dy > 40 {
                            onUndo()
                        }
                    }
            )
    }
}

struct WatchUndoToastModifier: ViewModifier {
    @Binding var token: UUID?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if token != nil {
                    WatchToastView(
                        message: NSLocalizedString(
                            "watch_undo_toast",
                            value: "已撤销",
                            comment: "Undo toast"
                        )
                    )
                    .padding(.bottom, 16)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }
            .onChange(of: token) { _, newToken in
                guard let newToken else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    guard token == newToken else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        token = nil
                    }
                }
            }
    }
}

extension View {
    func watchScoreboardGestures(
        suppressTapAfterLongPress: Binding<Bool>,
        enabled: Bool,
        onMenu: @escaping () -> Void,
        onUndo: @escaping () -> Void,
        onExit: @escaping () -> Void
    ) -> some View {
        modifier(WatchScoreboardGestureModifier(
            suppressTapAfterLongPress: suppressTapAfterLongPress,
            enabled: enabled,
            onMenu: onMenu,
            onUndo: onUndo,
            onExit: onExit
        ))
    }

    func watchUndoToast(token: Binding<UUID?>) -> some View {
        modifier(WatchUndoToastModifier(token: token))
    }
}

extension View {
    func watchFinishSaveFailure(
        isPresented: Binding<Bool>,
        onCancel: @escaping () -> Void = {},
        retry: @escaping () -> Void
    ) -> some View {
        alert(
            NSLocalizedString("watch_common_names_error_generic", value: "Couldn't save. Try again.", comment: ""),
            isPresented: isPresented
        ) {
            Button(NSLocalizedString("watch_phone_link_test_retry", value: "Retry", comment: ""), action: retry)
            Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel, action: onCancel)
        }
    }
}
