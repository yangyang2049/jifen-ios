import Foundation
import Observation
import ScoreCore
import SwiftUI

struct ScoreboardUsageHintDescriptor: Equatable, Hashable, Identifiable {
    let gameType: ScoreCore.GameType

    var id: String { gameType.rawValue }

    /// Singles and doubles are independent scoreboards for both copy and the
    /// lifetime-only automatic presentation rule.
    var scoreboardPersistenceID: String {
        gameType.rawValue
    }

    var localizationKey: String {
        switch gameType {
        case .football: "scoreboard_usage_hint_football"
        case .basketball: "scoreboard_usage_hint_basketball"
        case .threeBasketball: "scoreboard_usage_hint_three_basketball"
        case .volleyball: "scoreboard_usage_hint_volleyball"
        case .airVolleyball: "scoreboard_usage_hint_air_volleyball"
        case .beachVolleyball: "scoreboard_usage_hint_beach_volleyball"
        case .pingpong: "scoreboard_usage_hint_pingpong"
        case .pingpongDoubles: "scoreboard_usage_hint_pingpong_doubles"
        case .tennis: "scoreboard_usage_hint_tennis"
        case .tennisDoubles: "scoreboard_usage_hint_tennis_doubles"
        case .badminton: "scoreboard_usage_hint_badminton"
        case .badmintonDoubles: "scoreboard_usage_hint_badminton_doubles"
        case .pickleball: "scoreboard_usage_hint_pickleball"
        case .pickleballDoubles: "scoreboard_usage_hint_pickleball_doubles"
        case .archeryDual: "scoreboard_usage_hint_archery"
        case .boxing: "scoreboard_usage_hint_boxing"
        case .billiards: "scoreboard_usage_hint_billiards"
        case .eightBall: "scoreboard_usage_hint_eight_ball"
        case .nineBall: "scoreboard_usage_hint_nine_ball"
        case .snooker: "scoreboard_usage_hint_snooker"
        case .guandan: "scoreboard_usage_hint_guandan"
        case .shengji: "scoreboard_usage_hint_shengji"
        case .uno: "scoreboard_usage_hint_uno"
        case .doudizhu: "scoreboard_usage_hint_doudizhu"
        case .foosball: "scoreboard_usage_hint_foosball"
        case .foosballDoubles: "scoreboard_usage_hint_foosball_doubles"
        case .simpleScore: "scoreboard_usage_hint_simple_score"
        case .multiScoreboard: "scoreboard_usage_hint_multi_scoreboard"
        }
    }

    var localizedMessage: String {
        NSLocalizedString(localizationKey, comment: "Scoreboard-specific usage instructions")
    }

    static func resolve(
        gameType: GameType,
        setup: SportsSetupResult?,
        exactGameType: ScoreCore.GameType? = nil
    ) -> ScoreboardUsageHintDescriptor? {
        if let exactGameType {
            return ScoreboardUsageHintDescriptor(gameType: exactGameType)
        }
        guard let resolved = gameType.scoreCoreGameType(
            isSingles: setup?.isSingles != false
        ) else {
            return nil
        }
        return ScoreboardUsageHintDescriptor(gameType: resolved)
    }
}

struct ScoreboardUsageHintStore {
    /// This namespace is permanent: app updates must never change it or clear
    /// its values. Only uninstalling/clearing app data may reset the flags.
    static let keyPrefix = "scoreboard_usage_hint_shown_once_"
    private static let legacyKeyPrefix = "scoreboard_usage_hint_shown_v1_"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasShown(_ descriptor: ScoreboardUsageHintDescriptor) -> Bool {
        if defaults.bool(forKey: key(for: descriptor)) {
            return true
        }

        // Preserve the exact singles/doubles flag written by earlier builds.
        return defaults.bool(forKey: Self.legacyKeyPrefix + descriptor.gameType.rawValue)
    }

    func markShown(_ descriptor: ScoreboardUsageHintDescriptor) {
        defaults.set(true, forKey: key(for: descriptor))
    }

    func key(for descriptor: ScoreboardUsageHintDescriptor) -> String {
        Self.keyPrefix + descriptor.scoreboardPersistenceID
    }

