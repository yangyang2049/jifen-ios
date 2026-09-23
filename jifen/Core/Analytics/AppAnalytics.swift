import FirebaseAnalytics
import Foundation
import ScoreCore
import StoreKit
import SwiftUI
import UIKit

enum AnalyticsEvent: String, CaseIterable {
    case selectContent = "select_content"
    case share
    case shareFailed = "share_failed"
    case login
    case authResult = "auth_result"
    case scoreboardOpen = "scoreboard_open"
    case scoreSetupConfirm = "score_setup_confirm"
    case matchStart = "match_start"
    case matchFinish = "match_finish"
    case recordSave = "record_save"
    case scoreboardAction = "scoreboard_action"
    case timerStart = "timer_start"
    case timerFinish = "timer_finish"
    case timerAction = "timer_action"
    case toolAction = "tool_action"
    case recordAction = "record_action"
    case bookingAction = "booking_action"
    case commonDataAction = "common_data_action"
    case feedbackAction = "feedback_action"
    case settingsChange = "settings_change"
    case dataClear = "data_clear"
    case rateApp = "rate_app"
    case castAction = "cast_action"
    case purchaseFlow = "purchase_flow"
    case bookingReminderOpen = "booking_reminder_open"
}

enum AnalyticsParameter: String, CaseIterable {
    case contentType = "content_type"
    case itemID = "item_id"
    case gameType = "game_type"
    case recordType = "record_type"
    case entryPoint = "entry_point"
    case actionName = "action_name"
    case settingName = "setting_name"
    case settingValue = "setting_value"
    case result
    case outcome
    case playerCount = "player_count"
    case layoutMode = "layout_mode"
    case targetSide = "target_side"
    case winner
    case endReason = "end_reason"
    case durationMS = "duration_ms"
    case currentPlayer = "current_player"
    case fromPlayer = "from_player"
    case toPlayer = "to_player"
    case presetID = "preset_id"
    case presetType = "preset_type"
    case diceCount = "dice_count"
    case resultValues = "result_values"
    case teamCount = "team_count"
    case participantCount = "participant_count"
    case elapsedMS = "elapsed_ms"
    case deltaMS = "delta_ms"
    case lapCount = "lap_count"
    case displayMode = "display_mode"
    case sourceSurface = "source_surface"
    case method
    case sessionState = "session_state"
    case errorCategory = "error_category"
    case flow
}

enum AnalyticsScreen: String, CaseIterable {
    case homeTab = "home_tab"
    case recordsTab = "records_tab"
    case scoreTab = "score_tab"
    case timerTab = "timer_tab"
    case meTab = "me_tab"
    case legalConsentPage = "legal_consent_page"
    case legalWebPage = "legal_web_page"
    case recentActivityPage = "recent_activity_page"
    case scheduleList = "schedule_list"
    case createBookingPage = "create_booking_page"
    case bookingDetailPage = "booking_detail_page"
    case commonNamesPage = "common_names_page"
    case commonPlacesPage = "common_places_page"
    case scoreboardSettingsPage = "scoreboard_settings_page"
    case castPage = "cast_page"
    case feedbackPage = "feedback_page"
    case faqPage = "faq_page"
    case aboutUsPage = "about_us_page"
    case loginPage = "login_page"
    case passwordLoginPage = "password_login_page"
    case qrLoginPage = "qr_login_page"
    case profilePage = "profile_page"
    case accountDeletionPage = "account_deletion_page"
    case vipPage = "vip_page"
    case sportsRecordDetail = "sports_record_detail"
    case multiscoreRecordDetail = "multiscore_record_detail"
    case timerRecordDetail = "timer_record_detail"
    case toolsPage = "tools_page"

