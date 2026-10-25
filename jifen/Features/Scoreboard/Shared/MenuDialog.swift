//
//  MenuDialog.swift
//  jifen
//
//  Scoreboard operation menu. Layout follows HarmonyOS MenuDialog
//  (top sync area / middle match cards / bottom tools), with iOS-specific contrast.
//

import SwiftUI

// MARK: - Model

enum ScoreboardMenuGroup: String, Equatable {
    case sync
    case match
    case tools
}

enum ScoreboardMenuCardSize {
    case large
    case medium
    case small
}

struct ScoreboardMenuItem: Identifiable, Equatable {
    var id: String { action }
    let title: String
    let action: String
    let group: ScoreboardMenuGroup
    var icon: String? = nil
    var iconAsset: String? = nil
    var customText: String? = nil
    var customTextScale: CGFloat = 1
    var backgroundColor: Color? = nil
    var keepDialogOpen: Bool = false
    var confirming: Bool = false
    var enabled: Bool = true
    var sortOrder: Int = 0
    var placeAtEnd: Bool = false
}

enum ScoreboardMenuActionPolicy {
    private static let actionsAllowedWhileScoringLocked: Set<String> = [
        "usageHint",
        "displaySettings",
        "screenshot",
        "exit"
    ]

    static func isAllowedWhileScoringLocked(_ action: String) -> Bool {
        actionsAllowedWhileScoringLocked.contains(action)
    }
}

enum ScoreboardMenuActionID: String {
    case exchangeSide
}

// MARK: - Default items (aligned with HarmonyOS groups)

enum ScoreboardMenuItemBuilder {
    static func defaultItems(
        showEndGame: Bool = false,
        showExchangeSide: Bool = true,
        showWhistle: Bool = true,
        showScreenshot: Bool = true,
        showDisplaySettings: Bool = true,
        showSettleMatch: Bool = false,
        resetConfirming: Bool = false,
        exchangeConfirming: Bool = false,
        finishConfirming: Bool = false,
        settleConfirming: Bool = false,
        scoringEnabled: Bool = true,
        extraItems: [ScoreboardMenuItem] = []
    ) -> [ScoreboardMenuItem] {
        var items: [ScoreboardMenuItem] = []

        items.append(
            ScoreboardMenuItem(
                title: NSLocalizedString("menu_undo", comment: "Undo"),
                action: "undo",
                group: .match,
                icon: "arrow.uturn.backward",
                keepDialogOpen: true,
                enabled: scoringEnabled
            )
        )

        if showExchangeSide {
            items.append(
                ScoreboardMenuItem(
                    title: NSLocalizedString("menu_swap_sides", comment: "Exchange sides"),
                    action: ScoreboardMenuActionID.exchangeSide.rawValue,
                    group: .match,
                    icon: "arrow.left.arrow.right",
                    keepDialogOpen: true,
                    confirming: exchangeConfirming,
                    enabled: scoringEnabled
                )
            )
        }

        let matchExtras = extraItems.filter { $0.group == .match }.map { item in
            var copy = item
            if item.action != "frameRecord" {
                copy.enabled = item.enabled && scoringEnabled
            }
            return copy
        }
        items.append(contentsOf: matchExtras)

        items.append(
            ScoreboardMenuItem(
                title: NSLocalizedString("menu_reset", comment: "Reset"),
                action: "reset",
                group: .match,
                icon: "arrow.counterclockwise",
                keepDialogOpen: true,
                confirming: resetConfirming,
                enabled: scoringEnabled,
                sortOrder: 10
            )
        )

        if showSettleMatch {
            items.append(
                ScoreboardMenuItem(
                    title: NSLocalizedString("settle_match", value: "结算", comment: ""),
                    action: "settleMatch",
                    group: .match,
                    icon: "checkmark.seal",
                    keepDialogOpen: true,
                    confirming: settleConfirming,
                    enabled: scoringEnabled
                )
            )
        }

        if showEndGame {
            items.append(
                ScoreboardMenuItem(
                    title: NSLocalizedString("menu_end_game", value: "结束比赛", comment: "End game"),
                    action: "endGame",
                    group: .match,
                    icon: "flag.checkered",
                    keepDialogOpen: true,
                    confirming: finishConfirming,
                    enabled: scoringEnabled,
                    sortOrder: 100
                )
            )
        }

        if showWhistle {
            items.append(
                ScoreboardMenuItem(
                    title: NSLocalizedString("menu_whistle", comment: "Whistle"),
                    action: "whistle",
                    group: .tools,
                    icon: "bell.fill",
                    keepDialogOpen: true
                )
            )
        }

        if showDisplaySettings {
            items.append(
                ScoreboardMenuItem(
                    // 对齐安卓：所有计分板菜单项统一为“样式”（registry 项目进全屏样式
                    // 编辑器，非 registry 项目进旧版字号面板，标签相同）。
                    title: NSLocalizedString("scoreboard_style_edit", value: "样式", comment: ""),
                    action: "displaySettings",
                    group: .tools,
                    icon: "paintpalette"
                )
            )
        }

        if showScreenshot {
            items.append(
                ScoreboardMenuItem(
                    title: NSLocalizedString("menu_screenshot", comment: "Screenshot"),
                    action: "screenshot",
                    group: .tools,
                    icon: "camera.fill"
                )
            )
        }

        items.append(
            ScoreboardMenuItem(
                title: NSLocalizedString("scoreboard_usage_hint_menu", value: "使用说明", comment: ""),
                action: "usageHint",
                group: .tools,
                icon: "info.circle",
                keepDialogOpen: true
            )
        )

        items.append(contentsOf: extraItems.filter { $0.group == .sync })
        items.append(contentsOf: extraItems.filter { $0.group == .tools })

        return items
    }

