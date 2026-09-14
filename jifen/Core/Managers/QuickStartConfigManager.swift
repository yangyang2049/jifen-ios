import Foundation
import Combine // Import Combine for ObservableObject and Published

final class QuickStartConfigManager: ObservableObject { // Add ObservableObject
    static let shared = QuickStartConfigManager()
    private let userDefaults: UserDefaults
    private let configKey: String
    private var didResolveInitialConfig: Bool
    private(set) var configurationReadCount = 0

    @Published var quickStartConfig: QuickStartConfig // Add @Published property

    init(
        userDefaults: UserDefaults = .standard,
        configKey: String = "quickStartConfig"
    ) {
        self.userDefaults = userDefaults
        self.configKey = configKey
        configurationReadCount = 1
        if let data = userDefaults.data(forKey: configKey) {
            if let config = try? JSONDecoder().decode(QuickStartConfig.self, from: data) {
                self.quickStartConfig = config
                didResolveInitialConfig = true
            } else {
                self.quickStartConfig = QuickStartConfig.defaultPhoneConfig
                didResolveInitialConfig = false
            }
        } else {
            self.quickStartConfig = QuickStartConfig.defaultPhoneConfig
            didResolveInitialConfig = false
        }
    }

    /// Resolves device-specific defaults without reading UserDefaults again.
    /// A persisted configuration always wins and is decoded only in `init`.
    func configureDefaultsIfNeeded(isLargeScreen: Bool, is2in1: Bool) {
        guard !didResolveInitialConfig else { return }
        didResolveInitialConfig = true
        if is2in1 {
            quickStartConfig = .default2In1Config
        } else {
            quickStartConfig = isLargeScreen
                ? .defaultTabletConfig
                : .defaultPhoneConfig
        }
    }

    /// Saves the visible quick-start slots in one write. Compact layouts pass
    /// `nil` for the tertiary slot so an existing iPad choice is preserved.
    func setSports(
        primary: GameType,
        secondary: GameType,
        tertiary: GameType?
    ) async throws {
        var currentConfig = quickStartConfig
        currentConfig.primarySport = primary
        currentConfig.secondarySport = secondary
        if let tertiary {
            currentConfig.tertiarySport = tertiary
        }
        try await saveConfig(currentConfig)
        didResolveInitialConfig = true
        quickStartConfig = currentConfig
    }

    private func saveConfig(_ config: QuickStartConfig) async throws {
        do {
            let data = try JSONEncoder().encode(config)
            userDefaults.set(data, forKey: configKey)
        } catch {
            throw error
        }
    }
}
