import Foundation
import RecordCore
import ScoreCore

enum WatchGameType: String, Codable, CaseIterable {
    /// Regulation basketball scoreboards are retained for phone-initiated linkage only.
    /// These cases exist so linked matches can be represented in local Watch records;
    /// they must not be added to `WatchHomeItem` or `WatchSetupSport`.
    case basketball
    case threeBasketball = "three_basketball"
    case pingpong
    case badminton
    case tennis
    case pickleball
    case archery
    case eightBall = "eight_ball"
    case nineBall = "nine_ball"
    case snooker
    /// Local watch-only tool; not transferred to phone (phone has no training scoreboard yet).
    case basketballTraining

    var displayName: String {
        switch self {
        case .basketball:
            return NSLocalizedString("game_basketball", value: "篮球", comment: "Basketball")
        case .threeBasketball:
            return NSLocalizedString("game_three_basketball", value: "三人篮球", comment: "3x3 Basketball")
        case .pingpong:
            return NSLocalizedString("game_pingpong", comment: "Ping Pong")
        case .badminton:
            return NSLocalizedString("game_badminton", comment: "Badminton")
        case .tennis:
            return NSLocalizedString("game_tennis", comment: "Tennis")
        case .pickleball:
            return NSLocalizedString("game_pickleball", comment: "Pickleball")
        case .archery:
            return NSLocalizedString("game_archery", comment: "Archery")
        case .eightBall:
            return NSLocalizedString("game_eight_ball", value: "黑八", comment: "Eight Ball")
        case .nineBall:
            return NSLocalizedString("game_nine_ball", value: "追分", comment: "Nine-ball Chase")
        case .snooker:
            return NSLocalizedString("game_snooker", value: "斯诺克", comment: "Snooker")
        case .basketballTraining:
            return NSLocalizedString("tool_basketball_training", comment: "Basketball Training")
        }
    }

    var icon: String {
        switch self {
        case .basketball, .threeBasketball:
            return "🏀"
        case .pingpong:
            return "🏓"
        case .badminton:
            return "🏸"
        case .tennis:
            return "🎾"
        case .pickleball:
            return "🏓"
        case .archery:
            return "🏹"
        case .eightBall, .nineBall, .snooker:
            return "🎱"
        case .basketballTraining:
            return "🏀"
        }
    }

    var scoreCoreGameType: GameType? {
        switch self {
        case .basketball: .basketball
        case .threeBasketball: .threeBasketball
        case .pingpong: .pingpong
        case .badminton: .badminton
        case .tennis: .tennis
        case .pickleball: .pickleball
        case .archery: .archeryDual
        case .eightBall: .eightBall
        case .nineBall: .nineBall
        case .snooker: .snooker
        case .basketballTraining: nil
        }
    }

    /// Uses point totals (not set scores) when rendering watch record list rows.
    var usesPointScoreInList: Bool {
        switch self {
        case .basketball, .threeBasketball, .basketballTraining, .eightBall, .nineBall, .snooker:
            return true
        default:
            return false
        }
    }
}
