import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var presentedTool: ToolItem? = nil // State to present tool modally
    
    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()
            
            TabView(selection: $selectedTab) {
                HomeTab(
                    onNavigateToTab: { index in
                        selectedTab = index
                    },
                    onOpenTool: { toolItem in // Now accepts ToolItem directly
                        presentedTool = toolItem
                    }
                )
                    .tag(0)
                    .tabItem {
                        Label(NSLocalizedString("tab_home", comment: "Home tab"), systemImage: "house.fill")
                    }
                
                ScoreboardTab()
                    .tag(1)
                    .tabItem {
                        Label(NSLocalizedString("tab_score", comment: "Score tab"), systemImage: "sportscourt.fill")
                    }
                
                ToolsTab(
                    onOpenTool: { toolItem in // Pass onOpenTool to ToolsTab too
                        presentedTool = toolItem
                    }
                )
                    .tag(2)
                    .tabItem {
                        Label(NSLocalizedString("tab_tools", comment: "Tools tab"), systemImage: "wrench.and.screwdriver.fill")
                    }
            }
            .accentColor(Theme.accentColor)
            .fullScreenCover(item: $presentedTool) { toolItem in // Present tool modally
                NavigationStack {
                    toolItem.view
                        .toolbar(.visible, for: .navigationBar)
                        .toolbarBackground(.visible, for: .navigationBar)
                }
            }
        }
    }
}

#Preview {
    MainTabView()
}

