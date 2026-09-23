import SwiftUI
import UIKit

struct MainTabView: View {
    @State private var selectedTab = ProcessInfo.processInfo.arguments.contains("-UITestOpenTimer") ? 3 : 0
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
        .tint(Theme.accentColor)
        .onAppear {
            configureTabBarPresentation()
        }
        .onChange(of: selectedTab) { oldValue, newValue in
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
                .appAnalyticsScreen(.meTab)
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
        // 每个 Tab 内容自己持有 NavigationStack（RecordsTab.swift / TimerTab.swift / ScoreboardTab.swift / HomeTab.swift），
        // 这里不再包栈：双 NavigationStack 会让 toolbar 状态冒泡路径变长，且历史上出过导航异常。
        content()
            .appAnalyticsScreen(screen)
            .tag(tag)
            .tabItem {
                Label(NSLocalizedString(titleKey, comment: ""), systemImage: systemImage)
                    .accessibilityIdentifier("main_tab_\(tag)")
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

            if #available(iOS 26.0, *) {
                tabBarController.tabBarMinimizeBehavior = .never
            }
        }
    }
}

#Preview {
    MainTabView()
}
