import Foundation

enum WatchScoreboardRoute: Hashable, Identifiable {
    case pingpong(maxSets: Int)
    case badminton(maxSets: Int)
    case tennis(maxSets: Int)

    var id: String {
        switch self {
        case .pingpong(let maxSets):
            return "pingpong-\(maxSets)"
        case .badminton(let maxSets):
            return "badminton-\(maxSets)"
        case .tennis(let maxSets):
            return "tennis-\(maxSets)"
        }
    }
}
