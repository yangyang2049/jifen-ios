//
//  ContentView.swift
//  jifen
//
//  Created by Yangyang Shi on 2025/12/15.
//

import SwiftUI

struct ContentView: View {
    @State private var showLocalSync = false
    @State private var deepLinkJoinCode: String?

    var body: some View {
        MainTabView()
            .onOpenURL { url in
                guard let code = LocalSyncView.joinCode(from: url.absoluteString) else { return }
                deepLinkJoinCode = code
                showLocalSync = true
            }
            .sheet(isPresented: $showLocalSync) {
                LocalSyncView(initialJoinCode: deepLinkJoinCode)
            }
    }
}

#Preview {
    ContentView()
}
