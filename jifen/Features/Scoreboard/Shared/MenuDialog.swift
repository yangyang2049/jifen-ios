//
//  MenuDialog.swift
//  jifen
//
//  Scoreboard operation menu — 1:1 with HarmonyOS MenuDialog
//  (top sync strip / middle match large cards / bottom tools small cards).
//

import Photos
import SwiftUI
import UIKit

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
        showWhistle: Bool = true,
        showScreenshot: Bool = true,
        showDisplaySettings: Bool = true,
        showSettleMatch: Bool = false,
        resetConfirming: Bool = false,
        exchangeConfirming: Bool = false,
        finishConfirming: Bool = false,
        settleConfirming: Bool = false,
        extraItems: [ScoreboardMenuItem] = []
    ) -> [ScoreboardMenuItem] {
        var items: [ScoreboardMenuItem] = []

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

        if showSettleMatch {
            items.append(
                ScoreboardMenuItem(
                    title: NSLocalizedString("settle_match", value: "结算", comment: ""),
                    action: "settleMatch",
                    group: .match,
                    icon: "checkmark.seal",
                    keepDialogOpen: true,
                    confirming: settleConfirming
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

        items.append(
            ScoreboardMenuItem(
                title: NSLocalizedString("scoreboard_usage_hint_menu", value: "使用说明", comment: ""),
                action: "usageHint",
                group: .tools,
                customText: "?",
                keepDialogOpen: true
            )
        )

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
    @State private var showUsageHint = false

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
            .sheet(isPresented: $showUsageHint) {
                ScoreboardUsageHintView()
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
            // Always notify parent first so pending green-confirm state can clear
            // when tapping non-confirm actions handled inside the dialog.
            onMenuItemClick(item.action)
            if item.action == "usageHint" {
                showUsageHint = true
                return
            }
            if item.action == "whistle" {
                SoundManager.shared.playSound("whistle")
                return
            }
            if item.action == "screenshot" {
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

struct ScoreboardUsageHintView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                usageRow("hand.tap", "scoreboard_usage_tap", "点击计分区加分；部分项目点击后会打开回合或结算面板。")
                usageRow("arrow.uturn.backward", "scoreboard_usage_undo", "误操作后可在菜单中撤销。")
                usageRow("pencil", "scoreboard_usage_edit", "点击铅笔可编辑名称和比分，点击对勾保存。")
                usageRow("arrow.counterclockwise", "scoreboard_usage_reset", "重置、换边、结束比赛、结算等需要再次点击同一按钮确认（按钮会变绿）。")
                usageRow("flag.checkered", "scoreboard_usage_finish", "结束比赛后会保存为已完成记录。")
                usageRow("textformat.size", "scoreboard_usage_display", "显示设置可调整主题、字体和沉浸模式。")
            }
            .navigationTitle(NSLocalizedString("scoreboard_usage_hint_title", value: "计分板使用说明", comment: ""))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("done", value: "完成", comment: "")) { dismiss() }
                }
            }
        }
    }

    private func usageRow(_ icon: String, _ key: String, _ fallback: String) -> some View {
        Label(NSLocalizedString(key, value: fallback, comment: ""), systemImage: icon)
            .padding(.vertical, 4)
    }
}

private func captureScoreboardScreenshot() {
    guard let scene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState == .foregroundActive }),
          let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first else {
        ScoreboardScreenshotToast.show(NSLocalizedString("screenshot_failed", value: "截图失败", comment: ""))
        return
    }
    let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
    let image = renderer.image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    saveScoreboardScreenshotToPhotoLibrary(image)
}

private func saveScoreboardScreenshotToPhotoLibrary(_ image: UIImage) {
    let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

    switch status {
    case .authorized, .limited:
        performScoreboardScreenshotSave(image)
    case .notDetermined:
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
            DispatchQueue.main.async {
                if newStatus == .authorized || newStatus == .limited {
                    performScoreboardScreenshotSave(image)
                } else {
                    ScoreboardScreenshotToast.show(
                        NSLocalizedString("please_allow_photo_access", value: "请在设置中允许访问相册", comment: "")
                    )
                }
            }
        }
    case .denied, .restricted:
        ScoreboardScreenshotToast.show(
            NSLocalizedString("please_allow_photo_access", value: "请在设置中允许访问相册", comment: "")
        )
    @unknown default:
        ScoreboardScreenshotToast.show(
            NSLocalizedString("please_allow_photo_access", value: "请在设置中允许访问相册", comment: "")
        )
    }
}

private func performScoreboardScreenshotSave(_ image: UIImage) {
    PHPhotoLibrary.shared().performChanges({
        PHAssetChangeRequest.creationRequestForAsset(from: image)
    }) { success, error in
        DispatchQueue.main.async {
            if success {
                ScoreboardScreenshotToast.show(
                    NSLocalizedString("screenshot_saved", value: "截图已保存", comment: "")
                )
            } else {
                let errorMessage = error?.localizedDescription
                    ?? NSLocalizedString("unknown_error", value: "未知错误", comment: "")
                ScoreboardScreenshotToast.show(
                    String(format: NSLocalizedString("save_failed", value: "保存失败: %@", comment: ""), errorMessage)
                )
            }
        }
    }
}

@MainActor
private enum ScoreboardScreenshotToast {
    private static var hostingController: UIHostingController<ToastView>?
    private static var hideWorkItem: DispatchWorkItem?

    static func show(_ message: String, duration: TimeInterval = 2.0) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first else { return }

        hideWorkItem?.cancel()
        hostingController?.view.removeFromSuperview()
        hostingController = nil

        let toast = ToastView(message: message)
        let hosting = UIHostingController(rootView: toast)
        hosting.view.backgroundColor = .clear
        hosting.view.isUserInteractionEnabled = false
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: window.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: window.bottomAnchor),
        ])
        hostingController = hosting

        let workItem = DispatchWorkItem {
            hosting.view.removeFromSuperview()
            if hostingController === hosting {
                hostingController = nil
            }
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
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
