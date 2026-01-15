import SwiftUI

struct WatchToolsTabView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                NavigationLink(destination: WatchFlipCoinView()) {
                    WatchPillRow(icon: "🪙", title: "抛硬币")
                }
                .buttonStyle(.plain)

                NavigationLink(destination: WatchRandomNumberView()) {
                    WatchPillRow(icon: "🎲", title: "随机数")
                }
                .buttonStyle(.plain)

                NavigationLink(destination: WatchTenSecondChallengeView()) {
                    WatchPillRow(icon: "⏱️", title: "十秒挑战")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(WatchTheme.background)
        .navigationTitle("工具")
        .navigationBarTitleDisplayMode(.inline)
    }
}
