import ScoreCore
import SwiftUI

/// 迷你记分板皮肤：1:1 沿用 Rally 真实版式（红/蓝双面板、姓名加粗、
/// 大比分、局分数字、贴中线绿色发球三角），只是整体缩小进弹窗。
struct RallyMiniScoreboard: View {
    let state: HintFrameState
    let time: Double
    let leftName: String
    let rightName: String

    private var palette: ScoreboardPalette { ScoreboardTheme.defaultTheme.palette }

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.height
            HStack(spacing: 0) {
                half(side: .left, name: leftName, unit: unit)
                half(side: .right, name: rightName, unit: unit)
            }
            .overlay {
                serveIndicator(size: proxy.size)
            }
        }
    }

    private func half(side: MatchSide, name: String, unit: CGFloat) -> some View {
        let isLeft = side == .left
        let score = isLeft ? state.left : state.right
        let sets = isLeft ? state.setsLeft : state.setsRight
        let undoTime = isLeft ? state.undoLeftTime : state.undoRightTime
        let bumpTime = isLeft ? state.bumpLeftTime : state.bumpRightTime
        let undoElapsed = time - undoTime
        return VStack(spacing: 0) {
            Text(name)
                .font(.system(size: unit * 0.11, weight: .bold))
                .foregroundStyle(palette.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 8)
            Spacer().frame(height: unit * 0.06)
            Text("\(score)")
                .font(.system(size: unit * 0.38, weight: .bold))
                .foregroundStyle(
                    undoElapsed >= 0 && undoElapsed < 0.45
                        ? Color(hex: "FFD23E")
                        : palette.foreground
                )
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .scaleEffect(bumpScale(bumpTime: bumpTime))
            Spacer().frame(height: unit * 0.05)
            Text("\(sets)")
                .font(.system(size: unit * 0.13, weight: .bold))
                .foregroundStyle(palette.foreground.opacity(0.7))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isLeft ? palette.left : palette.right)
    }

    private func bumpScale(bumpTime: Double) -> CGFloat {
        let elapsed = time - bumpTime
        guard elapsed >= 0, elapsed < 0.32 else { return 1 }
        return 1 + 0.22 * CGFloat(sin(.pi * elapsed / 0.32))
    }

    /// 复用真实 CenterLineServeIndicator 保证缘贴中线；但尺寸按面板高度取比例，
    /// 不能用 ScoreboardLayoutMetrics.serveIndicatorSize——它有 36pt 下限（为全屏板调的），
    /// 放进矮弹窗会大到压住比分区数字。
    private func serveIndicator(size: CGSize) -> some View {
        CenterLineServeIndicator(
            isLeftServing: state.serving == .left,
            triangleSize: size.height * 0.075
        )
    }
}

