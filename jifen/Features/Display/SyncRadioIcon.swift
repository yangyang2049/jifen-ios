import SwiftUI

// MARK: - 同步状态大图标（Lucide radio）
//
// 与 Android `ic_menu_share.xml`、HarmonyOS `ic_share.svg` 同款：中心圆点 +
// 左右各两条同心弧（半径 6 / 10，各占 90°）。三端统一定稿为「两条辐射线依次渐显」：
// 内弧一组先亮 → 外弧一组再亮（内弧保持）→ 两组一起淡出 → 停顿 → 循环往复。
// 纯 opacity 渐显，不做描边绘制、不做位移、不做硬切。
//
// 生命周期：只在分享中且页面可见时播放；`scenePhase` 变化会重启/停止循环，
// 视图离开层级时 `.task` 自动取消；开启「减弱动态效果」时两组弧常亮。

/// 一组同心弧：左右各 90°，radius 以 24×24 坐标系表示。
private struct SyncRadioArcGroup: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = radius * scale
        var path = Path()
        // 拆成两个子 Path，避免两条弧首尾被自动连线。
        var right = Path()
        right.addArc(
            center: center,
            radius: r,
            startAngle: .degrees(-45),
            endAngle: .degrees(45),
            clockwise: false
        )
        path.addPath(right)
        var left = Path()
        left.addArc(
            center: center,
            radius: r,
            startAngle: .degrees(135),
            endAngle: .degrees(225),
            clockwise: false
        )
        path.addPath(left)
        return path
    }
}

/// 分享中角色卡头部的大同步图标。非动画状态下两组弧常亮，等价于静态 radio 图标。
struct SyncRadioIcon: View {
    var animated: Bool = true

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Int = 0  // 0 全暗 / 1 内弧亮 / 2 两组亮

    private var shouldAnimate: Bool {
        animated && scenePhase == .active && !reduceMotion
    }

    private var innerOpacity: Double {
        shouldAnimate ? (phase >= 1 ? 1 : 0.12) : 1
    }

    private var outerOpacity: Double {
        shouldAnimate ? (phase >= 2 ? 1 : 0.12) : 1
    }

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / 24
            ZStack {
                SyncRadioArcGroup(radius: 10)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round))
                    .opacity(outerOpacity)
                SyncRadioArcGroup(radius: 6)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round))
                    .opacity(innerOpacity)
                Circle()
                    .fill(Color.white)
                    .frame(width: 4 * scale, height: 4 * scale)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        // 周期 ≈2.4s：0.14 停顿 + 0.44 内弧渐显段 + 0.77 外弧渐显/保持段 + 1.05 淡出/停顿段。
        .task(id: shouldAnimate) {
            guard shouldAnimate else {
                phase = 2
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 140_000_000)
                withAnimation(.easeInOut(duration: 0.34)) { phase = 1 }
                try? await Task.sleep(nanoseconds: 440_000_000)
                withAnimation(.easeInOut(duration: 0.38)) { phase = 2 }
                try? await Task.sleep(nanoseconds: 770_000_000)
                withAnimation(.easeInOut(duration: 0.34)) { phase = 0 }
                try? await Task.sleep(nanoseconds: 1_050_000_000)
            }
        }
    }
}