    case footballScoreboard = "football_scoreboard"
    case football5v5Scoreboard = "football_5v5_scoreboard"
    case basketballScoreboard = "basketball_scoreboard"
    case shotTrainingScoreboard = "shot_training_scoreboard"
    case threeBasketballScoreboard = "three_basketball_scoreboard"
    case badmintonScoreboard = "badminton_scoreboard"
    case badmintonDoublesScoreboard = "badminton_doubles_scoreboard"
    case shuttlecockScoreboard = "shuttlecock_scoreboard"
    case squashScoreboard = "squash_scoreboard"
    case pingpongScoreboard = "pingpong_scoreboard"
    case pingpongDoublesScoreboard = "pingpong_doubles_scoreboard"
    case tennisScoreboard = "tennis_scoreboard"
    case tennisDoublesScoreboard = "tennis_doubles_scoreboard"
    case softTennisScoreboard = "soft_tennis_scoreboard"
    case softTennisDoublesScoreboard = "soft_tennis_doubles_scoreboard"
    case padelScoreboard = "padel_scoreboard"
    case volleyballScoreboard = "volleyball_scoreboard"
    case beachVolleyballScoreboard = "beach_volleyball_scoreboard"
    case airVolleyballScoreboard = "air_volleyball_scoreboard"
    case billiardsScoreboard = "billiards_scoreboard"
    case eightBallScoreboard = "eight_ball_scoreboard"
    case nineBallScoreboard = "nine_ball_scoreboard"
    case boxingScoreboard = "boxing_scoreboard"
    case pickleballScoreboard = "pickleball_scoreboard"
    case pickleballDoublesScoreboard = "pickleball_doubles_scoreboard"
    case archeryScoreboard = "archery_scoreboard"
    case snookerScoreboard = "snooker_scoreboard"
    case foosballScoreboard = "foosball_scoreboard"
    case simpleScorePage = "simple_score_page"
    case counterScoreboard = "counter_scoreboard"
    case multiGroupScore = "multi_group_score"
    case doudizhuScore = "doudizhu_score"
    case shengjiScore = "shengji_score"
    case guandanScore = "guandan_score"
    case unoScore = "uno_score"

    case goTimer = "go_timer"
    case xiangqiTimer = "xiangqi_timer"
    case chessTimer = "chess_timer"
    case checkersTimer = "checkers_timer"
    case cubeTimer = "cube_timer"
    case stopwatchPage = "stopwatch_page"
    case countdownPage = "countdown_page"

    case flipCoin = "flip_coin"
    case diceTool = "dice_tool"
    case whistleTool = "whistle_tool"
    case randomTeam = "random_team"
    case redYellowCard = "red_yellow_card"
    case fullscreenBarrage = "fullscreen_barrage"
    case pointsTable = "points_table"
    case pointsTableDetail = "points_table_detail"
    case dateTimeTool = "date_time_tool"
    case aaCalculator = "aa_calculator"
    case tenSecondChallenge = "ten_second_challenge"
}

enum AnalyticsEntryPoint: String, Hashable {
    case homeQuickStartPrimary = "home_quick_start_primary"
    case homeQuickStartSecondary = "home_quick_start_secondary"
    case homeNewGame = "home_new_game"
    case scoreTab = "score_tab"
    case timerTab = "timer_tab"
    case unfinishedBar = "unfinished_bar"
    case recordReplay = "record_replay"
    case recordsTab = "records_tab"
    case recentActivity = "recent_activity"
    case scheduleList = "schedule_list"
    case bookingDetail = "booking_detail"
    case bookingNotification = "booking_notification"
    case meTab = "me_tab"
    case autoAfterLaunchThreshold = "auto_after_launch_threshold"
    case homeTools = "home_tools"
    case toolsPage = "tools_page"
}

enum AnalyticsResult: String {
    case success
    case failed
    case cancelled
    case timeout
    case notReachable = "not_reachable"
    case rejected
    case requested
    case pending
    case started
}

enum AnalyticsSessionState: String {
    case new
    case resumed
}

enum AnalyticsWinner: String {
    case sideA = "side_a"
    case sideB = "side_b"
    case draw
    case unknown
}

enum AnalyticsEndReason: String {
    case ruleCompleted = "rule_completed"
    case manualFinish = "manual_finish"
    case abandoned
    case watchReported = "watch_reported"
}

enum AnalyticsSourceSurface: String {
    case phone
    case watch
}

enum AnalyticsValue: Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case strings([String])

    fileprivate var rawValue: Any? {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value.isFinite ? value : nil
        case .bool(let value): return value ? 1 : 0
        case .strings(let values): return values.joined(separator: ",")
        }
    }
}

struct AnalyticsParameters: ExpressibleByDictionaryLiteral, Equatable {
    private(set) var values: [AnalyticsParameter: AnalyticsValue]

