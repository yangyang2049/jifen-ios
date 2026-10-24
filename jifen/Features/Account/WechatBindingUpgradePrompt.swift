import Foundation

/// One persistent reminder for the app, shared across versions and accounts.
/// Eligibility alone does not consume it: record only an actual presentation.
@MainActor
final class WechatBindingUpgradePrompt {
    private let defaults: UserDefaults
    private let language: String
    private let presentedKey = "wechat.binding.prompt.presented"

    init(defaults: UserDefaults = .standard,
         language: String = Bundle.main.preferredLocalizations.first ?? "en") {
        self.defaults = defaults
        self.language = language
    }

    func offer(status: WechatBindingStatus?) -> Bool {
        !defaults.bool(forKey: presentedKey)
            && WechatBindingPolicy.canBind(isAuthenticated: true, language: language, status: status)
    }

    func markPresented() {
        defaults.set(true, forKey: presentedKey)
    }
}

nonisolated struct WechatBindingSessionContext: Sendable, Equatable {
    let id = UUID()
    let accountID: String
    let authRevision: UInt64
    let generation: UInt64
}
