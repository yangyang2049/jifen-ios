import ScoreCore
import SwiftUI

/// 逐项目手写的动画页清单（唯一口径）。当前仅羽毛球单打；
/// 返回 nil 的项目继续走原文字弹窗。双击减分/防误触两页仍跟随用户开关，
/// 关闭了功能就不演示该行为。
enum UsageHintAnimatedPages {
    @MainActor
    static func pages(for descriptor: ScoreboardUsageHintDescriptor) -> [HintPage]? {
        guard descriptor.gameType == .badminton else { return nil }
        let preferences = PreferencesManager.shared

        var pages: [HintPage] = [tapToScorePage, swipeAdjustPage]
        if preferences.scoreboardDoubleTapSubtractEnabled {
            pages.append(doubleTapSubtractPage)
        }
        if preferences.scoreboardTouchGuardEnabled {
            pages.append(touchGuardPage)
        }
        pages.append(autoJudgementPage)
        return pages
    }

    // MARK: - 页 1：点击比分区加分

    private static let tapToScorePage = HintPage(
        titleKey: "scoreboard_usage_hint_anim_tap_title",
        captionKey: "scoreboard_usage_hint_anim_tap_caption",
        animation: HintAnimation(
            initialLeft: 0,
            initialRight: 0,
            initialServing: .right,
            beats: [
                HintBeat(
                    at: 0.8,
                    gesture: .tap(at: HintNormalizedPoint(0.27, 0.52)),
                    then: [
                        HintBeat(action: .setScoreLeft(1), at: 0.8),
                        HintBeat(action: .setServeLeft, at: 0.8),
                    ]
                ),
                HintBeat(
                    at: 2.6,
                    gesture: .tap(at: HintNormalizedPoint(0.73, 0.52)),
                    then: [HintBeat(action: .setScoreRight(1), at: 2.6)]
                ),
            ],
            camera: [
                HintCameraKeyframe(0, 0.5, 0.5, 1),
                HintCameraKeyframe(0.7, 0.27, 0.56, 1.42),
                HintCameraKeyframe(2.0, 0.27, 0.56, 1.42),
                HintCameraKeyframe(2.5, 0.5, 0.5, 1),
            ],
            duration: 4.6
        )
    )

    // MARK: - 页 2：滑动微调比分（上滑加分 / 下滑减分 / 左滑撤销）

    private static let swipeAdjustPage = HintPage(
        titleKey: "scoreboard_usage_hint_anim_swipe_title",
        captionKey: "scoreboard_usage_hint_anim_swipe_caption",
        animation: HintAnimation(
            initialLeft: 5,
            initialRight: 3,
            initialServing: .left,
            beats: [
                // 上滑加分：左半区向上滑 5 → 6
                HintBeat(
                    at: 0.7,
                    gesture: .swipe(
                        from: HintNormalizedPoint(0.27, 0.66),
                        to: HintNormalizedPoint(0.27, 0.34),
                        end: 1.5
                    ),
                    rippleAt: 1.5,
                    then: [HintBeat(action: .setScoreLeft(6), at: 1.5)]
                ),
                // 下滑减分：右半区向下滑 3 → 2
                HintBeat(
                    at: 2.5,
                    gesture: .swipe(
                        from: HintNormalizedPoint(0.73, 0.34),
                        to: HintNormalizedPoint(0.73, 0.66),
                        end: 3.3
                    ),
                    rippleAt: 3.3,
                    then: [HintBeat(action: .setScoreRight(2), at: 3.3)]
                ),
                // 左滑撤销：整屏向左滑，撤销上一步（右 2 → 3）
                HintBeat(
                    at: 4.3,
                    gesture: .swipe(
                        from: HintNormalizedPoint(0.55, 0.5),
                        to: HintNormalizedPoint(0.28, 0.5),
                        end: 5.1
                    ),
                    rippleAt: 5.1,
                    then: [HintBeat(action: .undoScoreRight(3), at: 5.1)]
                ),
            ],
            camera: [
                HintCameraKeyframe(0, 0.5, 0.5, 1),
                HintCameraKeyframe(0.6, 0.27, 0.56, 1.42),
                HintCameraKeyframe(1.9, 0.27, 0.56, 1.42),
                HintCameraKeyframe(2.4, 0.73, 0.56, 1.42),
                HintCameraKeyframe(3.7, 0.73, 0.56, 1.42),
                HintCameraKeyframe(4.2, 0.5, 0.5, 1),
                HintCameraKeyframe(5.4, 0.5, 0.5, 1),
            ],
            duration: 6.0
        )
    )

