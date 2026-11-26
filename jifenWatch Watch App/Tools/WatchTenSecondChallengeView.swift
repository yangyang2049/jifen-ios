import SwiftUI

enum WatchTenSecondChallengePolicy {
    static let presetSeconds: [Int] = [1, 3, 5, 10]
    static let defaultTargetSeconds: Int = 10

    static func normalizedTargetSeconds(_ seconds: Int) -> Int {
        presetSeconds.contains(seconds) ? seconds : defaultTargetSeconds
    }

    static func difference(elapsed: TimeInterval, targetSeconds: Int) -> TimeInterval {
        abs(max(0, elapsed) - TimeInterval(normalizedTargetSeconds(targetSeconds)))
    }

    static func hapticType(for difference: TimeInterval) -> WatchHapticType {
        if difference < 0.01 {
            return .strong
        } else if difference < 0.1 {
            return .medium
        } else {
            return .light
        }
    }
}

/// A deliberately standalone Watch utility. The Watch target does not link
/// TimerCore because it does not expose a generic count-up/countdown tool;
/// this challenge owns only its short-lived local display timer.
struct WatchTenSecondChallengeView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("watch_ten_second_target_seconds") private var storedTargetSeconds: Int = WatchTenSecondChallengePolicy.defaultTargetSeconds
    @State private var isRunning = false
    @State private var currentTime: TimeInterval = 0
    @State private var tapHintPulse: CGFloat = 1.0
    @State private var historyByTarget: [Int: [TimeInterval]] = [:]
    @State private var showHistoryOverlay = false
    @State private var showUsageAlert = false
    @State private var usagePromptShown = false

    @State private var timer: Timer? = nil
    @State private var startTimestamp: Date = Date()

    private let historyRowHeight: CGFloat = 34

    private var selectedTargetSeconds: Int {
        WatchTenSecondChallengePolicy.normalizedTargetSeconds(storedTargetSeconds)
    }

    private var currentHistory: [TimeInterval] {
        historyByTarget[selectedTargetSeconds] ?? []
    }

    var body: some View {
        ZStack {
            WatchTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                targetPicker
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
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(WatchTheme.accent)
                        .scaleEffect(tapHintPulse)
                        .accessibilityHidden(true)
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
        .alert(NSLocalizedString("watch_ten_second_challenge", comment: "Stop the Clock"), isPresented: $showUsageAlert) {
            Button(NSLocalizedString("got_it", comment: "Got it"), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("watch_ten_second_usage", comment: "Stop the Clock usage message"))
        }
        .navigationTitle(
            showHistoryOverlay
                ? ""
                : NSLocalizedString("tool_ten_second", comment: "Stop the Clock")
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

    private var targetPicker: some View {
        let compact = WatchLayout.isCompactScreen
        let unit = NSLocalizedString("unit_second", value: "s", comment: "Seconds unit")
        return HStack(spacing: 2) {
            ForEach(WatchTenSecondChallengePolicy.presetSeconds, id: \.self) { seconds in
                targetOptionButton(seconds: seconds, compact: compact, unit: unit)
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.10), in: Capsule())
        .padding(.horizontal, WatchLayout.pageHorizontalPadding)
        .opacity(isRunning ? 0.35 : 1.0)
        .allowsHitTesting(!isRunning)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch_ten_second_target")
    }

    private func targetOptionButton(seconds: Int, compact: Bool, unit: String) -> some View {
        let selected = selectedTargetSeconds == seconds
        return Button {
            guard !isRunning, selectedTargetSeconds != seconds else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                storedTargetSeconds = seconds
            }
            currentTime = 0
            WatchHaptics.shared.play(.light)
        } label: {
            Text("\(seconds)\(unit)")
                .font(.system(size: compact ? 11 : 12, weight: selected ? .semibold : .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(selected ? Color.white : WatchTheme.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: compact ? 22 : 24)
                .background(
                    selected ? Color.white.opacity(0.26) : Color.clear,
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("watch_ten_second_target_\(seconds)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var recentHistory: [TimeInterval] {
        Array(currentHistory.suffix(2))
    }

    private var historyRow: some View {
        Group {
            if !showHistoryOverlay, !currentHistory.isEmpty {
                HStack(spacing: 8) {
                    ForEach(recentHistory.indices, id: \.self) { idx in
                        historyChip(formatShortTime(recentHistory[idx]))
                    }
                    if currentHistory.count > 2 {
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
                        ForEach(currentHistory.indices.reversed(), id: \.self) { idx in
                            let time = currentHistory[idx]
                            HStack {
                                Text("#\(currentHistory.count - idx)")
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

                            if idx != currentHistory.indices.first {
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

        let targetSeconds = selectedTargetSeconds
        var updatedHistory = historyByTarget[targetSeconds] ?? []
        updatedHistory.append(currentTime)
        if updatedHistory.count > 20 {
            updatedHistory = Array(updatedHistory.suffix(20))
        }
        historyByTarget[targetSeconds] = updatedHistory

        let diff = WatchTenSecondChallengePolicy.difference(
            elapsed: currentTime,
            targetSeconds: targetSeconds
        )
        WatchHaptics.shared.play(WatchTenSecondChallengePolicy.hapticType(for: diff))
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
