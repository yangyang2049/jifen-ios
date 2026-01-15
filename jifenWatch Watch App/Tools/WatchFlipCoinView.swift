import SwiftUI

struct WatchFlipCoinView: View {
    @State private var isFlipping = false
    @State private var currentSide: CoinSide = .heads
    @State private var rotationAngle: Double = 0
    @State private var coinPositionY: CGFloat = 0
    @State private var coinScale: CGFloat = 1
    @State private var hintShown = false
    @State private var showHint = false
    @State private var flipTimer: Timer? = nil

    var body: some View {
        ZStack {
            WatchTheme.background.ignoresSafeArea()

            coinView
                .onTapGesture {
                    flipCoin()
                }

            if showHint {
                VStack {
                    Spacer()
                    WatchToastView(message: "点击抛硬币")
                        .padding(.bottom, 16)
                }
            }
        }
        .onAppear {
            if !hintShown {
                DispatchQueue.main.asyncAfter(deadline: .now() + WatchTiming.hintDelay) {
                    guard !hintShown else { return }
                    hintShown = true
                    showHint = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showHint = false
                    }
                }
            }
        }
        .onDisappear {
            flipTimer?.invalidate()
            flipTimer = nil
            isFlipping = false
        }
    }

    private var coinView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0xD4AF37),
                            Color(hex: 0xC5A03C),
                            Color(hex: 0xE5C158)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 140, height: 140)
                .shadow(color: Color.black.opacity(0.5), radius: 12, x: 0, y: 8)
                .overlay(
                    Circle()
                        .fill(Color(hex: 0xC5A03C))
                        .frame(width: 128, height: 128)
                        .overlay(
                            Circle()
                                .fill(Color(hex: 0xE5C158))
                                .frame(width: 120, height: 120)
                                .overlay(coinFaceContent)
                        )
                )
        }
        .rotation3DEffect(
            .degrees(rotationAngle),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.6
        )
        .offset(y: coinPositionY)
        .scaleEffect(coinScale)
    }

    @ViewBuilder
    private var coinFaceContent: some View {
        let normalizedAngle = (rotationAngle.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let isShowingTails = normalizedAngle > 90 && normalizedAngle < 270

        if isShowingTails {
            Text("❀")
                .font(.system(size: 60))
                .foregroundColor(Color(hex: 0x8B6914))
                .rotationEffect(.degrees(180))
        } else {
            Text("666")
                .font(.system(size: 44, weight: .bold))
                .foregroundColor(Color(hex: 0x8B6914))
        }
    }

    private func flipCoin() {
        guard !isFlipping else { return }
        isFlipping = true
        showHint = false
        flipTimer?.invalidate()
        flipTimer = nil
        WatchSoundManager.shared.playSound(named: "flip_coin")
        WatchHaptics.shared.play(.medium)

        let finalSide: CoinSide = Bool.random() ? .heads : .tails
        let totalDuration = WatchAnimations.coinFlip
        let baseRotations = 4.0
        let extraRotation = Double.random(in: 0...1)

        let startAngle = rotationAngle
        let normalizedStart = (startAngle.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let fullRotations = baseRotations + extraRotation
        let finalAngle = finalSide == .heads ? fullRotations * 360 : fullRotations * 360 + 180

        var targetAngle = finalAngle - normalizedStart
        while targetAngle < fullRotations * 360 {
            targetAngle += 360
        }
        targetAngle = normalizedStart + targetAngle

        let startTime = Date()
        let maxHeight: CGFloat = -160

        flipTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { timer in
            let elapsed = Date().timeIntervalSince(startTime)
            let progress = min(elapsed / totalDuration, 1.0)
            let easeProgress = 1.0 - pow(1.0 - progress, 3)

            rotationAngle = normalizedStart + (targetAngle - normalizedStart) * easeProgress
            coinPositionY = -4 * maxHeight * CGFloat(progress) * CGFloat(progress - 1)
            coinScale = 1.0 + 0.25 * sin(progress * .pi)

            if progress >= 1.0 {
                timer.invalidate()
                flipTimer = nil
                isFlipping = false

                let fullTurns = round(targetAngle / 360)
                if finalSide == .heads {
                    rotationAngle = fullTurns * 360
                } else {
                    rotationAngle = fullTurns * 360 + 180
                }

                coinPositionY = 0
                coinScale = 1.0
                currentSide = finalSide
            }
        }
    }

    private enum CoinSide {
        case heads
        case tails
    }
}
