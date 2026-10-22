import SwiftUI

struct SportOptionView: View {
    let sport: GameType
    let isSelected: Bool
    var onClickOption: (() -> Void)? = nil
    /// 绕过内置适配、直接指定图标边长的闭包（参数为卡片边长）。
    /// 快捷入口编辑弹窗用它按卡片大小插值，iPad / Duo 展开内屏放大时图标同步变大。
    var iconSizeProvider: ((CGFloat) -> CGFloat)? = nil

    var body: some View {
        Button(action: {
            onClickOption?()
        }) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let iconSize = iconSizeProvider?(side) ?? max(24, min(56, side * 0.4))
                let fontSize = max(11, min(18, side * 0.12))
                VStack(spacing: Theme.sm) {
                    AppCatalogIcon(gameType: sport, size: iconSize)
                    Text(getGameName(type: sport))
                        .font(.system(size: fontSize, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            .background(Theme.dialogControlBackground)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Theme.homeEditButtonGreen : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(CardButtonStyle())
    }
}
