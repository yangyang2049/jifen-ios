import SwiftUI

/// 悬浮返回按钮：用于隐藏了系统导航栏的工具页，与边缘右滑返回手势并存。
struct FloatingBackButton: View {
    /// 指定配色（如红黄牌页随卡色切换）；不传则走 Theme.floatingIconColor。
    var iconColor: Color?
    var circleColor: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(iconColor ?? Theme.floatingIconColor)
                .frame(width: 40, height: 40)
                .background(Circle().fill(circleColor ?? Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString("back", value: "返回", comment: ""))
        .accessibilityIdentifier("BackButton")
    }
}
