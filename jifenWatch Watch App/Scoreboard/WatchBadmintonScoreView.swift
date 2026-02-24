import SwiftUI

struct WatchBadmintonScoreView: View {
    let maxSets: Int

    var body: some View {
        WatchScoreboardView(rules: WatchBadmintonRules(maxSets: maxSets))
    }
}
