import SwiftUI

/// Aligns with Android `ScoreCustomAdjustDialog` / HOS `CustomAdjustPanel`.
struct ScoreCustomAdjustPanel: View {
    let targetName: String
    let currentScore: Int
    let onDismiss: () -> Void
    let onAdjust: (Int) -> Void

    @State private var sign: Int = 1
    @State private var customValue: String = ""
    @State private var showCustomInput = false
    @State private var showInvalidToast = false

    @FocusState private var isCustomFieldFocused: Bool

    private let presets = Array(1...9)

    var body: some View {
        GeometryReader { geometry in
            let compactHeight = geometry.size.height < 400
            let sectionSpacing: CGFloat = compactHeight ? 16 : 22
            let buttonHeight: CGFloat = compactHeight ? 54 : 62
            let panelWidth = Theme.dialogWidth(
                availableWidth: geometry.size.width,
                role: .scoreAdjustment
            )

            ZStack {
                Theme.scoreboardDialogScrim
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)

                VStack(spacing: sectionSpacing) {
                    Capsule()
                        .fill(Color.white.opacity(0.34))
                        .frame(width: 52, height: 5)
                        .padding(.top, 2)
                        .onTapGesture(perform: onDismiss)

                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(targetName)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Theme.scoreboardDialogTextPrimary)
                                .lineLimit(1)
                            Text(NSLocalizedString("score_custom_adjust_label", value: "自定义加减分", comment: ""))
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.scoreboardDialogTextSecondary)
                        }
                        Spacer(minLength: 24)
                        Text("\(currentScore)")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(Theme.scoreboardDialogTextPrimary)
                            .monospacedDigit()
                    }
                    .padding(.bottom, compactHeight ? 2 : 8)

                    HStack(spacing: 14) {
                        signButton(
                            selected: sign > 0,
                            selectedColor: Theme.primary,
                            systemName: "plus",
                            labelKey: "score_custom_adjust_increment",
                            labelFallback: "加分",
                            height: buttonHeight
                        ) {
                            sign = 1
                            showCustomInput = false
                            customValue = ""
                            showInvalidToast = false
                        }
                        signButton(
                            selected: sign < 0,
                            selectedColor: Color(hex: "E5484D"),
                            systemName: "minus",
                            labelKey: "score_custom_adjust_decrement",
                            labelFallback: "减分",
                            height: buttonHeight
                        ) {
                            sign = -1
                            showCustomInput = false
                            customValue = ""
                            showInvalidToast = false
                        }
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                        ForEach(presets, id: \.self) { value in
                            Button {
                                apply(value)
                            } label: {
                                Text("\(value)")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(Theme.scoreboardDialogTextPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: buttonHeight)
                                    .background(Theme.scoreboardDialogControl)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            showCustomInput = true
                        } label: {
                            Text("…")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Theme.scoreboardDialogTextPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: buttonHeight)
                                .background(Theme.scoreboardDialogControl)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    if showCustomInput {
                        HStack(spacing: 12) {
                            TextField(
                                NSLocalizedString(
                                    "score_custom_adjust_custom_value_placeholder",
                                    value: "自定义分值",
                                    comment: ""
                                ),
                                text: $customValue
                            )
                            .keyboardType(.numberPad)
                            .textFieldStyle(.plain)
                            .focused($isCustomFieldFocused)
                            .foregroundStyle(Theme.scoreboardDialogTextPrimary)
                            .padding(.horizontal, 14)
                            .frame(height: 50)
                            .background(Theme.scoreboardDialogControl)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .onChange(of: customValue) { _, _ in
                                if showInvalidToast { showInvalidToast = false }
                            }

                            Button(action: applyCustomInput) {
                                Text(NSLocalizedString("score_custom_adjust_apply", value: "应用", comment: ""))
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 20)
                                    .frame(height: 50)
                                    .background(Theme.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if showInvalidToast {
                        Text(NSLocalizedString("score_custom_adjust_invalid_value", value: "请输入有效分值", comment: ""))
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "E5484D"))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, compactHeight ? 16 : 22)
                .frame(width: panelWidth)
                .background(Theme.scoreboardDialogSurface)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .offset(y: compactHeight ? 4 : 10)
            }
        }
        .environment(\.colorScheme, .dark)
        .onChange(of: showCustomInput) { _, shown in
            // 点击"…"出现自定义输入框后自动聚焦打开键盘，稍等视图插入完成
            guard shown else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if showCustomInput {
                    isCustomFieldFocused = true
                }
            }
        }
    }

    private func signButton(
        selected: Bool,
        selectedColor: Color,
        systemName: String,
        labelKey: String,
        labelFallback: String,
        height: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .bold))
                Text(NSLocalizedString(labelKey, value: labelFallback, comment: ""))
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(selected ? Color.white : Theme.scoreboardDialogTextPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(selected ? selectedColor : Theme.scoreboardDialogControl)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString(labelKey, value: labelFallback, comment: ""))
    }

    private func apply(_ value: Int) {
        // 对齐安卓 ScoreEditAdjustRows：调分提交时轻震反馈。
        VibrationManager.shared.vibrateLight()
        onAdjust(sign * value)
        onDismiss()
    }

    private func applyCustomInput() {
        guard let value = Int(customValue), value >= 1 else {
            showInvalidToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showInvalidToast = false
            }
            return
        }
        apply(value)
    }
}
