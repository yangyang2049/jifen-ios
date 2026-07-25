import ScoreCore
import SwiftUI

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

    init(
        kind: Kind,
        title: String,
        durationSeconds: Int,
        startedAt: Date = Date(),
        triggerID: String
    ) {
        self.kind = kind
        self.title = title
        self.durationSeconds = max(0, durationSeconds)
        self.startedAt = startedAt
        self.triggerID = triggerID
    }

    func remainingSeconds(at date: Date = Date()) -> Int {
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        return max(0, durationSeconds - Int(elapsed.rounded(.down)))
    }
}

enum WatchRestPolicy {
    static func betweenSetDuration(for gameType: GameType) -> Int? {
        switch gameType {
        case .pingpong, .pingpongDoubles:
            return 60
        case .badminton, .badmintonDoubles,
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
        let openingSlot = firstServer == .left ? 0 : 1
        if isTieBreak {
            let played = max(0, tieBreakPointsPlayed)
            guard played > 0 else { return openingSlot }
            return (openingSlot + 1 + (played - 1) / 2) % 4
        }
        return (openingSlot + max(0, completedGames)) % 4
    }
}

struct WatchScoreboardMenuOverlay: View {
    let onDismiss: () -> Void
    let onUndo: () -> Void
    let onFinish: () -> Void
    let onReset: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 4) {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: WatchLayout.isCompactScreen ? 5 : 6
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
                }

                WatchMenuGridButton(
                    title: NSLocalizedString("watch_menu_end_match", value: "结束比赛", comment: ""),
                    systemImage: "flag.checkered",
                    background: WatchTheme.dangerRed,
                    action: onFinish
                )

