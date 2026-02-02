import SwiftUI

struct WatchHomeTabView: View {
    @Binding var scoreboardRoute: WatchScoreboardRoute?
    @State private var pingpongSets: Int = 5
    @State private var tennisSets: Int = 3
    @State private var showPingpongPicker: Bool = false
    @State private var showTennisPicker: Bool = false
    @State private var showUsageAlert: Bool = false
    @State private var usagePromptShown: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                WatchPillButton(icon: "🏸", title: NSLocalizedString("game_badminton", comment: "Badminton")) {
                    navigateToBadminton()
                }

                WatchPillButton(icon: "🎾", title: NSLocalizedString("game_tennis", comment: "Tennis")) {
                    showTennisPicker = true
                }

                WatchPillButton(icon: "🏓", title: NSLocalizedString("game_pingpong", comment: "Ping Pong")) {
                    showPingpongPicker = true
                }

                WatchPillButton(icon: "ℹ️", title: NSLocalizedString("usage_guide", comment: "Usage Guide")) {
                    showUsagePromptOnce(force: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(WatchTheme.background)
        .navigationTitle(NSLocalizedString("tab_score", comment: "Score"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(NSLocalizedString("pingpong_sets", comment: "Ping Pong Sets"), isPresented: $showPingpongPicker) {
            Button(NSLocalizedString("best_of_3_sets", comment: "Best of 3")) { pingpongSets = 3; navigateToPingpong() }
            Button(NSLocalizedString("best_of_5_sets", comment: "Best of 5")) { pingpongSets = 5; navigateToPingpong() }
            Button(NSLocalizedString("best_of_7_sets", comment: "Best of 7")) { pingpongSets = 7; navigateToPingpong() }
            Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) { }
        }
        .confirmationDialog(NSLocalizedString("tennis_sets", comment: "Tennis Sets"), isPresented: $showTennisPicker) {
            Button(NSLocalizedString("sets_1", comment: "1 set")) { tennisSets = 1; navigateToTennis() }
            Button(NSLocalizedString("sets_3_best_of_2", comment: "Best of 3")) { tennisSets = 3; navigateToTennis() }
            Button(NSLocalizedString("sets_5_best_of_3", comment: "Best of 5")) { tennisSets = 5; navigateToTennis() }
            Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) { }
        }
        .alert(NSLocalizedString("usage_guide", comment: "Usage Guide"), isPresented: $showUsageAlert) {
            Button(NSLocalizedString("got_it", comment: "Got it"), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("usage_prompt_message", comment: "Usage prompt message"))
        }
        .onAppear {
            usagePromptShown = WatchPreferences.shared.bool(forKey: "watch_usage_prompt_shown", defaultValue: false)
            showUsagePromptOnce()
        }
    }

    private func showUsagePromptOnce(force: Bool = false) {
        if usagePromptShown && !force { return }
        showUsageAlert = true
        WatchPreferences.shared.setBool(true, forKey: "watch_usage_prompt_shown")
        usagePromptShown = true
    }

    private func navigateToPingpong() {
        showPingpongPicker = false
        DispatchQueue.main.async {
            scoreboardRoute = .pingpong(maxSets: pingpongSets)
        }
    }

    private func navigateToBadminton() {
        DispatchQueue.main.async {
            scoreboardRoute = .badminton(maxSets: 3)
        }
    }

    private func navigateToTennis() {
        showTennisPicker = false
        DispatchQueue.main.async {
            scoreboardRoute = .tennis(maxSets: tennisSets)
        }
    }
}