    init(_ values: [AnalyticsParameter: AnalyticsValue] = [:]) {
        self.values = values
    }

    init(dictionaryLiteral elements: (AnalyticsParameter, AnalyticsValue)...) {
        values = Dictionary(uniqueKeysWithValues: elements)
    }

    subscript(key: AnalyticsParameter) -> AnalyticsValue? {
        get { values[key] }
        set { values[key] = newValue }
    }

    func merging(_ other: AnalyticsParameters) -> AnalyticsParameters {
        AnalyticsParameters(values.merging(other.values) { _, new in new })
    }
}

protocol AnalyticsSink: AnyObject {
    func track(event: String, attributes: [String: Any])
}

private final class FirebaseAnalyticsSink: AnalyticsSink {
    func track(event: String, attributes: [String: Any]) {
        Analytics.logEvent(event, parameters: attributes)
    }
}

enum AnalyticsNormalizer {
    static let maxEventIDLength = 40
    static let maxParameterKeyLength = 40
    static let maxParameterValueLength = 100
    static let maxParameterCount = 25

    private static let reservedKeys: Set<String> = [
        "id", "ts", "du", "ds", "duration", "pn", "token", "device_name",
        "device_model", "device_brand", "country", "city", "channel", "province",
        "appkey", "app_version", "access", "launch", "pre_app_version", "terminate",
        "no_first_pay", "is_newpayer", "first_pay_at", "first_pay_level",
        "first_pay_source", "first_pay_user_level", "first_pay_version", "type"
    ]

    private static let reservedEventIDs: Set<String> = [
        "ad_activeview", "ad_click", "ad_exposure", "ad_impression", "ad_query", "ad_reward",
        "adunit_exposure", "app_clear_data", "app_exception", "app_install", "app_remove",
        "app_store_refund", "app_store_subscription_cancel", "app_store_subscription_convert",
        "app_store_subscription_renew", "app_update", "app_upgrade", "dynamic_link_app_open",
        "dynamic_link_app_update", "dynamic_link_first_open", "error", "firebase_campaign",
        "firebase_in_app_message_action", "firebase_in_app_message_dismiss",
        "firebase_in_app_message_impression", "first_open", "first_visit", "in_app_purchase",
        "notification_dismiss", "notification_foreground", "notification_open",
        "notification_receive", "notification_send", "os_update", "screen_view", "session_start",
        "session_start_with_rollout", "user_engagement"
    ]

    static func eventID(_ raw: String) -> String? {
        guard let identifier = identifier(raw, maximumLength: maxEventIDLength, leadingFallback: "event"),
              !reservedEventIDs.contains(identifier),
              !identifier.hasPrefix("firebase_"),
              !identifier.hasPrefix("google_"),
              !identifier.hasPrefix("ga_")
        else { return nil }
        return identifier
    }

    static func attributes(_ parameters: AnalyticsParameters) -> [String: Any] {
        var result: [String: Any] = [:]
        for (parameter, analyticsValue) in parameters.values.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard result.count < maxParameterCount,
                  let key = identifier(parameter.rawValue, maximumLength: maxParameterKeyLength, leadingFallback: "param"),
                  !reservedKeys.contains(key),
                  !key.hasPrefix("firebase_"),
                  !key.hasPrefix("google_"),
                  !key.hasPrefix("ga_"),
                  let rawValue = analyticsValue.rawValue,
                  let normalizedValue = normalizedValue(rawValue) else { continue }
            result[key] = normalizedValue
        }
        return result
    }

    private static func identifier(_ raw: String, maximumLength: Int, leadingFallback: String) -> String? {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let scalars = lowered.unicodeScalars.map { scalar -> Character in
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
            return allowed.contains(scalar) ? Character(String(scalar)) : "_"
        }
        var normalized = String(scalars)
        while normalized.contains("__") {
            normalized = normalized.replacingOccurrences(of: "__", with: "_")
        }
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        guard !normalized.isEmpty else { return nil }
        if normalized.first?.isLetter != true {
            normalized = "\(leadingFallback)_\(normalized)"
        }
        normalized = String(normalized.prefix(maximumLength))
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedValue(_ value: Any) -> Any? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return String(trimmed.prefix(maxParameterValueLength))
        case let int as Int:
            return int
        case let double as Double:
            return double.isFinite ? double : nil
        default:
            return nil
        }
    }
}

