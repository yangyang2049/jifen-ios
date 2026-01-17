import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var toolToOpen: String? = nil // New state to control tool navigation from HomeTab
    
    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()
            
            TabView(selection: $selectedTab) {
                HomeTab(
                    onNavigateToTab: { index in
                        selectedTab = index
                    },
                    onOpenTool: { toolId in // New callback for HomeTab
                        toolToOpen = toolId
                        selectedTab = 2 // Switch to ToolsTab
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
                
                ToolsTab(toolToOpen: $toolToOpen) // Pass binding to ToolsTab
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

