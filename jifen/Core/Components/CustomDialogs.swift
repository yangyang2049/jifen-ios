//
//  CustomDialogs.swift
//  jifen
//
//  对齐安卓 ui/dialog/CustomConfirmDialog.kt：
//  - CustomConfirmDialog：圆角 16 深卡、标题/正文居中、胶囊双按钮（取消在左、确认在右）
//  - CustomListDialog：标题 + 列表内容 + 底部全宽胶囊按钮
//  手机卡片宽 280，regular 布局 400（安卓 confirmDialogMaxWidthDp）。
//

import SwiftUI

/// 安卓 ToolWhistleRed
private let customDialogConfirmRed = Color(hex: "FF3B30")
/// 安卓选中项绿色勾（MeTabScreen 外观弹窗 Check tint）
private let customDialogCheckGreen = Color(hex: "22C55E")

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

struct CustomListDialog<Option: Identifiable, Content: View>: View {
    let title: String
    let options: [Option]
    /// 当前选中项 id；命中时行尾显示绿色勾。
    let selectedID: (Option) -> String
    let onSelect: (Option) -> Void
    var bottomButtonText: String
    let onDismiss: () -> Void
    @ViewBuilder let optionRow: (Option) -> Content

    var body: some View {
        CustomDialogScrim(onDismiss: onDismiss) {
            CustomDialogCard(title: title) {
                VStack(spacing: 0) {
                    ForEach(options) { option in
                        optionRow(option)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(option) }
                    }
                }
                .padding(.bottom, 16)

                CustomDialogPillButton(
                    title: bottomButtonText,
                    background: Theme.controlBackground,
                    foreground: Theme.textPrimary,
                    action: onDismiss
                )
            }
        }
    }
}

/// 安卓外观弹窗同款选项行：文本 + 行尾选中绿勾（未选中留 20pt 占位）。
struct CustomDialogCheckRow: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(customDialogCheckGreen)
                    .frame(width: 20, height: 20)
            } else {
                Color.clear
                    .frame(width: 20, height: 20)
            }
        }
        .padding(.vertical, 10)
    }
}