enum AppAnalytics {
    private nonisolated(unsafe) static var sink: AnalyticsSink = FirebaseAnalyticsSink()
    private nonisolated(unsafe) static var collectionAllowed: () -> Bool = { true }
    private nonisolated(unsafe) static var pendingEndReasons: [String: AnalyticsEndReason] = [:]
    private static let lock = NSLock()

    static func track(_ event: AnalyticsEvent, parameters: AnalyticsParameters = [:]) {
        guard let eventID = AnalyticsNormalizer.eventID(event.rawValue) else { return }
        let attributes = AnalyticsNormalizer.attributes(parameters)
        lock.lock()
        let currentSink = sink
        let isAllowed = collectionAllowed()
        lock.unlock()
        guard isAllowed else { return }
        currentSink.track(event: eventID, attributes: attributes)
    }

    static func trackContentSelection(
        contentType: String,
        itemID: String,
        entryPoint: AnalyticsEntryPoint? = nil
    ) {
        var parameters: AnalyticsParameters = [
            .contentType: .string(contentType),
            .itemID: .string(itemID)
        ]
        if let entryPoint { parameters[.entryPoint] = .string(entryPoint.rawValue) }
        track(.selectContent, parameters: parameters)
    }

    static func trackScoreboardAction(
        _ action: String,
        gameType: GameType? = nil,
        parameters: AnalyticsParameters = [:]
    ) {
        var base: AnalyticsParameters = [.actionName: .string(action)]
        if let gameType { base[.gameType] = .string(gameType.analyticsIdentifier) }
        track(.scoreboardAction, parameters: base.merging(parameters))
    }

    static func trackTimerAction(
        _ action: String,
        gameType: String,
        parameters: AnalyticsParameters = [:]
    ) {
        track(.timerAction, parameters: AnalyticsParameters([
            .actionName: .string(action),
            .gameType: .string(gameType)
        ]).merging(parameters))
    }

    static func trackToolAction(
        toolID: String,
        action: String,
        parameters: AnalyticsParameters = [:]
    ) {
        track(.toolAction, parameters: AnalyticsParameters([
            .itemID: .string(toolID),
            .actionName: .string(action)
        ]).merging(parameters))
    }

    static func trackSuccessfulShare(contentType: String, method: String, itemID: String? = nil) {
        var parameters: AnalyticsParameters = [
            .contentType: .string(contentType),
            .method: .string(method)
        ]
        if let itemID { parameters[.itemID] = .string(itemID) }
        track(.share, parameters: parameters)
    }

    static func trackShareFailure(
        contentType: String,
        method: String = "system_share_sheet",
        errorCategory: String
    ) {
        track(.shareFailed, parameters: [
            .contentType: .string(contentType),
            .method: .string(method),
            .errorCategory: .string(errorCategory)
        ])
    }

    static func trackLoginSuccess(method: String) {
        track(.login, parameters: [.method: .string(method)])
    }

    static func trackAuthResult(method: String, result: AnalyticsResult, errorCategory: String? = nil) {
        var parameters: AnalyticsParameters = [
            .method: .string(method),
            .result: .string(result.rawValue)
        ]
        if let errorCategory { parameters[.errorCategory] = .string(errorCategory) }
        track(.authResult, parameters: parameters)
    }

    static func trackPurchaseFlow(_ result: AnalyticsResult, flow: String, itemID: String? = nil) {
        var parameters: AnalyticsParameters = [
            .flow: .string(flow),
            .result: .string(result.rawValue)
        ]
        if let itemID { parameters[.itemID] = .string(itemID) }
        track(.purchaseFlow, parameters: parameters)
    }

    static func trackVerifiedStoreKitPurchase(_ transaction: StoreKit.Transaction) {
        // StoreKit 2 purchases are not observed through the legacy automatic
        // StoreKit 1 path. This Firebase API emits the standard in_app_purchase
        // event and includes its own transaction de-duplication identifier.
        Analytics.logTransaction(transaction)
    }

    static func trackFeedbackAction(
        _ action: String,
        contentType: String? = nil,
        result: AnalyticsResult? = nil
    ) {
        var parameters: AnalyticsParameters = [.actionName: .string(action)]
        if let contentType { parameters[.contentType] = .string(contentType) }
        if let result { parameters[.result] = .string(result.rawValue) }
        track(.feedbackAction, parameters: parameters)
    }

