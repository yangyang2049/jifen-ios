import ScoreCore
import SwiftUI

struct WatchPingPongScoreView: View {
    let maxSets: Int

    var body: some View {
        WatchRallyScoreView(gameType: .pingpong, rules: .pingPong(maxSets: maxSets))
    }
}
