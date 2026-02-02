import SwiftUI

struct WatchFlipCoinView: View {
    @State private var isFlipping = false
    @State private var currentSide: WatchCoinSide = .heads
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

    // MARK: - Coin dimensions (proportional to HarmonyOS: 144/132/124)
    private let coinSize: CGFloat = 120
    private let coinMiddle: CGFloat = 110
    private let coinInner: CGFloat = 104

    private var coinView: some View {
        ZStack {
            // Outer ring - base gold with subtle radial gradient for metallic look
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0xE8C84A),  // lighter center highlight
                            Color(hex: 0xD4AF37),  // standard gold
                            Color(hex: 0xB8962E)   // darker edge
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: coinSize / 2
                    )
                )
                .frame(width: coinSize, height: coinSize)
                .shadow(color: Color.black.opacity(0.5), radius: 16, x: 0, y: 10)

            // Middle ring - darker gold, gives depth
            Circle()
                .fill(Color(hex: 0xC5A03C))
                .frame(width: coinMiddle, height: coinMiddle)

            // Inner face - bright gold surface
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0xF0D060),  // bright highlight
                            Color(hex: 0xE5C158)   // standard inner gold
                        ],
                        center: UnitPoint(x: 0.35, y: 0.35),
                        startRadius: 0,
                        endRadius: coinInner / 2
                    )
                )
                .frame(width: coinInner, height: coinInner)

            // Coin face content (text)
            coinFaceContent

            // Subtle rim highlight
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.4),
                            Color.clear,
                            Color.black.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .frame(width: coinSize - 2, height: coinSize - 2)
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
            // Tails: flower symbol
            Text("❀")
                .font(.system(size: 52))
                .foregroundColor(Color(hex: 0x8B6914))
                .shadow(color: Color(hex: 0x6B5210).opacity(0.3), radius: 1, x: 1, y: 1)
                .rotationEffect(.degrees(180))
        } else {
            // Heads: lucky number
            Text("666")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: 0x8B6914))
                .shadow(color: Color(hex: 0x6B5210).opacity(0.3), radius: 1, x: 1, y: 1)
        }
    }

    private func flipCoin() {
        guard !isFlipping else { return }
        isFlipping = true
        showHint = false
        flipTimer?.invalidate()
        flipTimer = nil
        WatchSoundManager.shared.playSound(named: "flip_coin", fileExtension: "mp3", fallbackToSystemClick: false)
        // No haptic here so only flip_coin.mp3 plays (no system tap/click sound)

        let finalSide: WatchCoinSide = Bool.random() ? .heads : .tails
        let totalDuration = WatchAnimations.coinFlip

        // Use integer rotations so coin lands flat (0° or 180°)
        let rotationCount = Int.random(in: 4...6)
        let finalAngle: Double = finalSide == .heads
            ? Double(rotationCount) * 360.0        // lands at 0° (heads facing up)
            : Double(rotationCount) * 360.0 + 180.0 // lands at 180° (tails facing up)

        // Calculate target from current angle, ensuring we always rotate forward
        let startAngle = rotationAngle
        var targetAngle = finalAngle
        while targetAngle <= startAngle {
            targetAngle += 360.0
        }
        // Ensure minimum rotation for visual effect
        let minRotation = Double(rotationCount) * 360.0
        while (targetAngle - startAngle) < minRotation {
            targetAngle += 360.0
        }

        let startTime = Date()
        let maxHeight: CGFloat = -160

        flipTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { timer in
            let elapsed = Date().timeIntervalSince(startTime)
            let progress = min(elapsed / totalDuration, 1.0)
            let easeProgress = 1.0 - pow(1.0 - progress, 3)

            rotationAngle = startAngle + (targetAngle - startAngle) * easeProgress
            coinPositionY = -4 * maxHeight * CGFloat(progress) * CGFloat(progress - 1)
            coinScale = 1.0 + 0.25 * sin(progress * .pi)

            if progress >= 1.0 {
                timer.invalidate()
                flipTimer = nil
                isFlipping = false

                // Use exact target angle so the face doesn't snap; matches last frame of animation
                rotationAngle = targetAngle
                coinPositionY = 0
                coinScale = 1.0
                currentSide = finalSide
            }
        }
    }
}
