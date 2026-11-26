import SwiftUI

struct WatchTabView: View {
    @Binding var scoreboardRoute: WatchScoreboardRoute?
    let onResume: (WatchResumeSession) -> Void
    @State private var selection: Int = 1

    var body: some View {
        TabView(selection: $selection) {
            WatchToolsTabView()
                .tag(0)

            WatchHomeTabView(
                scoreboardRoute: $scoreboardRoute,
                onResume: onResume
            )
                .tag(1)

            WatchRecordListView()
                .tag(2)

            WatchSettingsView()
                .tag(3)
        }
        // 分页圆点由 TabView 自己绘制，只给四个根页签留出底部安全区
        // （46mm/49mm 模拟器实测约 6pt，各页 ScrollView 的 12pt 底内边距仍在其上）。
        // 计分板是 NavigationStack 的 destination，与 TabView 是兄弟节点，
        // 不会继承这圈留白；旧注释「留白漏进计分板」的结论在当前层级下不成立。
        .tabViewStyle(.page(indexDisplayMode: .automatic))
    }
}
