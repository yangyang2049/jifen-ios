import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var selectedGame: GameType? = nil

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()

            TabView(selection: $selectedTab) {
                NavigationStack {
                    HomeTab(onNavigateToTab: { index, game in
                        selectedTab = index
                        selectedGame = game
                    })
                }
                .tag(0)
                .tabItem {
                    Label(NSLocalizedString("tab_home", comment: "Home tab"), systemImage: "house.fill")
                }

                NavigationStack {
                    ScoreboardTab(selectedGame: $selectedGame)
                }
                .tag(1)
                .tabItem {
                    Label(NSLocalizedString("tab_score", comment: "Score tab"), systemImage: "sportscourt.fill")
                }

                NavigationStack {
                    ToolsTab()
                }
                .tag(2)
                .tabItem {
                    Label(NSLocalizedString("tab_tools", comment: "Tools tab"), systemImage: "wrench.and.screwdriver.fill")
                }
            }
            .accentColor(Theme.accentColor)
        }
    }
}

#Preview {
    MainTabView()
}
