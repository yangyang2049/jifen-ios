import SwiftUI
import ScoreCore

struct WatchRootView: View {
    @Environment(WatchLinkService.self) private var linkService
    @State private var scoreboardRoute: WatchScoreboardRoute? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                WatchTheme.background.ignoresSafeArea()
                WatchTabView(scoreboardRoute: $scoreboardRoute)
            }
            .navigationDestination(item: $scoreboardRoute) { route in
                destinationView(for: route)
            }
        }
        .accentColor(WatchTheme.accent)
        .onChange(of: linkService.requestedSetup) { _, setup in
            guard let setup, let route = WatchScoreboardRoute(linkedSetup: setup) else { return }
            scoreboardRoute = route
            linkService.clearRequestedSetup()
        }
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
            case .basketball(let threeXThree):
                WatchBasketballScoreView(gameMode: threeXThree ? .threeXThree : .fiveVFive)
            case .basketballTraining:
                WatchBasketballTrainingView()
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}
