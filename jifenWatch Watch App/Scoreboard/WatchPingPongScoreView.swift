import SwiftUI

struct WatchPingPongScoreView: View {
    let maxSets: Int

    var body: some View {
        WatchScoreboardView(rules: WatchPingPongRules(maxSets: maxSets))
            .navigationBarHidden(true)
    }
}
