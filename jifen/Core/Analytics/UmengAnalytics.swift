import Foundation

#if os(iOS)
import UMCommon

enum UmengAnalytics {
    private(set) static var isInitialized = false

    static func initializeIfConsented() {
        guard !isInitialized,
              !isDisabledForUITests,
              LegalConsent.hasAcceptedCurrentDocuments(),
              let appKey = configuredValue(forInfoKey: "UMENG_APP_KEY") else {
            logMissingConfigurationIfNeeded()
            return
        }

        let channel = configuredValue(forInfoKey: "UMENG_CHANNEL") ?? "App Store"

        #if DEBUG
        UMConfigure.setLogEnabled(true)
        #else
        UMConfigure.setLogEnabled(false)
        #endif

        // This release only needs product analytics. Disable attribution features
        // that are unrelated to the app's current scope before initializing.
        UMConfigure.setASAEnabled(false)
        UMConfigure.setSKANEnabled(false)
        UMConfigure.setEncryptEnabled(true)
        UMConfigure.setAnalyticsEnabled(true)
        UMConfigure.initWithAppkey(appKey, channel: channel)

        isInitialized = true
    }

    static func track(event: String, attributes: [String: Any] = [:]) {
        guard isInitialized else { return }

        let eventID = event.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eventID.isEmpty else { return }

        if attributes.isEmpty {
            MobClick.event(eventID)
        } else {
            MobClick.event(eventID, attributes: attributes)
        }
    }

    private static var isDisabledForUITests: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-UITestSkipLegalConsent")
            || arguments.contains("-UITestDisableAnalytics")
    }

    private static func configuredValue(forInfoKey key: String) -> String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }

    private static func logMissingConfigurationIfNeeded() {
        #if DEBUG
        guard !isInitialized,
              !isDisabledForUITests,
              LegalConsent.hasAcceptedCurrentDocuments(),
              configuredValue(forInfoKey: "UMENG_APP_KEY") == nil else {
            return
        }
        print("[UmengAnalytics] UMENG_APP_KEY is missing; analytics initialization was skipped.")
        #endif
    }
}
#endif
