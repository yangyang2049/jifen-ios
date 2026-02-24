import SwiftUI

struct WatchTenSecondChallengeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isRunning = false
    @State private var currentTime: TimeInterval = 0
    @State private var tapHintPulse: CGFloat = 1.0
    @State private var history: [TimeInterval] = []
    @State private var showHistoryOverlay = false
    @State private var showUsageAlert = false
    @State private var usagePromptShown = false

    @State private var timer: Timer? = nil
    @State private var startTimestamp: Date = Date()

    var body: some View {
        ZStack {
            WatchTheme.background.ignoresSafeArea()

            VStack {
                if isRunning {
                    Text(formatTime(currentTime))
                        .font(.system(size: 60, weight: .bold, design: .monospaced))
                        .foregroundColor(WatchTheme.accent)
                } else {
                    Text("👆")
                        .font(.system(size: 40))
                        .scaleEffect(tapHintPulse)
                }
            }

            if !showHistoryOverlay, !history.isEmpty {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(recentHistory.indices, id: \.self) { idx in
                            let value = recentHistory[idx]
                            Text(formatShortTime(value))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.12))
                                .cornerRadius(12)
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: 0xD0D0D0))
                        }
                        if history.count > 2 {
                            Text("···")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.12))
                                .cornerRadius(12)
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: 0xD0D0D0))
                        }
                    }
                    .padding(.bottom, 20)
                    .onTapGesture {
                        showHistoryOverlay = true
                    }
                }
            }

            if showHistoryOverlay {
                historyOverlay
            }
        }
        .onTapGesture {
            if !showHistoryOverlay {
                toggleChallenge()
            }
        }
        .onAppear {
            usagePromptShown = WatchPreferences.shared.bool(forKey: "watch_ten_second_usage_prompt_shown", defaultValue: false)
            if !usagePromptShown {
                showUsageAlert = true
                WatchPreferences.shared.setBool(true, forKey: "watch_ten_second_usage_prompt_shown")
                usagePromptShown = true
            }
            if !isRunning {
                startTapHintPulse()
            }
        }
        .onChange(of: isRunning) { _, running in
            if !running {
                startTapHintPulse()
            } else {
                tapHintPulse = 1.0
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
            isRunning = false
        }
        .alert(NSLocalizedString("watch_ten_second_challenge", comment: "Ten Second Challenge"), isPresented: $showUsageAlert) {
            Button(NSLocalizedString("got_it", comment: "Got it"), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("watch_ten_second_usage", comment: "Ten second usage message"))
        }
        .navigationTitle(NSLocalizedString("tool_ten_second", comment: "10s Challenge"))
        .navigationBarTitleDisplayMode(.inline)
        .gesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.width > 50 && abs(value.translation.height) < 50 {
                        dismiss()
                    }
                }
        )
    }

    private var recentHistory: [TimeInterval] {
        Array(history.suffix(2))
    }

    private func startTapHintPulse() {
        tapHintPulse = 1.0
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
            tapHintPulse = 1.15
        }
    }

    private var historyOverlay: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture { showHistoryOverlay = false }

            VStack(spacing: 8) {
                Text(NSLocalizedString("records", comment: "Records"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(WatchTheme.primaryText)
                    .padding(.top, 12)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(history.indices.reversed(), id: \.self) { idx in
                            let time = history[idx]
                            HStack {
                                Text("#\(history.count - idx)")
                                    .font(.system(size: 12))
                                    .foregroundColor(WatchTheme.secondaryText)
                                    .frame(width: 40, alignment: .leading)

                                Text(formatShortTime(time))
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(WatchTheme.primaryText)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 44)

                            if idx != history.indices.first {
                                Rectangle()
                                    .fill(Color.white.opacity(0.08))
                                    .frame(height: 0.5)
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                }
            }
            .frame(width: 140, height: 170)
            .background(WatchTheme.card)
            .cornerRadius(16)
        }
    }

    private func toggleChallenge() {
        if isRunning {
            stopChallenge()
        } else {
            startChallenge()
        }
    }

    private func startChallenge() {
        isRunning = true
        currentTime = 0
        startTimestamp = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
            let elapsed = Date().timeIntervalSince(startTimestamp)
            currentTime = min(elapsed, 59.99)
            if elapsed >= 59.99 {
                stopChallenge()
            }
        }
    }

    private func stopChallenge() {
        timer?.invalidate()
        timer = nil
        isRunning = false

        WatchSoundManager.shared.playSound(named: "ten_second_end")

        history.append(currentTime)
        if history.count > 20 {
            history = Array(history.suffix(20))
        }

        let diff = abs(currentTime - 10.0)
        if diff < 0.01 {
            WatchHaptics.shared.play(.strong)
        } else if diff < 0.1 {
            WatchHaptics.shared.play(.medium)
        } else {
            WatchHaptics.shared.play(.light)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let intSec = Int(seconds)
        let centis = Int((seconds - Double(intSec)) * 100)
        return String(format: "%02d.%02d", intSec, centis)
    }

    private func formatShortTime(_ seconds: TimeInterval) -> String {
        let intSec = Int(seconds)
        let centis = Int((seconds - Double(intSec)) * 100)
        return String(format: "%02d.%02d", intSec, centis)
    }
}
