//
//  CubeTimerView.swift
//  jifen
//
//  对齐鸿蒙魔方计时：双手按压 0.5 秒后抬起开始，再次双手按下停止。
//

import SwiftUI

enum CubeTimerPolicy {
    static let readinessHoldDuration: TimeInterval = 0.5
    static let createsHistoryRecord = false
}

struct CubeTimerView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var elapsedTime: TimeInterval = 0
    @State private var isRunning = false
    @State private var isWaitingToStart = false
    @State private var bothHandsDown = false
    @State private var leftHandDown = false
    @State private var rightHandDown = false
    @State private var canStart = false
    @State private var hasCompletedSolve = false

    @State private var displayTimer: Timer?
    @State private var handDownTimer: Timer?
    @State private var startReference: Date?

    @State private var hideButtons = false

    @State private var exitClickTime: Date?
    @State private var toastMessage: String?
    /// 一次性操作提示：进入页面时弹一次，点「确定」后不再显示，避免常驻文案盖住手掌
    @State private var showInitialHintDialog = true

    private var isTablet: Bool {
        Theme.usesPadLayout
    }

    private var isTwoInOne: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                VStack {
                    Spacer(minLength: 0)

                    Text(formatTime(elapsedTime))
                        .font(.system(size: responsiveTimeFontSize(width: geo.size.width), weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "00FF41"))
                        .padding(.bottom, 20)

                    Spacer(minLength: 0)

                    HStack(spacing: 0) {
                        handArea(
                            isLeft: true,
                            isDown: leftHandDown,
                            handIconSize: handIconSize,
                            handAreaHeight: handAreaHeight,
                            alignment: .trailing
                        )
                        .padding(.trailing, 20)

                        handArea(
                            isLeft: false,
                            isDown: rightHandDown,
                            handIconSize: handIconSize,
                            handAreaHeight: handAreaHeight,
                            alignment: .leading
                        )
                        .padding(.leading, 20)
                    }
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 0)
                }

                if !hideButtons {
                    bottomButtons
                }

                if isTwoInOne {
                    VStack {
                        Spacer()
                        Text(NSLocalizedString("cube_timer_no_touchscreen_hint", value: "💡 没有触摸屏无法工作，可在手机平板上使用", comment: ""))
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 24)
                    }
                }

                if let toastMessage {
                    VStack {
                        Spacer()
                        Text(toastMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.72))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.bottom, 120)
                    }
                }

                if showInitialHintDialog {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showInitialHintDialog = false
                        }
                    VStack(spacing: 16) {
                        Text(NSLocalizedString("cube_timer_place_hands", value: "双手放在屏幕上准备", comment: ""))
                            .font(.system(size: isTablet ? 20 : 18, weight: .semibold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        Text(NSLocalizedString("cube_timer_release_to_start", value: "松开双手开始计时", comment: ""))
                            .font(.system(size: isTablet ? 16 : 15))
                            .foregroundColor(.white.opacity(0.82))
                            .multilineTextAlignment(.center)
                        Button {
                            showInitialHintDialog = false
                        } label: {
                            Text(NSLocalizedString("confirm", comment: ""))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Theme.textOnPrimary)
                                .frame(
                                    minWidth: isTablet ? 240 : 200,
                                    minHeight: isTablet ? 56 : 52
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Theme.primary)
                        .clipShape(Capsule())
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, isTablet ? 36 : 24)
                    .padding(.vertical, isTablet ? 30 : 24)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
                            }
                    }
                    .shadow(color: Color.white.opacity(0.08), radius: 18)
                    .padding(.horizontal, 40)
                    .zIndex(1)
                }

            }
            .onAppear {
                if !isTablet && !isTwoInOne {
                    OrientationLock.shared.lock(.landscape)
                }
            }
            .onDisappear {
                cleanupTimers()
                if !isTablet && !isTwoInOne {
                    OrientationLock.shared.unlock()
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var handIconSize: CGFloat {
        if isTablet { return 400 }
        if isTwoInOne { return 380 }
        return 200
    }

    private var handAreaHeight: CGFloat {
        if isTablet { return 500 }
        if isTwoInOne { return 480 }
        return 250
    }

    private var bottomButtons: some View {
        VStack {
            Spacer()
            HStack(spacing: 0) {
                floatingButton(icon: "chevron.left") {
                    handleExitClick()
                }
                Spacer()
                floatingButton(icon: "camera") {
                    prepareScreenshot()
                }
                .padding(.trailing, 12)
                floatingButton(icon: "arrow.counterclockwise") {
                    resetTimer()
                }
            }
            .padding(.horizontal, ScoreboardConstants.buttonPadding)
            .padding(.bottom, ScoreboardConstants.buttonPadding)
        }
        .ignoresSafeArea(.all, edges: [.bottom, .leading, .trailing])
    }

    private func floatingButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: ScoreboardConstants.buttonIconSize, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: ScoreboardConstants.buttonSize, height: ScoreboardConstants.buttonSize)
                .background(Color.black.opacity(0.25))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func handArea(
        isLeft: Bool,
        isDown: Bool,
        handIconSize: CGFloat,
        handAreaHeight: CGFloat,
        alignment: Alignment
    ) -> some View {
        VStack {
            CubeTimerHandShape()
                .fill(isDown
                    ? Color(red: 0, green: 167.0 / 255, blue: 4.0 / 255)
                    : Color(red: 70.0 / 255, green: 70.0 / 255, blue: 70.0 / 255))
                .aspectRatio(1184.0 / 1310, contentMode: .fit)
                .scaleEffect(x: isLeft ? 1 : -1, y: 1)
                .frame(width: handIconSize, height: handIconSize)
                .accessibilityHidden(true)
                .animation(.easeInOut(duration: 0.2), value: isDown)
        }
        .frame(maxWidth: .infinity, maxHeight: handAreaHeight, alignment: alignment)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    onHandDown(isLeft: isLeft)
                }
                .onEnded { _ in
                    onHandUp(isLeft: isLeft)
                }
        )
    }

    private func responsiveTimeFontSize(width: CGFloat) -> CGFloat {
        if isTablet { return 120 }
        if isTwoInOne { return 100 }

        let base: CGFloat = 60
        let maxValue: CGFloat = 80
        let minValue: CGFloat = 50

        if width > 400 {
            return min(maxValue, base + (width - 360) * 0.05)
        }
        return max(minValue, base - (360 - width) * 0.03)
    }

    private func formatTime(_ elapsed: TimeInterval) -> String {
        let milliseconds = max(0, Int((elapsed * 1000).rounded(.down)))
        let totalSeconds = milliseconds / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let centiseconds = (milliseconds % 1000) / 10

        if minutes > 0 {
            return "\(minutes):\(String(format: "%02d", seconds)).\(String(format: "%02d", centiseconds))"
        }
        return "\(seconds).\(String(format: "%02d", centiseconds))"
    }

    private func onHandDown(isLeft: Bool) {
        if isLeft {
            guard !leftHandDown else { return }
            leftHandDown = true
        } else {
            guard !rightHandDown else { return }
            rightHandDown = true
        }

        let newBothHandsDown = leftHandDown && rightHandDown
        if newBothHandsDown && !bothHandsDown {
            bothHandsDown = true

            if isRunning {
                stopTimer()
                isRunning = false
                hasCompletedSolve = true
                VibrationManager.shared.vibrateHeavy()
                AppAnalytics.track(.timerFinish, parameters: [
                    .gameType: .string("cube"),
                    .durationMS: .int(Int(elapsedTime * 1_000)),
                    .endReason: .string(AnalyticsEndReason.ruleCompleted.rawValue)
                ])
            } else {
                isWaitingToStart = true
                canStart = false
                handDownTimer?.invalidate()
                handDownTimer = Timer.scheduledTimer(
                    withTimeInterval: CubeTimerPolicy.readinessHoldDuration,
                    repeats: false
                ) { _ in
                    canStart = true
                }
            }
        }
    }

    private func onHandUp(isLeft: Bool) {
        if isLeft {
            guard leftHandDown else { return }
            leftHandDown = false
        } else {
            guard rightHandDown else { return }
            rightHandDown = false
        }

        let wasBothHandsDown = bothHandsDown
        bothHandsDown = leftHandDown && rightHandDown

        if wasBothHandsDown && !bothHandsDown {
            handDownTimer?.invalidate()
            handDownTimer = nil

            if isWaitingToStart && canStart {
                isWaitingToStart = false
                isRunning = true
                elapsedTime = 0
                hasCompletedSolve = false
                startReference = Date()
                startTimer()
                VibrationManager.shared.vibrateMedium()
                AppAnalytics.track(.timerStart, parameters: [
                    .gameType: .string("cube")
                ])
            } else {
                isWaitingToStart = false
                canStart = false
            }
        }
    }

    private func startTimer() {
        displayTimer?.invalidate()
        let base = Date().addingTimeInterval(-elapsedTime)
        startReference = base
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
            elapsedTime = Date().timeIntervalSince(base)
        }
        if let displayTimer {
            RunLoop.current.add(displayTimer, forMode: .common)
        }
    }

    private func stopTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func resetTimer() {
        let previousElapsed = elapsedTime
        let wasRunning = isRunning
        let wasCompleted = hasCompletedSolve
        stopTimer()
        handDownTimer?.invalidate()
        handDownTimer = nil

        elapsedTime = 0
        isRunning = false
        isWaitingToStart = false
        bothHandsDown = false
        leftHandDown = false
        rightHandDown = false
        canStart = false
        hasCompletedSolve = false
        startReference = nil

        VibrationManager.shared.vibrateLight()
        trackCancelledSolveIfNeeded(
            elapsed: previousElapsed,
            wasRunning: wasRunning,
            wasCompleted: wasCompleted
        )
    }

    private func cleanupTimers() {
        stopTimer()
        handDownTimer?.invalidate()
        handDownTimer = nil
    }

    private func handleExitClick() {
        let now = Date()
        if let last = exitClickTime, now.timeIntervalSince(last) < 2 {
            exitClickTime = nil
            trackCancelledSolveIfNeeded(
                elapsed: elapsedTime,
                wasRunning: isRunning,
                wasCompleted: hasCompletedSolve
            )
            dismiss()
            return
        }
        exitClickTime = now
        showToast(
            isTwoInOne
            ? NSLocalizedString("click_again_to_exit", value: "再次点击退出", comment: "")
            : NSLocalizedString("tap_again_to_exit", value: "再次轻触退出", comment: ""),
            duration: 1.5
        )
    }

    private func trackCancelledSolveIfNeeded(
        elapsed: TimeInterval,
        wasRunning: Bool,
        wasCompleted: Bool
    ) {
        guard wasRunning, !wasCompleted, elapsed > 0 else { return }
        AppAnalytics.trackTimerAction("exit", gameType: "cube", parameters: [
            .elapsedMS: .int(Int(elapsed * 1_000)),
            .result: .string(AnalyticsResult.cancelled.rawValue)
        ])
    }

    private func showToast(_ message: String, duration: TimeInterval) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    private func prepareScreenshot() {
        ScreenshotSaveCoordinator.shared.prepareForCapture()
        hideButtons = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let image = ScreenshotSaveCoordinator.shared.captureCurrentWindowImage()
            hideButtons = false

            guard let image else {
                ScreenshotSaveCoordinator.shared.showCaptureFailure()
                return
            }

            ScreenshotSaveCoordinator.shared.submitCapturedImage(image)
        }
    }
}

