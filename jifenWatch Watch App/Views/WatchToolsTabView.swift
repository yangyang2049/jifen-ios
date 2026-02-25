import SwiftUI

struct WatchToolsTabView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                NavigationLink(destination: WatchFlipCoinView()) {
                    WatchPillRow(icon: "🪙", title: NSLocalizedString("tool_flip_coin", comment: "Flip Coin"))
                }
                .buttonStyle(.plain)

                NavigationLink(destination: WatchRandomNumberView()) {
                    WatchPillRow(icon: "🎲", title: NSLocalizedString("tool_random_number", comment: "Random Number"))
                }
                .buttonStyle(.plain)

                NavigationLink(destination: WatchTenSecondChallengeView()) {
                    WatchPillRow(icon: "⏱️", title: NSLocalizedString("tool_ten_second", comment: "10s Challenge"))
                }
                .buttonStyle(.plain)

                NavigationLink(destination: WatchCounterView()) {
                    WatchPillRow(icon: "➕", title: NSLocalizedString("game_counter", comment: "Counter"))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, WatchLayout.tabHorizontalPadding)
            .padding(.bottom, 12)
        }
        .background(WatchTheme.background)
        .navigationTitle(NSLocalizedString("tab_tools", comment: "Tools"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
