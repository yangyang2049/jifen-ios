import SwiftUI

struct WatchTimerPresetsView: View {
    private let presets: [TimerPreset] = [
        TimerPreset(seconds: 30, label: "30秒"),
        TimerPreset(seconds: 60, label: "1分"),
        TimerPreset(seconds: 90, label: "1分30"),
        TimerPreset(seconds: 120, label: "2分"),
        TimerPreset(seconds: 300, label: "5分"),
        TimerPreset(seconds: 600, label: "10分")
    ]

    private let ringSize: CGFloat = 60

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(presets) { preset in
                        NavigationLink(destination: WatchTimerDetailView(totalSeconds: preset.seconds)) {
                            VStack {
                                Text(preset.label)
                                    .font(.system(size: 14))
                                    .foregroundColor(WatchTheme.timerAccent)
                                    .frame(width: ringSize, height: ringSize)
                                    .background(
                                        Circle()
                                            .fill(WatchTheme.timerAccent.opacity(0.12))
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(WatchTheme.timerAccent, lineWidth: 2)
                                    )
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 12)
        }
        .background(WatchTheme.background)
        .navigationTitle("计时")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TimerPreset: Identifiable {
    let id = UUID()
    let seconds: Int
    let label: String
}
