import Foundation
import ScoreCore
import UIKit

/// Compile-always capability gates controlled by Info.plist (not `#if DEBUG`).
/// Set `JifenWatchLinkEntryEnabled` to `false` in Info.plist to hide Watch-link
/// entry points for App Store while keeping the implementation compiled.
enum AppFeatureFlags {
    private static let watchLinkEntryKey = "JifenWatchLinkEntryEnabled"

    /// Backend-backed capabilities are compiled into the app. Availability is
    /// kept in one place so additional identity providers can be enabled
    /// without scattering conditions through SwiftUI pages.
    static let accountFeaturesEnabled = true
    /// 反馈功能对全部语言开放（与安卓端一致，不再做中文 locale 闸门）。
    static let feedbackEntryEnabled = true
    static let commonDataCloudSyncEnabled = true
    static let qrLoginEnabled = true
    static let lanPeerSyncEnabled = false
    static let recordCrossDeviceSyncEnabled = true
    static let systemExternalDisplayEnabled = true

    /// Remote group push is available in Debug and Release; notification
    /// authorization and account binding still govern registration and delivery.
    static let groupRemotePushEnabled = true

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

    /// Apple Watch pairs with an iPhone, so phone-initiated WatchConnectivity
    /// entry points must not be offered by the iPad app.
    static var isWatchLinkSupportedOnCurrentDevice: Bool {
        isWatchLinkSupportedHostDevice(UIDevice.current.userInterfaceIdiom)
    }

    static func isWatchLinkSupportedHostDevice(_ idiom: UIUserInterfaceIdiom) -> Bool {
        idiom == .phone
    }

    static func isWatchLinkSupportedProject(_ gameType: GameType) -> Bool {
        // 必须与手机端服务层白名单 PhoneWatchLinkService.phoneInteractiveStartSupported
        // 及手表端 WatchLinkSession.isValidLinkedSetup 一致（由 PhoneWatchLinkServiceTests 守护）。
        switch gameType {
        case .pingpong, .badminton, .tennis, .pickleball,
             .shuttlecock, .squash, .foosball,
             .football, .football5v5,
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
        nineBallPlayerCount: Int? = nil,
        competitionFormat: CompetitionFormat? = nil
    ) -> Bool {
        guard isWatchLinkSupportedProject(gameType) else { return false }
        if gameType == .shuttlecock, competitionFormat == .team {
            return false
        }
        if gameType == .nineBall {
            let count = nineBallPlayerCount ?? 2
            return (2...4).contains(count)
        }
        // Singles/doubles share the same phone GameType entry; both are supported on watch.
        _ = isSingles
        return true
    }
}