    static func orderedMatchItems(_ items: [ScoreboardMenuItem]) -> [ScoreboardMenuItem] {
        // Android 3.1: undo is fixed first; regular actions are sorted; settlement
        // follows them; explicit trailing actions (football clock decisions) are last.
        let undoItems = items.filter { $0.action == "undo" }
        let trailingItems = items.filter(\.placeAtEnd)
        let settlementItems = items.filter {
            !$0.placeAtEnd && $0.action.lowercased().hasPrefix("settle")
        }
        let middleItems = items.enumerated().filter { _, item in
            item.action != "undo"
                && !item.placeAtEnd
                && !item.action.lowercased().hasPrefix("settle")
        }.sorted { lhs, rhs in
            let lhsOrder = lhs.element.action == "frameRecord" && lhs.element.sortOrder == 0
                ? 200
                : lhs.element.sortOrder
            let rhsOrder = rhs.element.action == "frameRecord" && rhs.element.sortOrder == 0
                ? 200
                : rhs.element.sortOrder
            return lhsOrder == rhsOrder ? lhs.offset < rhs.offset : lhsOrder < rhsOrder
        }.map(\.element)
        let sortedTrailingItems = trailingItems.enumerated().sorted { lhs, rhs in
            lhs.element.sortOrder == rhs.element.sortOrder
                ? lhs.offset < rhs.offset
                : lhs.element.sortOrder < rhs.element.sortOrder
        }.map(\.element)
        return undoItems + middleItems + settlementItems + sortedTrailingItems
    }
}

// MARK: - Dialog

struct MenuDialog: View {
    @Environment(\.scoreboardUsageHintCoordinator) private var usageHintCoordinator
    @Environment(\.scoreboardUsageHintPresenter) private var usageHintPresenter
    let isVisible: Bool
    let onClose: () -> Void
    let onMenuItemClick: (String) -> Void
    var onUsageHint: (() -> Void)? = nil
    var showEndGame: Bool = false
    var showExchangeSide: Bool = true
    var resetConfirming: Bool = false
    var items: [ScoreboardMenuItem]? = nil
    var analyticsGameType: GameType? = nil
    var voiceAnnouncementEnabled: Bool = false
    @AppStorage("pingpongAnnounceServer") private var announceServer = true
    @AppStorage("voiceAnnouncementLanguage") private var voiceLanguagePref = "auto"
    @State private var showServePopup = false

