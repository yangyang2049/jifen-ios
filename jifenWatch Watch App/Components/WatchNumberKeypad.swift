import SwiftUI

/// 自定义数值的校验规则（纯逻辑，便于单测）。
/// 口径对齐鸿蒙手表 `WatchNumberKeypadOverlay`：只收数字、不留前导 0、按档位长度截断，
/// 超出 [min, max] 或奇偶限制一律判非法（确认键置灰）。
enum WatchNumberKeypadRules {
    /// 取值上限对应的可输入位数：99 → 2 位，999 → 3 位。
    static func maxDigits(for maxValue: Int) -> Int {
        max(1, String(max(1, maxValue)).count)
    }

    /// 输入归一化：丢弃非数字、去掉前导 0、按 maxDigits 截断。
    static func sanitize(_ raw: String, maxDigits: Int) -> String {
        var digits = ""
        for character in raw where character.isNumber {
            if digits.isEmpty && character == "0" { continue }
            guard digits.count < maxDigits else { break }
            digits.append(character)
        }
        return digits
    }

    static func isValid(_ value: Int, minValue: Int, maxValue: Int, requiresOdd: Bool) -> Bool {
        guard value >= minValue, value <= maxValue else { return false }
        return !requiresOdd || value % 2 == 1
    }

    /// 把输入框里的字符串解析成可提交的值；非法返回 nil。
    static func validatedValue(
        _ raw: String,
        minValue: Int,
        maxValue: Int,
        requiresOdd: Bool
    ) -> Int? {
        guard let value = Int(raw), isValid(value, minValue: minValue, maxValue: maxValue, requiresOdd: requiresOdd) else {
            return nil
        }
        return value
    }

    /// 当前值不在档位里即视为「自定义」：末位铅笔 pill 显示数字而不是铅笔图标。
    static func isCustomActive(value: Int, presets: [Int]) -> Bool {
        !presets.contains(value)
    }

    /// 语言无关的取值范围提示（只用数字与连接号，不需要新增 47 语种文案）。
    static func rangeText(minValue: Int, maxValue: Int) -> String {
        "\(minValue)–\(maxValue)"
    }
}

/// 手表端自定义数字弹层：预设档位覆盖不到的值从这里输入。
/// 版面照 46mm 圆屏等比缩放到当前屏幕，40/42/46/49mm 共用一套。
struct WatchNumberKeypad: View {
    let minValue: Int
    let maxValue: Int
    var requiresOdd: Bool = false
    var initialValue: Int?
    let onConfirm: (Int) -> Void
    let onClose: () -> Void

    @State private var draft: String
    @State private var showsRangeHint = false

    /// 参考直径：46mm（208pt）下的基准尺寸，其余表径按比例缩放。
    private static let referenceDiameter: CGFloat = 300
    /// 内容区相对圆直径的宽度比例：内接方形是 1/√2 ≈ 0.707，留一点余量取 0.70。
    static let contentWidthRatio: CGFloat = 0.70

    init(
        minValue: Int,
        maxValue: Int,
        requiresOdd: Bool = false,
        initialValue: Int? = nil,
        onConfirm: @escaping (Int) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.minValue = minValue
        self.maxValue = maxValue
        self.requiresOdd = requiresOdd
        self.initialValue = initialValue
        self.onConfirm = onConfirm
        self.onClose = onClose
        _draft = State(initialValue: initialValue.map(String.init) ?? "")
    }

    private var maxDigits: Int {
        WatchNumberKeypadRules.maxDigits(for: maxValue)
    }

    private var validated: Int? {
        WatchNumberKeypadRules.validatedValue(
            draft,
            minValue: minValue,
            maxValue: maxValue,
            requiresOdd: requiresOdd
        )
    }

    /// 有输入但不合法时才标红，空输入用占位提示。
    private var isInvalid: Bool {
        !draft.isEmpty && validated == nil
    }

    private var rangeText: String {
        WatchNumberKeypadRules.rangeText(minValue: minValue, maxValue: maxValue)
    }

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let scale = min(1, max(0.5, diameter / Self.referenceDiameter))

