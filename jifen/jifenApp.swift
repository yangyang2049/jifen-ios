//
//  jifenApp.swift
//  jifen
//
//  Created by Yangyang Shi on 2025/12/15.
//

import SwiftUI
import UserNotifications

// Helper class for orientation lock
class OrientationLock {
    static let shared = OrientationLock()
    /// Mirrors Android/HarmonyOS normal-page policy: phones return to portrait,
    /// while iPad keeps following the device orientation.
    static func defaultOrientation(for idiom: UIUserInterfaceIdiom) -> UIInterfaceOrientationMask {
        idiom == .pad ? .all : .portrait
    }

    private static var defaultOrientation: UIInterfaceOrientationMask {
        defaultOrientation(for: UIDevice.current.userInterfaceIdiom)
    }

    private var lockedOrientation: UIInterfaceOrientationMask = OrientationLock.defaultOrientation
    /// Monotonic token to invalidate stale async orientation requests.
    private var requestToken: Int = 0
    
    func lock(_ orientation: UIInterfaceOrientationMask) {
        guard lockedOrientation != orientation else { return }
        requestToken += 1
        lockedOrientation = orientation
        updateSupportedInterfaceOrientations()
    }

    /// Locks to the given orientation AND proactively requests a geometry
    /// update so the device actually rotates (mirrors DateTimeToolView).
    func rotate(to orientation: UIInterfaceOrientationMask) {
        lock(orientation)
        guard let windowScene = activeWindowScene else { return }
        windowScene.windows.first(where: \.isKeyWindow)?
            .rootViewController?
            .setNeedsUpdateOfSupportedInterfaceOrientations()
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { error in
            #if DEBUG
            print("[OrientationLock] Geometry update failed: \(error.localizedDescription)")
            #endif
        }
    }
    
    func unlock() {
        let defaultOrientation = OrientationLock.defaultOrientation
        requestToken += 1
        let tokenAtRequest = requestToken
        lockedOrientation = defaultOrientation

        // Always refresh UIKit here, even when the stored mask already equals
        // the default. A previous scene geometry request may have left UIKit's
        // supported-orientation cache narrower than this value.
        DispatchQueue.main.async {
            guard self.requestToken == tokenAtRequest else { return }
            let windowScene = self.activeWindowScene

            if let windowScene {
                windowScene.windows.first(where: { $0.isKeyWindow })?
                    .rootViewController?
                    .setNeedsUpdateOfSupportedInterfaceOrientations()

                if defaultOrientation == .portrait {
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
                        #if DEBUG
                        print("[OrientationLock] Geometry update fallback due to error: \(error.localizedDescription)")
                        #endif
                    }
                }
            }
        }
    }

    private func updateSupportedInterfaceOrientations() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.activeWindowScene?.windows.first(where: { $0.isKeyWindow })?
                .rootViewController?
                .setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    private var activeWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }
    
    var currentOrientation: UIInterfaceOrientationMask {
        return lockedOrientation
    }
}

@main
struct jifenApp: App {
    @UIApplicationDelegateAdaptor(ScoreboardAppDelegate.self) var appDelegate
    @State private var appearance = AppAppearanceStore()
    @State private var watchLinkService = PhoneWatchLinkService()
    @State private var sessionStore = SessionStore.shared
    @State private var hasAcceptedLegal: Bool
    @State private var showPersistenceFailure = false
    @StateObject private var screenshotSaveCoordinator = ScreenshotSaveCoordinator.shared

