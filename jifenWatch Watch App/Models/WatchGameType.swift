import Foundation
import RecordCore
import ScoreCore

enum WatchGameType: String, Codable, CaseIterable {
    /// Regulation basketball cases are retained only to decode and display historical records.
    /// New phone-initiated linkage must not originate these cases, and they must not be added
    /// to `WatchHomeItem` or `WatchSetupSport`.
    case basketball
    case threeBasketball = "three_basketball"
    case pingpong
    case badminton
    case shuttlecock
    case squash
    case foosball
    case tennis
    case pickleball
    case archery
    case eightBall = "eight_ball"
    case nineBall = "nine_ball"
    case snooker
    case football
    case football5v5 = "football_5v5"
    case basketballTraining
    /// 计数器工具的历史记录；仅手表本地保存，不回传手机（对齐鸿蒙 WatchCounter 的计数记录）。
    case counter

    init?(scoreCoreGameType gameType: ScoreCore.GameType) {
        switch gameType {
        case .pingpong, .pingpongDoubles: self = .pingpong
        case .badminton, .badmintonDoubles: self = .badminton
        case .tennis, .tennisDoubles: self = .tennis
        case .pickleball, .pickleballDoubles: self = .pickleball
        case .shuttlecock: self = .shuttlecock
        case .squash: self = .squash
        case .foosball, .foosballDoubles: self = .foosball
        case .archeryDual: self = .archery
        case .eightBall: self = .eightBall
        case .nineBall: self = .nineBall
        case .snooker: self = .snooker
        case .football: self = .football
        case .football5v5: self = .football5v5
        case .basketball: self = .basketball
        case .threeBasketball: self = .threeBasketball
        case .basketballTraining: self = .basketballTraining
        default: return nil
        }
    }

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
        case .shuttlecock:
            return NSLocalizedString("game_shuttlecock", value: "毽子", comment: "Shuttlecock")
        case .squash:
            return NSLocalizedString("game_squash", value: "壁球", comment: "Squash")
        case .foosball:
            return NSLocalizedString("game_foosball", value: "桌上足球", comment: "Foosball")
        case .tennis:
            return NSLocalizedString("game_tennis", comment: "Tennis")
        case .pickleball:
            return NSLocalizedString("game_pickleball", comment: "Pickleball")
        case .archery:
            return NSLocalizedString("game_archery", comment: "Archery")
        case .eightBall:
            return NSLocalizedString("game_eight_ball", value: "黑八", comment: "Eight Ball")
        case .nineBall:
            return NSLocalizedString("game_nine_ball", value: "Chase", comment: "Nine-ball Chase")
        case .snooker:
            return NSLocalizedString("game_snooker", value: "斯诺克", comment: "Snooker")
        case .football:
            return NSLocalizedString("game_football", value: "足球", comment: "Football")
        case .football5v5:
            return NSLocalizedString("game_football_5v5", value: "五人制足球", comment: "5×5 Football")
        case .basketballTraining:
            return NSLocalizedString("tool_basketball_training", comment: "Basketball Training")
        case .counter:
            return NSLocalizedString("game_counter", comment: "Counter")
        }
    }

    var icon: String {
        switch self {
        case .basketball, .threeBasketball:
            return "🏀"
        case .pingpong:
            return "🏓"
        case .badminton, .shuttlecock:
            return "🏸"
        case .squash:
            return "🎾"
        case .foosball:
            return "⚽"
        case .tennis:
            return "🎾"
        case .pickleball:
            return "🏓"
        case .archery:
            return "🏹"
        case .eightBall, .nineBall, .snooker:
            return "🎱"
        case .football, .football5v5:
            return "⚽"
        case .basketballTraining:
            return "🏀"
        case .counter:
            return "➕"
        }
    }

    var scoreCoreGameType: GameType? {
        switch self {
        case .basketball: .basketball
        case .threeBasketball: .threeBasketball
        case .pingpong: .pingpong
        case .badminton: .badminton
        case .shuttlecock: .shuttlecock
        case .squash: .squash
        case .foosball: .foosball
        case .tennis: .tennis
        case .pickleball: .pickleball
        case .archery: .archeryDual
        case .eightBall: .eightBall
        case .nineBall: .nineBall
        case .snooker: .snooker
        case .football: .football
        case .football5v5: .football5v5
        case .basketballTraining: .basketballTraining
        case .counter: nil
        }
    }

    /// Uses point totals (not set scores) when rendering watch record list rows.
    var usesPointScoreInList: Bool {
        switch self {
        case .basketball, .threeBasketball, .basketballTraining, .eightBall, .nineBall, .snooker,
             .football, .football5v5, .counter:
            return true
        default:
            return false
        }
    }
}
