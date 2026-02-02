import Foundation
import Combine // Import Combine for ObservableObject and Published

final class QuickStartConfigManager: ObservableObject { // Add ObservableObject
    static let shared = QuickStartConfigManager()
    private let userDefaults = UserDefaults.standard
    private let configKey = "quickStartConfig"

    @Published var quickStartConfig: QuickStartConfig // Add @Published property

    private init() {
        // Direct initialization of quickStartConfig without calling a method on self
        if let data = userDefaults.data(forKey: configKey) {
            if let config = try? JSONDecoder().decode(QuickStartConfig.self, from: data) {
                self.quickStartConfig = config
            } else {
                self.quickStartConfig = QuickStartConfig.defaultPhoneConfig
            }
        } else {
            self.quickStartConfig = QuickStartConfig.defaultPhoneConfig
        }
    }

    func `init`() async {
        // No-op for UserDefaults, but can be used for more complex setup if needed
    }

    // Internal helper to load config without publishing changes directly
    private func loadConfigInternal(isLargeScreen: Bool, is2in1: Bool) -> QuickStartConfig {
        if let data = userDefaults.data(forKey: configKey) {
            if let config = try? JSONDecoder().decode(QuickStartConfig.self, from: data) {
                return config
            }
        }
        // Fallback to default
        return QuickStartConfig.defaultPhoneConfig
    }

    // Public method to load config and update the published property
    func loadConfig(isLargeScreen: Bool, is2in1: Bool) {
        self.quickStartConfig = loadConfigInternal(isLargeScreen: isLargeScreen, is2in1: is2in1)
    }

    func setPrimarySport(_ primary: GameType) async throws {
        var currentConfig = self.quickStartConfig // Access the published config
        currentConfig.primarySport = primary
        try await saveConfig(currentConfig)
        self.quickStartConfig = currentConfig // Update published property
    }

    func setSecondarySport(_ secondary: GameType) async throws {
        var currentConfig = self.quickStartConfig // Access the published config
        currentConfig.secondarySport = secondary
        try await saveConfig(currentConfig)
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
