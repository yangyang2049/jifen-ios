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
                WatchPillButton(icon: "🏸", title: "羽毛球") {
                    navigateToBadminton()
                }

                WatchPillButton(icon: "🏓", title: "乒乓球") {
                    showPingpongPicker = true
                }

                WatchPillButton(icon: "🎾", title: "网球") {
                    showTennisPicker = true
                }

                NavigationLink(destination: WatchRecordListView()) {
                    WatchPillRow(icon: "📝", title: "战绩")
                }
                .buttonStyle(.plain)

                WatchPillButton(icon: "ℹ️", title: "使用说明") {
                    showUsagePromptOnce(force: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(WatchTheme.background)
        .navigationTitle("计分")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("乒乓球局数", isPresented: $showPingpongPicker) {
            Button("三局两胜") { pingpongSets = 3; navigateToPingpong() }
            Button("五局三胜") { pingpongSets = 5; navigateToPingpong() }
            Button("七局四胜") { pingpongSets = 7; navigateToPingpong() }
            Button("取消", role: .cancel) { }
        }
        .confirmationDialog("网球盘数", isPresented: $showTennisPicker) {
            Button("一盘") { tennisSets = 1; navigateToTennis() }
            Button("三盘两胜") { tennisSets = 3; navigateToTennis() }
            Button("五盘三胜") { tennisSets = 5; navigateToTennis() }
            Button("取消", role: .cancel) { }
        }
        .alert("使用说明", isPresented: $showUsageAlert) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text("👆 上下半屏点击加分\n👇 下滑撤销上一分\n上滑打开菜单\n🏁 暂停可保存记录")
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
