//
//  MenuDialog.swift
//  jifen
//
//  Scoreboard operation menu — 1:1 with HarmonyOS MenuDialog
//  (top sync strip / middle match large cards / bottom tools small cards).
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
    var customText: String? = nil
    var keepDialogOpen: Bool = false
    var confirming: Bool = false
    var enabled: Bool = true
}

// MARK: - Default items (aligned with HarmonyOS groups)

enum ScoreboardMenuItemBuilder {
    static func defaultItems(
        showEndGame: Bool = false,
        showExchangeSide: Bool = true,
        showLocalSync: Bool = true,
        showWhistle: Bool = true,
        showScreenshot: Bool = true,
        showDisplaySettings: Bool = true,
        resetConfirming: Bool = false,
        exchangeConfirming: Bool = false,
        finishConfirming: Bool = false,
        extraItems: [ScoreboardMenuItem] = []
    ) -> [ScoreboardMenuItem] {
        var items: [ScoreboardMenuItem] = []

        if showLocalSync {
            items.append(
                ScoreboardMenuItem(
                    title: NSLocalizedString("sync_title", value: "局域网同步", comment: ""),
                    action: "localSync",
                    group: .sync,
                    icon: "rectangle.connected.to.line.below"
                )
            )
        }

        items.append(
            ScoreboardMenuItem(
                title: NSLocalizedString("menu_undo", comment: "Undo"),
                action: "undo",
                group: .match,
                icon: "arrow.uturn.backward",
                keepDialogOpen: true
            )
        )

        if showExchangeSide {
            items.append(
                ScoreboardMenuItem(
                    title: NSLocalizedString("menu_swap_sides", comment: "Exchange sides"),
                    action: "exchangeSide",
                    group: .match,
                    icon: "arrow.left.arrow.right",
                    keepDialogOpen: true,
                    confirming: exchangeConfirming
                )
            )
        }

        let matchExtras = extraItems.filter { $0.group == .match }
        items.append(contentsOf: matchExtras)

        items.append(
            ScoreboardMenuItem(
                title: NSLocalizedString("menu_reset", comment: "Reset"),
                action: "reset",
                group: .match,
                icon: "arrow.counterclockwise",
                keepDialogOpen: true,
                confirming: resetConfirming
            )
        )

        if showEndGame {
            items.append(
                ScoreboardMenuItem(
                    title: NSLocalizedString("menu_end_game", value: "结束比赛", comment: "End game"),
                    action: "endGame",
                    group: .match,
                    icon: "flag.checkered",
                    confirming: finishConfirming
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
                    title: NSLocalizedString("scoreboard_display_settings", value: "显示设置", comment: ""),
                    action: "displaySettings",
                    group: .tools,
                    customText: "Aa"
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

        items.append(contentsOf: extraItems.filter { $0.group == .sync })
        items.append(contentsOf: extraItems.filter { $0.group == .tools })

        return items
    }

    static func orderedMatchItems(_ items: [ScoreboardMenuItem]) -> [ScoreboardMenuItem] {
        let undo = items.filter { $0.action == "undo" }
        let settle = items.filter {
            $0.action.hasPrefix("settle") ||
            $0.action == "endGame" ||
            $0.action == "finish" ||
            $0.action == "exit"
        }
        let middle = items.filter {
            $0.action != "undo" &&
            !$0.action.hasPrefix("settle") &&
            $0.action != "endGame" &&
            $0.action != "finish" &&
            $0.action != "exit"
        }
        return undo + middle + settle
    }
}

// MARK: - Dialog

struct MenuDialog: View {
    let isVisible: Bool
    let onClose: () -> Void
    let onMenuItemClick: (String) -> Void
    var showEndGame: Bool = false
    var showExchangeSide: Bool = true
    var resetConfirming: Bool = false
    var items: [ScoreboardMenuItem]? = nil

    private let dialogBackground = Color(hex: "2C2C2E")
    private let cardBackground = Color(hex: "3A3A3C")
    private let sectionStrip = Color.white.opacity(0.06)
    private let secondaryText = Color(hex: "98989D")
    private let confirmBackground = Color(hex: "4CAF50").opacity(0.5)

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

    private var isCompact: Bool {
        min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) < 400
    }

    private var dialogWidth: CGFloat {
        let shortSide = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        let maxWidth: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 420 : 320
        return min(maxWidth, max(280, shortSide - 32))
    }

    private var syncCardHeight: CGFloat { isCompact ? 44 : 48 }
    private var matchCardHeight: CGFloat { 72 }
    private var toolsCardWidth: CGFloat { isCompact ? 44 : 48 }
    private var toolsCardHeight: CGFloat { isCompact ? 36 : 40 }
    private var sectionPaddingV: CGFloat { isCompact ? 8 : 10 }
    private var toolsRowGap: CGFloat { isCompact ? 10 : 12 }

    var body: some View {
        if isVisible {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onClose)

                VStack(spacing: 0) {
                    if syncItems.isEmpty {
                        closeOnlyHeader
                    } else {
                        topStrip(items: syncItems)
                    }

                    if !matchItems.isEmpty {
                        matchGrid(items: matchItems)
                    }

                    if !toolItems.isEmpty {
                        toolsBar(items: toolItems)
                    }
                }
                .frame(width: dialogWidth)
                .background(dialogBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 32, x: 0, y: 12)
                .contentShape(Rectangle())
                .onTapGesture { }
            }
        }
    }

