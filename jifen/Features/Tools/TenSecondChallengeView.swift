//
//  TenSecondChallengeView.swift
//  jifen
//
//  Ten second challenge - pixel perfect copy from HarmonyOS
//

import SwiftUI

struct TenSecondChallengeView: View {
    @State private var isRunning = false
    @State private var currentTime: TimeInterval = 0 // milliseconds
    @State private var results: [ChallengeResult] = []
    @State private var bestScore: TimeInterval = -1
    @State private var showResult = false
    @State private var lastDifference: TimeInterval = 0
    @State private var showHint = false
    
    @State private var timer: Timer?
    @State private var startTimestamp: Date?
    private let targetTime: TimeInterval = 10.0 // 10 seconds = 10000ms
    private let hintShownKey = "ten_second_hint_shown"
    
    struct ChallengeResult: Identifiable {
        let id = UUID()
        let time: TimeInterval // in milliseconds
        let timestamp: Date
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                // Main content area
                VStack {
                    Spacer()
                    
                    // Time display
                    buildTimeDisplay()
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Hint text (only show once, at bottom)
                if !isRunning && currentTime == 0 && results.isEmpty && showHint {
                    VStack(spacing: 12) {
                        Text("点击开始，尽量在10秒时停止")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                        
                        Text("目标是10.00秒")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.4))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity)
                    .position(x: geometry.size.width / 2, y: geometry.size.height - 120)
                }
                
                // Floating stats panel (top right)
                if !results.isEmpty {
                    buildFloatingStats(geometry: geometry)
                }
            }
        }
        .navigationTitle("十秒挑战")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear {
            checkAndShowHint()
        }
        .onDisappear {
            stopTimerIfNeeded()
        }
    }
    
    @ViewBuilder
    private func buildTimeDisplay() -> some View {
        VStack(spacing: 16) {
            // Main timer display
            Text(formatTime(currentTime))
                .font(.system(size: 100, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "FFD700"))
            
            // Result display
            if showResult {
                VStack(spacing: 8) {
                    Text("误差")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                    
                    HStack(spacing: 2) {
                        Text(formatDifferenceNumber(lastDifference))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(lastDifference < 100 ? Color(hex: "4CAF50") : Color(hex: "FF9800"))
                        Text("秒")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(lastDifference < 100 ? Color(hex: "4CAF50") : Color(hex: "FF9800"))
                    }
                }
                .padding(.top, 8)
            }
            
            // Control button
            Button(action: startChallenge) {
                Text(isRunning ? "停止" : "开始")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 200, height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 30)
                            .fill(isRunning ? Color(hex: "FF5252") : Color(hex: "4CAF50"))
                    )
            }
            .padding(.top, 32)
        }
    }
    
    @ViewBuilder
    private func buildFloatingStats(geometry: GeometryProxy) -> some View {
        VStack(spacing: 12) {
            // Best score
            if bestScore != -1 {
                VStack(spacing: 4) {
                    Text("最佳")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                    HStack(spacing: 2) {
                        Text(formatDifferenceNumber(bestScore))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(hex: "FFD700"))
                        Text("秒")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(hex: "FFD700"))
                    }
                }
                .frame(maxWidth: .infinity)
                
                Divider()
                    .background(Color.white.opacity(0.1))
                    .frame(width: 100 * 0.8)
            }
            
            // Attempts count
            VStack(spacing: 4) {
                Text("尝试")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                Text("\(results.count)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            
            if !results.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.1))
                    .frame(width: 100 * 0.8)
                
                // Clear button
                Button(action: clearHistory) {
                    Text("清空")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "FF6B6B"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: "FF6B6B").opacity(0.15))
                        )
                }
            }
        }
        .frame(width: 100)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .position(x: geometry.size.width - 112, y: 16 + 50) // 112 = 100 + 12 padding
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
    
    private func formatTime(_ milliseconds: TimeInterval) -> String {
        let totalSeconds = Int(milliseconds / 1000)
        let centiseconds = Int((milliseconds.truncatingRemainder(dividingBy: 1000)) / 10)
        return String(format: "%02d.%02d", totalSeconds, centiseconds)
    }
    
    private func formatDifferenceNumber(_ milliseconds: TimeInterval) -> String {
        let seconds = Int(milliseconds / 1000)
        let centiseconds = Int((milliseconds.truncatingRemainder(dividingBy: 1000)) / 10)
        if seconds > 0 {
            return String(format: "%d.%02d", seconds, centiseconds)
        } else {
            return String(format: "0.%02d", centiseconds)
        }
    }
    
    private func startChallenge() {
        if isRunning {
            stopChallenge()
        } else {
            // Start timing
            VibrationManager.shared.vibrateMedium()
            showResult = false
            currentTime = 0
            isRunning = true
            
            let startTime = Date()
            startTimestamp = startTime
            
            timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [self] timer in
                guard let start = startTimestamp else {
                    timer.invalidate()
                    return
                }
                
                let elapsed = Date().timeIntervalSince(start) * 1000 // Convert to milliseconds
                currentTime = elapsed
                
                // Auto stop at 59.99 seconds
                if elapsed >= 59990 {
                    stopChallenge()
                    timer.invalidate()
                }
            }
            
            if let timer = timer {
                RunLoop.current.add(timer, forMode: .common)
            }
        }
    }
    
    private func stopChallenge() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        let finalTime = currentTime
        
        // Calculate difference from 10 seconds
        let targetTimeMs: TimeInterval = 10000 // 10 seconds in milliseconds
        let difference = abs(finalTime - targetTimeMs)
        lastDifference = difference
        
        // Vibration feedback based on accuracy
        if difference == 0 {
            VibrationManager.shared.vibrateHeavy() // Perfect!
        } else if difference < 100 {
            VibrationManager.shared.vibrateMedium() // Great!
        } else {
            VibrationManager.shared.vibrateLight() // Keep trying
        }
        
        // Save result
        let result = ChallengeResult(
            time: finalTime,
            timestamp: Date()
        )
        results.insert(result, at: 0)
        
        // Limit history
        if results.count > 20 {
            results = Array(results.prefix(20))
        }
        
        // Update best score
        if bestScore == -1 || difference < bestScore {
            bestScore = difference
        }
        
        showResult = true
    }
    
    private func stopTimerIfNeeded() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }
    
    private func clearHistory() {
        VibrationManager.shared.vibrateLight()
        results = []
        bestScore = -1
    }
}

#Preview {
    NavigationStack {
        TenSecondChallengeView()
    }
}
