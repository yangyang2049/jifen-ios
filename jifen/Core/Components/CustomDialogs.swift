//
//  CustomDialogs.swift
//  jifen
//
//  对齐安卓 ui/dialog/CustomConfirmDialog.kt：
//  - CustomConfirmDialog：圆角 16 深卡、标题/正文居中、胶囊双按钮（取消在左、确认在右）
//  手机卡片宽 280，regular 布局 400（安卓 confirmDialogMaxWidthDp）。
//

import SwiftUI

/// 与触发按钮保持空间关系的系统帮助 Popover。
/// 不指定呈现背景，让 iOS 26 使用 Liquid Glass，旧系统自动回退到原生材质。
/// 小屏（如 iPhone SE）上靠下的按钮下方空间不足，会自动改为向锚点上方展开。
struct SystemHelpButton: View {
    let title: String
    let message: String
    var iconFontSize: CGFloat = 15
    var accessibilityIdentifier: String? = nil
    /// 手动指定箭头边（.top = 气泡在锚点下方展开、.bottom = 在上方展开）；nil 时自动判断。
    var preferredArrowEdge: Edge? = nil

    @State private var isPresented = false
    @State private var fitsBelowAnchor = true

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: iconFontSize, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .modifier(OptionalAccessibilityIdentifier(identifier: accessibilityIdentifier))
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { fitsBelowAnchor = Self.popoverFitsBelow(geo.frame(in: .global)) }
                    .onChange(of: isPresented) { _, presented in
                        guard presented else { return }
                        fitsBelowAnchor = Self.popoverFitsBelow(geo.frame(in: .global))
                    }
            }
        )
        .popover(
            isPresented: $isPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: preferredArrowEdge ?? (fitsBelowAnchor ? .top : .bottom)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(idealWidth: 280, maxWidth: 320, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
    }

    /// 估算锚点下方的可用空间能否容纳气泡（内容约 260pt 高，含边距）；
    /// 放不下且上方空间更大时返回 false（气泡改在锚点上方展开）。
    private static func popoverFitsBelow(_ anchorFrame: CGRect) -> Bool {
        let windowHeight = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.bounds.height }
            .first ?? UIScreen.main.bounds.height
        let below = windowHeight - anchorFrame.maxY
        let above = anchorFrame.minY
        return below >= min(260, above)
    }
}

private struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

/// 安卓 ToolWhistleRed
private let customDialogConfirmRed = Color(hex: "FF3B30")

private var customDialogMaxWidth: CGFloat {
    Theme.usesPadLayout ? 400 : 280
}

/// 深色卡片容器：圆角 16、阴影、内边距 24，标题 20 Bold 居中。
private struct CustomDialogCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)

            content()
        }
        .padding(24)
        .frame(maxWidth: customDialogMaxWidth)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.cardBackground)
                .shadow(color: .black.opacity(0.25), radius: 8)
        )
    }
}

/// 胶囊按钮（高 48，文字 16 Medium）。
private struct CustomDialogPillButton: View {
    let title: String
    let background: Color
    let foreground: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Capsule().fill(background))
        }
        .buttonStyle(.plain)
    }
}

/// 全屏遮罩 + 居中卡片；点遮罩取消（安卓 dismissOnClickOutside）。
private struct CustomDialogScrim<Content: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Theme.scoreboardDialogScrim
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .transition(.opacity)

            content()
                .padding(.horizontal, 24)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }
}

struct CustomConfirmDialog: View {
    let title: String
    let message: String
    let confirmText: String
    var cancelText: String? = nil
    var confirmColor: Color = customDialogConfirmRed
    let onConfirm: () -> Void
    /// 取消按钮独立回调；未提供时与点遮罩一样走 onDismiss（安卓 dismissOnClickOutside 语义）。
    var onCancel: (() -> Void)? = nil
    let onDismiss: () -> Void

    var body: some View {
        CustomDialogScrim(onDismiss: onDismiss) {
            CustomDialogCard(title: title) {
                Text(message)
                    .font(.system(size: 16))
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)

                HStack(spacing: 16) {
                    if let cancelText {
                        CustomDialogPillButton(
                            title: cancelText,
                            background: Theme.controlBackground,
                            foreground: Theme.textPrimary,
                            action: onCancel ?? onDismiss
                        )
                    }
                    CustomDialogPillButton(
                        title: confirmText,
                        background: confirmColor,
                        foreground: .white,
                        action: onConfirm
                    )
                }
            }
        }
    }
}
