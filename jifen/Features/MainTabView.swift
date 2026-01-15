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
                        Label("首页", systemImage: "house.fill")
                    }
                
                ScoreboardTab()
                    .tag(1)
                    .tabItem {
                        Label("计分", systemImage: "sportscourt.fill")
                    }
                
                ToolsTab()
                    .tag(2)
                    .tabItem {
                        Label("工具", systemImage: "wrench.and.screwdriver.fill")
                    }
            }
            .accentColor(Theme.accentColor)
        }
    }
}

#Preview {
    MainTabView()
}

