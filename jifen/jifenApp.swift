//
//  jifenApp.swift
//  jifen
//
//  Created by Yangyang Shi on 2025/12/15.
//

import FirebaseCore
import SwiftUI
import UserNotifications

enum ScoreboardOrientationPolicy {
    /// Phones keep each scoreboard's requested orientation. iPad follows the
    /// physical device unless the user has explicitly enabled forced landscape.
    static func requestedOrientation(
        _ requestedOrientation: UIInterfaceOrientationMask,
        usesPadLayout: Bool,
        forceIPadLandscape: Bool
    ) -> UIInterfaceOrientationMask? {
        guard usesPadLayout else { return requestedOrientation }
        return forceIPadLandscape ? .landscape : nil
    }

    static func shouldShowIPadLandscapeHint(
        usesPadLayout: Bool,
        forceIPadLandscape: Bool,
        hasShownHint: Bool,
        interfaceOrientation: UIInterfaceOrientation?
    ) -> Bool {
        usesPadLayout
            && !forceIPadLandscape
            && !hasShownHint
            && interfaceOrientation?.isPortrait == true
    }
}

// Helper class for orientation lock
class OrientationLock {
    private struct ScoreboardOrientationRequest {
        let orientation: UIInterfaceOrientationMask?
        let sequence: UInt64
    }

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
    /// A geometry request has no success callback. Keep its target until the
    /// policy changes so duplicate lifecycle callbacks cannot issue the same
    /// request while the first rotation is still being applied.
    private var pendingGeometryOrientation: UIInterfaceOrientationMask?
    private var scoreboardOrientationRequests: [UUID: ScoreboardOrientationRequest] = [:]
    private var scoreboardRequestSequence: UInt64 = 0
    private var scoreboardRestoreGeneration: UInt64 = 0
    private var scoreboardOwnerGraceDeadline: CFTimeInterval?
    private var isPreparingScoreboardExit = false

