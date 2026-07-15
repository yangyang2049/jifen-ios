import SwiftUI

@main
struct JifenWatchApp: App {
    @State private var linkService = WatchLinkService()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(linkService)
        }
    }
}
