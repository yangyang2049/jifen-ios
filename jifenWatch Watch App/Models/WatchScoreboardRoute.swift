import Foundation

enum WatchScoreboardRoute: Hashable, Identifiable {
    case pingpong(maxSets: Int)
    case badminton(maxSets: Int)
    case tennis(maxSets: Int)
    case pickleball(maxSets: Int)
    case archery
    case basketball(threeXThree: Bool)
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
        case .basketball(let threeXThree):
            return threeXThree ? "basketball-3x3" : "basketball-5x5"
        case .basketballTraining:
            return "basketballTraining"
        }
    }
}
