import Foundation

/// Capabilities available in the phone and tablet app.
enum AppFeatureFlags {

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

}
