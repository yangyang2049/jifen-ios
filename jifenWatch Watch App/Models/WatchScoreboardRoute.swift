import Foundation

enum WatchScoreboardRoute: Hashable, Identifiable {
    case pingpong(maxSets: Int)
    case badminton(maxSets: Int)
    case tennis(maxSets: Int)
    case pickleball(maxSets: Int)
    case archery
    case basketballTraining

    var id: String {
        switch self {
        case .pingpong(let maxSets):
            return "pingpong-\(maxSets)"
        case .badminton(let maxSets):
            return "badminton-\(maxSets)"
        case .tennis(let maxSets):
            return "tennis-\(maxSets)"
        case .pickleball(let maxSets):
            return "pickleball-\(maxSets)"
        case .archery:
            return "archery"
        case .basketballTraining:
            return "basketballTraining"
        }
    }
}
