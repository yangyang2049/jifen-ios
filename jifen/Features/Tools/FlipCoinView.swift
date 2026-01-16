//
//  FlipCoinView.swift
//  jifen
//
//  Flip coin tool - pixel perfect copy from HarmonyOS
//

import SwiftUI

struct FlipCoinView: View {
    @State private var isFlipping = false
    @State private var currentSide: CoinSide = .heads
    @State private var flipHistory: [CoinResult] = []
    @State private var headsCount = 0
    @State private var tailsCount = 0
    @State private var rotationAngle: Double = 0
    @State private var coinPositionY: CGFloat = 0
    @State private var coinScale: CGFloat = 1.0
    @State private var isEnglish = false
    @State private var showHint = false
    
    private let hintShownKey = "flip_coin_hint_shown"
    
    enum CoinSide {
        case heads, tails
    }
    
    struct CoinResult: Identifiable {
        let id = UUID()
        let side: CoinSide
        let timestamp: Date
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    flipCoin()
                }
            
            // Main coin display area
            VStack {
                Spacer()
                
                // Coin display
                ZStack {
                    // Coin circle with gradient
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "D4AF37"),
                                    Color(hex: "C5A03C"),
                                    Color(hex: "E5C158")
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 180, height: 180)
                        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                        .overlay(
                            // Inner circle (simulating depression)
                            Circle()
                                .fill(Color(hex: "C5A03C"))
                                .frame(width: 165, height: 165)
                                .overlay(
                                    // Center plane
                                    Circle()
                                        .fill(Color(hex: "E5C158"))
                                        .frame(width: 155, height: 155)
                                        .overlay(
                                            // Coin face content
                                            coinFaceContent
                                        )
                                )
                        )
                        .rotation3DEffect(
                            .degrees(rotationAngle),
                            axis: (x: 1, y: 0, z: 0),
                            perspective: 0.5
                        )
                        .offset(y: coinPositionY)
                        .scaleEffect(coinScale)
                }
                
                Spacer()
                
                // Hint text (only show once across app installation)
                if !isFlipping && headsCount + tailsCount == 0 && showHint {
                    Text(NSLocalizedString("tap_to_flip", comment: "Tap to flip coin"))
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.bottom, 100)
                }
                
                // Statistics at bottom center (horizontal layout)
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
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationTitle(NSLocalizedString("flip_coin_title", comment: "Flip Coin title"))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear {
            checkAndShowHint()
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
        // Determine which side is showing based on rotation angle
        // Normalize angle to 0-360 range
        let normalizedAngle = (rotationAngle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        
        // Check if showing tails (180° ± 90°)
        // Tails is at 180°, so we check if angle is between 90° and 270°
        let isShowingTails = normalizedAngle > 90 && normalizedAngle < 270
        
        if isShowingTails {
            // Tails side - flower
            Text("❀")
                .font(.system(size: 80))
                .foregroundColor(Color(hex: "8B6914"))
                .rotationEffect(.degrees(180))
        } else {
            // Heads side - number (0° or 360°)
            Text(isEnglish ? "8" : "666")
                .font(.system(size: isEnglish ? 80 : 56, weight: .bold))
                .foregroundColor(Color(hex: "8B6914"))
        }
    }
    
    private func flipCoin() {
        guard !isFlipping else { return }
        
        isFlipping = true
        VibrationManager.shared.vibrateMedium()
        SoundManager.shared.playSound("flip_coin")
        
        // Random final result
        let finalResult: CoinSide = Bool.random() ? .heads : .tails
        
        // Animation parameters
        let totalDuration: TimeInterval = 2.0 // 2 seconds
        let baseRotations = 4.0
        let extraRotation = Double.random(in: 0...1)
        
        // Calculate target angle to ensure coin ends at perfect front or back face
        // Start from current angle
        let startAngle = rotationAngle
        // Normalize start angle to 0-360 range
        let normalizedStart = (startAngle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        
        // Calculate how many full rotations we need
        let fullRotations = baseRotations + extraRotation
        
        // Determine final angle based on result
        // Heads = 0° (or 360°), Tails = 180°
        let finalAngle: Double
        if finalResult == .heads {
            // End at 0° (or 360°)
            // Find the nearest 0° position after full rotations
            let targetBase = fullRotations * 360
            finalAngle = targetBase
        } else {
            // End at 180°
            // Find the nearest 180° position after full rotations
            let targetBase = fullRotations * 360 + 180
            finalAngle = targetBase
        }
        
        // Calculate total rotation needed from start
        var targetAngle = finalAngle - normalizedStart
        
        // Ensure we rotate in the positive direction (at least baseRotations)
        // If targetAngle is negative or too small, add 360° to ensure enough rotation
        while targetAngle < fullRotations * 360 {
            targetAngle += 360
        }
        
        // Add the normalized start angle back to get absolute target
        targetAngle = normalizedStart + targetAngle
        
        let startTime = Date()
        let maxHeight: CGFloat = -200
        
        // Animation loop
        Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { timer in
            let elapsed = Date().timeIntervalSince(startTime)
            let progress = min(elapsed / totalDuration, 1.0)
            
            // Easing function (ease-out cubic)
            let easeProgress = 1.0 - pow(1.0 - progress, 3)
            
            // Rotation animation
            rotationAngle = normalizedStart + (targetAngle - normalizedStart) * easeProgress
            
            // Parabolic motion (up then down)
            coinPositionY = -4 * maxHeight * CGFloat(progress) * CGFloat(progress - 1)
            
            // Scale effect (depth)
            coinScale = 1.0 + 0.3 * sin(progress * .pi)
            
            if progress >= 1.0 {
                timer.invalidate()
                isFlipping = false
                
                // Ensure final angle is exactly 0° for heads or 180° for tails
                // This ensures the coin ends at perfect front or back face, not in the middle
                let fullRotations = round(targetAngle / 360)
                if finalResult == .heads {
                    // Snap to 0° (or 360° * n) - perfect front face
                    rotationAngle = fullRotations * 360
                } else {
                    // Snap to 180° (or 180° + 360° * n) - perfect back face
                    rotationAngle = fullRotations * 360 + 180
                }
                
                coinPositionY = 0
                coinScale = 1.0
                currentSide = finalResult
                
                // Update counts
                if finalResult == .heads {
                    headsCount += 1
                } else {
                    tailsCount += 1
                }
                
                // Add to history
                flipHistory.insert(CoinResult(side: finalResult, timestamp: Date()), at: 0)
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
