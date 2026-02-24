import SwiftUI

private enum WatchHomeItem: String, CaseIterable {
    case badminton
    case tennis
    case pingpong
    case pickleball
    case archery
    case basketball_training
}

struct WatchHomeTabView: View {
    @Binding var scoreboardRoute: WatchScoreboardRoute?
    @State private var pingpongSets: Int = 5
    @State private var tennisSets: Int = 3
    @State private var showPingpongPicker: Bool = false
    @State private var showTennisPicker: Bool = false
    @State private var showPickleballPicker: Bool = false
    @State private var pickleballSets: Int = 3
    @State private var orderedItems: [WatchHomeItem] = WatchHomeItem.allCases

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(orderedItems, id: \.rawValue) { item in
                    switch item {
                    case .badminton:
                        WatchPillButton(icon: "🏸", title: NSLocalizedString("game_badminton", comment: "Badminton")) {
                            saveLastSelected(item)
                            navigateToBadminton()
                        }
                    case .tennis:
                        WatchPillButton(icon: "🎾", title: NSLocalizedString("game_tennis", comment: "Tennis")) {
                            saveLastSelected(item)
                            showTennisPicker = true
                        }
                    case .pingpong:
                        WatchPillButton(icon: "🏓", title: NSLocalizedString("game_pingpong", comment: "Ping Pong")) {
                            saveLastSelected(item)
                            showPingpongPicker = true
                        }
                    case .pickleball:
                        WatchPillButton(icon: "🎾", title: NSLocalizedString("game_pickleball", comment: "Pickleball")) {
                            saveLastSelected(item)
                            showPickleballPicker = true
                        }
                    case .archery:
                        WatchPillButton(icon: "🏹", title: NSLocalizedString("game_archery", comment: "Archery")) {
                            saveLastSelected(item)
                            navigateToArchery()
                        }
                    case .basketball_training:
                        WatchPillButton(icon: "🏀", title: NSLocalizedString("tool_basketball_training", comment: "Basketball Training")) {
                            saveLastSelected(item)
                            navigateToBasketballTraining()
                        }
                    }
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
        .confirmationDialog(NSLocalizedString("pickleball_sets", comment: "Pickleball Sets"), isPresented: $showPickleballPicker) {
            Button(NSLocalizedString("best_of_3_sets", comment: "Best of 3")) { pickleballSets = 3; navigateToPickleball() }
            Button(NSLocalizedString("best_of_5_sets", comment: "Best of 5")) { pickleballSets = 5; navigateToPickleball() }
            Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) { }
        }
        .onAppear {
            updateOrderedItems()
        }
    }

    private func saveLastSelected(_ item: WatchHomeItem) {
        WatchPreferences.shared.setString(item.rawValue, forKey: "watchLastSelectedGame")
        updateOrderedItems()
    }

    private func updateOrderedItems() {
        let last = WatchPreferences.shared.string(forKey: "watchLastSelectedGame", defaultValue: "")
        guard let lastItem = WatchHomeItem(rawValue: last), lastItem != .badminton else {
            orderedItems = WatchHomeItem.allCases
            return
        }
        var items = WatchHomeItem.allCases
        if let idx = items.firstIndex(of: lastItem), idx > 0 {
            items.remove(at: idx)
            items.insert(lastItem, at: 0)
        }
        orderedItems = items
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

    private func navigateToPickleball() {
        showPickleballPicker = false
        DispatchQueue.main.async {
            scoreboardRoute = .pickleball(maxSets: pickleballSets)
        }
    }

    private func navigateToArchery() {
        DispatchQueue.main.async {
            scoreboardRoute = .archery
        }
    }

    private func navigateToBasketballTraining() {
        DispatchQueue.main.async {
            scoreboardRoute = .basketballTraining
        }
    }
}