    // MARK: - Sections

    private var closeOnlyHeader: some View {
        HStack {
            Spacer()
            closeButton
        }
        .padding(.leading, 4)
        .padding(.top, sectionPaddingV)
        .frame(height: syncCardHeight + sectionPaddingV)
    }

    private func topStrip(items: [ScoreboardMenuItem]) -> some View {
        HStack(spacing: 4) {
            Color.clear.frame(width: 40, height: 32)

            HStack(spacing: 4) {
                ForEach(items) { item in
                    menuCard(item: item, size: .medium, stripItem: true)
                        .frame(maxWidth: .infinity)
                        .frame(height: syncCardHeight)
                }
            }
            .frame(maxWidth: .infinity)

            closeButton
        }
        .padding(.leading, 4)
        .padding(.vertical, sectionPaddingV)
        .background(sectionStrip)
    }

    private func matchGrid(items: [ScoreboardMenuItem]) -> some View {
        VStack(spacing: 6) {
            if items.count <= 3 {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        menuCard(item: item, size: .large, stripItem: false)
                            .frame(maxWidth: .infinity)
                            .frame(height: matchCardHeight)
                    }
                }
            } else {
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, sectionPaddingV)
    }

    private func toolsBar(items: [ScoreboardMenuItem]) -> some View {
        HStack(spacing: toolsRowGap) {
            ForEach(items) { item in
                menuCard(item: item, size: .small, stripItem: true)
                    .frame(width: toolsCardWidth, height: toolsCardHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, sectionPaddingV)
        .padding(.bottom, sectionPaddingV + 2)
        .background(sectionStrip)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .padding(.trailing, 8)
    }

    // MARK: - Card

    private func menuCard(item: ScoreboardMenuItem, size: ScoreboardMenuCardSize, stripItem: Bool) -> some View {
        Button {
            guard item.enabled else { return }
            onMenuItemClick(item.action)
            if !item.keepDialogOpen {
                onClose()
            }
        } label: {
            VStack(spacing: size == .large ? 4 : 3) {
                if let customText = item.customText {
                    Text(customText)
                        .font(.system(size: customTextSize(size), weight: .bold))
                        .foregroundColor(.white)
                } else if let icon = item.icon {
                    Image(systemName: icon)
                        .font(.system(size: iconSize(size), weight: .semibold))
                        .foregroundColor(.white)
                }

                Text(item.title)
                    .font(.system(size: labelSize(size), weight: size == .large ? .medium : .regular))
                    .foregroundColor(size == .large ? .white.opacity(0.82) : secondaryText)
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
        .disabled(!item.enabled)
    }

    private func cardFill(item: ScoreboardMenuItem, stripItem: Bool) -> Color {
        if item.confirming { return confirmBackground }
        if stripItem { return .clear }
        return cardBackground
    }

    private func iconSize(_ size: ScoreboardMenuCardSize) -> CGFloat {
        switch size {
        case .large: return 28
        case .medium: return isCompact ? 18 : 20
        case .small: return isCompact ? 16 : 18
        }
    }

    private func labelSize(_ size: ScoreboardMenuCardSize) -> CGFloat {
        switch size {
        case .large: return 12
        case .medium: return 10
        case .small: return 9
        }
    }

    private func customTextSize(_ size: ScoreboardMenuCardSize) -> CGFloat {
        switch size {
        case .large: return 28
        case .medium: return 18
        case .small: return 14
        }
    }
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