    func removeAllShownFlags() {
        for key in defaults.dictionaryRepresentation().keys where
            key.hasPrefix(Self.keyPrefix) || key.hasPrefix(Self.legacyKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

enum ScoreboardUsageHintAutomaticPresentationPolicy {
    static func allows(
        requested: Bool,
        setup: SportsSetupResult?
    ) -> Bool {
        guard requested else { return false }
        return setup?.startOnWatch != true && setup?.linkedWatchSessionId == nil
    }
}

@MainActor
@Observable
final class ScoreboardUsageHintCoordinator {
    let descriptor: ScoreboardUsageHintDescriptor
    private let store: ScoreboardUsageHintStore
    private(set) var isPresented = false
    private static var didPrepareUITestState = false

    init(
        descriptor: ScoreboardUsageHintDescriptor,
        store: ScoreboardUsageHintStore? = nil
    ) {
        self.descriptor = descriptor
        self.store = store ?? ScoreboardUsageHintStore()
    }

    func presentAutomaticallyIfNeeded() {
        Self.prepareUITestStateIfRequested(store: store)
        guard !Self.skipsAutomaticPresentationForUITests,
              !store.hasShown(descriptor) else { return }
        isPresented = true
    }

    func presentFromMenu() {
        isPresented = true
    }

    func dismissAndMarkShown() {
        store.markShown(descriptor)
        isPresented = false
    }

    private static var skipsAutomaticPresentationForUITests: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITestSkipScoreboardUsageHints")
#else
        false
#endif
    }

    private static func prepareUITestStateIfRequested(store: ScoreboardUsageHintStore) {
#if DEBUG
        guard !didPrepareUITestState,
              ProcessInfo.processInfo.arguments.contains("-UITestResetScoreboardUsageHints") else { return }
        didPrepareUITestState = true
        store.removeAllShownFlags()
#endif
    }
}

private struct ScoreboardUsageHintCoordinatorEnvironmentKey: EnvironmentKey {
    static let defaultValue: ScoreboardUsageHintCoordinator? = nil
}

extension EnvironmentValues {
    var scoreboardUsageHintCoordinator: ScoreboardUsageHintCoordinator? {
        get { self[ScoreboardUsageHintCoordinatorEnvironmentKey.self] }
        set { self[ScoreboardUsageHintCoordinatorEnvironmentKey.self] = newValue }
    }
}

struct ScoreboardUsageHintDialog: View {
    let descriptor: ScoreboardUsageHintDescriptor
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let compactHeight = proxy.size.height < 420
            let dialogWidth = Theme.dialogWidth(
                availableWidth: proxy.size.width,
                role: .informational
            )
            let maximumBodyHeight = max(
                88,
                min(300, proxy.size.height * 0.92 - (compactHeight ? 132 : 168))
            )

            ZStack {
                Theme.scoreboardDialogScrim
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { }

                VStack(spacing: compactHeight ? 10 : 16) {
                    ZStack {
                        Text(NSLocalizedString(
                            "scoreboard_usage_hint_title",
                            value: "计分板使用说明",
                            comment: ""
                        ))
                        .font(.system(size: compactHeight ? 18 : 20, weight: .bold))
                        .foregroundStyle(Theme.scoreboardDialogTextPrimary)
                        .frame(maxWidth: .infinity)

                        HStack {
                            Spacer()
                            ScoreboardDialogCloseButton(
                                action: onDismiss,
                                accessibilityIdentifier: "scoreboard_usage_hint_close"
                            )
                        }
                    }

                    ScrollView {
                        Text(descriptor.localizedMessage)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.scoreboardDialogTextPrimary.opacity(0.86))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("scoreboard_usage_hint_body")
                    }
                    .scrollIndicators(.automatic)
                    .frame(maxHeight: maximumBodyHeight)

                    Button(action: onDismiss) {
                        Text(NSLocalizedString(
                            "scoreboard_usage_hint_got_it",
                            value: "知道了",
                            comment: ""
                        ))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Theme.accentColor)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("scoreboard_usage_hint_confirm")
                }
                .padding(.horizontal, compactHeight ? 16 : 22)
                .padding(.vertical, compactHeight ? 12 : 18)
                .frame(width: dialogWidth)
                .background(Theme.scoreboardDialogSurface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 24, x: 0, y: 10)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("scoreboard_usage_hint_dialog")
            }
        }
        .ignoresSafeArea()
    }
}
