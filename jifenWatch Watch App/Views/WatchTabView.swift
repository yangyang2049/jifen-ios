import SwiftUI

struct WatchTabView: View {
    @Binding var scoreboardRoute: WatchScoreboardRoute?
    @State private var selection: Int = 1

    var body: some View {
        TabView(selection: $selection) {
            WatchToolsTabView()
                .tag(0)

            WatchHomeTabView(scoreboardRoute: $scoreboardRoute)
                .tag(1)

            WatchRecordListView()
                .tag(2)

            WatchSettingsView()
                .tag(3)
        }
        // Keep page indicator hidden to avoid bottom reserved area leaking into pushed scoreboards.
        .tabViewStyle(.page(indexDisplayMode: .never))
    }
}