/// 动画舞台：TimelineView 驱动，帧 = f(t) 纯函数，播完停在末帧。
/// 重播由外层更换 `startDate` 触发。
struct HintAnimationPlayerView: View {
    let animation: HintAnimation
    let startDate: Date
    /// 进场停顿：避免一打开就播，用户来不及反应。
    var startDelay: Double = 1.1
    /// 播放倍速：<1 整体放慢。
    var playbackRate: Double = 0.8

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            let time = min(max((elapsed - startDelay) * playbackRate, 0), animation.duration)
            let state = HintFrameResolver.state(for: animation, at: time)
            let camera = HintFrameResolver.camera(for: animation, at: time)

            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    Color(hex: "12151B")
                    boardLayer(state: state, time: time, camera: camera, size: size)
                    overlayLayer(state: state, time: time, size: size)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .accessibilityIdentifier("scoreboard_usage_hint_animation")
    }

    private func boardLayer(
        state: HintFrameState,
        time: Double,
        camera: (scale: Double, focus: HintNormalizedPoint),
        size: CGSize
    ) -> some View {
        // 相机平移要夹在放大余量内：focus 靠近边缘时若照搬 (0.5-focus)·scale 的偏移，
        // 会把记分板远边拉进画面、露出深色底。夹到 ±(scale-1)/2 保证永远盖满舞台。
        let scale = CGFloat(camera.scale)
        let maxOffsetX = max(0, (scale - 1) * size.width / 2)
        let maxOffsetY = max(0, (scale - 1) * size.height / 2)
        let dx = min(max((CGFloat(0.5 - camera.focus.x) * size.width) * scale, -maxOffsetX), maxOffsetX)
        let dy = min(max((CGFloat(0.5 - camera.focus.y) * size.height) * scale, -maxOffsetY), maxOffsetY)
        return ZStack {
            // 示例名字跟随应用语言：与记分板缺省名同源（选手A/选手B…），见 DefaultParticipantNames。
            let names = DefaultParticipantNames.resolve(for: .badminton)
            RallyMiniScoreboard(state: state, time: time, leftName: names.left, rightName: names.right)
            gestureLayer(time: time, size: size)
        }
        .scaleEffect(scale)
        .offset(x: dx, y: dy)
    }

    private func gestureLayer(time: Double, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            if let gesture = HintFrameResolver.gesture(for: animation, at: time) {
                if let trail = gesture.trail {
                    ForEach(Array(trail.enumerated()), id: \.offset) { index, point in
                        Circle()
                            .fill(Color.white.opacity(0.45))
                            .frame(width: 6, height: 6)
                            .offset(
                                x: CGFloat(point.x) * size.width - 3,
                                y: CGFloat(point.y) * size.height - 3
                            )
                            .opacity(0.25 + Double(index) * 0.1)
                    }
                }
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 2)
                    .background(Circle().fill(Color.white.opacity(0.14)))
                    .frame(width: 30, height: 30)
                    .offset(
                        x: CGFloat(gesture.position.x) * size.width - 15,
                        y: CGFloat(gesture.position.y) * size.height - 15
                    )
            }
            ForEach(Array(HintFrameResolver.ripples(for: animation, at: time).enumerated()), id: \.offset) { _, ripple in
                Circle()
                    .stroke(Color.white.opacity(0.85 * (1 - ripple.progress)), lineWidth: 2)
                    .frame(width: 30, height: 30)
                    .scaleEffect(0.5 + 1.4 * CGFloat(ripple.progress))
                    .offset(
                        x: CGFloat(ripple.position.x) * size.width - 15,
                        y: CGFloat(ripple.position.y) * size.height - 15
                    )
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func overlayLayer(state: HintFrameState, time: Double, size: CGSize) -> some View {
        let unit = size.height
        return ZStack {
            if state.matchPoint {
                badge(
                    text: NSLocalizedString("scoreboard_usage_hint_anim_match_point", value: "赛点", comment: ""),
                    foreground: Color(hex: "FF9D9D"),
                    background: Color(hex: "FF5050")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, unit * 0.05)
            }
            if let text = state.setFlashText, time - state.setFlashTime < 1.1 {
                Text(text)
                    .font(.system(size: max(13, unit * 0.09), weight: .heavy))
                    .foregroundStyle(Color(hex: "3DDC84"))
                    .shadow(color: Color(hex: "3DDC84").opacity(0.5), radius: 8)
                    .padding(.horizontal, 12)
                    .multilineTextAlignment(.center)
                    // 局分结果横幅放顶部，避开中线上的绿色发球三角（两者都在正中会叠字）
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, unit * 0.17)
            }
            if state.guardNotice, time - beatTime(of: .guardIgnored) < 2.6 {
                badge(
                    text: NSLocalizedString("scoreboard_usage_hint_anim_guard_ignored", value: "已忽略连续快速点击", comment: ""),
                    foreground: Color(hex: "FFD23E"),
                    background: Color(hex: "FFD23E")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, unit * 0.05)
            }
            if state.finalFlash {
                Color(hex: "2F7BFF")
                    .opacity(max(0, 0.14 - (time - beatTime(of: .finalFlash)) * 0.2))
                    .allowsHitTesting(false)
            }
        }
    }

    private func badge(text: String, foreground: Color, background: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(background.opacity(0.16)))
            .overlay(Capsule().stroke(background.opacity(0.45), lineWidth: 1))
    }

    private func beatTime(of action: HintAction) -> Double {
        for beat in animation.beats where beat.action == action {
            return beat.time
        }
        return .infinity
    }
}
