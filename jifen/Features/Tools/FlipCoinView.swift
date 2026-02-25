//
//  FlipCoinView.swift
//  jifen
//
//  Flip coin tool - pixel perfect copy from HarmonyOS
//

import SwiftUI

struct FlipCoinView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isFlipping = false
    @State private var currentSide: FlipCoinSide = .heads
    @State private var flipHistory: [FlipCoinResult] = []
    @State private var headsCount = 0
    @State private var tailsCount = 0
    @State private var rotationAngle: Double = 0
    @State private var coinPositionY: CGFloat = 0
    @State private var coinScale: CGFloat = 1.0
    @State private var isEnglish = false
    @State private var showHint = false
    @State private var flipTimer: Timer?

    private let hintShownKey = "flip_coin_hint_shown"

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Theme.backgroundColor : Theme.homeBackgroundLight).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    flipCoin()
                }

            // Always centered coin display (style aligned with Watch: radial gradient, rim, text shadow)
            GeometryReader { geometry in
                ZStack {
                    // Coin display - Watch-style: outer/middle/inner ratio 120/110/104 → 180/165/156
                    ZStack {
                        // Outer ring - radial gradient metallic look
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color(hex: "E8C84A"),
                                        Color(hex: "D4AF37"),
                                        Color(hex: "B8962E")
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 90
                                )
                            )
                            .frame(width: 180, height: 180)
                            .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)

                        // Middle ring - darker gold depth
                        Circle()
                            .fill(Color(hex: "C5A03C"))
                            .frame(width: 165, height: 165)

                        // Inner face - bright gold surface
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color(hex: "F0D060"),
                                        Color(hex: "E5C158")
                                    ],
                                    center: UnitPoint(x: 0.35, y: 0.35),
                                    startRadius: 0,
                                    endRadius: 78
                                )
                            )
                            .frame(width: 156, height: 156)

                        coinFaceContent

                        // Rim highlight
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
                            .frame(width: 178, height: 178)
                    }
                    .rotation3DEffect(
                        .degrees(rotationAngle),
                        axis: (x: 1, y: 0, z: 0),
                        perspective: 0.6
                    )
                    .offset(y: coinPositionY)
                    .scaleEffect(coinScale)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                    // Floating results overlay
                    VStack {
                        Spacer()

                        // Hint text (only show once across app installation)
                        if !isFlipping && headsCount + tailsCount == 0 && showHint {
                            Text(NSLocalizedString("tap_to_flip", comment: "Tap to flip coin"))
                                .font(.system(size: 18))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.bottom, 100)
                        }

                        // Statistics at bottom center (horizontal layout) - floating
                        if headsCount + tailsCount > 0 {
                            HStack(spacing: 40) {
                                // Heads count
                                VStack(spacing: 4) {
                                    Text(NSLocalizedString("heads", comment: "Heads"))
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.6))
                                    Text("\(headsCount)")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(Color(hex: "FFD700"))
                                }

                                // Tails count
                                VStack(spacing: 4) {
                                    Text(NSLocalizedString("tails", comment: "Tails"))
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.6))
                                    Text("\(tailsCount)")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(Color(hex: "E5C158"))
                                }

                                // Total count
                                VStack(spacing: 4) {
                                    Text(NSLocalizedString("total", comment: "Total"))
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.6))
                                    Text("\(headsCount + tailsCount)")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.bottom, 24)
                        }

                        // Hidden logs section (takes space but invisible initially)
                        VStack(spacing: 8) {
                            // Recent flips display (hidden but maintains space)
                            if flipHistory.count > 0 {
                                VStack(spacing: 8) {
                                    Text(NSLocalizedString("flip_coin_recent", value: "最近抛掷", comment: ""))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))

                                    // Show last 5 flips
                                    HStack(spacing: 12) {
                                        ForEach(flipHistory.prefix(5)) { result in
                                            ZStack {
                                                Circle()
                                                    .fill(result.side == .heads ? Color(hex: "FFD700") : Color(hex: "E5C158"))
                                                    .frame(width: 32, height: 32)
                                                    .opacity(0.8)

                                                Text(result.side == .heads ? (isEnglish ? "8" : "666") : "❀")
                                                    .font(.system(size: 16))
                                                    .foregroundColor(Color(hex: "8B6914"))
                                            }
                                        }
                                    }
                                }
                                .opacity(0) // Hidden but maintains layout space
                                .frame(height: 60) // Fixed height to prevent shifting
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("flip_coin_title", comment: "Flip Coin title"))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear {
            checkAndShowHint()
        }
        .onDisappear {
            flipTimer?.invalidate()
            flipTimer = nil
        }
    }
    
    private func checkAndShowHint() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: hintShownKey) {
            showHint = true
            defaults.set(true, forKey: hintShownKey)
        } else {
            showHint = false
        }
    }
    
    @ViewBuilder
    private var coinFaceContent: some View {
        let normalizedAngle = (rotationAngle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let isShowingTails = normalizedAngle > 90 && normalizedAngle < 270

        if isShowingTails {
            Text("❀")
                .font(.system(size: 78))
                .foregroundColor(Color(hex: "8B6914"))
                .shadow(color: Color(hex: "6B5210").opacity(0.3), radius: 1, x: 1, y: 1)
                .rotationEffect(.degrees(180))
        } else {
            Text(isEnglish ? "8" : "666")
                .font(.system(size: isEnglish ? 78 : 57, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "8B6914"))
                .shadow(color: Color(hex: "6B5210").opacity(0.3), radius: 1, x: 1, y: 1)
        }
    }
    
    private func flipCoin() {
        guard !isFlipping else { return }

        isFlipping = true
        VibrationManager.shared.vibrateMedium()
        SoundManager.shared.playSound("flip_coin")

        let finalResult: FlipCoinSide = Bool.random() ? .heads : .tails
        let isHeads: Bool = (finalResult == .heads)
        let totalDuration: TimeInterval = 2.0

        // Integer rotations so coin lands flat (0° or 180°), aligned with Watch
        let rotationCount = Int.random(in: 4...6)
        let finalAngle: Double = isHeads
            ? Double(rotationCount) * 360.0
            : Double(rotationCount) * 360.0 + 180.0

        let startAngle = rotationAngle
        var targetAngle = finalAngle
        while targetAngle <= startAngle {
            targetAngle += 360.0
        }
        let minRotation = Double(rotationCount) * 360.0
        while (targetAngle - startAngle) < minRotation {
            targetAngle += 360.0
        }

        let startTime = Date()
        let maxHeight: CGFloat = -200

        flipTimer?.invalidate()
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

                rotationAngle = targetAngle
                coinPositionY = 0
                coinScale = 1.0
                currentSide = isHeads ? .heads : .tails

                if isHeads {
                    headsCount += 1
                } else {
                    tailsCount += 1
                }
                flipHistory.insert(FlipCoinResult(side: isHeads ? .heads : .tails, timestamp: Date()), at: 0)
                if flipHistory.count > 20 {
                    flipHistory = Array(flipHistory.prefix(20))
                }
            }
        }
    }
    
    private func clearHistory() {
        flipHistory = []
        headsCount = 0
        tailsCount = 0
        VibrationManager.shared.vibrateLight()
    }
}

#Preview {
    NavigationStack {
        FlipCoinView()
    }
}
