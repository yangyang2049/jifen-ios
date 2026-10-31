import SwiftUI

/// 手机端多人计分投屏分页控件（对齐安卓 `MultiScoreCastPagingEntry`）：
/// 「投屏图标 + ‹ 当前屏/总屏 ›」，48pt 圆形热区，方向不可用时淡显。
///
/// 它只驱动**本地独立大屏**的当前屏：切换时把锚点写进同进程的
/// `ScoreboardDisplayOutputs`（独立扩展屏据此换屏），再回调给手机端自己保存。
/// 手机端每页 9/10 人的分页、翻页手势与计分状态保持独立；锚点不进 wire 协议、
/// 偏好或战绩，大屏仍按完整名单取名字、分数与配色。
///
/// 由上层嵌入手机计分页；`isActive == false`（未处于本地独立投屏会话）时整体不渲染。
@MainActor
struct MultiScoreCastPagingControl: View {
    var playerCount: Int
    var anchorPlayer: Int
    var onAnchorPlayer: (Int) -> Void
    var isActive: Bool

    /// 大屏恒为横屏 5 列 15 人（对齐安卓 `multiScoreDisplayPage(landscape = true)`）。
    private var page: MultiScoreDisplayPage {
        MultiScoreDisplayPaging.page(
            playerCount: playerCount,
            landscape: true,
            anchorPlayer: anchorPlayer
        )
    }

    var body: some View {
        if isActive {
            HStack(spacing: 0) {
                castBadge
                if page.pageCount > 1 {
                    previousButton
                    Text(pageText)
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.scoreboardDialogTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(minWidth: 32)
                        .accessibilityLabel(pageDescription)
                        .accessibilityIdentifier("multi_score_cast_page")
                    nextButton
                }
            }
            .background(Theme.black.opacity(0.25), in: Capsule())
            .accessibilityIdentifier("multi_score_cast_controls")
            // 上层（手机计分页）持有锚点是唯一真相：出现、被上层改写（重新开局/归零）
            // 时都同步给独立大屏，避免手机显示第 1 屏而大屏还停在旧页。
            .onAppear { syncDisplayAnchor(anchorPlayer) }
            .onChange(of: anchorPlayer) { _, next in syncDisplayAnchor(next) }
        }
    }

    /// 投屏状态图标（对齐安卓圆形 Primary 底 + 白色图标）。签名未提供设置回调，
    /// 这里只作为「本机独立投屏进行中」的状态标识，不打开投屏说明页。
    private var castBadge: some View {
        Image(systemName: "airplayvideo")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Theme.textOnPrimary)
            .frame(width: 48, height: 48)
            .background(Theme.primary, in: Circle())
            .accessibilityLabel(NSLocalizedString("cast_active", value: "Casting", comment: ""))
            .accessibilityIdentifier("multi_score_cast_status")
    }

    private var previousButton: some View {
        Button {
            selectPage(page.page - 1)
        } label: {
            pagerIcon(systemName: "chevron.left", enabled: page.page > 0)
        }
        .disabled(page.page <= 0)
        .accessibilityLabel(NSLocalizedString(
            "multi_score_display_previous",
            value: "Previous display page",
            comment: ""
        ))
        .accessibilityIdentifier("multi_score_cast_previous")
    }

    private var nextButton: some View {
        Button {
            selectPage(page.page + 1)
        } label: {
            pagerIcon(systemName: "chevron.right", enabled: page.page + 1 < page.pageCount)
        }
        .disabled(page.page + 1 >= page.pageCount)
        .accessibilityLabel(NSLocalizedString(
            "multi_score_display_next",
            value: "Next display page",
            comment: ""
        ))
        .accessibilityIdentifier("multi_score_cast_next")
    }

    private func pagerIcon(systemName: String, enabled: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Theme.scoreboardDialogTextPrimary.opacity(enabled ? 1 : 0.3))
            .frame(width: 48, height: 48)
            .contentShape(Circle())
    }

    private var pageText: String {
        String(
            format: NSLocalizedString(
                "multi_score_display_page_number",
                value: "%d/%d",
                comment: ""
            ),
            page.page + 1,
            page.pageCount
        )
    }

    private var pageDescription: String {
        String(
            format: NSLocalizedString(
                "multi_score_display_page_description",
                value: "Display page %d of %d, players %d to %d",
                comment: ""
            ),
            page.page + 1,
            page.pageCount,
            page.start + 1,
            page.start + page.count
        )
    }

    /// 切到目标屏：先落锚点（大屏换屏），再交给手机端保存。
    private func selectPage(_ targetPage: Int) {
        guard targetPage >= 0, targetPage < page.pageCount else { return }
        let anchor = targetPage * page.capacity
        syncDisplayAnchor(anchor)
        onAnchorPlayer(anchor)
    }

    private func syncDisplayAnchor(_ anchor: Int) {
        ScoreboardDisplayOutputs.shared.setLocalMultiScoreAnchorPlayer(anchor)
    }
}