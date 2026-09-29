import Foundation
import ScoreCore

/// 使用说明动画的数据模型 —— 与 demo/usage-hint-animation 的 HTML 播放器同构：
/// 帧 = f(t) 纯函数（beats 全部按时间应用），任意时刻可定格截图。

nonisolated struct HintNormalizedPoint: Equatable {
    let x: Double
    let y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

nonisolated struct HintCameraKeyframe: Equatable {
    let time: Double
    let focus: HintNormalizedPoint
    let scale: Double

    init(_ time: Double, _ x: Double, _ y: Double, _ scale: Double) {
        self.time = time
        focus = HintNormalizedPoint(x, y)
        self.scale = scale
    }
}

nonisolated enum HintAction: Equatable {
    case setScoreLeft(Int)
    case setScoreRight(Int)
    /// 撤销语义的比分变化（回退闪黄动画）
    case undoScoreLeft(Int)
    case undoScoreRight(Int)
    case setServeLeft
    case setServeRight
    case matchPoint(Bool)
    case setWonLeft(String)
    case setWonRight(String)
    case guardIgnored
    case finalFlash
}

nonisolated enum HintGesture: Equatable {
    case tap(at: HintNormalizedPoint)
    /// 第二波纹在 start + 0.15s 处自动叠加
    case doubleTap(at: HintNormalizedPoint)
    case swipe(from: HintNormalizedPoint, to: HintNormalizedPoint, end: Double)
}

nonisolated struct HintBeat: Equatable {
    var action: HintAction?
    var gesture: HintGesture?
    /// 波纹触发时刻；nil 时取 gesture 起始时间
    var rippleAt: Double?
    var then: [HintBeat]
    var time: Double

    init(
        action: HintAction? = nil,
        at time: Double = 0,
        gesture: HintGesture? = nil,
        rippleAt: Double? = nil,
        then: [HintBeat] = []
    ) {
        self.action = action
        self.time = time
        self.gesture = gesture
        self.rippleAt = rippleAt
        self.then = then
    }
}

nonisolated struct HintAnimation: Equatable {
    var initialLeft = 0
    var initialRight = 0
    var initialSetsLeft = 0
    var initialSetsRight = 0
    var initialServing: MatchSide = .left
    var initialMatchPoint = false
    var beats: [HintBeat] = []
    var camera: [HintCameraKeyframe] = [HintCameraKeyframe(0, 0.5, 0.5, 1)]
    var duration: Double = 4
}

nonisolated struct HintPage: Equatable {
    let titleKey: String
    let captionKey: String?
    let animation: HintAnimation

    init(titleKey: String, captionKey: String? = nil, animation: HintAnimation) {
        self.titleKey = titleKey
        self.captionKey = captionKey
        self.animation = animation
    }
}

// MARK: - 帧求解（纯函数）

nonisolated struct HintFrameState: Equatable {
    var left = 0
    var right = 0
    var setsLeft = 0
    var setsRight = 0
    var serving: MatchSide = .left
    var matchPoint = false
    var guardNotice = false
    var finalFlash = false
    var setFlashText: String?
    var setFlashTime: Double = -.infinity
    var bumpLeftTime: Double = -.infinity
    var bumpRightTime: Double = -.infinity
    var undoLeftTime: Double = -.infinity
    var undoRightTime: Double = -.infinity
}

nonisolated struct HintGestureState: Equatable {
    let position: HintNormalizedPoint
    let trail: [HintNormalizedPoint]?
}

nonisolated struct HintRipple: Equatable {
    let position: HintNormalizedPoint
    let progress: Double
}

enum HintFrameResolver {
    private struct Accumulator {
        var state = HintFrameState()
        var effectTimes: [(time: Double, action: HintAction)] = []
    }

    static func state(for animation: HintAnimation, at time: Double) -> HintFrameState {
        var acc = Accumulator(
            state: HintFrameState(
                left: animation.initialLeft,
                right: animation.initialRight,
                setsLeft: animation.initialSetsLeft,
                setsRight: animation.initialSetsRight,
                serving: animation.initialServing,
                matchPoint: animation.initialMatchPoint
            )
        )
        apply(beats: animation.beats, through: time, to: &acc)
        return acc.state
    }

    static func gesture(for animation: HintAnimation, at time: Double) -> HintGestureState? {
        for beat in animation.beats {
            if let result = gesture(of: beat, at: time) {
                return result
            }
        }
        return nil
    }

    static func ripples(for animation: HintAnimation, at time: Double) -> [HintRipple] {
        var result: [HintRipple] = []
        for beat in animation.beats {
            collectRipples(of: beat, at: time, into: &result)
        }
        return result
    }

    static func camera(for animation: HintAnimation, at time: Double) -> (scale: Double, focus: HintNormalizedPoint) {
        let keys = animation.camera
        guard let first = keys.first else { return (1, HintNormalizedPoint(0.5, 0.5)) }
        var k0 = first
        var k1 = first
        for key in keys where time >= key.time {
            k1 = key
        }
        // k1 = 最后一个 time<=t 的关键帧；找它之后的下一帧做插值
        if let index = keys.firstIndex(where: { $0.time == k1.time }), index + 1 < keys.count {
            k0 = k1
            k1 = keys[index + 1]
            let span = k1.time - k0.time
            let progress = span <= 0 ? 1 : min(1, max(0, (time - k0.time) / span))
            let eased = 1 - pow(1 - progress, 3)
            return (
                k0.scale + (k1.scale - k0.scale) * eased,
                HintNormalizedPoint(
                    k0.focus.x + (k1.focus.x - k0.focus.x) * eased,
                    k0.focus.y + (k1.focus.y - k0.focus.y) * eased
                )
            )
        }
        return (k1.scale, k1.focus)
    }

    // MARK: - 私有

    private static func apply(beats: [HintBeat], through time: Double, to acc: inout Accumulator) {
        for beat in beats {
            if let action = beat.action, beat.time <= time {
                perform(action, at: effectTime(of: beat), to: &acc)
            }
            apply(beats: beat.then, through: time, to: &acc)
        }
    }

    private static func effectTime(of beat: HintBeat) -> Double {
        beat.rippleAt ?? beat.time
    }

    private static func perform(_ action: HintAction, at time: Double, to acc: inout Accumulator) {
        acc.effectTimes.append((time, action))
        switch action {
        case .setScoreLeft(let value):
            acc.state.left = value
            acc.state.bumpLeftTime = time
        case .setScoreRight(let value):
            acc.state.right = value
            acc.state.bumpRightTime = time
        case .undoScoreLeft(let value):
            acc.state.left = value
            acc.state.undoLeftTime = time
        case .undoScoreRight(let value):
            acc.state.right = value
            acc.state.undoRightTime = time
        case .setServeLeft:
            acc.state.serving = .left
        case .setServeRight:
            acc.state.serving = .right
        case .matchPoint(let on):
            acc.state.matchPoint = on
        case .setWonLeft(let text):
            acc.state.setsLeft += 1
            acc.state.setFlashText = text
            acc.state.setFlashTime = time
        case .setWonRight(let text):
            acc.state.setsRight += 1
            acc.state.setFlashText = text
            acc.state.setFlashTime = time
        case .guardIgnored:
            acc.state.guardNotice = true
        case .finalFlash:
            acc.state.finalFlash = true
        }
    }

    private static func gesture(of beat: HintBeat, at time: Double) -> HintGestureState? {
        guard let gesture = beat.gesture else { return nil }
        switch gesture {
        case .tap(let point):
            let end = (beat.rippleAt ?? beat.time) + 0.5
            return time >= beat.time && time < end ? HintGestureState(position: point, trail: nil) : nil
        case .doubleTap(let point):
            let end = beat.time + 0.8
            return time >= beat.time && time < end ? HintGestureState(position: point, trail: nil) : nil
        case .swipe(let from, let to, let end):
            guard time >= beat.time, time < end else { return nil }
            let span = max(end - beat.time, 0.001)
            let progress = min(1, max(0, (time - beat.time) / span))
            let point = HintNormalizedPoint(
                from.x + (to.x - from.x) * progress,
                from.y + (to.y - from.y) * progress
            )
            let trail = (0...6).map { step in
                HintNormalizedPoint(
                    from.x + (to.x - from.x) * Double(step) / 6,
                    from.y + (to.y - from.y) * Double(step) / 6
                )
            }
            return HintGestureState(position: point, trail: trail)
        }
    }

    private static func collectRipples(of beat: HintBeat, at time: Double, into result: inout [HintRipple]) {
        if let gesture = beat.gesture {
            switch gesture {
            case .tap(let point):
                appendRipple(point, start: beat.rippleAt ?? beat.time, at: time, into: &result)
            case .doubleTap(let point):
                appendRipple(point, start: beat.time, at: time, into: &result)
                appendRipple(point, start: beat.time + 0.15, at: time, into: &result)
            case .swipe:
                break
            }
        }
        for sub in beat.then {
            collectRipples(of: sub, at: time, into: &result)
        }
    }

    private static func appendRipple(
        _ point: HintNormalizedPoint,
        start: Double,
        at time: Double,
        into result: inout [HintRipple]
    ) {
        guard time >= start, time < start + 0.42 else { return }
        result.append(HintRipple(position: point, progress: (time - start) / 0.42))
    }
}
