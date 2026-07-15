import ScoreCore
import SwiftUI

struct WatchBadmintonScoreView: View {
    let maxSets: Int

    var body: some View {
        WatchRallyScoreView(gameType: .badminton, rules: .badminton(maxSets: maxSets))
    }
}