    static func trackCastAction(_ action: String, result: AnalyticsResult, outcome: String? = nil) {
        var parameters: AnalyticsParameters = [
            .actionName: .string(action),
            .result: .string(result.rawValue)
        ]
        if let outcome { parameters[.outcome] = .string(outcome) }
        track(.castAction, parameters: parameters)
    }

    static func scoreSetupConfirmed(gameType: GameType, setup: SportsSetupResult, entryPoint: AnalyticsEntryPoint) {
        track(.scoreSetupConfirm, parameters: [
            .gameType: .string(gameType.analyticsIdentifier),
            .playerCount: .int(setup.analyticsPlayerCount),
            .layoutMode: .string(setup.analyticsLayoutMode),
            .entryPoint: .string(entryPoint.rawValue)
        ])
    }

    static func scoreboardRecordSaved(_ record: ScoreboardRecord, previous: ScoreboardRecord?) {
        let sourceSurface: AnalyticsSourceSurface = record.isSyncedFromWatch ? .watch : .phone
        let base: AnalyticsParameters = [
            .gameType: .string(record.gameType.analyticsIdentifier),
            .recordType: .string(record.gameType == .multiScoreboard ? "multiscore" : "scoreboard"),
            .sourceSurface: .string(sourceSurface.rawValue)
        ]

        if record.totalScoreChanges > 0, (previous?.totalScoreChanges ?? 0) == 0 {
            track(.matchStart, parameters: base)
        }

        guard record.status == .finished, previous?.status != .finished else { return }
        let durationMilliseconds = Int(max(0, record.duration ?? record.endTime.map { $0.timeIntervalSince(record.startTime) } ?? 0) * 1_000)
        let endReason: AnalyticsEndReason
        if record.isSyncedFromWatch {
            endReason = .watchReported
        } else {
            lock.lock()
            endReason = pendingEndReasons.removeValue(forKey: record.gameType.analyticsIdentifier) ?? .ruleCompleted
            lock.unlock()
        }
        track(.matchFinish, parameters: base.merging([
            .durationMS: .int(durationMilliseconds),
            .winner: .string(record.analyticsWinner.rawValue),
            .endReason: .string(endReason.rawValue)
        ]))
        track(.recordSave, parameters: base.merging([.result: .string(AnalyticsResult.success.rawValue)]))
    }

    static func scoreboardRecordSaveFailed(_ record: ScoreboardRecord) {
        guard record.status == .finished else { return }
        track(.recordSave, parameters: [
            .gameType: .string(record.gameType.analyticsIdentifier),
            .recordType: .string(record.gameType == .multiScoreboard ? "multiscore" : "scoreboard"),
            .sourceSurface: .string(record.isSyncedFromWatch ? AnalyticsSourceSurface.watch.rawValue : AnalyticsSourceSurface.phone.rawValue),
            .result: .string(AnalyticsResult.failed.rawValue)
        ])
    }

    static func markNextMatchEndReason(_ reason: AnalyticsEndReason, gameType: GameType) {
        lock.lock()
        pendingEndReasons[gameType.analyticsIdentifier] = reason
        lock.unlock()
    }

    static func installSinkForTesting(_ newSink: AnalyticsSink, collectionAllowed: Bool = true) {
        lock.lock()
        sink = newSink
        self.collectionAllowed = { collectionAllowed }
        lock.unlock()
    }

    static func restoreProductionSink() {
        lock.lock()
        sink = FirebaseAnalyticsSink()
        collectionAllowed = { true }
        pendingEndReasons.removeAll()
        lock.unlock()
    }
}

final class MatchAnalyticsContext {
    let gameType: GameType
    let entryPoint: AnalyticsEntryPoint
    let sourceSurface: AnalyticsSourceSurface
    let screen: AnalyticsScreen

    private let lock = NSLock()
    private var didTrackLaunch = false

    init(
        gameType: GameType,
        setup: SportsSetupResult?,
        entryPoint: AnalyticsEntryPoint,
        sourceSurface: AnalyticsSourceSurface = .phone
    ) {
        self.gameType = gameType
        self.entryPoint = entryPoint
        self.sourceSurface = sourceSurface
        screen = AnalyticsScreen.scoreboard(for: gameType, setup: setup)
    }

