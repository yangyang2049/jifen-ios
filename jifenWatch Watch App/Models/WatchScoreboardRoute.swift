import Foundation
import LinkCore
import ScoreCore
import SessionCore

enum WatchScoreboardRoute: Hashable, Identifiable {
    case setup(sport: WatchSetupSport, playerCount: Int)
    case configured(WatchScoreboardLaunchConfig)
    case pingpong(maxSets: Int)
    case pingpongDoubles(maxSets: Int)
    case badminton(maxSets: Int)
    case badmintonDoubles(maxSets: Int)
    case tennis(maxSets: Int)
    case tennisDoubles(maxSets: Int)
    case pickleball(maxSets: Int)
    case pickleballDoubles(maxSets: Int)
    case archery
    case basketball(threeXThree: Bool)
    case basketballTraining(mode: WatchBasketballTrainingMode)
    case eightBall
    case nineBall
    case snooker

    var id: String {
        switch self {
        case .setup(let sport, let playerCount): return "setup-\(sport.rawValue)-\(playerCount)"
        case .configured(let config): return "configured-\(config.sport.rawValue)-\(config.hashValue)"
        case .pingpong(let maxSets): return "pingpong-\(maxSets)"
        case .pingpongDoubles(let maxSets): return "pingpong-d-\(maxSets)"
        case .badminton(let maxSets): return "badminton-\(maxSets)"
        case .badmintonDoubles(let maxSets): return "badminton-d-\(maxSets)"
        case .tennis(let maxSets): return "tennis-\(maxSets)"
        case .tennisDoubles(let maxSets): return "tennis-d-\(maxSets)"
        case .pickleball(let maxSets): return "pickleball-\(maxSets)"
        case .pickleballDoubles(let maxSets): return "pickleball-d-\(maxSets)"
        case .archery: return "archery"
        case .basketball(let threeXThree): return threeXThree ? "basketball-3x3" : "basketball-5v5"
        case .basketballTraining(let mode): return "basketballTraining-\(mode.rawValue)"
        case .eightBall: return "eightBall"
        case .nineBall: return "nineBall"
        case .snooker: return "snooker"
        }
    }
}

extension WatchScoreboardRoute {
    init?(resumeSession: WatchResumeSession) {
        switch resumeSession.payload {
        case .rally(let gameType, let bundle, _):
            let maxSets = bundle.currentSession.state.rules.maxSets
            switch gameType {
            case .pingpong: self = .pingpong(maxSets: maxSets)
            case .pingpongDoubles: self = .pingpongDoubles(maxSets: maxSets)
            case .badminton: self = .badminton(maxSets: maxSets)
            case .badmintonDoubles: self = .badmintonDoubles(maxSets: maxSets)
            case .pickleball: self = .pickleball(maxSets: maxSets)
            case .pickleballDoubles: self = .pickleballDoubles(maxSets: maxSets)
            default: return nil
            }
        case .tennis(let isDoubles, let bundle, _):
            let maxSets = bundle.currentSession.state.rules.maxSets
            self = isDoubles ? .tennisDoubles(maxSets: maxSets) : .tennis(maxSets: maxSets)
        case .basketball(let gameMode, _):
            self = .basketball(threeXThree: gameMode == .threeXThree)
        case .archery:
            self = .archery
        case .eightBall:
            self = .eightBall
        case .nineBall:
            self = .nineBall
        case .snooker:
            self = .snooker
        case .basketballTraining(let mode, _):
            self = .basketballTraining(mode: mode)
        }
    }

    init?(linkedSetup: LinkedScoreboardSetup) {
        switch linkedSetup.gameType {
        case .basketball:
            self = .basketball(threeXThree: linkedSetup.basketballThreeXThree)
        case .threeBasketball:
            self = .basketball(threeXThree: true)
        case .pingpong:
            self = .pingpong(maxSets: linkedSetup.maxSets ?? 5)
        case .pingpongDoubles:
            self = .pingpongDoubles(maxSets: linkedSetup.maxSets ?? 5)
        case .badminton:
            self = .badminton(maxSets: linkedSetup.maxSets ?? 3)
        case .badmintonDoubles:
            self = .badmintonDoubles(maxSets: linkedSetup.maxSets ?? 3)
        case .tennis:
            self = .tennis(maxSets: linkedSetup.maxSets ?? 3)
        case .tennisDoubles:
            self = .tennisDoubles(maxSets: linkedSetup.maxSets ?? 3)
        case .pickleball:
            self = .pickleball(maxSets: linkedSetup.maxSets ?? 3)
        case .pickleballDoubles:
            self = .pickleballDoubles(maxSets: linkedSetup.maxSets ?? 3)
        case .archeryDual:
            self = .archery
        case .eightBall:
            self = .eightBall
        case .nineBall:
            self = .nineBall
        case .snooker:
            self = .snooker
        default:
            return nil
        }
    }
}