    init() {
        FontRegistrar.registerFonts()
        UITestRecordFixtures.installIfRequested()
        AppReviewPrompt.recordLaunchIfAllowed()
        // v1 intentionally does NOT present the First Launch Legal Screen (code removed).
        // Consent is treated as implicitly accepted at launch (same effect as tapping "同意")
        // so analytics/session flow run.
        let hadAcceptedLegal = LegalConsent.hasAcceptedCurrentDocuments()
        if !hadAcceptedLegal {
            LegalConsent.acceptCurrentDocuments()
        }
        PreferencesManager.shared.migrateLegacyDoubleTapSubtractIfNeeded(hasLegalConsent: true)
        _hasAcceptedLegal = State(initialValue: true)
        UmengAnalytics.initializeIfConsented()
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                rootView
                ScreenshotSaveOverlay(coordinator: screenshotSaveCoordinator)
                    .zIndex(10_000)
            }
            .environment(appearance)
            .environment(watchLinkService)
            .environment(sessionStore)
            .preferredColorScheme(appearance.mode.preferredColorScheme)
            .task(id: hasAcceptedLegal) {
                guard hasAcceptedLegal || shouldSkipLegalForUITests else { return }
                guard AppFeatureFlags.accountFeaturesEnabled else { return }
                await sessionStore.restore()
            }
            .onReceive(NotificationCenter.default.publisher(for: .scoreboardPersistenceFailed)) { _ in
                showPersistenceFailure = true
            }
            .alert(
                NSLocalizedString("save_failed", value: "保存失败", comment: ""),
                isPresented: $showPersistenceFailure
            ) {
                Button(NSLocalizedString("confirm", value: "确定", comment: ""), role: .cancel) { }
            } message: {
                Text(NSLocalizedString("scoreboard_save_failed", value: "保存失败，请稍后重试", comment: ""))
            }
            .alert(
                NSLocalizedString("linked_score_force_takeover", value: "强制接管", comment: ""),
                isPresented: Binding(
                    get: { watchLinkService.forceTakeoverConfirmationSessionId != nil },
                    set: { if !$0 { watchLinkService.cancelForceTakeoverConfirmation() } }
                )
            ) {
                Button(
                    NSLocalizedString("cancel", value: "取消", comment: ""),
                    role: .cancel
                ) {
                    watchLinkService.cancelForceTakeoverConfirmation()
                }
                Button(
                    NSLocalizedString("linked_score_force_takeover_confirm", value: "仍要接管", comment: ""),
                    role: .destructive
                ) {
                    watchLinkService.confirmForceTakeover()
                }
            } message: {
                Text(NSLocalizedString(
                    "linked_score_force_takeover_warning",
                    value: "未同步的手表操作可能丢失。手机会基于最后一次已确认的比分继续。",
                    comment: ""
                ))
            }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-UITestRecordDetail"),
           arguments.indices.contains(index + 1) {
            NavigationStack {
                ScoreboardRecordDetailPage(recordId: "ui-fixture-\(arguments[index + 1])")
            }
        } else {
            legalGatedContent
        }
        #else
        legalGatedContent
        #endif
    }

    @ViewBuilder
    private var legalGatedContent: some View {
        // v1: the First Launch Legal Screen is intentionally not shown (see init).
        // Re-add the consent gate below if App Store review later requires it.
        ContentView()
            .requestsReviewOnEligibleLaunch()
    }

    private var shouldSkipLegalForUITests: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITestSkipLegalConsent")
        #else
        false
        #endif
    }
}

// AppDelegate for orientation lock
class ScoreboardAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return OrientationLock.shared.currentOrientation
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Task { @MainActor in
            ScoreboardDisplayOutputs.shared.setControllerAway(true)
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        Task { @MainActor in
            ScoreboardDisplayOutputs.shared.setControllerAway(false)
            ExternalDisplayCoordinator.shared.refreshStatus()
            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
            let permitsBackendAccess = LegalConsent.hasAcceptedCurrentDocuments()
                || Self.shouldSkipLegalForUITests
            if permitsBackendAccess, AppFeatureFlags.accountFeaturesEnabled {
                await SessionStore.shared.restore()
                if AppFeatureFlags.commonDataCloudSyncEnabled {
                    CommonDataCloudSyncManager.shared.appBecameActive()
                }
            }
        }
    }

    private static var shouldSkipLegalForUITests: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITestSkipLegalConsent")
        #else
        false
        #endif
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.content.userInfo["bookingId"] != nil {
            AppAnalytics.track(.notificationOpen, parameters: [
                .contentType: .string("booking_reminder"),
                .entryPoint: .string(AnalyticsEntryPoint.bookingNotification.rawValue),
                .actionName: .string("open")
            ])
        }
        completionHandler()
    }
}