    func trackLaunch(isResume: Bool) {
        lock.lock()
        guard !didTrackLaunch else {
            lock.unlock()
            return
        }
        didTrackLaunch = true
        lock.unlock()

        AppAnalytics.track(.scoreboardOpen, parameters: [
            .gameType: .string(gameType.analyticsIdentifier),
            .entryPoint: .string(entryPoint.rawValue),
            .sourceSurface: .string(sourceSurface.rawValue),
            .sessionState: .string(isResume ? AnalyticsSessionState.resumed.rawValue : AnalyticsSessionState.new.rawValue)
        ])
    }
}

extension View {
    func appAnalyticsScreen(
        _ screen: AnalyticsScreen,
        screenClass: String? = nil
    ) -> some View {
        analyticsScreen(
            name: screen.rawValue,
            class: screenClass ?? screen.analyticsScreenClass
        )
    }
}

struct AnalyticsActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let contentType: String

    func makeCoordinator() -> Coordinator {
        Coordinator(contentType: contentType)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            context.coordinator.complete(completed: completed, error: error)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }

    final class Coordinator {
        private let contentType: String
        private var didComplete = false

        init(contentType: String) {
            self.contentType = contentType
        }

        func complete(completed: Bool, error: Error?, method: String = "system_share_sheet") {
            guard !didComplete else { return }
            didComplete = true
            if error != nil {
                AppAnalytics.trackShareFailure(
                    contentType: contentType,
                    method: method,
                    errorCategory: "system_share"
                )
                return
            }
            guard completed else { return }
            AppAnalytics.trackSuccessfulShare(contentType: contentType, method: method)
        }
    }
}

extension GameType {
    var analyticsIdentifier: String { canonicalScoreboardIdentifier }
}

extension BookingSportType {
    var analyticsGameTypeIdentifier: String {
        gameType?.analyticsIdentifier ?? rawValue
    }
}

extension ScoreboardRecord {
    var analyticsWinner: AnalyticsWinner {
        switch resolvedWinnerIdentity {
        case .team(.team0), .participant(index: 0):
            return .sideA
        case .team(.team1), .participant(index: 1):
            return .sideB
        case .participant:
            // Analytics has two historical side buckets and cannot represent a
            // third/fourth participant without changing the event contract.
            return .unknown
        case nil:
            if gameType == .doudizhu {
                let scores = displayParticipants.map(\.score)
                guard let best = scores.max() else { return .unknown }
                return scores.filter { $0 == best }.count > 1 ? .draw : .unknown
            }
            return team1FinalScore == team2FinalScore ? .draw : .unknown
        }
    }
}

extension SportsSetupResult {
    var analyticsPlayerCount: Int {
        if let playerCount { return max(1, playerCount) }
        return isSingles == false ? 4 : 2
    }

    var analyticsLayoutMode: String {
        if let playerCount, playerCount > 2 { return "multi" }
        return isSingles == false ? "doubles" : "singles"
    }
}

extension AnalyticsScreen {
    var analyticsScreenClass: String {
        switch self {
        case .homeTab, .recordsTab, .scoreTab, .timerTab, .meTab:
            return "tab"
        case .footballScoreboard, .football5v5Scoreboard, .basketballScoreboard, .shotTrainingScoreboard,
             .threeBasketballScoreboard, .badmintonScoreboard, .badmintonDoublesScoreboard,
             .shuttlecockScoreboard, .squashScoreboard, .pingpongScoreboard,
             .pingpongDoublesScoreboard, .tennisScoreboard, .tennisDoublesScoreboard,
             .softTennisScoreboard, .softTennisDoublesScoreboard, .padelScoreboard,
             .volleyballScoreboard, .beachVolleyballScoreboard,
             .airVolleyballScoreboard, .billiardsScoreboard, .eightBallScoreboard,
             .nineBallScoreboard, .boxingScoreboard, .pickleballScoreboard,
             .pickleballDoublesScoreboard, .archeryScoreboard, .snookerScoreboard,
             .foosballScoreboard, .simpleScorePage, .counterScoreboard, .multiGroupScore, .doudizhuScore,
             .shengjiScore, .guandanScore, .unoScore:
            return "scoreboard"
        case .goTimer, .xiangqiTimer, .chessTimer, .checkersTimer, .cubeTimer,
             .stopwatchPage, .countdownPage:
            return "timer"
        case .toolsPage, .flipCoin, .diceTool, .whistleTool, .randomTeam,
             .redYellowCard, .fullscreenBarrage, .pointsTable, .pointsTableDetail,
             .dateTimeTool, .aaCalculator, .tenSecondChallenge:
            return "tool"
        case .sportsRecordDetail, .multiscoreRecordDetail, .timerRecordDetail,
             .recentActivityPage:
            return "record_detail"
        case .scheduleList, .createBookingPage, .bookingDetailPage:
            return "schedule"
        case .loginPage, .passwordLoginPage, .qrLoginPage, .profilePage, .accountDeletionPage, .vipPage:
            return "account"
        case .commonNamesPage, .commonPlacesPage, .scoreboardSettingsPage,
             .feedbackPage, .faqPage, .aboutUsPage, .legalConsentPage, .legalWebPage:
            return "settings"
        case .castPage:
            return "display"
        }
    }

