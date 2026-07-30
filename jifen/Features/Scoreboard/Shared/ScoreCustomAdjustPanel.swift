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
                Color.black.opacity(0.45)
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
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Text(NSLocalizedString("score_custom_adjust_label", value: "自定义加减分", comment: ""))
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 24)
                        Text("\(currentScore)")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
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
                        }
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                        ForEach(presets, id: \.self) { value in
                            Button {
                                apply(value)
                            } label: {
                                Text("\(value)")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: buttonHeight)
                                    .background(Theme.dialogControlBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            showCustomInput = true
                        } label: {
                            Text("…")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: buttonHeight)
                                .background(Theme.dialogControlBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                            .padding(.horizontal, 14)
                            .frame(height: 50)
                            .background(Theme.dialogControlBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

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
                .background(Theme.homeDialogBackground)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .offset(y: compactHeight ? 4 : 10)
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
            .foregroundStyle(selected ? Color.white : Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(selected ? selectedColor : Theme.dialogControlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString(labelKey, value: labelFallback, comment: ""))
    }

    private func apply(_ value: Int) {
        onAdjust(sign * value)
        onDismiss()
    }

    private func applyCustomInput() {
        guard let value = Int(customValue), value >= 1 else {
            showInvalidToast = true
            return
        }
        apply(value)
    }
}
