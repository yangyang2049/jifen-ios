//
//  StopwatchView.swift
//  jifen
//
//  秒表：开始/暂停/继续、重置；分段（中途）计时；不保存记录、不出现在记录 Tab。
//

import SwiftUI

/// 单条分段记录：本段时长 + 累计总时长
struct StopwatchLapEntry: Identifiable {
    let id: Int
    let segmentTime: TimeInterval
    let totalTime: TimeInterval
}

struct StopwatchView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var startTime: Date?
    @State private var accumulated: TimeInterval = 0
    @State private var displayElapsed: TimeInterval = 0
    @State private var displayTimer: Timer?
    @State private var laps: [StopwatchLapEntry] = []

    private var isRunning: Bool { startTime != nil }

    /// 当前总时长（运行中或暂停时的累计值）
    private var currentTotalElapsed: TimeInterval {
        if let start = startTime {
            return accumulated + Date().timeIntervalSince(start)
        }
        return accumulated
    }

    /// 是否可记录分段（运行中或已有时间时）
    private var canRecordLap: Bool {
        isRunning || accumulated > 0
    }

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Theme.backgroundColor : Theme.homeBackgroundLight).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 20)
                Text(formatElapsedPrecise(displayElapsed))
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.accentColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(NSLocalizedString("stopwatch_total", value: "总时长", comment: "Stopwatch total"))
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.top, 4)
                Spacer(minLength: 24)
                HStack(spacing: 12) {
                    Button {
                        if isRunning { pauseTimer() } else { startOrResumeTimer() }
                    } label: {
                        Text(isRunning ? NSLocalizedString("pause", value: "暂停", comment: "") : NSLocalizedString("start", value: "开始", comment: ""))
                            .font(.system(size: 16, weight: .semibold))
                            .frame(minWidth: 80, minHeight: 44)
                            .background(Theme.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(22)
                    }
                    .buttonStyle(.plain)
                    Button {
                        recordLap()
                    } label: {
                        Text(NSLocalizedString("stopwatch_lap", value: "分段", comment: "Lap"))
                            .font(.system(size: 16, weight: .semibold))
                            .frame(minWidth: 80, minHeight: 44)
                            .background(canRecordLap ? Theme.surface : Theme.surface.opacity(0.5))
                            .foregroundColor(canRecordLap ? Theme.textPrimary : Theme.textSecondary)
                            .cornerRadius(22)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canRecordLap)
                    Button {
                        resetTimer()
                    } label: {
                        Text(NSLocalizedString("menu_reset", value: "重置", comment: ""))
                            .font(.system(size: 16, weight: .semibold))
                            .frame(minWidth: 80, minHeight: 44)
                            .background(Theme.surface)
                            .foregroundColor(Theme.textPrimary)
                            .cornerRadius(22)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.padding)
                if !laps.isEmpty {
                    lapListSection
                }
                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(NSLocalizedString("tool_stopwatch", value: "秒表", comment: "Stopwatch"))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear {
            updateDisplayFromAccumulated()
        }
        .onDisappear {
            stopDisplayTimer()
        }
    }

    private var lapListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(NSLocalizedString("stopwatch_lap_list_title", value: "分段记录", comment: "Lap list"))
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, Theme.padding)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    lapTableHeader
                    ForEach(laps) { lap in
                        lapRow(lap)
                    }
                }
                .padding(.horizontal, Theme.padding)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: 220)
            .background(Theme.surface.opacity(0.5))
            .cornerRadius(12)
            .padding(.horizontal, Theme.padding)
            .padding(.top, 8)
        }
        .padding(.top, 16)
    }

    private var lapTableHeader: some View {
        HStack {
            Text(NSLocalizedString("stopwatch_lap_no", value: "序号", comment: ""))
                .frame(width: 24, alignment: .leading)
            Spacer()
            Text(NSLocalizedString("stopwatch_lap_segment", value: "本段", comment: ""))
                .frame(width: 130, alignment: .trailing)
            Text(NSLocalizedString("stopwatch_lap_total", value: "总时长", comment: ""))
                .frame(width: 130, alignment: .trailing)
        }
        .font(.caption.weight(.medium))
        .foregroundColor(Theme.textSecondary)
        .padding(.vertical, 8)
    }

    private func lapRow(_ lap: StopwatchLapEntry) -> some View {
        HStack {
            Text("\(lap.id)")
                .font(.system(.body, design: .monospaced))
                .frame(width: 24, alignment: .leading)
            Spacer()
            Text(formatElapsedPrecise(lap.segmentTime))
                .font(.system(.body, design: .monospaced))
                .frame(width: 130, alignment: .trailing)
            Text(formatElapsedPrecise(lap.totalTime))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(Theme.accentColor)
                .frame(width: 130, alignment: .trailing)
        }
        .font(.system(size: 15))
        .foregroundColor(Theme.textPrimary)
        .padding(.vertical, 6)
    }

    /// 格式化为 00:00.00 或 0:00:00.00（精确到百分之一秒）
    private func formatElapsedPrecise(_ seconds: TimeInterval) -> String {
        let totalCentisec = Int(round(seconds * 100))
        let totalSec = totalCentisec / 100
        let centisec = totalCentisec % 100
        let h = totalSec / 3600
        let m = (totalSec % 3600) / 60
        let s = totalSec % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d.%02d", h, m, s, centisec)
        }
        return String(format: "%02d:%02d.%02d", m, s, centisec)
    }

    private func startOrResumeTimer() {
        startTime = Date()
        startDisplayTimer()
        VibrationManager.shared.vibrateLight()
    }

    private func pauseTimer() {
        if let start = startTime {
            accumulated += Date().timeIntervalSince(start)
            startTime = nil
        }
        stopDisplayTimer()
        updateDisplayFromAccumulated()
        VibrationManager.shared.vibrateLight()
    }

    private func recordLap() {
        guard canRecordLap else { return }
        let total = currentTotalElapsed
        let lastTotal = laps.last?.totalTime ?? 0
        let segment = total - lastTotal
        let nextId = laps.count + 1
        laps.append(StopwatchLapEntry(id: nextId, segmentTime: segment, totalTime: total))
        VibrationManager.shared.vibrateLight()
    }

    private func resetTimer() {
        startTime = nil
        accumulated = 0
        laps = []
        stopDisplayTimer()
        displayElapsed = 0
        VibrationManager.shared.vibrateLight()
    }

    private func startDisplayTimer() {
        stopDisplayTimer()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
            updateDisplayFromAccumulated()
        }
        if let t = displayTimer {
            RunLoop.current.add(t, forMode: .common)
        }
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func updateDisplayFromAccumulated() {
        if let start = startTime {
            displayElapsed = accumulated + Date().timeIntervalSince(start)
        } else {
            displayElapsed = accumulated
        }
    }
}

#Preview {
    NavigationStack {
        StopwatchView()
    }
}
