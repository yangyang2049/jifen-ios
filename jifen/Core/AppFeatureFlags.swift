import Foundation

/// Compile-always capability gates controlled by Info.plist (not `#if DEBUG`).
/// Set `JifenWatchLinkEntryEnabled` to `false` in Info.plist to hide Watch-link
/// entry points for App Store while keeping the implementation compiled.
enum AppFeatureFlags {
    private static let watchLinkEntryKey = "JifenWatchLinkEntryEnabled"

    /// When true, Setup / Me / scoreboard menus may show Watch-link actions.
    static var watchLinkEntryEnabled: Bool {
        if let value = Bundle.main.object(forInfoDictionaryKey: watchLinkEntryKey) as? Bool {
            return value
        }
        if let number = Bundle.main.object(forInfoDictionaryKey: watchLinkEntryKey) as? NSNumber {
            return number.boolValue
        }
        if let string = Bundle.main.object(forInfoDictionaryKey: watchLinkEntryKey) as? String {
            return (string as NSString).boolValue
        }
        // Default open when the key is absent (dev / older builds).
        return true
    }

    static func isWatchLinkSupportedProject(_ gameType: GameType) -> Bool {
        // Aligned with HOS `linkedScoreboardCapability.ts` phoneLinkedStartSupported.
        switch gameType {
        case .pingpong, .badminton, .tennis, .pickleball,
             .archery,
             .eightBall, .nineBall, .snooker:
            return true
        default:
            return false
        }
    }

    /// Whether the current setup mode (singles/doubles, nine-ball player count) can start on watch.
    static func isWatchLinkSupportedSetup(
        gameType: GameType,
        isSingles: Bool? = nil,
        nineBallPlayerCount: Int? = nil
    ) -> Bool {
        guard isWatchLinkSupportedProject(gameType) else { return false }
        if gameType == .nineBall {
            let count = nineBallPlayerCount ?? 2
            return (2...4).contains(count)
        }
        // Singles/doubles share the same phone GameType entry; both are supported on watch.
        _ = isSingles
        return true
    }
}