/// One smooth outline shared by both hands and both touch states.
private struct CubeTimerHandShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 590, y: 1248))
        path.addCurve(to: CGPoint(x: 236, y: 1074), control1: CGPoint(x: 403, y: 1248), control2: CGPoint(x: 294, y: 1160))
        path.addCurve(to: CGPoint(x: 151, y: 823), control1: CGPoint(x: 179, y: 996), control2: CGPoint(x: 168, y: 919))
        path.addCurve(to: CGPoint(x: 66, y: 514), control1: CGPoint(x: 135, y: 735), control2: CGPoint(x: 98, y: 623))
        path.addCurve(to: CGPoint(x: 90, y: 408), control1: CGPoint(x: 48, y: 465), control2: CGPoint(x: 60, y: 425))
        path.addCurve(to: CGPoint(x: 183, y: 487), control1: CGPoint(x: 128, y: 390), control2: CGPoint(x: 160, y: 433))
        path.addLine(to: CGPoint(x: 267, y: 675))
        path.addCurve(to: CGPoint(x: 294, y: 687), control1: CGPoint(x: 276, y: 700), control2: CGPoint(x: 301, y: 714))
        path.addLine(to: CGPoint(x: 212, y: 371))
        path.addCurve(to: CGPoint(x: 239, y: 205), control1: CGPoint(x: 189, y: 292), control2: CGPoint(x: 204, y: 231))
        path.addCurve(to: CGPoint(x: 344, y: 258), control1: CGPoint(x: 285, y: 172), control2: CGPoint(x: 326, y: 204))
        path.addCurve(to: CGPoint(x: 432, y: 610), control1: CGPoint(x: 389, y: 371), control2: CGPoint(x: 416, y: 492))
        path.addCurve(to: CGPoint(x: 461, y: 631), control1: CGPoint(x: 438, y: 637), control2: CGPoint(x: 466, y: 665))
        path.addLine(to: CGPoint(x: 407, y: 260))
        path.addCurve(to: CGPoint(x: 409, y: 90), control1: CGPoint(x: 395, y: 205), control2: CGPoint(x: 389, y: 128))
        path.addCurve(to: CGPoint(x: 464, y: 58), control1: CGPoint(x: 422, y: 65), control2: CGPoint(x: 442, y: 55))
        path.addCurve(to: CGPoint(x: 553, y: 153), control1: CGPoint(x: 507, y: 61), control2: CGPoint(x: 540, y: 102))
        path.addCurve(to: CGPoint(x: 606, y: 544), control1: CGPoint(x: 591, y: 276), control2: CGPoint(x: 605, y: 414))
        path.addCurve(to: CGPoint(x: 639, y: 580), control1: CGPoint(x: 606, y: 578), control2: CGPoint(x: 639, y: 614))
        path.addLine(to: CGPoint(x: 641, y: 256))
        path.addCurve(to: CGPoint(x: 704, y: 139), control1: CGPoint(x: 643, y: 198), control2: CGPoint(x: 672, y: 145))
        path.addCurve(to: CGPoint(x: 790, y: 233), control1: CGPoint(x: 748, y: 135), control2: CGPoint(x: 786, y: 172))
        path.addCurve(to: CGPoint(x: 797, y: 559), control1: CGPoint(x: 796, y: 351), control2: CGPoint(x: 799, y: 449))
        path.addCurve(to: CGPoint(x: 842, y: 792), control1: CGPoint(x: 791, y: 668), control2: CGPoint(x: 803, y: 728))
        path.addCurve(to: CGPoint(x: 872, y: 794), control1: CGPoint(x: 850, y: 805), control2: CGPoint(x: 854, y: 817))
        path.addLine(to: CGPoint(x: 999, y: 635))
        path.addCurve(to: CGPoint(x: 1101, y: 588), control1: CGPoint(x: 1028, y: 592), control2: CGPoint(x: 1065, y: 571))
        path.addCurve(to: CGPoint(x: 1109, y: 681), control1: CGPoint(x: 1147, y: 608), control2: CGPoint(x: 1138, y: 639))
        path.addLine(to: CGPoint(x: 967, y: 890))
        path.addCurve(to: CGPoint(x: 817, y: 1123), control1: CGPoint(x: 917, y: 966), control2: CGPoint(x: 883, y: 1059))
        path.addCurve(to: CGPoint(x: 590, y: 1248), control1: CGPoint(x: 743, y: 1195), control2: CGPoint(x: 664, y: 1248))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width / 1184, y: rect.height / 1310))
    }
}

#Preview {
    NavigationStack {
        CubeTimerView()
    }
}