    /// "zh-CN"/"en-US" 当前生效值:显式偏好优先,未手动选择时跟随 App 语言。
    private var selectedLanguageCode: String {
        if voiceLanguagePref == "zh-CN" || voiceLanguagePref == "en-US" { return voiceLanguagePref }
        return SportsVoiceSupport.localization.hasPrefix("zh") ? "zh-CN" : "en-US"
    }

    /// 语言选择器仅面向中文 App 用户(其他语言暂不提供入口,偏好仍生效)。
    private var showsLanguagePicker: Bool {
        SportsVoiceSupport.localization.hasPrefix("zh")
    }
    @State private var voiceCardCenterX: CGFloat = 0
    @State private var containerSize: CGSize = .zero

    private var hasServeOption: Bool {
        analyticsGameType == .pingpong && resolvedItems.contains { $0.action == "voiceAnnouncement" }
    }

    private var hasVoiceOptions: Bool {
        SportsVoiceOptionsPolicy.canPresent(
            isVoiceControl: resolvedItems.contains { $0.action == "voiceAnnouncement" },
            isVoiceEnabled: voiceAnnouncementEnabled,
            hasServeOption: hasServeOption,
            appLanguage: SportsVoiceSupport.localization
        )
    }

    private var servePopupWidth: CGFloat { min(280, dialogWidth - 32) }
    private var voiceAnchorOffset: CGFloat { voiceCardCenterX > 0 ? voiceCardCenterX - dialogWidth / 2 : 0 }
    private var servePopupOffset: CGFloat {
        let limit = max(0, (dialogWidth - servePopupWidth) / 2 - 16)
        return min(limit, max(-limit, voiceAnchorOffset))
    }

    private func revealServePopup() {
        guard hasVoiceOptions else { return }
        showServePopup = true
    }

    // Keep the operation menu opaque over the saturated score panels. A single
    // surface and subtle dividers read more clearly than three stacked grays.
    private let dialogBackground = Color(hex: "202124")
    private let cardBackground = Theme.scoreboardDialogControl
    private let secondaryText = Color(hex: "C7C7CC")
    private let sectionDivider = Color.white.opacity(0.12)
    private let menuScrim = Color.black.opacity(0.54)
    /// 与 .tint(Theme.primary) 同源，避免确认态写死浅色 #4CAF50、
    /// 与强制 dark 环境下的 accent #30D158 形成同一弹层里的两种绿。
    private let confirmBackground = Theme.accentColor.opacity(0.55)

    private var resolvedItems: [ScoreboardMenuItem] {
        items ?? ScoreboardMenuItemBuilder.defaultItems(
            showEndGame: showEndGame,
            showExchangeSide: showExchangeSide,
            resetConfirming: resetConfirming
        )
    }

    private var syncItems: [ScoreboardMenuItem] {
        resolvedItems.filter { $0.group == .sync }
    }

    private var matchItems: [ScoreboardMenuItem] {
        ScoreboardMenuItemBuilder.orderedMatchItems(resolvedItems.filter { $0.group == .match })
    }

    private var toolItems: [ScoreboardMenuItem] {
        resolvedItems.filter { $0.group == .tools }
    }

    private var containerShortSide: CGFloat {
        let shortSide = min(containerSize.width, containerSize.height)
        return shortSide > 0 ? shortSide : 320
    }

    private var dialogWidth: CGFloat {
        Theme.dialogWidth(
            availableWidth: containerSize.width > 0
                ? containerSize.width
                : (Theme.usesPadLayout ? 1_024 : 430),
            role: .scoreboardMenu
        )
    }

