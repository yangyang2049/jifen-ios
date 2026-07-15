import Observation
import SwiftUI

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "jifen-v2.appAppearanceMode"

    var id: String { rawValue }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    var localizedTitle: String {
        NSLocalizedString("appearance_\(rawValue)", comment: "App appearance mode")
    }
}

@MainActor
@Observable
final class AppAppearanceStore {
    @ObservationIgnored private let defaults: UserDefaults

    var mode: AppAppearanceMode {
        didSet {
            defaults.set(mode.rawValue, forKey: AppAppearanceMode.storageKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.mode = AppAppearanceMode(rawValue: defaults.string(forKey: AppAppearanceMode.storageKey) ?? "") ?? .light
    }
}
