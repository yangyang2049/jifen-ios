import SwiftUI
import UIKit

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var selectedGame: GameType? = nil
    @State private var navigatingFromTab: Int? = nil
    @State private var pendingTimerGameType: GameType? = nil

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()
            if isPad {
                iPadLayout(
                    selectedTab: $selectedTab,
                    selectedGame: $selectedGame,
                    navigatingFromTab: $navigatingFromTab,
                    pendingTimerGameType: $pendingTimerGameType
                )
            } else {
                phoneLayout(
                    selectedTab: $selectedTab,
                    selectedGame: $selectedGame,
                    navigatingFromTab: $navigatingFromTab,
                    pendingTimerGameType: $pendingTimerGameType
                )
            }
        }
        .accentColor(Theme.accentColor)
    }

    @ViewBuilder
    private func phoneLayout(
        selectedTab: Binding<Int>,
        selectedGame: Binding<GameType?>,
        navigatingFromTab: Binding<Int?>,
        pendingTimerGameType: Binding<GameType?>
    ) -> some View {
        TabView(selection: selectedTab) {
            tabItem(tag: 0, titleKey: "tab_home", systemImage: "house.fill") {
                HomeTab(onNavigateToTab: { index, game in
                    navigatingFromTab.wrappedValue = selectedTab.wrappedValue
                    selectedTab.wrappedValue = index
                    if index == 3 {
                        pendingTimerGameType.wrappedValue = game
                        selectedGame.wrappedValue = nil
                    } else {
                        pendingTimerGameType.wrappedValue = nil
                        selectedGame.wrappedValue = game
                    }
                })
            }
            tabItem(tag: 1, titleKey: "tab_records", systemImage: "list.bullet.clipboard.fill") {
                RecordsTab()
            }
            tabItem(tag: 2, titleKey: "tab_score", systemImage: "sportscourt.fill") {
                ScoreboardTab(selectedGame: selectedGame, onDismiss: {
                    if let source = navigatingFromTab.wrappedValue {
                        selectedTab.wrappedValue = source
                        navigatingFromTab.wrappedValue = nil
                    }
                })
            }
            tabItem(tag: 3, titleKey: "tab_timer", systemImage: "timer") {
                TimerTab(pendingTimerGameType: pendingTimerGameType)
            }
        }
    }

    @ViewBuilder
    private func tabItem<Content: View>(
        tag: Int,
        titleKey: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            content()
        }
        .tag(tag)
        .tabItem {
            Label(NSLocalizedString(titleKey, comment: ""), systemImage: systemImage)
        }
    }

    @ViewBuilder
    private func iPadLayout(
        selectedTab: Binding<Int>,
        selectedGame: Binding<GameType?>,
        navigatingFromTab: Binding<Int?>,
        pendingTimerGameType: Binding<GameType?>
    ) -> some View {
        NavigationSplitView {
            List {
                ForEach(0..<4, id: \.self) { index in
                    Button {
                        selectedTab.wrappedValue = index
                    } label: {
                        tabSidebarLabel(index: index)
                    }
                    .listRowBackground(selectedTab.wrappedValue == index ? Color.accentColor.opacity(0.25) : nil)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle(NSLocalizedString("app_name", comment: ""))
        } detail: {
            NavigationStack {
                iPadDetailView(
                    selectedTab: selectedTab.wrappedValue,
                    selectedGame: selectedGame,
                    pendingTimerGameType: pendingTimerGameType,
                    onTabChange: { selectedTab.wrappedValue = $0 },
                    onSetSelectedGame: { selectedGame.wrappedValue = $0 },
                    onSetNavigatingFromTab: { navigatingFromTab.wrappedValue = $0 },
                    onDismissFromScoreboard: {
                        if let source = navigatingFromTab.wrappedValue {
                            selectedTab.wrappedValue = source
                            navigatingFromTab.wrappedValue = nil
                        }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func tabSidebarLabel(index: Int) -> some View {
        switch index {
        case 0: Label(NSLocalizedString("tab_home", comment: ""), systemImage: "house.fill")
        case 1: Label(NSLocalizedString("tab_records", comment: ""), systemImage: "list.bullet.clipboard.fill")
        case 2: Label(NSLocalizedString("tab_score", comment: ""), systemImage: "sportscourt.fill")
        case 3: Label(NSLocalizedString("tab_timer", comment: ""), systemImage: "timer")
        default: EmptyView()
        }
    }
}

private struct iPadDetailView: View {
    let selectedTab: Int
    @Binding var selectedGame: GameType?
    @Binding var pendingTimerGameType: GameType?
    var onTabChange: (Int) -> Void
    var onSetSelectedGame: (GameType?) -> Void
    var onSetNavigatingFromTab: (Int?) -> Void
    var onDismissFromScoreboard: () -> Void

    var body: some View {
        Group {
            switch selectedTab {
            case 0:
                HomeTab(onNavigateToTab: { index, game in
                    onSetNavigatingFromTab(selectedTab)
                    onTabChange(index)
                    if index == 3 {
                        pendingTimerGameType = game
                        onSetSelectedGame(nil)
                    } else {
                        pendingTimerGameType = nil
                        onSetSelectedGame(game)
                    }
                })
            case 1:
                RecordsTab()
            case 2:
                ScoreboardTab(selectedGame: $selectedGame, onDismiss: onDismissFromScoreboard)
            case 3:
                TimerTab(pendingTimerGameType: $pendingTimerGameType)
            default:
                HomeTab(onNavigateToTab: { index, _ in onTabChange(index) })
            }
        }
    }
}

#Preview {
    MainTabView()
}
