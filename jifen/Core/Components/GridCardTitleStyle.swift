import SwiftUI

/// 网格卡片标题行数唯一口径：中文（简/繁）一行，卡片保持近正方形；
/// 外文两行并等高占位，避免单词过长被截断。
/// 供记分/计时/工具 Tab 与首页工具区网格卡片共用。
struct GridCardTitleStyle: ViewModifier {
    func body(content: Content) -> some View {
        if ChineseScript.isChinese {
            content
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else {
            content
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
    }
}

extension View {
    func gridCardTitleStyle() -> some View {
        modifier(GridCardTitleStyle())
    }
}
