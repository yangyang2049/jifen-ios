import SwiftUI

enum WatchHomeItem: String, CaseIterable {
    case badminton
    case badmintonDoubles
    case tennis
    case tennisDoubles
    case pingpong
    case pingpongDoubles
    case pickleball
    case pickleballDoubles
    case archery
    case eightBall
    case nineBall
    case snooker
    /// Watch-only tool (not synced to phone).
    case basketball_training
}

enum WatchHomePinning {
    static let maximumPinnedItems = 2

    static func normalizedItems(from itemIDs: [String]) -> [WatchHomeItem] {
        var result: [WatchHomeItem] = []
        for itemID in itemIDs {
            guard let item = WatchHomeItem(rawValue: itemID),
                  !result.contains(item) else {
                continue
            }
            result.append(item)
            if result.count == maximumPinnedItems {
                break
            }
        }
        return result
    }

    static func orderedItems(pinnedItems: [WatchHomeItem]) -> [WatchHomeItem] {
        let normalized = normalizedItems(from: pinnedItems.map(\.rawValue))
        return normalized + WatchHomeItem.allCases.filter { !normalized.contains($0) }
    }

    static func adding(
        _ item: WatchHomeItem,
        to pinnedItems: [WatchHomeItem]
    ) -> [WatchHomeItem]? {
        let normalized = normalizedItems(from: pinnedItems.map(\.rawValue))
        if normalized.contains(item) {
            return normalized
        }
        guard normalized.count < maximumPinnedItems else { return nil }
        return normalized + [item]
    }

    static func removing(
        _ item: WatchHomeItem,
        from pinnedItems: [WatchHomeItem]
    ) -> [WatchHomeItem] {
        normalizedItems(from: pinnedItems.map(\.rawValue)).filter { $0 != item }
    }
}

private enum WatchHomePreflightPicker {
    case nineBallPlayers
    case basketballTraining
}

struct WatchHomeTabView: View {
    private static let scrollTopAnchor = "watch-home-top"

    @Binding var scoreboardRoute: WatchScoreboardRoute?
    @State private var pinnedItems: [WatchHomeItem] = []
    @State private var preflightPicker: WatchHomePreflightPicker?
    @State private var pinDialogItem: WatchHomeItem?
    @State private var showPinLimitAlert = false
    @State private var toastMessage: String?
    @State private var toastToken = UUID()
    @State private var scrollToTopRequest = 0

    private var orderedItems: [WatchHomeItem] {
        WatchHomePinning.orderedItems(pinnedItems: pinnedItems)
    }

    var body: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        Color.clear
                            .frame(height: 0)
                            .id(Self.scrollTopAnchor)

                        ForEach(orderedItems, id: \.rawValue) { item in
                            WatchHomePillControl(
                                icon: icon(for: item),
                                title: title(for: item),
                                isPinned: pinnedItems.contains(item),
                                longPressActionTitle: pinActionTitle(for: item),
                                onTap: { handleTap(item) },
                                onLongPress: { handleLongPress(item) }
                            )
                        }

