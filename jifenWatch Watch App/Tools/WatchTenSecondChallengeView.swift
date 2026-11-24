import SwiftUI

/// A deliberately standalone Watch utility. The Watch target does not link
/// TimerCore because it does not expose a generic count-up/countdown tool;
/// this challenge owns only its short-lived local display timer.
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

    private let historyRowHeight: CGFloat = 34

    var body: some View {
        ZStack {
            WatchTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: historyRowHeight)

                Spacer()

                if isRunning {
                    Text(formatTime(currentTime))
                        .font(.system(
                            size: WatchLayout.isCompactScreen ? 42 : 48,
                            weight: .bold,
                            design: .monospaced
                        ))
                        .foregroundColor(WatchTheme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                } else {
                    Text("👆")
                        .font(.system(size: 40))
                        .scaleEffect(tapHintPulse)
                }

                Spacer()

                historyRow
                    .frame(height: historyRowHeight)
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
        .navigationTitle(
            showHistoryOverlay
                ? ""
                : NSLocalizedString("tool_ten_second", comment: "10s Challenge")
        )
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

    private var historyRow: some View {
        Group {
            if !showHistoryOverlay, !history.isEmpty {
                HStack(spacing: 8) {
                    ForEach(recentHistory.indices, id: \.self) { idx in
                        historyChip(formatShortTime(recentHistory[idx]))
                    }
                    if history.count > 2 {
                        historyChip("···")
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    showHistoryOverlay = true
                }
            } else {
                Color.clear
            }
        }
    }

    private func historyChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundColor(Color(hex: 0xD0D0D0))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.12))
            .cornerRadius(12)
    }

    private func startTapHintPulse() {
        tapHintPulse = 1.0
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
            tapHintPulse = 1.15
        }
    }

    private var historyOverlay: some View {
        let compact = WatchLayout.isCompactScreen
        return ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()
                .onTapGesture { showHistoryOverlay = false }

            VStack(spacing: 0) {
                WatchDialogHeader(
                    title: NSLocalizedString("records", comment: "Records"),
                    onClose: { showHistoryOverlay = false }
                )
                .padding(.bottom, compact ? 6 : 10)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(history.indices.reversed(), id: \.self) { idx in
                            let time = history[idx]
                            HStack {
                                Text("#\(history.count - idx)")
                                    .font(.system(size: 12))
                                    .foregroundColor(WatchTheme.secondaryText)
                                    .frame(width: 38, alignment: .leading)

                                Text(formatShortTime(time))
                                    .font(.system(size: compact ? 18 : 20, weight: .medium))
                                    .foregroundColor(WatchTheme.primaryText)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: compact ? 38 : 42)

                            if idx != history.indices.first {
                                Rectangle()
                                    .fill(WatchTheme.subtleFill)
                                    .frame(height: 0.5)
                                    .padding(.horizontal, 6)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.top, compact ? 10 : 12)
            .padding(.bottom, compact ? 8 : 10)
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 152 : 186)
            .background(WatchTheme.listItemBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, WatchLayout.pageHorizontalPadding)
            .padding(.top, compact ? 22 : 26)
            .padding(.bottom, compact ? 4 : 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
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
