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

    func `init`() async {
        // No-op for UserDefaults, but can be used for more complex setup if needed
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

    func setPrimarySport(_ primary: GameType) async throws {
        var currentConfig = self.quickStartConfig // Access the published config
        currentConfig.primarySport = primary
        try await saveConfig(currentConfig)
        didResolveInitialConfig = true
        self.quickStartConfig = currentConfig // Update published property
    }

    func setSecondarySport(_ secondary: GameType) async throws {
        var currentConfig = self.quickStartConfig // Access the published config
        currentConfig.secondarySport = secondary
        try await saveConfig(currentConfig)
        didResolveInitialConfig = true
        self.quickStartConfig = currentConfig // Update published property
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
