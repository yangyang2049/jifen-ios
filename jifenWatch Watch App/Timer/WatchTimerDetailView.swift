import SwiftUI

struct WatchTimerDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var totalSeconds: Int
    @State private var remainingSeconds: Int
    @State private var isRunning = false
    @State private var isFinished = false
    @State private var hasStarted = false

    @State private var timer: Timer? = nil
    @State private var startTimestamp: Date = Date()
    @State private var pausedRemaining: Int = 0

    init(totalSeconds: Int) {
        _totalSeconds = State(initialValue: totalSeconds)
        _remainingSeconds = State(initialValue: totalSeconds)
    }

    var body: some View {
        ZStack {
            WatchTheme.background.ignoresSafeArea()

            Text(formatTime(remainingSeconds))
                .font(.system(size: 60, weight: .bold))
                .foregroundColor(WatchTheme.primaryText)
                .kerning(2)

            VStack {
                Spacer()
                HStack(spacing: 20) {
                    Button(action: handleStart) {
                        Image(systemName: isRunning ? "pause.fill" : "play.fill")
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(primaryButtonColor)
                            .clipShape(Circle())
                    }

                    if shouldShowStop {
                        Button(action: handleStop) {
                            Image(systemName: "stop.fill")
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(Color.red.opacity(0.85))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
        .navigationTitle(NSLocalizedString("tab_timer", comment: "Timer"))
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

    private var primaryButtonColor: Color {
        isRunning ? WatchTheme.card.opacity(0.8) : WatchTheme.timerAccent.opacity(0.4)
    }

    private var shouldShowStop: Bool {
        !isRunning && (hasStarted || isFinished)
    }

    private func handleStart() {
        if isRunning {
            handlePause()
            return
        }
        if isFinished || remainingSeconds <= 0 {
            resetTimer()
        }
        hasStarted = true
        startTimer()
    }

    private func handlePause() {
        guard isRunning else { return }
        let elapsed = Int(Date().timeIntervalSince(startTimestamp))
        remainingSeconds = max(0, pausedRemaining - elapsed)
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    private func handleStop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        isFinished = false
        hasStarted = false
        remainingSeconds = totalSeconds
    }

    private func startTimer() {
        guard timer == nil else { return }
        isRunning = true
        isFinished = false
        hasStarted = true
        startTimestamp = Date()
        pausedRemaining = remainingSeconds

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            let elapsed = Int(Date().timeIntervalSince(startTimestamp))
            let newRemaining = max(0, pausedRemaining - elapsed)
            if newRemaining != remainingSeconds {
                remainingSeconds = newRemaining
            }
            if remainingSeconds <= 0 {
                onTimerFinished()
            }
        }
    }

    private func onTimerFinished() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        isFinished = true
        remainingSeconds = 0
        WatchHaptics.shared.play(.strong)
    }

    private func resetTimer() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        isFinished = false
        hasStarted = false
        remainingSeconds = totalSeconds
    }

    private func formatTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
