//
//  BasketballCountdownView.swift
//  jifen
//
//  篮球 24 秒 / 12 秒 进攻倒计时。
//

import SwiftUI

struct BasketballCountdownView: View {
    let duration: Int
    @Environment(\.dismiss) var dismiss

    @State private var timeLeft: Double
    @State private var isRunning: Bool = false
    @State private var timerSubscription: Timer?
    @State private var startTime: Date?
    @State private var gameStartTime: Date?
    @State private var recordSaved: Bool = false

    init(duration: Int) {
        self.duration = duration
        _timeLeft = State(initialValue: Double(duration))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Text(formatTime(timeLeft))
                    .font(.system(size: 72, weight: .bold, design: .monospaced))
                    .foregroundColor(timeLeft <= 5 ? Color(hex: "FF3B30") : .white)
                HStack(spacing: 20) {
                    Button {
                        if isRunning { pauseTimer() } else { startTimer() }
                    } label: {
                        Text(isRunning ? NSLocalizedString("pause", comment: "") : NSLocalizedString("start", comment: ""))
                            .frame(width: 100, height: 44)
                            .background(Theme.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(22)
                    }
                    .buttonStyle(.plain)
                    Button {
                        resetTimer()
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
        .navigationTitle("\(duration) " + NSLocalizedString("seconds", value: "秒", comment: ""))
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

    private func formatTime(_ seconds: Double) -> String {
        let t = max(0, Int(seconds))
        return String(format: "%d", t)
    }

    private func startTimer() {
        let now = Date()
        startTime = now
        if gameStartTime == nil { gameStartTime = now }
        timerSubscription = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in tick() }
        if let t = timerSubscription {
            RunLoop.current.add(t, forMode: .common)
        }
        isRunning = true
        VibrationManager.shared.vibrateLight()
    }

    private func pauseTimer() {
        stopTimer()
        isRunning = false
        VibrationManager.shared.vibrateLight()
    }

    private func resetTimer() {
        stopTimer()
        timeLeft = Double(duration)
        startTime = nil
        gameStartTime = nil
        isRunning = false
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
        let id = "basketball_\(duration)s_\(Int(start.timeIntervalSince1970))_\(Int(end.timeIntervalSince1970))"
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
        BasketballCountdownView(duration: 24)
    }
}
