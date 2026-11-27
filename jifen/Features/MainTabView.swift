import SwiftUI
import UIKit

struct MainTabView: View {
    @Environment(SessionStore.self) private var session
    @Environment(PhoneWatchLinkService.self) private var watchLinkService: PhoneWatchLinkService?
    @Environment(WatchLinkIntroPresentation.self) private var watchLinkIntro: WatchLinkIntroPresentation?
    @Environment(\.scenePhase) private var scenePhase
    @State private var showWechatBinding = false
    @State private var showBindingLogin = false
    @State private var bindingRequested = false
    @State private var previewsWechatBindingPrompt = false
    @State private var hasOpenedBindingPreview = false
    @State private var settingsPath = NavigationPath()
    @State private var selectedTab = ProcessInfo.processInfo.arguments.contains("-UITestOpenTimer") ? 3 : 0
    @State private var selectedGame: GameType? = nil
    @State private var navigatingFromTab: Int? = nil
    @State private var pendingTimerGameType: GameType? = nil
    @State private var groupInvitation: GroupInvitation?
    @State private var groupReminders = GroupActivityReminder.shared

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
        .sheet(isPresented: watchLinkIntroBinding, onDismiss: { watchLinkIntro?.dismiss() }) {
            if let artwork = watchLinkIntro?.artwork {
                WatchLinkIntroSheet(artwork: artwork) {
                    settingsPath.append(SettingsView.Route.watchLink)
                    selectedTab = 4
                }
                .onAppear { watchLinkIntro?.sheetDidAppear() }
            }
        }
        // 兜底：下拉关闭、或 present 之后被系统收起时也复位遮罩状态，
        // 不能只依赖 onDismiss（present 失败时它根本不会回调）。
        .onChange(of: watchLinkIntro?.isPresented) { _, presented in
            guard presented != true else { return }
            watchLinkIntro?.dismiss()
        }
        .task(id: canPresentWatchLinkIntro) {
            guard canPresentWatchLinkIntro else { return }
            // Give a launch notification or deep link a chance to select its destination.
            await Task.yield()
            guard !Task.isCancelled, canPresentWatchLinkIntro else { return }
            watchLinkIntro?.present()
        }
        .sheet(isPresented: Binding(
            get: {
                guard watchLinkIntro?.reservesLaunchPresentation != true,
                      selectedTab != 4 || settingsPath.isEmpty else { return false }
                return previewsWechatBindingPrompt || (
                    session.presentsWechatUpgradePrompt && selectedGame == nil
                        && groupInvitation == nil && !VipCommunityAvailability.shared.isPresenting
                )
            },
            set: { if !$0 { dismissBindingPrompt() } }
        ), onDismiss: {
            guard bindingRequested else { return }
            bindingRequested = false
            if session.isAuthenticated { showWechatBinding = true }
            else { showBindingLogin = true }
        }) {
            WechatBindingPromptSheet(onBind: {
                bindingRequested = true
                dismissBindingPrompt()
            }, onLater: { dismissBindingPrompt() })
            .onAppear {
                if !previewsWechatBindingPrompt { session.markWechatBindingPromptPresented() }
            }
        }
        .sheet(isPresented: $showWechatBinding) { WechatBindingSheet() }
        .sheet(isPresented: $showBindingLogin) { AccountLoginSheet() }
        .onChange(of: GroupPushManager.shared.destination) { _, value in if value != nil { selectedTab = 0 } }
        .onChange(of: groupReminders.destination) { _, value in if value != nil { selectedTab = 0 } }
        .onOpenURL { url in
            if !ProductionWechatAuthProvider.shared.handle(url: url) { receiveGroupInvitation(url) }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if !ProductionWechatAuthProvider.shared.handle(activity: activity),
               let url = activity.webpageURL { receiveGroupInvitation(url) }
        }
        .onAppear {
            configureTabBarPresentation()
            #if DEBUG
            if !hasOpenedBindingPreview && ProcessInfo.processInfo.arguments.contains("-PreviewWechatBindingPrompt") {
                hasOpenedBindingPreview = true
                previewsWechatBindingPrompt = true
            }
            #endif
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            configureTabBarPresentation()
        }
    }

    private var canPresentWatchLinkIntro: Bool {
        guard let watchLinkIntro,
              watchLinkIntro.hasLaunchPriority,
              !watchLinkIntro.wasDismissed,
              !watchLinkIntro.isPresented,
              // 与微信绑定弹层同一口径：社群邀请卡在场时不再叠加介绍页。
              !VipCommunityAvailability.shared.isPresenting else { return false }
        return scenePhase == .active && selectedTab == 0 && selectedGame == nil
            && groupInvitation == nil && GroupPushManager.shared.destination == nil
            && groupReminders.destination == nil && watchLinkService?.activeSessionId == nil
    }

    private var watchLinkIntroBinding: Binding<Bool> {
        Binding(
            get: { watchLinkIntro?.isPresented == true },
            set: { watchLinkIntro?.isPresented = $0 }
        )
    }

    private var allowsWeekendMembershipPresentation: Bool {
        selectedTab == 0 && selectedGame == nil && watchLinkService?.activeSessionId == nil
            && watchLinkIntro?.reservesLaunchPresentation != true
            && !session.presentsWechatUpgradePrompt && !previewsWechatBindingPrompt
            && !bindingRequested && !showWechatBinding && !showBindingLogin
            && !VipCommunityAvailability.shared.isPresenting
    }

    private func dismissBindingPrompt() {
        previewsWechatBindingPrompt = false
        session.presentsWechatUpgradePrompt = false
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
                HomeTab(
                    onNavigateToTab: { index, game in
                        navigatingFromTab.wrappedValue = selectedTab.wrappedValue
                        selectedTab.wrappedValue = index
                        if index == 3 {
                            pendingTimerGameType.wrappedValue = game
                            selectedGame.wrappedValue = nil
                        } else {
                            pendingTimerGameType.wrappedValue = nil
                            selectedGame.wrappedValue = game
                        }
                    },
                    groupInvitation: $groupInvitation,
                    allowsWeekendMembershipPresentation: allowsWeekendMembershipPresentation
                )
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
            MeTab(path: $settingsPath)
                .appAnalyticsScreen(.meTab)
                .tag(4)
                .tabItem {
                    Label(NSLocalizedString("tab_me", comment: ""), systemImage: "person.fill")
                        .accessibilityIdentifier("main_tab_4")
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

    private func receiveGroupInvitation(_ url: URL) {
        guard let number = GroupInvitationLink.groupNumber(from: url, capabilities: GroupStore.shared.capabilities) else { return }
        selectedTab = 0
        groupInvitation = GroupInvitation(groupNo: number)
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
