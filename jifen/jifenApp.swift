//
//  jifenApp.swift
//  jifen
//
//  Created by Yangyang Shi on 2025/12/15.
//

import SwiftUI

// Helper class for orientation lock
class OrientationLock {
    static let shared = OrientationLock()
    private var lockedOrientation: UIInterfaceOrientationMask = .all
    private var isPortraitUpdateInFlight: Bool = false
    /// Monotonic token to invalidate stale async orientation requests.
    private var requestToken: Int = 0
    
    func lock(_ orientation: UIInterfaceOrientationMask) {
        if lockedOrientation == orientation && !isPortraitUpdateInFlight {
            return
        }
        requestToken += 1
        lockedOrientation = orientation
        if orientation != .portrait {
            isPortraitUpdateInFlight = false
        }
    }
    
    func unlock() {
        if lockedOrientation == .portrait && !isPortraitUpdateInFlight {
            return
        }
        requestToken += 1
        let tokenAtRequest = requestToken
        guard !isPortraitUpdateInFlight else { return }
        isPortraitUpdateInFlight = true

        // Apply portrait unlock only if request is still current.
        DispatchQueue.main.async {
            // If lock state changed after scheduling, cancel this outdated unlock.
            guard self.requestToken == tokenAtRequest else {
                self.isPortraitUpdateInFlight = false
                return
            }
            self.lockedOrientation = .portrait
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
                ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first

            if let windowScene {
                windowScene.windows.first(where: { $0.isKeyWindow })?
                    .rootViewController?
                    .setNeedsUpdateOfSupportedInterfaceOrientations()

                if #available(iOS 16.0, *) {
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
                        #if DEBUG
                        print("[OrientationLock] Geometry update fallback due to error: \(error.localizedDescription)")
                        #endif
                        // 不再使用 UIDevice.setValue/attemptRotation（UIKit 不支持），仅重置状态，依赖 supportedInterfaceOrientations 更新后系统自动旋转
                        self.isPortraitUpdateInFlight = false
                    }
                } else {
                    self.isPortraitUpdateInFlight = false
                }
            } else {
                self.isPortraitUpdateInFlight = false
            }
        }
    }
    
    var currentOrientation: UIInterfaceOrientationMask {
        return lockedOrientation
    }
}

@main
struct jifenApp: App {
    @UIApplicationDelegateAdaptor(ScoreboardAppDelegate.self) var appDelegate

    init() {
        FontRegistrar.registerFonts()
        
        let coloredAppearance = UINavigationBarAppearance()
        coloredAppearance.configureWithOpaqueBackground()
        coloredAppearance.backgroundColor = UIColor(Theme.backgroundColor)
        coloredAppearance.titleTextAttributes = [.foregroundColor: UIColor(Theme.accentColor)]
        coloredAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.accentColor)]
        
        UINavigationBar.appearance().standardAppearance = coloredAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = coloredAppearance
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

// AppDelegate for orientation lock
class ScoreboardAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return OrientationLock.shared.currentOrientation
    }
}
