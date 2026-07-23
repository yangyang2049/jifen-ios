import Foundation
import RecordCore
import ScoreCore

enum WatchGameType: String, Codable, CaseIterable {
    case pingpong
    case badminton
    case tennis
    case pickleball
    case archery
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
            return "🎾"
        case .archery:
            return "🏹"
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
        case .basketballTraining: nil
        }
    }
}