                        Text(NSLocalizedString(
                            "watch_home_pin_hint",
                            value: "长按可置顶项目",
                            comment: "Long press to pin projects"
                        ))
                        .font(.system(size: 11))
                        .foregroundStyle(WatchTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, WatchLayout.tabHorizontalPadding)
                    .padding(.bottom, 12)
                }
                .onChange(of: scrollToTopRequest) { _, _ in
                    withAnimation {
                        proxy.scrollTo(Self.scrollTopAnchor, anchor: .top)
                    }
                }
            }

            if let preflightPicker {
                preflightOverlay(preflightPicker)
            }

            if let toastMessage {
                VStack {
                    Spacer()
                    WatchToastView(message: toastMessage)
                        .padding(.bottom, 14)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .background(WatchTheme.background)
        .navigationTitle(NSLocalizedString("tab_score", comment: "Score"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadPinnedItems() }
        .confirmationDialog(
            pinDialogTitle,
            isPresented: pinDialogPresented,
            titleVisibility: .visible
        ) {
            if let item = pinDialogItem {
                if pinnedItems.contains(item) {
                    Button(
                        NSLocalizedString(
                            "watch_home_unpin_confirm",
                            value: "取消置顶",
                            comment: "Unpin project"
                        ),
                        role: .destructive
                    ) {
                        unpin(item)
                    }
                } else {
                    Button(NSLocalizedString(
                        "watch_home_pin_confirm",
                        value: "置顶",
                        comment: "Pin project"
                    )) {
                        pin(item)
                    }
                }
            }
            Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) { }
        } message: {
            Text(pinDialogMessage)
        }
        .alert(
            NSLocalizedString(
                "watch_home_pin_full_title",
                value: "置顶已满",
                comment: "Pinned projects full"
            ),
            isPresented: $showPinLimitAlert
        ) {
            Button(NSLocalizedString("confirm", comment: "Confirm"), role: .cancel) { }
        } message: {
            Text(NSLocalizedString(
                "watch_home_pin_full_message",
                value: "最多置顶 2 个项目，请先取消一个。",
                comment: "Up to two projects can be pinned"
            ))
        }
    }

    private var pinDialogPresented: Binding<Bool> {
        Binding(
            get: { pinDialogItem != nil },
            set: { isPresented in
                if !isPresented {
                    pinDialogItem = nil
                }
            }
        )
    }

    private var pinDialogTitle: String {
        guard let item = pinDialogItem else { return "" }
        return pinnedItems.contains(item)
            ? NSLocalizedString(
                "watch_home_unpin_title",
                value: "取消置顶？",
                comment: "Unpin project confirmation title"
            )
            : NSLocalizedString(
                "watch_home_pin_title",
                value: "置顶项目？",
                comment: "Pin project confirmation title"
            )
    }

    private var pinDialogMessage: String {
        guard let item = pinDialogItem else { return "" }
        return pinnedItems.contains(item)
            ? NSLocalizedString(
                "watch_home_unpin_message",
                value: "将这个项目从置顶项目中移除？",
                comment: "Unpin project confirmation message"
            )
            : NSLocalizedString(
                "watch_home_pin_message",
                value: "将这个项目置顶到首页列表顶部？",
                comment: "Pin project confirmation message"
            )
    }

    private func icon(for item: WatchHomeItem) -> String {
        switch item {
        case .badminton, .badmintonDoubles: return "🏸"
        case .tennis, .tennisDoubles: return "🎾"
        case .pingpong, .pingpongDoubles: return "🏓"
        case .pickleball, .pickleballDoubles: return "🏓"
        case .archery: return "🏹"
        case .eightBall, .nineBall, .snooker: return "🎱"
        case .basketball_training: return "🏀"
        }
    }

    private func title(for item: WatchHomeItem) -> String {
        switch item {
        case .badminton: return NSLocalizedString("game_badminton", comment: "")
        case .badmintonDoubles: return NSLocalizedString("game_badminton_doubles", value: "羽毛球双打", comment: "")
        case .tennis: return NSLocalizedString("game_tennis", comment: "")
        case .tennisDoubles: return NSLocalizedString("game_tennis_doubles", value: "网球双打", comment: "")
        case .pingpong: return NSLocalizedString("game_pingpong", comment: "")
        case .pingpongDoubles: return NSLocalizedString("game_pingpong_doubles", value: "乒乓球双打", comment: "")
        case .pickleball: return NSLocalizedString("game_pickleball", comment: "")
        case .pickleballDoubles: return NSLocalizedString("game_pickleball_doubles", value: "匹克球双打", comment: "")
        case .archery: return NSLocalizedString("game_archery", comment: "")
        case .eightBall: return NSLocalizedString("game_eight_ball", value: "黑八", comment: "")
        case .nineBall: return NSLocalizedString("game_nine_ball", value: "九球", comment: "")
        case .snooker: return NSLocalizedString("game_snooker", value: "斯诺克", comment: "")
        case .basketball_training: return NSLocalizedString("tool_basketball_training", comment: "")
        }
    }

    private func handleTap(_ item: WatchHomeItem) {
        switch item {
        case .nineBall:
            preflightPicker = .nineBallPlayers
        case .basketball_training:
            preflightPicker = .basketballTraining
        default:
            guard let sport = setupSport(for: item) else { return }
            scoreboardRoute = .setup(sport: sport, playerCount: sport.defaultPlayerCount)
        }
    }

    private func handleLongPress(_ item: WatchHomeItem) {
        WatchHaptics.shared.play(.strong)
        if !pinnedItems.contains(item),
           pinnedItems.count >= WatchHomePinning.maximumPinnedItems {
            showPinLimitAlert = true
            return
        }
        pinDialogItem = item
    }

    private func setupSport(for item: WatchHomeItem) -> WatchSetupSport? {
        switch item {
        case .badminton: .badminton
        case .badmintonDoubles: .badmintonDoubles
        case .tennis: .tennis
        case .tennisDoubles: .tennisDoubles
        case .pingpong: .pingpong
        case .pingpongDoubles: .pingpongDoubles
        case .pickleball: .pickleball
        case .pickleballDoubles: .pickleballDoubles
        case .archery: .archery
        case .eightBall: .eightBall
        case .nineBall: .nineBall
        case .snooker: .snooker
        case .basketball_training: nil
        }
    }

    @ViewBuilder
    private func preflightOverlay(_ picker: WatchHomePreflightPicker) -> some View {
        ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()
                .onTapGesture { preflightPicker = nil }

            VStack(spacing: 12) {
                Text(
                    picker == .nineBallPlayers
                        ? NSLocalizedString("watch_setup_select_players", value: "选择人数", comment: "")
                        : NSLocalizedString("watch_bb_select_mode", value: "选择计分方式", comment: "")
                )
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(WatchTheme.primaryText)
                .multilineTextAlignment(.center)

                if picker == .nineBallPlayers {
                    VStack(spacing: 8) {
                        ForEach(2...4, id: \.self) { count in
                            preflightButton(
                                String.localizedStringWithFormat(
                                    NSLocalizedString("watch_setup_player_count", value: "%d 人", comment: ""),
                                    count
                                )
                            ) {
                                preflightPicker = nil
                                scoreboardRoute = .setup(sport: .nineBall, playerCount: count)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            trainingModeButton(.onePoint, title: NSLocalizedString("watch_bb_1pt", value: "1分", comment: ""))
                            trainingModeButton(.twoPoint, title: NSLocalizedString("watch_bb_2pt", value: "2分", comment: ""))
                            trainingModeButton(.threePoint, title: NSLocalizedString("watch_bb_3pt", value: "3分", comment: ""))
                        }
                        trainingModeButton(
                            .free,
                            title: NSLocalizedString("watch_bb_free", value: "自由", comment: ""),
                            fillsWidth: true
                        )
                    }
                }
            }
            .padding(14)
            .frame(width: WatchLayout.isCompactScreen ? 184 : 208)
            .background(WatchTheme.listItemBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func trainingModeButton(
        _ mode: WatchBasketballTrainingMode,
        title: String,
        fillsWidth: Bool = false
    ) -> some View {
        Button {
            preflightPicker = nil
            scoreboardRoute = .basketballTraining(mode: mode)
        } label: {
            Text(title)
                .font(.system(size: fillsWidth ? 16 : 14, weight: .medium))
                .foregroundStyle(WatchTheme.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: WatchLayout.isCompactScreen ? 42 : 50)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: fillsWidth ? .infinity : nil)
    }

    private func preflightButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(WatchTheme.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func pinActionTitle(for item: WatchHomeItem) -> String {
        pinnedItems.contains(item)
            ? NSLocalizedString(
                "watch_home_unpin_confirm",
                value: "取消置顶",
                comment: "Unpin project"
            )
            : NSLocalizedString(
                "watch_home_pin_confirm",
                value: "置顶",
                comment: "Pin project"
            )
    }

    private func loadPinnedItems() {
        let storedIDs = WatchPreferences.shared.pinnedHomeItemIDs
        let normalized = WatchHomePinning.normalizedItems(from: storedIDs)
        pinnedItems = normalized
        let normalizedIDs = normalized.map(\.rawValue)
        if normalizedIDs != storedIDs {
            WatchPreferences.shared.pinnedHomeItemIDs = normalizedIDs
        }
    }

    private func pin(_ item: WatchHomeItem) {
        pinDialogItem = nil
        guard let updated = WatchHomePinning.adding(item, to: pinnedItems) else {
            showPinLimitAlert = true
            return
        }
        persistPinnedItems(updated)
        scrollToTopRequest += 1
        showToast(NSLocalizedString(
            "watch_home_pin_success",
            value: "已置顶",
            comment: "Pinned to top"
        ))
    }

    private func unpin(_ item: WatchHomeItem) {
        pinDialogItem = nil
        persistPinnedItems(WatchHomePinning.removing(item, from: pinnedItems))
        showToast(NSLocalizedString(
            "watch_home_unpin_success",
            value: "已取消置顶",
            comment: "Removed from pinned"
        ))
    }

    private func persistPinnedItems(_ items: [WatchHomeItem]) {
        let normalized = WatchHomePinning.normalizedItems(from: items.map(\.rawValue))
        pinnedItems = normalized
        WatchPreferences.shared.pinnedHomeItemIDs = normalized.map(\.rawValue)
    }

    private func showToast(_ message: String) {
        let token = UUID()
        toastToken = token
        withAnimation {
            toastMessage = message
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard toastToken == token else { return }
            withAnimation {
                toastMessage = nil
            }
        }
    }
}

private struct WatchHomePillControl: View {
    let icon: String
    let title: String
    let isPinned: Bool
    let longPressActionTitle: String
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        WatchPillRow(
            icon: icon,
            title: title,
            trailingIcon: isPinned ? "📌" : nil
        )
        .contentShape(Rectangle())
        .gesture(
            LongPressGesture(minimumDuration: WatchTiming.longPressThreshold)
                .exclusively(before: TapGesture())
                .onEnded { value in
                    switch value {
                    case .first:
                        onLongPress()
                    case .second:
                        onTap()
                    }
                }
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onTap()
        }
        .accessibilityAction(named: Text(longPressActionTitle)) {
            onLongPress()
        }
    }
}
