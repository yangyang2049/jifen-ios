import SwiftUI
import UIKit

private enum StopwatchLapTone {
    case fastest
    case slowest
    case normal
}

private struct StopwatchLapRow: Identifiable {
    let id: Int
    let splitMilliseconds: Double
    let totalMilliseconds: Double
    let tone: StopwatchLapTone
}

struct StopwatchView: View {
    @State private var state = TimerToolStateStore.loadStopwatch()
    @State private var previousIdleTimerDisabled: Bool?

    private let maximumLapCount = 100

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()

            TimelineView(.animation(minimumInterval: 0.01, paused: state.phase != .running)) { context in
                let elapsed = state.elapsedMilliseconds(at: context.date)

                VStack(spacing: 0) {
                    Spacer(minLength: 24)

                    Text(formatStopwatch(elapsed))
                        .font(.system(size: 64, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .minimumScaleFactor(0.45)
                        .lineLimit(1)
                        .padding(.horizontal, 20)

                    if state.phase == .running, let lastLap = state.lapCumulativeMilliseconds.last {
                        Text(formatStopwatch(max(0, elapsed - lastLap)))
                            .font(.system(size: 17, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 8)
                    }

                    Spacer(minLength: 28)

                    if !state.lapCumulativeMilliseconds.isEmpty {
                        lapList
                            .frame(maxHeight: 310)
                    }

                    Spacer(minLength: 24)

                    controls
                        .padding(.bottom, 28)
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(NSLocalizedString("tool_stopwatch", value: "秒表", comment: "Stopwatch"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            state = TimerToolStateStore.loadStopwatch()
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            updateIdleTimer()
        }
        .onChange(of: state.phase) { _, _ in
            updateIdleTimer()
        }
        .onDisappear {
            TimerToolStateStore.saveStopwatch(state)
            if let previousIdleTimerDisabled {
                UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
            }
        }
    }

    private var lapList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(lapRows) { row in
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(toneColor(row.tone).opacity(row.tone == .normal ? 0.12 : 0.16))
                            Text("\(row.id)")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(toneColor(row.tone))
                        .frame(width: 34, height: 34)

                        Text("+\(formatStopwatch(row.splitMilliseconds))")
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(formatStopwatch(row.totalMilliseconds))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(toneColor(row.tone))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)

                    if row.id != lapRows.last?.id {
                        Divider().padding(.leading, 64)
                    }
                }
            }
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
    }

    private var controls: some View {
        HStack(spacing: 30) {
            if state.phase == .running {
                circleButton(
                    systemName: "flag",
                    diameter: 60,
                    foreground: Theme.textPrimary,
                    background: Theme.controlBackground,
                    border: Theme.divider,
                    disabled: state.lapCumulativeMilliseconds.count >= maximumLapCount,
                    action: recordLap
                )
            } else {
                circleButton(
                    systemName: "arrow.counterclockwise",
                    diameter: 60,
                    foreground: Theme.textPrimary,
                    background: .clear,
                    border: Theme.divider,
                    disabled: state.baseMilliseconds <= 0 && state.lapCumulativeMilliseconds.isEmpty,
                    action: reset
                )
            }

            if state.phase == .running {
                circleButton(
                    systemName: "pause.fill",
                    diameter: 60,
                    foreground: Color.white,
                    background: Theme.accentColor,
                    border: Color.clear,
                    disabled: false,
                    action: pause
                )
            } else {
                circleButton(
                    systemName: "play.fill",
                    diameter: 60,
                    foreground: Color.white,
                    background: Theme.accentColor,
                    border: Color.clear,
                    disabled: false,
                    action: startOrResume
                )
            }
        }
    }

    private func circleButton(
        systemName: String,
        diameter: CGFloat,
        foreground: Color,
        background: Color,
        border: Color,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: diameter, height: diameter)
                .background(background)
                .clipShape(Circle())
                .overlay(Circle().stroke(border, lineWidth: 1))
                .opacity(disabled ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(Text(systemName))
    }

    private var lapRows: [StopwatchLapRow] {
        let totals = state.lapCumulativeMilliseconds
        let splits = totals.indices.map { index in
            totals[index] - (index > 0 ? totals[index - 1] : 0)
        }
        let minimum = splits.min() ?? 0
        let maximum = splits.max() ?? 0
        let canCompare = splits.count >= 2 && minimum < maximum

        return totals.indices.reversed().map { index in
            let tone: StopwatchLapTone
            if canCompare, splits[index] == minimum {
                tone = .fastest
            } else if canCompare, splits[index] == maximum {
                tone = .slowest
            } else {
                tone = .normal
            }
            return StopwatchLapRow(
                id: index + 1,
                splitMilliseconds: splits[index],
                totalMilliseconds: totals[index],
                tone: tone
            )
        }
    }

    private func toneColor(_ tone: StopwatchLapTone) -> Color {
        switch tone {
        case .fastest: return Theme.positiveText
        case .slowest: return Theme.destructiveText
        case .normal: return Theme.textSecondary
        }
    }

    private func startOrResume() {
        state.runStartedAt = Date().timeIntervalSince1970 * 1_000
        state.phase = .running
        TimerToolStateStore.saveStopwatch(state)
        VibrationManager.shared.vibrateMedium()
    }

    private func pause() {
        state.baseMilliseconds = state.elapsedMilliseconds()
        state.runStartedAt = 0
        state.phase = .paused
        TimerToolStateStore.saveStopwatch(state)
        VibrationManager.shared.vibrateMedium()
    }

    private func reset() {
        state = StopwatchPersistedState()
        TimerToolStateStore.saveStopwatch(state)
        VibrationManager.shared.vibrateMedium()
    }

    private func recordLap() {
        guard state.phase == .running, state.lapCumulativeMilliseconds.count < maximumLapCount else { return }
        state.lapCumulativeMilliseconds.append(state.elapsedMilliseconds())
        TimerToolStateStore.saveStopwatch(state)
        VibrationManager.shared.vibrateLight()
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = state.phase == .running
    }

    private func formatStopwatch(_ milliseconds: Double) -> String {
        let value = max(0, Int(milliseconds))
        if value >= 3_600_000 {
            let seconds = value / 1_000
            return String(format: "%02d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60)
        }
        let seconds = value / 1_000
        return String(format: "%02d:%02d.%02d", seconds / 60, seconds % 60, value % 1_000 / 10)
    }
}

#Preview {
    NavigationStack { StopwatchView() }
}
