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

            WatchSettingsView()
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
    }
}
