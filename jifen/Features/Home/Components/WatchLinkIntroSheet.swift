import SwiftUI
import UIKit

/// Launch-only introduction for the release that brings back Apple Watch linking.
@MainActor @Observable
final class WatchLinkIntroPresentation {
    static let releaseVersion = "3.4.4"
    static let seenKey = "watch_link_intro_seen_" + releaseVersion
    /// 素材命名：WatchLinkIntroArtwork-<locale>。
    /// 三套素材由 scripts/compose_watch_link_intro_artwork.py 合成，
    /// 由 WatchLinkIntroLaunchTests 在版本号等于 releaseVersion 时强制校验存在。
    static let artworkNamePrefix = "WatchLinkIntroArtwork-"
    private static let supportedLocalizations = ["zh-Hans", "zh-Hant", "en"]

    let hasLaunchPriority: Bool
    let artwork: UIImage?
    private let defaults: UserDefaults
    /// 只有 sheet 真正出现（`sheetDidAppear`）后才置为 true。
    /// present 失败（同层已有模态、进后台）时必须保持 false，否则
    /// alertUnlessWatchLinkIntro 会把保存失败等全局告警永久静音。
    private(set) var isCoveringHome = false
    private(set) var wasDismissed = false

    var reservesLaunchPresentation: Bool { hasLaunchPriority && !wasDismissed }
    var isPresented = false

    init(
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.defaults = defaults
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let locale = Bundle.main.preferredLocalizations.first ?? ""
        let supportsLocale = Self.supportedLocalizations.contains(locale)
        let artwork = supportsLocale ? UIImage(named: Self.artworkNamePrefix + locale) : nil
        #if DEBUG
        let previewsIntro = arguments.contains("-UITestWatchLinkIntro")
        // Exercise the sheet's presentation in UI tests without bundling device artwork.
        self.artwork = artwork ?? (previewsIntro && supportsLocale ? UIImage(systemName: "photo") : nil)
        #else
        let previewsIntro = false
        self.artwork = artwork
        #endif

        let isAutomation = arguments.contains { $0.hasPrefix("-UITest") }
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        hasLaunchPriority = AppFeatureFlags.watchLinkEntryEnabled
            && AppFeatureFlags.isWatchLinkSupportedOnCurrentDevice
            && !ProcessInfo.processInfo.isiOSAppOnMac
            && self.artwork != nil
            && !defaults.bool(forKey: Self.seenKey)
            && (previewsIntro || (version == Self.releaseVersion && !isAutomation))
    }

    /// 只发出「请展示」的请求；遮住首页要等 sheet 的 onAppear。
    func present() {
        guard hasLaunchPriority, !isCoveringHome, !wasDismissed, !isPresented else { return }
        isPresented = true
    }

    /// sheet 的 onAppear：确认弹层真的上屏了，才开始压制其它首页弹层与全局告警。
    func sheetDidAppear() {
        guard isPresented else { return }
        isCoveringHome = true
    }

    /// 幂等：sheet 的 onDismiss 与 isPresented 变化都会走到这里。
    func dismiss() {
        isCoveringHome = false
        isPresented = false
        wasDismissed = true
        defaults.set(true, forKey: Self.seenKey)
    }
}

struct WatchLinkIntroSheet: View {
    let artwork: UIImage
    let onOpenSettings: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var titleSize = 26.0
    @ScaledMetric(relativeTo: .subheadline) private var messageSize = 15.0
    @ScaledMetric(relativeTo: .body) private var actionSize = 17.0

    private static let compactDetent = PresentationDetent.height(480)

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(uiImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: 356, maxHeight: 266)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(String(localized: "intro_title", table: "WatchLinkIntro"))
                        .font(.system(size: titleSize, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("watch_link_intro_title")

                    Text(String(localized: "intro_message", table: "WatchLinkIntro"))
                        .font(.system(size: messageSize))
                        .foregroundStyle(Theme.adaptive(Color(hex: "454545"), Color(hex: "C5C5C5")))
                        .lineSpacing(3)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Text(String(localized: "intro_done", table: "WatchLinkIntro"))
                            .font(.system(size: actionSize, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .overlay { Capsule().strokeBorder(Theme.divider) }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watch_link_intro_done")

                    Button {
                        onOpenSettings()
                        dismiss()
                    } label: {
                        Text(String(localized: "intro_open_settings", table: "WatchLinkIntro"))
                            .font(.system(size: actionSize, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color(hex: "24823E"), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watch_link_intro_open_settings")
                }
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [Self.compactDetent, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.dialogSurfaceBackground)
    }
}
