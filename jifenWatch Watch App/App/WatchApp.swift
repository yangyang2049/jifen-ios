import LinkCore
import SwiftUI

@main
struct JifenWatchApp: App {
    private let phoneLinkTransport = WatchConnectivityTransport()

    init() {
        phoneLinkTransport.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}
