//
//  CountUpTimerView.swift
//  jifen
//
//  正计时：从 0 开始正向计时，开始/暂停/重置；仅用于计时 Tab，与工具里的秒表区分。参考鸿蒙。
//

import SwiftUI

struct CountUpTimerView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var startTime: Date?
    @State private var accumulated: TimeInterval = 0
    @State private var displayElapsed: TimeInterval = 0
    @State private var displayTimer: Timer?

    private var isRunning: Bool { startTime != nil }

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Theme.backgroundColor : Theme.homeBackgroundLight).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 24)
                Text(formatElapsed(displayElapsed))
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.accentColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Spacer(minLength: 32)
                HStack(spacing: 16) {
                    Button {
                        if isRunning { pauseTimer() } else { startOrResumeTimer() }
                    } label: {
                        Text(isRunning ? NSLocalizedString("pause", value: "暂停", comment: "") : NSLocalizedString("start", value: "开始", comment: ""))
                            .font(.system(size: 16, weight: .medium))
                            .frame(minWidth: 88, minHeight: 44)
                            .padding(.horizontal, 20)
                            .background(Theme.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(22)
                    }
                    .buttonStyle(.plain)
                    Button {
                        resetTimer()
                    } label: {
                        Text(NSLocalizedString("menu_reset", value: "重置", comment: ""))
                            .font(.system(size: 16, weight: .medium))
                            .frame(minWidth: 88, minHeight: 44)
                            .padding(.horizontal, 20)
                            .background(Theme.surface)
                            .foregroundColor(Theme.textPrimary)
                            .cornerRadius(22)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.padding)
                Spacer(minLength: 48)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(NSLocalizedString("timer_count_up", value: "正计时", comment: "Count-up timer"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(Theme.textPrimary)
                }
            }
        }
        .onAppear {
            updateDisplayFromAccumulated()
        }
        .onDisappear {
            stopDisplayTimer()
        }
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
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

    private func resetTimer() {
        startTime = nil
        accumulated = 0
        stopDisplayTimer()
        displayElapsed = 0
        VibrationManager.shared.vibrateLight()
    }

    private func startDisplayTimer() {
        stopDisplayTimer()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
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
        CountUpTimerView()
    }
}