    func beginScoreboardOrientation(
        ownerID: UUID,
        orientation: UIInterfaceOrientationMask?
    ) {
        performOnMain { [weak self] in
            guard let self else { return }
            self.scoreboardRestoreGeneration &+= 1
            self.scoreboardOwnerGraceDeadline = nil
            if self.scoreboardOrientationRequests.isEmpty {
                self.isPreparingScoreboardExit = false
            }
            self.scoreboardRequestSequence &+= 1
            self.scoreboardOrientationRequests[ownerID] = ScoreboardOrientationRequest(
                orientation: orientation,
                sequence: self.scoreboardRequestSequence
            )
            if let orientation,
               self.activeWindowScene.map({
                   !Self.interfaceOrientation($0.effectiveGeometry.interfaceOrientation, isAllowedBy: orientation)
               }) == true {
                // NavigationStack republishes the outgoing page's portrait mask
                // during its transition. Claim ownership now, but rotate only
                // after that transient preference has disappeared.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    guard let self,
                          self.scoreboardOrientationRequests[ownerID] != nil else {
                        return
                    }
                    self.applyActiveScoreboardOrientation()
                }
            } else {
                self.applyActiveScoreboardOrientation()
            }
        }
    }

    func updateScoreboardOrientation(
        ownerID: UUID,
        orientation: UIInterfaceOrientationMask?
    ) {
        performOnMain { [weak self] in
            guard let self, self.scoreboardOrientationRequests[ownerID] != nil else { return }
            self.scoreboardRequestSequence &+= 1
            self.scoreboardOrientationRequests[ownerID] = ScoreboardOrientationRequest(
                orientation: orientation,
                sequence: self.scoreboardRequestSequence
            )
            self.applyActiveScoreboardOrientation()
        }
    }

    func endScoreboardOrientation(ownerID: UUID) {
        performOnMain { [weak self] in
            guard let self, self.scoreboardOrientationRequests.removeValue(forKey: ownerID) != nil else {
                return
            }
            if self.scoreboardOrientationRequests.isEmpty {
                if self.isPreparingScoreboardExit {
                    self.isPreparingScoreboardExit = false
                    self.scoreboardOwnerGraceDeadline = nil
                    let target = OrientationLock.defaultOrientation
                    self.apply(target, requestsGeometryUpdate: target == .portrait)
                } else {
                    self.deferNormalOrientationRestoreAfterOwnerTransition()
                }
            } else {
                self.applyActiveScoreboardOrientation()
            }
        }
    }
    
    func lock(_ orientation: UIInterfaceOrientationMask) {
        performOnMain { [weak self] in
            self?.apply(orientation, requestsGeometryUpdate: false)
        }
    }

    /// Locks to the given orientation and proactively requests scene geometry.
    func rotate(to orientation: UIInterfaceOrientationMask) {
        performOnMain { [weak self] in
            self?.apply(orientation, requestsGeometryUpdate: true)
        }
    }
    
    func unlock() {
        performOnMain { [weak self] in
            guard let self else { return }
            guard self.scoreboardOrientationRequests.isEmpty || self.isPreparingScoreboardExit else {
                return
            }
            if let deadline = self.scoreboardOwnerGraceDeadline,
               CACurrentMediaTime() < deadline {
                return
            }
            let target = OrientationLock.defaultOrientation
            self.apply(target, requestsGeometryUpdate: target == .portrait)
        }
    }

    /// Ends text input, restores the normal-page orientation, and waits for the
    /// compact-phone rotation to settle before allowing NavigationStack to pop.
    /// This keeps keyboard, scene and TabBar safe-area updates out of one frame.
    func unlockBeforeScoreboardExit(then completion: @escaping () -> Void) {
        performOnMain { [weak self] in
            guard let self else {
                completion()
                return
            }
            let target = OrientationLock.defaultOrientation
            let scene = self.activeWindowScene
            let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
            let hadActiveTextInput = window?.containsFirstResponder == true
            window?.endEditing(true)

            self.scoreboardRestoreGeneration &+= 1
            self.scoreboardOwnerGraceDeadline = nil
            self.isPreparingScoreboardExit = !self.scoreboardOrientationRequests.isEmpty
            let needsRotation = target == .portrait
                && scene.map {
                    !Self.interfaceOrientation($0.effectiveGeometry.interfaceOrientation, isAllowedBy: target)
                } == true
            self.apply(target, requestsGeometryUpdate: target == .portrait, in: scene)
            self.finishExitWhenLayoutSettles(
                scene: scene,
                target: target,
                needsRotation: needsRotation,
                hadActiveTextInput: hadActiveTextInput,
                startedAt: CACurrentMediaTime(),
                completion: completion
            )
        }
    }

    private func applyActiveScoreboardOrientation() {
        guard !isPreparingScoreboardExit else { return }
        let latestRequest = scoreboardOrientationRequests.values.max {
            $0.sequence < $1.sequence
        }
        if let orientation = latestRequest?.orientation {
            apply(orientation, requestsGeometryUpdate: true)
        } else {
            let target = OrientationLock.defaultOrientation
            apply(target, requestsGeometryUpdate: target == .portrait)
        }
    }

    /// SwiftUI can briefly tear down and rebuild a destination when its setup
    /// binding is consumed. Keep the scoreboard's orientation through that
    /// lifecycle gap; explicit exits bypass this grace period above.
    private func deferNormalOrientationRestoreAfterOwnerTransition() {
        scoreboardRestoreGeneration &+= 1
        let generation = scoreboardRestoreGeneration
        let delay: CFTimeInterval = 0.25
        scoreboardOwnerGraceDeadline = CACurrentMediaTime() + delay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  self.scoreboardRestoreGeneration == generation,
                  self.scoreboardOrientationRequests.isEmpty,
                  !self.isPreparingScoreboardExit else {
                return
            }
            self.scoreboardOwnerGraceDeadline = nil
            let target = OrientationLock.defaultOrientation
            self.apply(target, requestsGeometryUpdate: target == .portrait)
        }
    }

    private func apply(
        _ orientation: UIInterfaceOrientationMask,
        requestsGeometryUpdate: Bool,
        in suppliedScene: UIWindowScene? = nil
    ) {
        let policyChanged = lockedOrientation != orientation
        if policyChanged {
            lockedOrientation = orientation
            pendingGeometryOrientation = nil
        }

        guard policyChanged || requestsGeometryUpdate else { return }
        guard let windowScene = suppliedScene ?? activeWindowScene else { return }
        let rootViewController = (windowScene.windows.first(where: { $0.isKeyWindow })
            ?? windowScene.windows.first)?.rootViewController

        guard requestsGeometryUpdate else {
            rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            return
        }
        if Self.interfaceOrientation(
            windowScene.effectiveGeometry.interfaceOrientation,
            isAllowedBy: orientation
        ) {
            pendingGeometryOrientation = nil
            rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            return
        }
        guard pendingGeometryOrientation != orientation else { return }
        pendingGeometryOrientation = orientation
        // NavigationStack briefly republishes its outgoing controller's mask
        // while installing a destination. Publish the new mask only after that
        // handoff, then request geometry; otherwise iOS 26 can start rotating,
        // see the outgoing mask, snap back, then rotate again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self, weak windowScene] in
            guard let self,
                  let windowScene,
                  self.pendingGeometryOrientation == orientation,
                  self.lockedOrientation == orientation else {
                return
            }
            (windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first)?
                .rootViewController?
                .setNeedsUpdateOfSupportedInterfaceOrientations()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self, weak windowScene] in
                guard let self,
                      let windowScene,
                      self.pendingGeometryOrientation == orientation,
                      self.lockedOrientation == orientation else {
                    return
                }
                if Self.interfaceOrientation(
                    windowScene.effectiveGeometry.interfaceOrientation,
                    isAllowedBy: orientation
                ) {
                    self.pendingGeometryOrientation = nil
                    return
                }
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { [weak self] error in
                    DispatchQueue.main.async {
                        if self?.pendingGeometryOrientation == orientation {
                            self?.pendingGeometryOrientation = nil
                        }
                        #if DEBUG
                        print("[OrientationLock] Geometry update failed: \(error.localizedDescription)")
                        #endif
                    }
                }
            }
        }
    }

    private func finishExitWhenLayoutSettles(
        scene: UIWindowScene?,
        target: UIInterfaceOrientationMask,
        needsRotation: Bool,
        hadActiveTextInput: Bool,
        startedAt: CFTimeInterval,
        completion: @escaping () -> Void
    ) {
        let elapsed = CACurrentMediaTime() - startedAt
        let minimumSettleTime: CFTimeInterval = hadActiveTextInput ? 0.30 : (needsRotation ? 0.25 : 0)
        let orientationIsReady = scene.map {
            Self.interfaceOrientation($0.effectiveGeometry.interfaceOrientation, isAllowedBy: target)
        } ?? true

        if (orientationIsReady && elapsed >= minimumSettleTime) || elapsed >= 0.8 {
            // Give SwiftUI one final layout pass before the destination is removed.
            DispatchQueue.main.async(execute: completion)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.finishExitWhenLayoutSettles(
                scene: scene,
                target: target,
                needsRotation: needsRotation,
                hadActiveTextInput: hadActiveTextInput,
                startedAt: startedAt,
                completion: completion
            )
        }
    }

    private func performOnMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }

    static func interfaceOrientation(
        _ interfaceOrientation: UIInterfaceOrientation,
        isAllowedBy mask: UIInterfaceOrientationMask
    ) -> Bool {
        switch interfaceOrientation {
        case .portrait: return mask.contains(.portrait)
        case .portraitUpsideDown: return mask.contains(.portraitUpsideDown)
        case .landscapeLeft: return mask.contains(.landscapeLeft)
        case .landscapeRight: return mask.contains(.landscapeRight)
        case .unknown: return true
        @unknown default: return true
        }
    }

    private var activeWindowScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first {
            $0.activationState == .foregroundActive
                && $0.windows.contains(where: { $0.isKeyWindow })
        } ?? scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first
    }

    var currentInterfaceOrientation: UIInterfaceOrientation? {
        activeWindowScene?.effectiveGeometry.interfaceOrientation
    }
    
    var currentOrientation: UIInterfaceOrientationMask {
        return lockedOrientation
    }
}

