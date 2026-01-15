import WatchKit

enum WatchHapticType {
    case score
    case undo
    case finish
    case light
    case medium
    case strong
}

final class WatchHaptics {
    static let shared = WatchHaptics()

    private init() {}

    func play(_ type: WatchHapticType) {
        guard WatchPreferences.shared.vibrationEnabled else { return }

        let haptic: WKHapticType
        switch type {
        case .score:
            haptic = .click
        case .undo:
            haptic = .directionDown
        case .finish:
            haptic = .success
        case .light:
            haptic = .click
        case .medium:
            haptic = .directionUp
        case .strong:
            haptic = .failure
        }
        WKInterfaceDevice.current().play(haptic)
    }
}