            ZStack {
                // 遮罩不接管点按：鸿蒙手表同样只给关闭按钮，避免弹层刚出现就被
                // 同一次抬手事件命中而立即关掉。
                WatchTheme.panelScrim
                    .ignoresSafeArea()

                panel(scale: scale, diameter: diameter * 0.98)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func panel(scale: CGFloat, diameter: CGFloat) -> some View {
        VStack(spacing: 8 * scale) {
            HStack(spacing: 10 * scale) {
                // 关闭钮与输入框同高，整块落在内接方形里；圆屏下左右两端的
                // 触控目标再靠 buttonStyle 外扩，不去挤内容宽度。
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18 * scale, weight: .semibold))
                        .foregroundStyle(WatchTheme.primaryText)
                        .frame(width: 44 * scale, height: 44 * scale)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("cancel", value: "取消", comment: ""))

                displayField(scale: scale)
            }

            digitRow([1, 2, 3, 4], scale: scale)
            digitRow([5, 6, 7, 8], scale: scale)
            HStack(spacing: 8 * scale) {
                digitButton(9, scale: scale)
                digitButton(0, scale: scale)
                deleteButton(scale: scale)
                confirmButton(scale: scale)
            }
        }
        // 圆形裁切只保留内接方形：内容宽度按直径的 0.70 收口（内接方形为 0.707d），
        // 否则最上一行与最下一行会被圆边切掉。
        .frame(width: diameter * Self.contentWidthRatio)
        .frame(width: diameter, height: diameter)
        .background(WatchTheme.card)
        .clipShape(Circle())
    }

    private func displayField(scale: CGFloat) -> some View {
        Text(draft.isEmpty ? rangeText : draft)
            .font(.system(size: 30 * scale, weight: .bold, design: .rounded))
            .foregroundStyle(
                isInvalid
                    ? WatchTheme.dangerRed
                    : (draft.isEmpty ? Color.white.opacity(0.38) : WatchTheme.accent)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
            .frame(height: 44 * scale)
            .background(Color.white.opacity(0.10))
            .clipShape(Capsule())
            .accessibilityIdentifier("watch_keypad_display")
            .accessibilityValue(draft.isEmpty ? rangeText : draft)
    }

    private func digitRow(_ values: [Int], scale: CGFloat) -> some View {
        HStack(spacing: 8 * scale) {
            ForEach(values, id: \.self) { value in
                digitButton(value, scale: scale)
            }
        }
    }

    private func digitButton(_ value: Int, scale: CGFloat) -> some View {
        Button {
            var updated = draft + String(value)
            updated = WatchNumberKeypadRules.sanitize(updated, maxDigits: maxDigits)
            if updated.isEmpty { updated = "0" }
            draft = updated
            showsRangeHint = false
        } label: {
            Text("\(value)")
                .font(.system(size: 24 * scale, weight: .medium, design: .rounded))
                .foregroundStyle(WatchTheme.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 56 * scale)
                .background(Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("watch_keypad_digit_\(value)")
    }

    private func deleteButton(scale: CGFloat) -> some View {
        Button {
            guard !draft.isEmpty else { return }
            draft.removeLast()
        } label: {
            Image(systemName: "delete.left")
                .font(.system(size: 20 * scale, weight: .medium))
                .foregroundStyle(WatchTheme.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 56 * scale)
                .background(Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString("delete", value: "删除", comment: ""))
        .accessibilityIdentifier("watch_keypad_delete")
    }

    private func confirmButton(scale: CGFloat) -> some View {
        Button {
            guard let value = validated else {
                showsRangeHint = true
                return
            }
            onConfirm(value)
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 20 * scale, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56 * scale)
                .background(WatchTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(validated == nil)
        .opacity(validated == nil ? 0.4 : 1)
        .accessibilityLabel(NSLocalizedString("confirm", value: "确认", comment: ""))
        .accessibilityIdentifier("watch_keypad_confirm")
    }
}
