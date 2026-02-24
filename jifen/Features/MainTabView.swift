import SwiftUI
import UIKit

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var selectedGame: GameType? = nil
    @State private var navigatingFromTab: Int? = nil
    @State private var pendingTimerGameType: GameType? = nil

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()
            mainLayout(
                selectedTab: $selectedTab,
                selectedGame: $selectedGame,
                navigatingFromTab: $navigatingFromTab,
                pendingTimerGameType: $pendingTimerGameType
            )
        }
        .accentColor(Theme.accentColor)
        .onAppear {
            configureTabBarPresentation()
        }
        .onChange(of: selectedTab) { _, _ in
            configureTabBarPresentation()
        }
    }

    @ViewBuilder
    private func mainLayout(
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

    private func configureTabBarPresentation() {
        DispatchQueue.main.async {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                    ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
                  let rootViewController = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                    ?? scene.windows.first?.rootViewController,
                  let tabBarController = rootViewController.findTabBarController()
            else {
                return
            }

            if #available(iOS 18.0, *) {
                tabBarController.mode = .tabBar
                tabBarController.setTabBarHidden(false, animated: false)
            }
            if #available(iOS 26.0, *) {
                tabBarController.tabBarMinimizeBehavior = .never
            }
        }
    }
}

#Preview {
    MainTabView()
}