                WatchMenuCloseButton(action: onDismiss)
            }
            .padding(.horizontal, WatchLayout.isCompactScreen ? 20 : 26)
            .padding(.bottom, WatchLayout.isCompactScreen ? 4 : 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
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
        ZStack {
            Color.black.opacity(resolvedBackdropOpacity).ignoresSafeArea()
            VStack(spacing: WatchLayout.isCompactScreen ? 8 : 12) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                HStack(spacing: WatchLayout.isCompactScreen ? 18 : 22) {
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
            }
            .padding(WatchLayout.isCompactScreen ? 12 : 18)
            .background(Color.black.opacity(resolvedCardOpacity))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
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
    let onContinue: () -> Void
    let onUndo: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let remaining = state.remainingSeconds(at: context.date)
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                VStack(spacing: WatchLayout.isCompactScreen ? 8 : 12) {
                    Text(state.title)
                        .font(.system(size: WatchLayout.isCompactScreen ? 17 : 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(Self.timeText(remaining))
                        .font(.system(size: WatchLayout.isCompactScreen ? 30 : 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(WatchTheme.timerAccent)
                    Button(
                        remaining == 0
                            ? NSLocalizedString("watch_continue_match", value: "继续比赛", comment: "")
                            : NSLocalizedString("watch_continue", value: "继续", comment: ""),
                        action: onContinue
                    )
                    .buttonStyle(.borderedProminent)
                    .tint(remaining == 0 ? WatchTheme.successGreen : WatchTheme.card)

                    Button(
                        NSLocalizedString("menu_undo", value: "撤销", comment: ""),
                        action: onUndo
                    )
                    .buttonStyle(.bordered)
                }
                .frame(width: WatchLayout.isCompactScreen ? 148 : 172)
                .padding(.vertical, WatchLayout.isCompactScreen ? 12 : 18)
                .background(Color.black.opacity(0.52))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    static func timeText(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        return String(format: "%02d:%02d", safe / 60, safe % 60)
    }
}

struct WatchFinishedOverlay: View {
    let title: String
    let scoreText: String
    let winnerText: String?
    let undoAvailable: Bool
    let onUndo: () -> Void
    let onPlayAgain: () -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.40).ignoresSafeArea()
            VStack(spacing: WatchLayout.isCompactScreen ? 7 : 10) {
                Text(title)
                    .font(.headline)
                Text(scoreText)
                    .font(.title3.monospacedDigit().weight(.bold))
                if let winnerText, !winnerText.isEmpty {
                    Text(winnerText)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(2)
                }
                if undoAvailable {
                    Button(
                        NSLocalizedString("menu_undo", value: "撤销", comment: ""),
                        action: onUndo
                    )
                    .buttonStyle(.borderedProminent)
                    .tint(WatchTheme.card)
                } else {
                    Button(
                        NSLocalizedString("watch_play_again", value: "再来一局", comment: ""),
                        action: onPlayAgain
                    )
                    .buttonStyle(.borderedProminent)
                    .tint(WatchTheme.successGreen)
                }
                Button(
                    NSLocalizedString("watch_exit", value: "退出", comment: ""),
                    action: onExit
                )
                .buttonStyle(.bordered)
            }
            .foregroundStyle(.white)
            .padding(WatchLayout.isCompactScreen ? 10 : 16)
            .frame(width: WatchLayout.isCompactScreen ? 154 : 176)
            .background(Color.black.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
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
        let team0 = logicalSide == .left
        var topIndex = team0 ? 0 : 1
        var bottomIndex = team0 ? 2 : 3
        var serverIsTop: Bool?

        switch doubles.rotation {
        case .badminton(let rotation):
            let orderSwapped = team0
                ? rotation.team0CourtOrderSwapped
                : rotation.team1CourtOrderSwapped
            if orderSwapped {
                swap(&topIndex, &bottomIndex)
            }
            if isTeam0DoublesSlot(rotation.serverSlotIndex) == team0 {
                serverIsTop = rotation.serverSlotIndex == topIndex
            }

        case .pickleball(let rotation):
            let partnersSwapped = team0
                ? rotation.team0PartnersSwapped
                : rotation.team1PartnersSwapped
            if partnersSwapped {
                swap(&topIndex, &bottomIndex)
            }
            if screenSide == .right {
                swap(&topIndex, &bottomIndex)
            }
            if isTeam0DoublesSlot(rotation.serverSlotIndex) == team0 {
                let logicalServerOnTop = rotation.serverNumber == 2
                let displayLogicalTop = logicalServerOnTop != partnersSwapped
                serverIsTop = screenSide == .right ? !displayLogicalTop : displayLogicalTop
            }

        case .pingPong(let rotation):
            if isTeam0DoublesSlot(rotation.serverSlotIndex) == team0 {
                serverIsTop = rotation.serverSlotIndex == topIndex
            }

        case .foosball:
            break
        }

        return WatchDoublesDisplayState(
            topPlayerIndex: topIndex,
            bottomPlayerIndex: bottomIndex,
            serverIsTop: serverIsTop
        )
    }
}

struct WatchDoublesBoard: View {
    let isHorizontal: Bool
    let left: WatchDoublesHalfModel
    let right: WatchDoublesHalfModel

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing
            let height = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            Group {
                if isHorizontal {
                    HStack(spacing: 0) {
                        half(left, size: .init(width: width / 2, height: height), isFirst: true)
                        half(right, size: .init(width: width / 2, height: height), isFirst: false)
                    }
                } else {
                    VStack(spacing: 0) {
                        half(left, size: .init(width: width, height: height / 2), isFirst: true)
                        half(right, size: .init(width: width, height: height / 2), isFirst: false)
                    }
                }
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

            if isHorizontal {
                playerName(model.topName, alignment: .top)
                    .padding(.top, WatchLayout.isCompactScreen ? 24 : 32)
                playerName(model.bottomName, alignment: .bottom)
                    .padding(.bottom, WatchLayout.isCompactScreen ? 24 : 32)
            } else {
                HStack {
                    playerName(model.topName, alignment: .leading)
                    Spacer(minLength: 50)
                    playerName(model.bottomName, alignment: .trailing)
                }
                .padding(.horizontal, 8)
            }

            if let servingPosition = model.servingPosition {
                WatchServerIndicator(
                    direction: isHorizontal
                        ? (isFirst ? .left : .right)
                        : (isFirst ? .top : .bottom),
                    size: 14,
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
                .padding(.vertical, isHorizontal
                    ? (WatchLayout.isCompactScreen ? 24 : 32)
                    : 0
                )
                .padding(.horizontal, isHorizontal ? 0 : 8)
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
        HStack(spacing: 2) {
            if isFirst {
                mainScore(model.score)
                innerScore(primary: model.primaryMeta, secondary: model.secondaryMeta)
            } else {
                innerScore(primary: model.primaryMeta, secondary: model.secondaryMeta)
                mainScore(model.score)
            }
        }
        .padding(.horizontal, 3)
    }

    private func mainScore(_ score: String) -> some View {
        Text(score)
            .font(.system(
                size: isHorizontal
                    ? (WatchLayout.isCompactScreen ? 42 : 52)
                    : (WatchLayout.isCompactScreen ? 38 : 46),
                weight: .bold,
                design: .rounded
            ))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
    }

    @ViewBuilder
    private func innerScore(primary: String?, secondary: String?) -> some View {
        if primary != nil || secondary != nil {
            VStack(spacing: 2) {
                if let primary {
                    Text(primary)
                        .font(.system(size: secondary == nil ? 24 : 28, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                if let secondary {
                    Text(secondary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(minWidth: 22, minHeight: 22)
                        .padding(.horizontal, 2)
                        .background(Color.black.opacity(0.16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.white.opacity(0.42), lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
            .frame(width: secondary == nil ? 30 : 40)
        }
    }

    private func playerName(_ name: String, alignment: Alignment) -> some View {
        Text(name)
            .font(.system(size: WatchLayout.isCompactScreen ? 10 : 12, weight: .medium))
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
        if isHorizontal {
            switch (isFirst, position) {
            case (true, .top): .topTrailing
            case (true, .bottom): .bottomTrailing
            case (false, .top): .topLeading
            case (false, .bottom): .bottomLeading
            }
        } else {
            switch (isFirst, position) {
            case (true, .top): .bottomLeading
            case (true, .bottom): .bottomTrailing
            case (false, .top): .topLeading
            case (false, .bottom): .topTrailing
            }
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
}
