import Foundation
import ScoreCore
import SwiftUI // For Color (though not directly used here, good practice if views are nearby)
// Assuming GameType is part of the main 'jifen' module
// and formatScoreboardDuration is globally available or imported from the same module



// MARK: - ActivityType Enum
enum ActivityType: Int, Codable, Identifiable {
    var id: Self { self } // Conforming to Identifiable for ForEach loops
    case scoreboard = 0
    case timer = 1
}

enum TimerActionType: String, Codable {
    case start
    case pause
    case resume
    case move
    case timeout
    case manualStop
    case gameEnd
}

struct TimerActionRecord: Identifiable, Codable, Equatable {
    let id: String
    let elapsed: TimeInterval
    let type: TimerActionType
    var actor: String?
    var leftRemaining: Int?
    var rightRemaining: Int?
}

// MARK: - GameRecordSummary Struct (for timer records)
// This struct is inferred from HarmonyOS HomeTab.ets logic for timer activities.
// It will be used to represent a summary of a timer record.
struct GameRecordSummary: Identifiable, Codable, Equatable {
    let id: String
    let gameType: GameType
    let timestamp: TimeInterval
    var duration: TimeInterval?
    var winner: String?
    var actions: [TimerActionRecord]? = nil
    
    var title: String {
        gameType.displayName
    }
    var description: String {
        if let duration = duration {
            return "Duration: \(formatDuration(duration))"
        }
        return ""
    }
    var date: String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    var time: String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // Equatable conformance
    static func == (lhs: GameRecordSummary, rhs: GameRecordSummary) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - RecentActivity Struct
// This struct combines common fields from both timer and scoreboard records
// to be displayed in the recent activities list.
struct RecentActivity: Identifiable, Codable {
    let id: String
    let activityType: ActivityType
    let gameType: GameType
    let timestamp: TimeInterval // Unix timestamp
    let title: String
    let description: String
    /// Matches phone `extraData.syncFrom == "watch"` for Watch-originated records.
    var syncFrom: String? = nil

    var isSyncedFromWatch: Bool { syncFrom == "watch" }
}

// MARK: - SourcePage Enum
enum SourcePage: String, Codable {
    case home = "HOME"
    case newGameDialog = "NEW_GAME_DIALOG" // Added based on typical usage
    // Add other cases as needed from HarmonyOS project
}

// MARK: - GameItem Struct
struct GameItem: Identifiable {
    let id = UUID() // Using UUID for Identifiable conformance
    let type: GameType
    let nameKey: String // Using key for localization $r('app.string.tab_volleyball') etc.
    let emoji: String // Icon
    let route: String // String for route, to be translated to NavigationLink later
}

// MARK: - QuickStartConfig Struct
struct QuickStartConfig: Codable, Equatable {
    var primarySport: GameType
    var secondarySport: GameType

