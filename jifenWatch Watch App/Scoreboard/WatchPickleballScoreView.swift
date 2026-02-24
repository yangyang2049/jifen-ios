//
//  WatchPickleballScoreView.swift
//  jifenWatch Watch App
//

import SwiftUI

struct WatchPickleballScoreView: View {
    let maxSets: Int

    var body: some View {
        WatchScoreboardView(rules: WatchPickleballRules(maxSets: maxSets))
            .navigationBarHidden(true)
    }
}
