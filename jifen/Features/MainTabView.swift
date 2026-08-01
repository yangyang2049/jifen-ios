import SwiftUI
import UIKit

struct MainTabView: View {
    @State private var selectedTab = ProcessInfo.processInfo.arguments.contains("-UITestOpenTimer") ? 3 : 0
    @State private var selectedGame: GameType? = nil
    @State private var navigatingFromTab: Int? = nil
    @State private var pendingTimerGameType: GameType? = nil
    @State private var didTrackAppShell = false

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
        .tint(Theme.accentColor)
        .onAppear {
            configureTabBarPresentation()
            guard !didTrackAppShell else { return }
            didTrackAppShell = true
            AppAnalytics.screenView(.appShell, screenClass: "app_shell")
            AppAnalytics.tabView(analyticsScreen(for: selectedTab))
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            configureTabBarPresentation()
            guard oldValue != newValue else { return }
            AppAnalytics.tabView(
                analyticsScreen(for: newValue),
                source: analyticsScreen(for: oldValue)
            )
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
            tabItem(tag: 0, titleKey: "tab_home", systemImage: "house.fill", screen: .homeTab) {
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
            tabItem(tag: 1, titleKey: "tab_records", systemImage: "list.bullet.clipboard.fill", screen: .recordsTab) {
                RecordsTab()
            }
            tabItem(tag: 2, titleKey: "tab_score", systemImage: "sportscourt.fill", screen: .scoreTab) {
                ScoreboardTab(selectedGame: selectedGame, onDismiss: {
                    if let source = navigatingFromTab.wrappedValue {
                        selectedTab.wrappedValue = source
                        navigatingFromTab.wrappedValue = nil
                    }
                })
            }
            tabItem(tag: 3, titleKey: "tab_timer", systemImage: "timer", screen: .timerTab) {
                TimerTab(pendingTimerGameType: pendingTimerGameType)
            }
            MeTab()
                .analyticsScreen(.meTab, screenClass: "me_tab")
                .tag(4)
                .tabItem {
                    Label(NSLocalizedString("tab_me", comment: ""), systemImage: "person.fill")
                }
        }
    }

    @ViewBuilder
    private func tabItem<Content: View>(
        tag: Int,
        titleKey: String,
        systemImage: String,
        screen: AnalyticsScreen,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            content()
                .analyticsScreen(screen, screenClass: screen.rawValue)
        }
        .tag(tag)
        .tabItem {
            Label(NSLocalizedString(titleKey, comment: ""), systemImage: systemImage)
                .accessibilityIdentifier("main_tab_\(tag)")
        }
    }

    private func analyticsScreen(for tab: Int) -> AnalyticsScreen {
        switch tab {
        case 1: return .recordsTab
        case 2: return .scoreTab
        case 3: return .timerTab
        case 4: return .meTab
        default: return .homeTab
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

            tabBarController.mode = .tabBar
            tabBarController.setTabBarHidden(false, animated: false)
            if #available(iOS 26.0, *) {
                tabBarController.tabBarMinimizeBehavior = .never
            }
        }
    }
}

#Preview {
    MainTabView()
}