    // Let wide iPad cards gain enough vertical breathing room without turning
    // them into squares. Phones stay at the established 72pt height.
    private var syncCardHeight: CGFloat { 56 }
    private var matchCardHeight: CGFloat {
        let cardWidth = (dialogWidth - 32 - 16) / 3
        return min(108, max(72, cardWidth * 0.75))
    }
    private var toolsCardWidth: CGFloat {
        let count = max(toolItems.count, 1)
        let availableWidth = dialogWidth - 32 - CGFloat(count - 1) * toolsRowGap
        return min(64, max(44, availableWidth / CGFloat(count)))
    }
    private var toolsCardHeight: CGFloat { 52 }
    private var topBarPadding: CGFloat { 10 }
    private var gridVerticalPadding: CGFloat { 14 }
    private var toolsRowGap: CGFloat { 16 }
    private var closeHeaderHeight: CGFloat { 60 }
    private var topBarHeight: CGFloat { syncCardHeight + topBarPadding * 2 }
    private var toolsBarHeight: CGFloat { toolsCardHeight + gridVerticalPadding * 2 }

    private var maxMatchSectionHeight: CGFloat {
        let headerHeight = syncItems.isEmpty ? closeHeaderHeight : topBarHeight
        let toolsHeight = toolItems.isEmpty ? 0 : toolsBarHeight
        return max(matchCardHeight + 16, containerShortSide - headerHeight - toolsHeight - 32)
    }

    /// Wrap height of the match grid is determined by its fixed rows, row gap,
    /// and vertical section padding, so runtime measurement is unnecessary.
    private var wrappedMatchSectionHeight: CGFloat {
        let rows = max(1, Int(ceil(Double(matchItems.count) / 3)))
        return CGFloat(rows) * matchCardHeight + CGFloat(rows - 1) * 8 + gridVerticalPadding * 2
    }

    private var resolvedMatchSectionHeight: CGFloat {
        min(wrappedMatchSectionHeight, maxMatchSectionHeight)
    }

