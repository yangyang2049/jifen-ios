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
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let digitSize = min(geo.size.width, geo.size.height) * (isLandscape ? 0.58 : 0.42)

            ZStack {
                Color.black.ignoresSafeArea()

                Group {
                    if isLandscape {
                        HStack(spacing: 28) {
                            controlColumn
                            Text(formatTime(timeLeft))
                                .font(.system(size: digitSize, weight: .bold, design: .monospaced))
                                .foregroundColor(timeLeft <= 5 ? Color(hex: "FF3B30") : .white)
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                            Text("\(duration)\n" + NSLocalizedString("seconds", value: "秒", comment: ""))
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white.opacity(0.55))
                                .multilineTextAlignment(.center)
                                .frame(width: 56)
                        }
                        .padding(.horizontal, 28)
                    } else {
                        VStack(spacing: 28) {
                            Text("\(duration) " + NSLocalizedString("seconds", value: "秒", comment: ""))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.55))
                            Text(formatTime(timeLeft))
                                .font(.system(size: digitSize, weight: .bold, design: .monospaced))
                                .foregroundColor(timeLeft <= 5 ? Color(hex: "FF3B30") : .white)
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                            controlColumn
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 24)
                    }
                }

                VStack {
                    HStack {
                        Button {
                            saveRecordIfNeeded()
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.white.opacity(0.14))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        .onAppear {
            OrientationLock.shared.lock(.landscape)
        }
        .onDisappear {
            OrientationLock.shared.unlock()
            stopTimer()
            saveRecordIfNeeded()
        }
    }

    private var controlColumn: some View {
        VStack(spacing: 16) {
            controlButton(
                title: isRunning
                    ? NSLocalizedString("pause", comment: "")
                    : NSLocalizedString("start", comment: ""),
                fill: Theme.accentColor
            ) {
                if isRunning { pauseTimer() } else { startTimer() }
            }
            controlButton(
                title: NSLocalizedString("menu_reset", value: "重置", comment: ""),
                fill: Color.white.opacity(0.12)
            ) {
                resetTimer()
            }
        }
    }

    private func controlButton(title: String, fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 120, height: 48)
                .background(fill)
                .foregroundColor(.white)
                .cornerRadius(24)
        }
        .buttonStyle(.plain)
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
