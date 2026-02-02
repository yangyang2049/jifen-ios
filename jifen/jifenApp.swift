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
    
    func lock(_ orientation: UIInterfaceOrientationMask) {
        lockedOrientation = orientation
    }
    
    func unlock() {
        lockedOrientation = .portrait
        // Force return to portrait when unlocking
        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                if #available(iOS 16.0, *) {
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
                        #if DEBUG
                        print("[OrientationLock] Geometry update result: \(error)")
                        #endif
                    }
                } else {
                    // Fallback for iOS 15 and earlier
                    UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
                }
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
