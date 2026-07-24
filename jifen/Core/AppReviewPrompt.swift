import Foundation
import StoreKit
import SwiftUI

enum AppReviewPrompt {
    /// Change this Info.plist value to tune the number of cold launches before
    /// requesting a review. Set it to 0 to disable the automatic request.
    static let launchThresholdInfoPlistKey = "JifenReviewPromptLaunchThreshold"
    static let defaultLaunchThreshold = 5

    private static let launchCountDefaultsKey = "app_review_launch_count"
    private static let requestAttemptedDefaultsKey = "app_review_request_attempted"

    static var configuredLaunchThreshold: Int {
        if let number = Bundle.main.object(
            forInfoDictionaryKey: launchThresholdInfoPlistKey
        ) as? NSNumber {
            return number.intValue
        }
        if let string = Bundle.main.object(
            forInfoDictionaryKey: launchThresholdInfoPlistKey
        ) as? String,
           let value = Int(string) {
            return value
        }
        return defaultLaunchThreshold
    }

    /// Records one cold app launch. Foreground transitions do not call this.
    static func recordLaunch(defaults: UserDefaults = .standard) {
        let currentCount = max(0, defaults.integer(forKey: launchCountDefaultsKey))
        let nextCount = currentCount == Int.max ? currentCount : currentCount + 1
        defaults.set(nextCount, forKey: launchCountDefaultsKey)
    }

    static func recordLaunchIfAllowed(defaults: UserDefaults = .standard) {
        guard !isAutomationProcess else { return }
        recordLaunch(defaults: defaults)
    }

    /// Atomically consumes the one-time review request once the launch
    /// threshold has been reached.
    static func consumePendingRequest(
        defaults: UserDefaults = .standard,
        launchThreshold: Int? = nil
    ) -> Bool {
        let threshold = launchThreshold ?? configuredLaunchThreshold
        guard threshold > 0,
              defaults.integer(forKey: launchCountDefaultsKey) >= threshold,
              !defaults.bool(forKey: requestAttemptedDefaultsKey) else {
            return false
        }

        // Store the attempt before calling StoreKit because Apple intentionally
        // does not report whether the system prompt was actually displayed.
        defaults.set(true, forKey: requestAttemptedDefaultsKey)
        return true
    }

    static func consumePendingRequestIfAllowed(
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard !isAutomationProcess else { return false }
        return consumePendingRequest(defaults: defaults)
    }

    private static var isAutomationProcess: Bool {
        let processInfo = ProcessInfo.processInfo
        return processInfo.arguments.contains { $0.hasPrefix("-UITest") }
            || processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

private struct LaunchReviewPromptModifier: ViewModifier {
    @Environment(\.requestReview) private var requestReview
    @State private var hasCheckedThisPresentation = false

    func body(content: Content) -> some View {
        content.task {
            guard !hasCheckedThisPresentation else { return }
            hasCheckedThisPresentation = true
            guard AppReviewPrompt.consumePendingRequestIfAllowed() else { return }

            // Let the main scene finish becoming active before asking StoreKit.
            await Task.yield()
            requestReview()
        }
    }
}

extension View {
    func requestsReviewOnEligibleLaunch() -> some View {
        modifier(LaunchReviewPromptModifier())
    }
}
