//
//  TenSecondChallengeView.swift
//  jifen
//
//  Ten second challenge - pixel perfect copy from HarmonyOS
//

import SwiftUI

enum TenSecondChallengePolicy {
    static let presetSeconds: [Int] = [1, 3, 5, 10]
    static let defaultTargetSeconds: Int = 10
    static let targetMilliseconds: TimeInterval = 10_000
    static let automaticStopMilliseconds: TimeInterval = 59_990

    static func normalizedTargetSeconds(_ seconds: Int) -> Int {
        presetSeconds.contains(seconds) ? seconds : defaultTargetSeconds
    }

    static func targetMilliseconds(for targetSeconds: Int) -> TimeInterval {
        TimeInterval(normalizedTargetSeconds(targetSeconds)) * 1_000
    }

    static func absoluteDifference(
        milliseconds: TimeInterval,
        targetSeconds: Int = defaultTargetSeconds
    ) -> TimeInterval {
        abs(max(0, milliseconds) - targetMilliseconds(for: targetSeconds))
    }
}

struct TenSecondChallengeView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("ten_second_target_seconds") private var storedTargetSeconds: Int = TenSecondChallengePolicy.defaultTargetSeconds
    @State private var isRunning = false
    @State private var currentTime: TimeInterval = 0 // milliseconds
    @State private var showResult = false
    @State private var lastDifference: TimeInterval = 0
    @State private var showHint = false

    @State private var timer: Timer?
    @State private var startTimestamp: Date?
    private let hintShownKey = "ten_second_hint_shown"

    private var selectedTargetSeconds: Int {
        TenSecondChallengePolicy.normalizedTargetSeconds(storedTargetSeconds)
    }

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()

            // Main content area
            VStack {
                Spacer()

                // Time display
                buildTimeDisplay()

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Hint text (only show once, at bottom)
            if !isRunning && currentTime == 0 && showHint {
                VStack {
                    Spacer()

                    VStack(spacing: 12) {
                        Text(NSLocalizedString("tap_to_start_stop", comment: "Tap to start, try to stop right on target"))
                            .font(.system(size: 18))
                            .foregroundColor(Theme.textSecondary)
                            .multilineTextAlignment(.center)

                        Text(String(format: NSLocalizedString("target_10_seconds", comment: "Target time format"), selectedTargetSeconds))
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity)
                }
                .allowsHitTesting(false)
            }
        }
        .navigationTitle(NSLocalizedString("ten_second_title", comment: "Stop the Clock title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            checkAndShowHint()
        }
        .onDisappear {
            stopTimerIfNeeded()
        }
    }

    private var targetPicker: some View {
        let unit = NSLocalizedString("seconds_short", value: "秒", comment: "")
        return HStack(spacing: 4) {
            ForEach(TenSecondChallengePolicy.presetSeconds, id: \.self) { seconds in
                let selected = selectedTargetSeconds == seconds
                Button {
                    selectTarget(seconds)
                } label: {
                    Text("\(seconds)\(unit)")
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(selected ? Theme.textOnPrimary : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(selected ? Theme.primary : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isRunning)
                .accessibilityIdentifier("ten_second_target_\(seconds)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.controlBackground, in: Capsule())
        .frame(maxWidth: 300)
        .padding(.horizontal, 24)
        .opacity(isRunning ? 0.55 : 1.0)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ten_second_target_picker")
    }

    @ViewBuilder
    private func buildTimeDisplay() -> some View {
        VStack(spacing: 16) {
            targetPicker
                .padding(.bottom, 12)

            // Main timer display
            Text(formatTime(currentTime))
                .font(.system(size: 100, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            
            // Result display
            if showResult {
                VStack(spacing: 8) {
                    Text(NSLocalizedString("ten_second_error_label", value: "误差", comment: ""))
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSecondary)
                    
                    HStack(spacing: 2) {
                        Text(formatDifferenceNumber(lastDifference))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(resultColor)
                        Text(NSLocalizedString("seconds_short", value: "秒", comment: ""))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(resultColor)
                    }
                }
                .padding(.top, 8)
            }
            
            // Control button
            Button(action: startChallenge) {
                Text(isRunning ? NSLocalizedString("ten_second_stop", value: "停止", comment: "") : NSLocalizedString("ten_second_start", value: "开始", comment: ""))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Theme.actionForeground(on: isRunning ? Color(hex: "FF5252") : Color(hex: "4CAF50")))
                    .frame(width: 200, height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 30)
                            .fill(isRunning ? Color(hex: "FF5252") : Color(hex: "4CAF50"))
                    )
            }
            .padding(.top, 32)
        }
    }

    private var resultColor: Color {
        lastDifference < 100 ? Theme.positiveText : Theme.warningText
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
    
    private func selectTarget(_ seconds: Int) {
        guard !isRunning && selectedTargetSeconds != seconds else { return }
        VibrationManager.shared.vibrateLight()
        withAnimation(.easeInOut(duration: 0.16)) {
            storedTargetSeconds = seconds
        }
        currentTime = 0
        showResult = false
        lastDifference = 0
        AppAnalytics.track(.toolAction, parameters: [
            .itemID: .string("ten_second"),
            .actionName: .string("setting_change"),
            .settingName: .string("target_seconds"),
            .settingValue: .string("\(seconds)")
        ])
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
            AppAnalytics.track(.toolAction, parameters: [
                .itemID: .string("ten_second"),
                .actionName: .string("start"),
                .durationMS: .int(Int(TenSecondChallengePolicy.targetMilliseconds(for: selectedTargetSeconds)))
            ])
            
            timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [self] timer in
                guard let start = startTimestamp else {
                    timer.invalidate()
                    return
                }
                
                let elapsed = Date().timeIntervalSince(start) * 1000 // Convert to milliseconds
                currentTime = elapsed
                
                // Auto stop at 59.99 seconds
                if elapsed >= TenSecondChallengePolicy.automaticStopMilliseconds {
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

        // Calculate difference from selected target
        let targetSeconds = selectedTargetSeconds
        let difference = TenSecondChallengePolicy.absoluteDifference(
            milliseconds: finalTime,
            targetSeconds: targetSeconds
        )
        lastDifference = difference

        // Vibration feedback based on accuracy
        if difference == 0 {
            VibrationManager.shared.vibrateHeavy() // Perfect!
        } else if difference < 100 {
            VibrationManager.shared.vibrateMedium() // Great!
        } else {
            VibrationManager.shared.vibrateLight() // Keep trying
        }

        showResult = true
        AppAnalytics.track(.toolAction, parameters: [
            .itemID: .string("ten_second"),
            .actionName: .string("result"),
            .elapsedMS: .int(Int(finalTime)),
            .deltaMS: .int(Int(difference)),
            .durationMS: .int(Int(TenSecondChallengePolicy.targetMilliseconds(for: targetSeconds))),
            .result: .string(AnalyticsResult.success.rawValue)
        ])
    }
    
    private func stopTimerIfNeeded() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }
}

#Preview {
    NavigationStack {
        TenSecondChallengeView()
    }
}
