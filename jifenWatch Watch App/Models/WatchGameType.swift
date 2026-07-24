import Foundation
import RecordCore
import ScoreCore

enum WatchGameType: String, Codable, CaseIterable {
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
        case .basketballTraining, .eightBall, .nineBall, .snooker:
            return true
        default:
            return false
        }
    }
}