    // A default configuration for phone, similar to DEFAULT_QUICK_START_CONFIG_PHONE
    static let defaultPhoneConfig = QuickStartConfig(primarySport: .badminton, secondarySport: .pingpong)
    static let defaultTabletConfig = QuickStartConfig(primarySport: .basketball, secondarySport: .badminton)
    // iOS has no tertiary quick-start card yet, so the 2-in-1 default currently
    // shares the two visible sports with the tablet configuration.
    static let default2In1Config = QuickStartConfig(primarySport: .basketball, secondarySport: .badminton)
}

// MARK: - ScoreboardSetupItem (for sheet(item:) so content is never empty)
struct ScoreboardSetupItem: Identifiable {
    let gameType: GameType
    var id: String { gameType.rawValue }
}

// MARK: - SportsSetupResult Struct (refined for 6 supported sports)
// Based on HarmonyOS SportsSetupDialog.ets, excluding pickleball-specific fields
struct SportsSetupResult: Codable, Hashable {
    var team1Name: String
    var team2Name: String
    var team3Name: String? = nil
    var team4Name: String? = nil
    var maxSets: Int? = nil
    var matchCompletionMode: MatchCompletionMode? = nil
    var pointsPerSet: Int? = nil
    var tieBreakPoints: Int? = nil
    var gamesPerSet: Int? = nil // Tennis traditional format: 4 or 6
    var setScoringMode: String? = nil // "regular" or "tiebreak_only"
    var autoChangeSides: Bool? = nil // autoChangeSides (Pingpong, Tennis, Badminton, Volleyball)
    var isSingles: Bool? = nil // 乒乓球/羽毛球/网球：true=单打，false=双打
    var team1Player1Name: String? = nil
    var team1Player2Name: String? = nil
    var team2Player1Name: String? = nil
    var team2Player2Name: String? = nil
    var basketballMode: String? = nil // "five_v_five" or "three_x_three"
    var basketballRuleSet: String? = nil // "fiba" or "nba"
    var tennisDeuceMode: String? = nil // "advantage" or "no_ad"
    var servingSide: String? = nil // "left" or "right"
    var voiceAnnouncement: Bool? = nil
    var targetScore: Int? = nil
    var winByTwo: Bool? = nil
    var scoreCap: Int? = nil
    var useRallyScoring: Bool? = nil
    var maxRounds: Int? = nil
    var eightBallHandicapRacks: Int? = nil
    var eightBallHandicapBeneficiary: String? = nil // "team1", "team2", or "none"
    var nineBallBigGold: Int? = nil
    var nineBallSmallGold: Int? = nil
    var nineBallGoldenNine: Int? = nil
    var nineBallNormalWin: Int? = nil
    var nineBallBallInHand: Int? = nil
    var nineBallFoul: Int? = nil
    var startOnWatch: Bool? = nil
    var linkedWatchSessionId: UUID? = nil
    var playerCount: Int? = nil // 多人计分：3-9
    var playerNames: [String]? = nil // 多人计分玩家名
    /// Simple score: tap opens ±N panel instead of +1. Aligns with Android/HOS.
    var multiScoreCustomAdjustEnabled: Bool? = nil
    /// 掼蛋：三 A / 过 A / 回退级牌（对齐 CardGameSetupResult）
    var guandanTripleA: Bool? = nil
    var guandanPassACondition: String? = nil // "not_last" | "double_up"
    var guandanTripleAFallbackRank: String? = nil
}

/// Typed projection used by every billiards entry path (fresh setup, resume,
/// replay and Watch setup). `SportsSetupResult` remains the compatibility
/// payload for existing records and navigation state.
enum BilliardsSetupConfiguration: Codable, Equatable {
    case billiards
    case eightBall(targetRacks: Int, handicapRacks: Int, beneficiary: MatchSide?)
    case nineBall(playerNames: [String], points: NineBallChaseConfig)
    case snooker(maxFrames: Int, firstBreaker: MatchSide)
}

extension SportsSetupResult {
    func billiardsConfiguration(for gameType: GameType) -> BilliardsSetupConfiguration? {
        switch gameType {
        case .billiards:
            return .billiards
        case .eightBall:
            let target = min(99, max(1, maxSets ?? 9))
            let handicap = min(max(0, eightBallHandicapRacks ?? 0), max(0, target - 1))
            let beneficiary: MatchSide? = eightBallHandicapBeneficiary == "team1" ? .left
                : (eightBallHandicapBeneficiary == "team2" ? .right : nil)
            return .eightBall(
                targetRacks: target,
                handicapRacks: beneficiary == nil ? 0 : handicap,
                beneficiary: beneficiary
            )
        case .nineBall:
            let candidates = playerNames ?? [team1Name, team2Name, team3Name, team4Name].compactMap { $0 }
            let count = min(4, max(2, playerCount ?? candidates.count))
            let names = (0..<count).map { index in
                let trimmed = index < candidates.count
                    ? candidates[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
                return trimmed.isEmpty ? "P\(index + 1)" : trimmed
            }
            return .nineBall(
                playerNames: names,
                points: NineBallChaseConfig(
                    bigGold: min(99, max(0, nineBallBigGold ?? 10)),
                    smallGold: min(99, max(0, nineBallSmallGold ?? 7)),
                    goldenNine: min(99, max(0, nineBallGoldenNine ?? 8)),
                    normalWin: min(99, max(0, nineBallNormalWin ?? 4)),
                    ballInHand: min(99, max(0, nineBallBallInHand ?? 1)),
                    foul: min(99, max(0, nineBallFoul ?? 1))
                )
            )
        case .snooker:
            return .snooker(
                maxFrames: SnookerState.normalizedMaxFrames(maxSets ?? 3),
                firstBreaker: servingSide == MatchSide.right.rawValue ? .right : .left
            )
        default:
            return nil
        }
    }
}

extension SportsSetupResult {
    var badmintonRules: RallyRuleSet {
        var rules = RallyRuleSet.badminton(
            maxSets: maxSets ?? 3,
            matchCompletionMode: matchCompletionMode ?? .bestOf
        )
        let target = max(1, pointsPerSet ?? 21)
        let coreType: ScoreCore.GameType = isSingles == false ? .badmintonDoubles : .badminton
        rules.pointsToWinSet = target
        rules.pointCap = RallyRuleSet.badmintonPointCap(for: target)
        rules.decidingSetSideSwitchPoint = RallyRuleSet.decidingSetSideSwitchPoint(
            for: coreType,
            pointsPerSet: target
        )
        rules.autoChangeSides = autoChangeSides ?? true
        return rules
    }

    var foosballRules: RallyRuleSet {
        var rules = RallyRuleSet.foosball(maxSets: maxSets ?? 3)
        rules.matchCompletionMode = matchCompletionMode ?? .bestOf
        let pointsToWin = max(1, pointsPerSet ?? targetScore ?? 5)
        rules.pointsToWinSet = pointsToWin
        rules.finalSetWinByTwo = winByTwo ?? false
        rules.finalSetPointCap = winByTwo == true
            ? scoreCap.flatMap { (pointsToWin...99).contains($0) ? $0 : nil }
            : nil
        return rules
    }
}
