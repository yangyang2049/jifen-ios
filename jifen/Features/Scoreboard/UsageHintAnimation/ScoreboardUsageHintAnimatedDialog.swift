import ScoreCore
import SwiftUI

/// 动画分页版使用说明弹窗。交互口径（与 HTML 演示稿一致）：
/// - 每页动画播一遍停在末帧，轻点画面重播本页；
/// - 导航行 = 左箭头（首页禁用）· 居中圆点 · 右箭头；
/// - 首次打开：底部无「知道了」，必须滑到末页，右箭头原位变成「知道了」；
/// - 菜单回看：右箭头只用于翻页（末页收起），底部常驻「知道了」。
struct ScoreboardUsageHintAnimatedDialog: View {
    let pages: [HintPage]
    let alreadyShown: Bool
    let onDismiss: () -> Void

    @State private var pageIdx = 0
    @State private var startDates: [Int: Date] = [:]

    var body: some View {
        GeometryReader { proxy in
            let compactHeight = proxy.size.height < 420
            let metrics = ScoreboardUsageHintDialogMetrics.resolve(
                isPad: Theme.usesPadLayout,
                compactHeight: compactHeight
            )
            let dialogWidth = Theme.dialogWidth(
                availableWidth: proxy.size.width,
                role: .informational
            )
            // 舞台按视口 responsive：矮设备（SE 横屏）用更扁的比例 + 更小的高度占比，
            // 保证标题/说明/导航不被挤出屏；平板空间富余，比例更松弛、占比更大。
            let isPad = Theme.usesPadLayout
            let stageRatio: CGFloat = isPad ? 1.78 : (compactHeight ? 2.4 : 2.1)
            let stageHeightFraction: CGFloat = isPad ? 0.62 : (compactHeight ? 0.42 : 0.52)
            let stageMaxHeight = proxy.size.height * stageHeightFraction

            ZStack {
                Theme.scoreboardDialogScrim
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { }

                VStack(spacing: metrics.contentSpacing) {
                    Text(NSLocalizedString(
                        pages[pageIdx].titleKey,
                        value: "使用说明",
                        comment: "Scoreboard usage hint animated page title"
                    ))
                    .font(.system(size: metrics.titleFontSize, weight: .bold))
                    .foregroundStyle(Theme.scoreboardDialogTextPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: metrics.titleFontSize * 1.6)
                    .padding(.vertical, metrics.contentSpacing * 0.4)
                    .multilineTextAlignment(.center)

                    carousel(ratio: stageRatio, maxHeight: stageMaxHeight)

                    Text(captionText(for: pages[pageIdx]))
                        .font(.system(size: metrics.bodyFontSize * 0.82))
                        .lineSpacing(metrics.bodyLineSpacing * 0.8)
                        .foregroundStyle(Theme.scoreboardDialogTextPrimary.opacity(0.86))
                        .multilineTextAlignment(.center)
                        // 固定两行高的占位：一行/两行都占同一块，翻页时整卡不再上下跳；
                        // 万一译文超两行则缩放收进，不撑高。
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: metrics.bodyFontSize * 0.82 * 2.6)

                    navRow(metrics: metrics)

                    if alreadyShown {
                        Button(action: onDismiss) {
                            Text(NSLocalizedString(
                                "scoreboard_usage_hint_got_it",
                                value: "知道了",
                                comment: ""
                            ))
                            .font(.system(size: metrics.buttonFontSize, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: metrics.buttonHeight)
                            .background(Theme.accentColor)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("scoreboard_usage_hint_confirm")
                    }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical, metrics.verticalPadding)
                .frame(width: dialogWidth)
                .background(Theme.scoreboardDialogSurface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 24, x: 0, y: 10)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("scoreboard_usage_hint_dialog")
            }
        }
        .ignoresSafeArea()
        .onAppear { replayCurrentPage() }
    }

    private func carousel(ratio: CGFloat, maxHeight: CGFloat) -> some View {
        TabView(selection: $pageIdx) {
            ForEach(pages.indices, id: \.self) { index in
                HintAnimationPlayerView(
                    animation: pages[index].animation,
                    startDate: startDates[index] ?? .distantPast
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .aspectRatio(ratio, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: maxHeight)
        .overlay(
            // 轻点画面重播本页；透明层只吃 tap，横向滑动仍由 TabView 处理
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { replayCurrentPage() }
                .accessibilityHidden(true)
        )
        .onChange(of: pageIdx) { _, _ in
            replayCurrentPage()
        }
    }

    private func replayCurrentPage() {
        startDates[pageIdx] = Date()
    }

    private func navRow(metrics: ScoreboardUsageHintDialogMetrics) -> some View {
        let isLast = pageIdx == pages.count - 1
        return HStack(spacing: 10) {
            navButton(systemName: "chevron.left", enabled: pageIdx > 0) {
                pageIdx -= 1
            }

            HStack(spacing: 7) {
                ForEach(pages.indices, id: \.self) { index in
                    Circle()
                        .fill(index == pageIdx ? Theme.accentColor : Color.white.opacity(0.22))
                        .frame(width: 7, height: 7)
                        .scaleEffect(index == pageIdx ? 1.25 : 1)
                        .onTapGesture { pageIdx = index }
                }
            }
            .frame(maxWidth: .infinity)

            if isLast && !alreadyShown {
                Button(action: onDismiss) {
                    Text(NSLocalizedString(
                        "scoreboard_usage_hint_got_it",
                        value: "知道了",
                        comment: ""
                    ))
                    .font(.system(size: metrics.buttonFontSize, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 18)
                    .frame(height: metrics.buttonHeight * 0.86)
                    .background(Theme.accentColor)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("scoreboard_usage_hint_confirm")
            } else if !(isLast && alreadyShown) {
                navButton(systemName: "chevron.right", enabled: true) {
                    pageIdx += 1
                }
            } else {
                Color.clear
                    .frame(width: 44, height: metrics.buttonHeight * 0.86)
            }
        }
        .frame(minHeight: metrics.buttonHeight)
    }

    private func navButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.scoreboardDialogTextPrimary)
                .frame(width: 44, height: 36)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(systemName == "chevron.left"
            ? NSLocalizedString("common_previous", value: "上一页", comment: "")
            : NSLocalizedString("common_next", value: "下一页", comment: ""))
    }

    private func captionText(for page: HintPage) -> String {
        guard let key = page.captionKey else { return " " }
        return NSLocalizedString(key, value: "使用说明", comment: "Scoreboard usage hint animated page caption")
    }
}
