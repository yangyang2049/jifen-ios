import LinkCore
import SwiftUI
import ScoreCore

struct WatchRootView: View {
    @Environment(WatchLinkService.self) private var linkService
    @State private var scoreboardRoute: WatchScoreboardRoute? = nil
    @State private var linkedSetup: LinkedScoreboardSetup?
    @State private var linkedSessionId: UUID?

    var body: some View {
        NavigationStack {
            ZStack {
                WatchTheme.background.ignoresSafeArea()
                WatchTabView(scoreboardRoute: localScoreboardRoute)
            }
            .navigationDestination(item: $scoreboardRoute) { route in
                destinationView(for: route)
            }
        }
        .accentColor(WatchTheme.accent)
        .onChange(of: linkService.requestedSetup) { _, request in
            guard let request, let route = WatchScoreboardRoute(linkedSetup: request.setup) else { return }
            linkedSetup = request.setup
            linkedSessionId = request.sessionId
            scoreboardRoute = route
            linkService.clearRequestedSetup()
        }
    }

    private func destinationView(for route: WatchScoreboardRoute) -> some View {
        Group {
            switch route {
            case .pingpong(let maxSets):
                WatchPingPongScoreView(
                    maxSets: maxSets,
                    initialState: rallyInitialState(for: route),
                    linkedSessionId: linkedSessionId(for: route)
                )
            case .badminton(let maxSets):
                WatchBadmintonScoreView(
                    maxSets: maxSets,
                    initialState: rallyInitialState(for: route),
                    linkedSessionId: linkedSessionId(for: route)
                )
            case .tennis(let maxSets):
                WatchTennisScoreView(maxSets: maxSets)
            case .pickleball(let maxSets):
                WatchPickleballScoreView(
                    maxSets: maxSets,
                    initialState: rallyInitialState(for: route),
                    linkedSessionId: linkedSessionId(for: route)
                )
            case .archery:
                WatchArcheryScoreView()
            case .basketball(let threeXThree):
                WatchBasketballScoreView(
                    gameMode: threeXThree ? .threeXThree : .fiveVFive,
                    initialState: basketballInitialState(for: route),
                    linkedSessionId: linkedSessionId(for: route)
                )
            case .basketballTraining:
                WatchBasketballTrainingView()
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var localScoreboardRoute: Binding<WatchScoreboardRoute?> {
        Binding(
            get: { scoreboardRoute },
            set: { route in
                linkedSetup = nil
                linkedSessionId = nil
                scoreboardRoute = route
            }
        )
    }

    private func basketballInitialState(for route: WatchScoreboardRoute) -> BasketballMatchState? {
        guard case .basketball(let threeXThree) = route,
              let linkedSetup,
              case .basketball(let state)? = linkedSetup.initialSnapshot else { return nil }
        switch (threeXThree, state.gameMode) {
        case (true, .threeXThree), (false, .fiveVFive):
            return state
        default:
            return nil
        }
    }

    private func rallyInitialState(for route: WatchScoreboardRoute) -> RallyMatchState? {
        guard let linkedSetup,
              case .rally(let state)? = linkedSetup.initialSnapshot else { return nil }
        switch (route, linkedSetup.gameType) {
        case (.pingpong(_), .pingpong), (.pingpong(_), .pingpongDoubles),
             (.badminton(_), .badminton), (.badminton(_), .badmintonDoubles),
             (.pickleball(_), .pickleball), (.pickleball(_), .pickleballDoubles):
            return state
        default:
            return nil
        }
    }

    private func linkedSessionId(for route: WatchScoreboardRoute) -> UUID? {
        switch route {
        case .basketball where basketballInitialState(for: route) != nil:
            return linkedSessionId
        case .pingpong, .badminton, .pickleball where rallyInitialState(for: route) != nil:
            return linkedSessionId
        default:
            return nil
        }
    }
}
