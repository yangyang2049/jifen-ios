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
/// 版面为贴底方形面板（设计稿方案 B）：顶部一行是关闭/当前值/退格，中间 3×3 数字
/// 加通栏 0，底部为通栏绿色确认条；46mm 全屏宽为基准，40/42/49mm 等比缩放共用。
struct WatchNumberKeypad: View {
    let minValue: Int
    let maxValue: Int
    var requiresOdd: Bool = false
    var initialValue: Int?
    let onConfirm: (Int) -> Void
    let onClose: () -> Void

    @State private var draft: String
    @State private var showsRangeHint = false

    /// 参考宽度：46mm（208pt）全屏宽，其余表径按宽度比例缩放。
    private static let referenceWidth: CGFloat = 208

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
            let scale = min(1.1, max(0.5, proxy.size.width / Self.referenceWidth))

            ZStack(alignment: .bottom) {
                // 遮罩不接管点按：鸿蒙手表同样只给关闭按钮，避免弹层刚出现就被
                // 同一次抬手事件命中而立即关掉。
                WatchTheme.panelScrim
                    .ignoresSafeArea()

                panel(scale: scale)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // 面板贴住屏幕物理底边，确认条不被安全区垫高。
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private func panel(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 6 * scale) {
                HStack(spacing: 8 * scale) {
                    closeButton(scale: scale)
                    displayField(scale: scale)
                    deleteButton(scale: scale)
                }

                digitRow([1, 2, 3], scale: scale)
                digitRow([4, 5, 6], scale: scale)
                digitRow([7, 8, 9], scale: scale)
                digitButton(0, scale: scale)
            }
            .padding(.horizontal, 12 * scale)
            .padding(.top, 8 * scale)
            .padding(.bottom, 6 * scale)

            confirmBar(scale: scale)
        }
        .background(WatchTheme.overlayCard)
        .clipShape(TopRoundedCornerShape(radius: 18 * scale))
        .shadow(color: .black.opacity(0.45), radius: 10 * scale, x: 0, y: -4 * scale)
    }

    private func closeButton(scale: CGFloat) -> some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 14 * scale, weight: .semibold))
                .foregroundStyle(WatchTheme.primaryText)
                .frame(width: 34 * scale, height: 34 * scale)
                .background(Color.white.opacity(0.10))
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString("cancel", value: "取消", comment: ""))
    }

    private func displayField(scale: CGFloat) -> some View {
        Text(draft.isEmpty ? rangeText : draft)
            .font(.system(size: 24 * scale, weight: .bold, design: .rounded))
            .foregroundStyle(
                isInvalid
                    ? WatchTheme.dangerRed
                    : (draft.isEmpty ? Color.white.opacity(0.38) : WatchTheme.primaryText)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 34 * scale)
            .accessibilityIdentifier("watch_keypad_display")
            .accessibilityValue(draft.isEmpty ? rangeText : draft)
    }

    private func digitRow(_ values: [Int], scale: CGFloat) -> some View {
        HStack(spacing: 6 * scale) {
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
                .font(.system(size: 17 * scale, weight: .medium, design: .rounded))
                .foregroundStyle(WatchTheme.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 28 * scale)
                .background(Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10 * scale, style: .continuous))
                .contentShape(Rectangle())
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
                .font(.system(size: 15 * scale, weight: .medium))
                .foregroundStyle(WatchTheme.primaryText)
                .frame(width: 34 * scale, height: 34 * scale)
                .background(Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10 * scale, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString("delete", value: "删除", comment: ""))
        .accessibilityIdentifier("watch_keypad_delete")
    }

    private func confirmBar(scale: CGFloat) -> some View {
        Button {
            guard let value = validated else {
                showsRangeHint = true
                return
            }
            onConfirm(value)
        } label: {
            // 绿色实底确认条必须显式白字（项目规范：自动对比度不得改成黑字）。
            Text(NSLocalizedString("confirm", value: "确认", comment: ""))
                .font(.system(size: 15 * scale, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40 * scale)
                .background(WatchTheme.accent)
        }
        .buttonStyle(.plain)
        .disabled(validated == nil)
        .opacity(validated == nil ? 0.4 : 1)
        .accessibilityIdentifier("watch_keypad_confirm")
    }
}

/// 只圆上角的矩形：面板底部贴住屏幕下缘，下角交给系统屏幕圆角裁切。
private struct TopRoundedCornerShape: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: radius, height: radius)
        ).cgPath)
    }
}
