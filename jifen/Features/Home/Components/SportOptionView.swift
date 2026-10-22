import SwiftUI

struct SportOptionView: View {
    let sport: GameType
    let isSelected: Bool
    var onClickOption: (() -> Void)? = nil
    /// 指定图标占卡片边长的比例；传 nil 时沿用旧的自适应算法。
    /// 快捷入口编辑弹窗按 iPhone 卡片的比例设置，iPad / Duo 展开内屏放大后
    /// 图标随笔变大，不会出现"卡片很大、图标很小"的观感失衡。
    var iconRatio: CGFloat? = nil

    var body: some View {
        Button(action: {
            onClickOption?()
        }) {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let iconSize = iconRatio.map { side * $0 } ?? max(24, min(56, side * 0.4))
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
