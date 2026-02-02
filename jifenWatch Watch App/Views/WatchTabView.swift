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
        .tabViewStyle(.page(indexDisplayMode: .automatic))
    }
}