    // MARK: - 页 3：双击减分（跟随开关）

    private static let doubleTapSubtractPage = HintPage(
        titleKey: "scoreboard_usage_hint_anim_double_tap_title",
        captionKey: "scoreboard_usage_hint_double_tap_point",
        animation: HintAnimation(
            initialLeft: 8,
            initialRight: 6,
            initialSetsLeft: 1,
            initialServing: .left,
            beats: [
                HintBeat(
                    at: 0.6,
                    gesture: .doubleTap(at: HintNormalizedPoint(0.27, 0.52)),
                    then: [HintBeat(action: .undoScoreLeft(7), at: 0.85)]
                ),
            ],
            camera: [
                HintCameraKeyframe(0, 0.5, 0.5, 1),
                HintCameraKeyframe(0.5, 0.27, 0.56, 1.42),
                HintCameraKeyframe(3.2, 0.27, 0.56, 1.42),
                HintCameraKeyframe(3.7, 0.5, 0.5, 1),
            ],
            duration: 4.2
        )
    )

    // MARK: - 页 4：防误触保护（跟随开关）

    private static let touchGuardPage = HintPage(
        titleKey: "scoreboard_usage_hint_anim_touch_guard_title",
        captionKey: "scoreboard_usage_hint_touch_guard",
        animation: HintAnimation(
            initialLeft: 11,
            initialRight: 9,
            initialSetsLeft: 1,
            initialServing: .right,
            beats: [
                HintBeat(
                    at: 0.6,
                    gesture: .tap(at: HintNormalizedPoint(0.73, 0.52)),
                    then: [HintBeat(action: .setScoreRight(10), at: 0.6)]
                ),
                HintBeat(
                    at: 0.95,
                    gesture: .doubleTap(at: HintNormalizedPoint(0.73, 0.52)),
                    then: [HintBeat(action: .guardIgnored, at: 1.4)]
                ),
            ],
            camera: [
                HintCameraKeyframe(0, 0.5, 0.5, 1),
                HintCameraKeyframe(0.5, 0.73, 0.56, 1.42),
                HintCameraKeyframe(3.4, 0.73, 0.56, 1.42),
                HintCameraKeyframe(3.9, 0.5, 0.5, 1),
            ],
            duration: 4.4
        )
    )

    // MARK: - 收尾页：自动判定局分与赛点

    private static let autoJudgementPage = HintPage(
        titleKey: "scoreboard_usage_hint_anim_auto_title",
        captionKey: "scoreboard_usage_hint_anim_auto_caption",
        animation: HintAnimation(
            initialLeft: 20,
            initialRight: 18,
            initialSetsLeft: 1,
            initialServing: .left,
            initialMatchPoint: true,
            beats: [
                HintBeat(
                    at: 2.8,
                    gesture: .tap(at: HintNormalizedPoint(0.27, 0.5)),
                    then: [
                        HintBeat(action: .setScoreLeft(21), at: 2.8),
                        HintBeat(action: .matchPoint(false), at: 2.8),
                    ]
                ),
                HintBeat(action: .setWonLeft("2:0"), at: 3.3),
                HintBeat(action: .setScoreLeft(0), at: 3.9),
                HintBeat(action: .setScoreRight(0), at: 3.9),
                HintBeat(action: .finalFlash, at: 4.2),
            ],
            camera: [
                HintCameraKeyframe(0, 0.5, 0.5, 1),
                HintCameraKeyframe(0.5, 0.3, 0.52, 1.35),
                HintCameraKeyframe(2.1, 0.3, 0.52, 1.35),
                HintCameraKeyframe(2.7, 0.5, 0.4, 1.12),
                HintCameraKeyframe(4.2, 0.5, 0.4, 1.12),
                HintCameraKeyframe(4.7, 0.5, 0.5, 1),
            ],
            duration: 5.6
        )
    )
}