    var body: some View {
        if isVisible {
            ZStack {
                menuScrim
                    .ignoresSafeArea()
                    .onTapGesture(perform: onClose)
                    .transition(.opacity)

                VStack(spacing: 0) {
                    if syncItems.isEmpty {
                        closeOnlyHeader
                    } else {
                        topStrip(items: syncItems)
                    }

                    if !matchItems.isEmpty {
                        ScrollView(
                            .vertical,
                            showsIndicators: wrappedMatchSectionHeight > maxMatchSectionHeight + 1
                        ) {
                            matchGrid(items: matchItems)
                        }
                        .frame(height: resolvedMatchSectionHeight)
                    }

                    if !toolItems.isEmpty {
                        toolsBar(items: toolItems)
                    }
                }
                .frame(width: dialogWidth)
                .coordinateSpace(name: "scoreboard_menu")
                // 高度完全 wrap_content：头部/底栏固定，中部网格由
                // resolvedMatchSectionHeight 按行数撑开（上限 maxMatchSectionHeight
                // 保证总高不超出屏幕）。不要用 frame(maxHeight:)——flexible frame
                // 会把钳制后的提议高度当成自身尺寸，把卡片撑到接近全屏。
                .background(dialogBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 32, x: 0, y: 12)
                .contentShape(Rectangle())
                .onTapGesture { }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .overlay(alignment: .topTrailing) {
                    Text(" ")
                        .font(.system(size: 1))
                        .frame(width: 1, height: 1)
                        .opacity(0.001)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(NSLocalizedString("menu", value: "Menu", comment: "Scoreboard menu"))
                        .accessibilityIdentifier("scoreboard_menu_dialog")
                }
            }
            // 弹层表面固定深色（dialogBackground #202124），但内部仍引用 Theme.primary 等
            // 动态色；不强制 dark 会让同一个绿色随系统外观在 #4CAF50/#30D158 之间跳。
            // 与 GameOverDialog 对齐：固定深色面板一律锁定 dark 环境。
            .environment(\.colorScheme, .dark)
            .onAppear {
                revealServePopup()
                var parameters: AnalyticsParameters = [.actionName: .string("menu_open")]
                if let analyticsGameType {
                    parameters[.gameType] = .string(analyticsGameType.analyticsIdentifier)
                }
                AppAnalytics.track(.scoreboardAction, parameters: parameters)
            }
            .onChange(of: voiceAnnouncementEnabled) { _, enabled in
                if enabled { revealServePopup() } else { showServePopup = false }
            }
            .onDisappear { showServePopup = false }
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                containerSize = size
            }
        }
    }

    // MARK: - Sections

    private var closeOnlyHeader: some View {
        HStack {
            Spacer()
            closeButton
        }
        .padding(.horizontal, topBarPadding)
        .padding(.top, topBarPadding)
        .frame(height: closeHeaderHeight)
    }

    private func topStrip(items: [ScoreboardMenuItem]) -> some View {
        HStack(spacing: 4) {
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            HStack(spacing: 4) {
                ForEach(items) { item in
                    menuCard(item: item, size: .medium, stripItem: true)
                        .frame(maxWidth: .infinity)
                        .frame(height: syncCardHeight)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.frame(in: .named("scoreboard_menu")).midX
                        } action: { center in
                            if item.action == "voiceAnnouncement" { voiceCardCenterX = center }
                        }
                            .overlay(alignment: .trailing) {
                                if item.action == "voiceAnnouncement", hasVoiceOptions {
                                    Button {
                                        if showServePopup { showServePopup = false } else { revealServePopup() }
                                    } label: {
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .frame(width: 24, height: 44)
                                    }
                                    .accessibilityLabel(NSLocalizedString("voice_announcement_language", value: "Announcement language", comment: ""))
                                    .accessibilityIdentifier("scoreboard_voice_options")
                                }
                            }
                }
            }
            .frame(maxWidth: .infinity)

            closeButton
        }
        .padding(.horizontal, topBarPadding)
        .padding(.vertical, topBarPadding)
        .overlay(alignment: .bottom) {
            sectionDivider.frame(height: 1).allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            if showServePopup, hasVoiceOptions {
                VStack(spacing: 0) {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(cardBackground)
                        .padding(.bottom, -3)
                        .offset(x: voiceAnchorOffset - servePopupOffset)
                    VStack(spacing: 0) {
                        if hasServeOption {
                            Toggle(NSLocalizedString("voice_announce_server", value: "Announce server", comment: ""), isOn: $announceServer)
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                                .tint(Theme.primary)
                                .padding(14)
                                .accessibilityIdentifier("scoreboard_announce_server_toggle")
                                .onChange(of: announceServer) { _, _ in
                                    ScoreVoiceAnnouncer.shared.stop()
                                }
                            sectionDivider.frame(height: 1).padding(.horizontal, 14)
                        }
                        if showsLanguagePicker {
                            Text(NSLocalizedString("voice_announcement_language", value: "Announcement language", comment: ""))
                                .font(.system(size: 12))
                                .foregroundStyle(secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.top, 10)
                            voiceLanguageRow(code: "zh-CN", identifier: "scoreboard_voice_language_zh")
                            voiceLanguageRow(code: "en-US", identifier: "scoreboard_voice_language_en")
                            if analyticsGameType == .pingpong {
                                Text(selectedLanguageCode == "zh-CN"
                                     ? NSLocalizedString("voice_call_note_zh", value: "国内比赛口径:比分播「3比2」,平分播「3平」。", comment: "")
                                     : NSLocalizedString("voice_call_note_en", value: "ITTF-style calls: 0 as love, 0–0 as Love all, names in pinyin.", comment: ""))
                                    .font(.system(size: 11))
                                    .foregroundStyle(secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                    .padding(.horizontal, 14)
                                    .padding(.top, 10)
                            }
                        }
                    }
                    .padding(.bottom, showsLanguagePicker ? 14 : 0)
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 14))
                }
                .frame(width: servePopupWidth)
                .offset(x: servePopupOffset, y: topBarHeight - 4)
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            }
        }
        .zIndex(1)
    }

    /// 气泡内的语言勾选行:点选即写偏好,下一次播报生效。
    private func voiceLanguageRow(code: String, identifier: String) -> some View {
        Button {
            voiceLanguagePref = code
        } label: {
            HStack {
                Text(code == "zh-CN"
                     ? NSLocalizedString("voice_language_zh_cn", value: "Simplified Chinese", comment: "")
                     : NSLocalizedString("voice_language_en_us", value: "English", comment: ""))
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                Spacer()
                if selectedLanguageCode == code {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func matchGrid(items: [ScoreboardMenuItem]) -> some View {
        VStack(spacing: 8) {
            let rows = stride(from: 0, to: items.count, by: 3).map { start in
                Array(items[start..<min(start + 3, items.count)])
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row) { item in
                        menuCard(item: item, size: .large, stripItem: false)
                            .frame(maxWidth: .infinity)
                            .frame(height: matchCardHeight)
                    }
                    if row.count < 3 {
                        ForEach(0..<(3 - row.count), id: \.self) { _ in
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: matchCardHeight)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, gridVerticalPadding)
    }

    private func toolsBar(items: [ScoreboardMenuItem]) -> some View {
        HStack(spacing: toolsRowGap) {
            ForEach(items) { item in
                menuCard(item: item, size: .small, stripItem: true)
                    .frame(width: toolsCardWidth, height: toolsCardHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, gridVerticalPadding)
        .overlay(alignment: .top) {
            sectionDivider.frame(height: 1).allowsHitTesting(false)
        }
    }

    private var closeButton: some View {
        ScoreboardDialogCloseButton(
            action: onClose,
            accessibilityIdentifier: "scoreboard_menu_close_button"
        )
    }

    // MARK: - Card

    private func menuCard(item: ScoreboardMenuItem, size: ScoreboardMenuCardSize, stripItem: Bool) -> some View {
        Button {
            guard item.enabled else { return }
            trackMenuAction(item)
            if item.action == "usageHint" {
                onClose()
                // Let the menu leave the hierarchy before presenting the
                // blocking usage overlay. Presenting both in one transaction
                // can leave the second-open card unhittable in landscape.
                DispatchQueue.main.async {
                    if let usageHintPresenter {
                        usageHintPresenter()
                    } else if let onUsageHint {
                        onUsageHint()
                    } else {
                        usageHintCoordinator?.presentFromMenu()
                    }
                }
                return
            }
            // Always notify parent first so pending green-confirm state can clear
            // when tapping non-confirm actions handled inside the dialog.
            onMenuItemClick(item.action)
            if item.action == "whistle" {
                SoundManager.shared.playSound("whistle")
                return
            }
            if item.action == "screenshot" {
                ScreenshotSaveCoordinator.shared.prepareForCapture()
                onClose()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    captureScoreboardScreenshot()
                }
                return
            }
            if !item.keepDialogOpen {
                onClose()
            }
        } label: {
            VStack(spacing: size == .large ? 7 : 4) {
                if let iconAsset = item.iconAsset {
                    Image(iconAsset)
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: iconSize(size), height: iconSize(size))
                        .accessibilityHidden(true)
                } else if let customText = item.customText {
                    Text(customText)
                        .font(.system(
                            size: customTextSize(size) * min(2, max(0.5, item.customTextScale)),
                            weight: .bold
                        ))
                        .foregroundColor(.white)
                } else if let icon = item.icon {
                    Group {
                        if icon == "pause" {
                            ScoreboardMenuPauseIcon()
                                .frame(width: iconSize(size), height: iconSize(size))
                        } else {
                            Image(systemName: icon)
                                .font(.system(size: iconSize(size), weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                }

                Text(item.title)
                    .font(.system(size: labelSize(size), weight: size == .large ? .medium : .regular))
                    .foregroundColor(size == .large ? .white : secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: stripItem ? 8 : (size == .large ? 12 : 10), style: .continuous)
                    .fill(cardFill(item: item, stripItem: stripItem))
            )
            .opacity(item.enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        // Preserve SwiftUI's native Button accessibility role. The compact
        // tool cards must remain queryable as Buttons in landscape UI tests.
        .accessibilityLabel(item.title)
        .accessibilityIdentifier("scoreboard_menu_action_\(item.action)")
        .disabled(!item.enabled)
    }

    private func trackMenuAction(_ item: ScoreboardMenuItem) {
        var parameters: AnalyticsParameters = [
            .actionName: .string(analyticsActionName(item.action))
        ]
        if let analyticsGameType {
            parameters[.gameType] = .string(analyticsGameType.analyticsIdentifier)
            if item.confirming,
               ["endGame", "finish", "settleMatch"].contains(item.action) {
                AppAnalytics.markNextMatchEndReason(.manualFinish, gameType: analyticsGameType)
            }
        }

        switch item.action {
        case "undo":
            AppAnalytics.track(.scoreboardAction, parameters: parameters)
        case "reset" where item.confirming:
            parameters[.result] = .string(AnalyticsResult.success.rawValue)
            AppAnalytics.track(.scoreboardAction, parameters: parameters)
        case "reset":
            parameters[.result] = .string(AnalyticsResult.requested.rawValue)
            AppAnalytics.track(.scoreboardAction, parameters: parameters)
        default:
            parameters[.result] = .string(AnalyticsResult.requested.rawValue)
            AppAnalytics.track(.scoreboardAction, parameters: parameters)
        }
    }

    private func analyticsActionName(_ action: String) -> String {
        var value = ""
        for character in action {
            if character.isUppercase {
                if !value.isEmpty { value.append("_") }
                value.append(character.lowercased())
            } else {
                value.append(character)
            }
        }
        return value
    }

    private func cardFill(item: ScoreboardMenuItem, stripItem: Bool) -> Color {
        if item.confirming { return confirmBackground }
        if stripItem { return .clear }
        // 对齐安卓：extra 菜单项可携带自定义底色（如斯诺克浅绿高亮卡）。
        return item.backgroundColor ?? cardBackground
    }

    private func iconSize(_ size: ScoreboardMenuCardSize) -> CGFloat {
        switch size {
        case .large: return min(34, max(28, matchCardHeight * 0.35))
        case .medium: return 20
        case .small: return 18
        }
    }

    private func labelSize(_ size: ScoreboardMenuCardSize) -> CGFloat {
        switch size {
        case .large: return min(15, max(13, matchCardHeight * 0.15))
        case .medium: return 12
        case .small: return 11
        }
    }

    private func customTextSize(_ size: ScoreboardMenuCardSize) -> CGFloat {
        switch size {
        case .large: return min(34, max(28, matchCardHeight * 0.35))
        case .medium: return 18
        case .small: return 14
        }
    }
}

private struct ScoreboardMenuPauseIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let barWidth = size * 0.2
        let barHeight = size * 0.62
        let gap = size * 0.24
        let cornerSize = CGSize(width: barWidth * 0.36, height: barWidth * 0.36)
        let y = rect.midY - barHeight / 2
        var path = Path()
        for x in [rect.midX - gap / 2 - barWidth, rect.midX + gap / 2] {
            path.addRoundedRect(
                in: CGRect(x: x, y: y, width: barWidth, height: barHeight),
                cornerSize: cornerSize,
                style: .continuous
            )
        }
        return path
    }
}

private func captureScoreboardScreenshot() {
    ScreenshotSaveCoordinator.shared.captureCurrentWindowAndSubmit()
}

#Preview {
    ZStack {
        Color.red.opacity(0.8)
        MenuDialog(
            isVisible: true,
            onClose: {},
            onMenuItemClick: { _ in },
            showEndGame: true,
            resetConfirming: true
        )
    }
}
