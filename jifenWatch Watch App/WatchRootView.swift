import SwiftUI
import WatchKit

struct WatchRootView: View {
    @AppStorage("watch_privacy_accepted") private var privacyAccepted: Bool = false
    @State private var scoreboardRoute: WatchScoreboardRoute? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                WatchTheme.background.ignoresSafeArea()
                if privacyAccepted {
                    WatchTabView(scoreboardRoute: $scoreboardRoute)
                } else {
                    WatchPrivacyAgreementView(onConfirm: {
                        privacyAccepted = true
                    }, onCancel: {
                        WatchAppExit.exit()
                    })
                }
            }
            .navigationDestination(item: $scoreboardRoute) { route in
                destinationView(for: route)
            }
        }
        .accentColor(WatchTheme.accent)
    }

    private func destinationView(for route: WatchScoreboardRoute) -> some View {
        Group {
            switch route {
            case .pingpong(let maxSets):
                WatchPingPongScoreView(maxSets: maxSets)
            case .badminton(let maxSets):
                WatchBadmintonScoreView(maxSets: maxSets)
            case .tennis(let maxSets):
                WatchTennisScoreView(maxSets: maxSets)
            case .pickleball(let maxSets):
                WatchPickleballScoreView(maxSets: maxSets)
            case .archery:
                WatchArcheryScoreView()
            case .basketballTraining:
                WatchBasketballTrainingView()
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}

enum WatchAppExit {
    static func exit() {
        // watchOS has no public API to terminate apps; best-effort dismiss if available.
        WKExtension.shared().rootInterfaceController?.dismiss()
    }
}
