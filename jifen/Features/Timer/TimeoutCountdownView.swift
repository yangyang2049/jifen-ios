//
//  TimeoutCountdownView.swift
//  jifen
//
//  暂停/超时：预设时间倒计时（15s～30min），选预设后开始。
//

import SwiftUI

struct TimeoutPreset: Identifiable {
    let id: String
    let name: String
    let seconds: Int
}

struct TimeoutCountdownView: View {
    @Environment(\.dismiss) var dismiss
    @State private var presets: [TimeoutPreset] = [
        TimeoutPreset(id: "15", name: "15 " + NSLocalizedString("seconds_short", value: "秒", comment: ""), seconds: 15),
        TimeoutPreset(id: "30", name: "30 " + NSLocalizedString("seconds_short", value: "秒", comment: ""), seconds: 30),
        TimeoutPreset(id: "60", name: "1 " + NSLocalizedString("minute", value: "分钟", comment: ""), seconds: 60),
        TimeoutPreset(id: "120", name: "2 " + NSLocalizedString("minutes", value: "分钟", comment: ""), seconds: 120),
        TimeoutPreset(id: "300", name: "5 " + NSLocalizedString("minutes", value: "分钟", comment: ""), seconds: 300),
        TimeoutPreset(id: "600", name: "10 " + NSLocalizedString("minutes", value: "分钟", comment: ""), seconds: 600),
        TimeoutPreset(id: "1800", name: "30 " + NSLocalizedString("minutes", value: "分钟", comment: ""), seconds: 1800)
    ]
    @State private var selectedSeconds: Int?
    @State private var timeLeft: Double = 0
    @State private var isRunning: Bool = false
    @State private var timerSubscription: Timer?
    @State private var startTime: Date?
    @State private var gameStartTime: Date?
    @State private var recordSaved: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let sec = selectedSeconds, sec > 0 {
                countdownView(total: sec)
            } else {
                presetListView
            }
        }
        .navigationTitle(NSLocalizedString("timer_timeout", value: "暂停/超时", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    saveRecordIfNeeded()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(Theme.textPrimary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear {
            stopTimer()
            saveRecordIfNeeded()
        }
    }

    private var presetListView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.spacing) {
                ForEach(presets) { p in
                    Button {
                        selectedSeconds = p.seconds
                        timeLeft = Double(p.seconds)
                        VibrationManager.shared.vibrateLight()
                    } label: {
                        Text(p.name)
                            .font(.system(size: Theme.fontBody1, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Theme.homeCardDark)
                            .cornerRadius(Theme.cornerRadius)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.padding)
        }
    }

    private func countdownView(total: Int) -> some View {
        VStack(spacing: 24) {
            Text(formatTime(timeLeft))
                .font(.system(size: 56, weight: .bold, design: .monospaced))
                .foregroundColor(timeLeft <= 10 ? Color(hex: "FF3B30") : .white)
            HStack(spacing: 20) {
                if !isRunning && timeLeft == Double(total) {
                    Button {
                        startTimer(total: total)
                    } label: {
                        Text(NSLocalizedString("start", comment: ""))
                            .frame(width: 100, height: 44)
                            .background(Theme.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(22)
                    }
                    .buttonStyle(.plain)
                } else if isRunning {
                    Button { pauseTimer() } label: {
                        Text(NSLocalizedString("pause", comment: ""))
                            .frame(width: 100, height: 44)
                            .background(Theme.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(22)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { resumeTimer() } label: {
                        Text(NSLocalizedString("resume", value: "继续", comment: ""))
                            .frame(width: 100, height: 44)
                            .background(Theme.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(22)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    stopTimer()
                    selectedSeconds = nil
                    timeLeft = 0
                    gameStartTime = nil
                } label: {
                    Text(NSLocalizedString("menu_reset", value: "重置", comment: ""))
                        .frame(width: 100, height: 44)
                        .background(Theme.homeCardDark)
                        .foregroundColor(.white)
                        .cornerRadius(22)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let t = max(0, Int(seconds))
        let m = t / 60
        let s = t % 60
        if m > 0 {
            return String(format: "%d:%02d", m, s)
        }
        return String(format: "%d", s)
    }

    private func startTimer(total: Int) {
        let now = Date()
        startTime = now
        gameStartTime = now
        timerSubscription = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in tick() }
        RunLoop.current.add(timerSubscription!, forMode: .common)
        isRunning = true
        VibrationManager.shared.vibrateLight()
    }

    private func pauseTimer() {
        stopTimer()
        isRunning = false
        VibrationManager.shared.vibrateLight()
    }

    private func resumeTimer() {
        startTime = Date()
        timerSubscription = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in tick() }
        RunLoop.current.add(timerSubscription!, forMode: .common)
        isRunning = true
        VibrationManager.shared.vibrateLight()
    }

    private func tick() {
        guard let start = startTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        startTime = Date()
        timeLeft -= elapsed
        if timeLeft <= 0 {
            timeLeft = 0
            stopTimer()
            isRunning = false
            VibrationManager.shared.vibrateHeavy()
        }
    }

    private func stopTimer() {
        timerSubscription?.invalidate()
        timerSubscription = nil
    }

    private func saveRecordIfNeeded() {
        guard !recordSaved, let start = gameStartTime else { return }
        let end = Date()
        let elapsed = end.timeIntervalSince(start)
        let id = "timeout_\(Int(start.timeIntervalSince1970))_\(Int(end.timeIntervalSince1970))"
        let record = GameRecordSummary(
            id: id,
            gameType: .stopwatch,
            timestamp: start.timeIntervalSince1970,
            duration: elapsed,
            winner: nil
        )
        TimerRecordsViewModel.shared.addRecord(record)
        recordSaved = true
    }
}

#Preview {
    NavigationStack {
        TimeoutCountdownView()
    }
}
