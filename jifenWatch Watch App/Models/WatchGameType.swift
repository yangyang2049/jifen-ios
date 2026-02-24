import Foundation

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
            return "乒乓球"
        case .badminton:
            return "羽毛球"
        case .tennis:
            return "网球"
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
}
