//
//  MainTabView.swift
//  jifen
//
//  Main tab navigation with liquid design
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()
            
            TabView(selection: $selectedTab) {
                HomeTab()
                    .tag(0)
                    .tabItem {
                        Label(NSLocalizedString("tab_home", comment: "Home tab"), systemImage: "house.fill")
                    }
                
                ScoreboardTab()
                    .tag(1)
                    .tabItem {
                        Label(NSLocalizedString("tab_score", comment: "Score tab"), systemImage: "sportscourt.fill")
                    }
                
                ToolsTab()
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