    static func scoreboard(for gameType: GameType, setup: SportsSetupResult?) -> AnalyticsScreen {
        switch gameType {
        case .football: return .footballScoreboard
        case .football5v5: return .football5v5Scoreboard
        case .basketball: return setup?.basketballMode == "three_x_three" ? .threeBasketballScoreboard : .basketballScoreboard
        case .basketballTraining: return .shotTrainingScoreboard
        case .threeBasketball: return .threeBasketballScoreboard
        case .badminton: return setup?.isSingles == false ? .badmintonDoublesScoreboard : .badmintonScoreboard
        case .shuttlecock: return .shuttlecockScoreboard
        case .squash: return .squashScoreboard
        case .pingpong: return setup?.isSingles == false ? .pingpongDoublesScoreboard : .pingpongScoreboard
        case .tennis: return setup?.isSingles == false ? .tennisDoublesScoreboard : .tennisScoreboard
        case .softTennis: return setup?.isSingles == false ? .softTennisDoublesScoreboard : .softTennisScoreboard
        case .padel: return .padelScoreboard
        case .pickleball: return setup?.isSingles == false ? .pickleballDoublesScoreboard : .pickleballScoreboard
        case .volleyball: return .volleyballScoreboard
        case .beachVolleyball: return .beachVolleyballScoreboard
        case .airVolleyball: return .airVolleyballScoreboard
        case .billiards: return .billiardsScoreboard
        case .eightBall: return .eightBallScoreboard
        case .nineBall: return .nineBallScoreboard
        case .boxing: return .boxingScoreboard
        case .archery: return .archeryScoreboard
        case .snooker: return .snookerScoreboard
        case .foosball: return .foosballScoreboard
        case .simpleScore: return .simpleScorePage
        case .counter: return .counterScoreboard
        case .multiScoreboard: return .multiGroupScore
        case .doudizhu: return .doudizhuScore
        case .shengji: return .shengjiScore
        case .guandan: return .guandanScore
        case .uno: return .unoScore
        case .go: return .goTimer
        case .xiangqi: return .xiangqiTimer
        case .chess: return .chessTimer
        case .checkers: return .checkersTimer
        case .stopwatch: return .stopwatchPage
        }
    }

    static func timer(for destination: TimerDestination) -> AnalyticsScreen {
        switch destination {
        case .stopwatch: return .stopwatchPage
        case .go: return .goTimer
        case .xiangqi: return .xiangqiTimer
        case .chess: return .chessTimer
        case .checkers: return .checkersTimer
        case .cube: return .cubeTimer
        case .timeout: return .countdownPage
        }
    }

    static func tool(id: String) -> AnalyticsScreen? {
        switch id {
        case "flip_coin": return .flipCoin
        case "dice": return .diceTool
        case "whistle": return .whistleTool
        case "random_team": return .randomTeam
        case "red_yellow_card": return .redYellowCard
        case "fullscreen_barrage": return .fullscreenBarrage
        case "points_table": return .pointsTable
        case "time": return .dateTimeTool
        case "aa_calculator": return .aaCalculator
        case "ten_second": return .tenSecondChallenge
        default: return nil
        }
    }
}
