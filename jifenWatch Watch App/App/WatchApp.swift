import SwiftUI

@main
struct JifenWatchApp: App {
    @State private var linkService = WatchLinkService()
    @State private var resumeStore = WatchResumeSessionStore.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(linkService)
                .environment(resumeStore)
        }
    }
}