private extension UIView {
    var containsFirstResponder: Bool {
        if isFirstResponder { return true }
        return subviews.contains(where: \.containsFirstResponder)
    }
}

@main
struct jifenApp: App {
    @UIApplicationDelegateAdaptor(ScoreboardAppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var appearance = AppAppearanceStore()
    @State private var sessionStore = SessionStore.shared
    @State private var hasAcceptedLegal: Bool
    @State private var showPersistenceFailure = false
    @StateObject private var screenshotSaveCoordinator = ScreenshotSaveCoordinator.shared

    init() {
        FontRegistrar.registerFonts()
        UITestRecordFixtures.installIfRequested()
        #if DEBUG
        PreferencesManager.shared.resetIPadOrientationPreferencesForUITestsIfRequested()
        #endif
        AppReviewPrompt.recordLaunchIfAllowed()
        // v1 intentionally does NOT present the First Launch Legal Screen (code removed).
        // Consent is treated as implicitly accepted at launch (same effect as tapping "同意")
        // so analytics/session flow run.
        let hadAcceptedLegal = LegalConsent.hasAcceptedCurrentDocuments()
        PreferencesManager.shared.migrateLegacyDoubleTapSubtractIfNeeded(
            hasLegalConsent: hadAcceptedLegal
        )
        if !hadAcceptedLegal {
            LegalConsent.acceptCurrentDocuments()
        }
        _hasAcceptedLegal = State(initialValue: true)
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                rootView
                ScreenshotSaveOverlay(coordinator: screenshotSaveCoordinator)
                    .zIndex(10_000)
            }
            .environment(appearance)
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
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task {
                    await StoreKitPurchaseManager.shared.refreshLocalEntitlement()
                }
            }
            .alert(
                NSLocalizedString("save_failed", value: "保存失败", comment: ""),
                isPresented: $showPersistenceFailure
            ) {
                Button(NSLocalizedString("confirm", value: "确定", comment: ""), role: .cancel) { }
            } message: {
                Text(NSLocalizedString("scoreboard_save_failed", value: "保存失败，请稍后重试", comment: ""))
            }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let fixtureName = DisplaySnapshotFixture.requestedName {
            DisplaySnapshotFixtureView(name: fixtureName)
        } else if let index = arguments.firstIndex(of: "-UITestRecordDetail"),
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
        FirebaseApp.configure()
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
                let wasAuthenticated = SessionStore.shared.isAuthenticated
                await SessionStore.shared.restore()
                // restore() runs the purchase sync during its own post-login warmup.
                if wasAuthenticated && SessionStore.shared.isAuthenticated {
                    await StoreKitPurchaseManager.shared.sessionDidAuthenticate()
                }
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
