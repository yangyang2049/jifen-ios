import Foundation
import LinkCore
import ScoreCore

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

extension WatchScoreboardRoute {
    init?(linkedSetup: LinkedScoreboardSetup) {
        switch linkedSetup.gameType {
        case .basketball:
            self = .basketball(threeXThree: linkedSetup.basketballThreeXThree)
        case .threeBasketball:
            self = .basketball(threeXThree: true)
        case .pingpong, .pingpongDoubles:
            self = .pingpong(maxSets: linkedSetup.maxSets ?? 5)
        case .badminton, .badmintonDoubles:
            self = .badminton(maxSets: linkedSetup.maxSets ?? 3)
        case .tennis, .tennisDoubles:
            self = .tennis(maxSets: linkedSetup.maxSets ?? 3)
        case .pickleball, .pickleballDoubles:
            self = .pickleball(maxSets: linkedSetup.maxSets ?? 3)
        default:
            return nil
        }
    }
}
