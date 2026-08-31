import SwiftUI

/// 区块标题：左侧一条绿色竖条 + 标题文字，样式对齐安卓 `SectionTitleWithBar`。
///
/// 仅新增竖条，保留各调用处原有的字号/字重与间距（默认 H5 / medium / textPrimary）。
/// 绿色取 `Theme.accentColor`（浅色 #4CAF50、深色 #30D158），与安卓 `Primary` 一致。
struct SectionTitleView: View {
    let title: String
    var font: Font = .system(size: Theme.fontH5, weight: .medium)
    var color: Color = Theme.textPrimary

    var body: some View {
        HStack(spacing: Theme.sm) {
            Rectangle()
                .fill(Theme.accentColor)
                .frame(width: 3, height: 16)
                .cornerRadius(2)
            Text(title)
                .font(font)
                .foregroundColor(color)
        }
    }
}
