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
    case shuttlecock(maxSets: Int)
    case squash(maxSets: Int)
    case foosball(maxSets: Int)
    case foosballDoubles(maxSets: Int)
    case archery
    case basketballTraining(mode: WatchBasketballTrainingMode)
    case eightBall
    case nineBall
    case snooker
    case football(halfLengthSeconds: Int)
    case football5v5(halfLengthSeconds: Int)

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
        case .shuttlecock(let maxSets): return "shuttlecock-\(maxSets)"
        case .squash(let maxSets): return "squash-\(maxSets)"
        case .foosball(let maxSets): return "foosball-\(maxSets)"
        case .foosballDoubles(let maxSets): return "foosball-d-\(maxSets)"
        case .archery: return "archery"
        case .basketballTraining(let mode): return "basketballTraining-\(mode.rawValue)"
        case .eightBall: return "eightBall"
        case .nineBall: return "nineBall"
        case .snooker: return "snooker"
        case .football(let halfLengthSeconds): return "football-\(halfLengthSeconds)"
        case .football5v5(let halfLengthSeconds): return "football5v5-\(halfLengthSeconds)"
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
            case .shuttlecock: self = .shuttlecock(maxSets: maxSets)
            case .squash: self = .squash(maxSets: maxSets)
            case .foosball: self = .foosball(maxSets: maxSets)
            case .foosballDoubles: self = .foosballDoubles(maxSets: maxSets)
            default: return nil
            }
        case .tennis(let isDoubles, let bundle, _):
            let maxSets = bundle.currentSession.state.rules.maxSets
            self = isDoubles ? .tennisDoubles(maxSets: maxSets) : .tennis(maxSets: maxSets)
        case .archery:
            self = .archery
        case .eightBall:
            self = .eightBall
        case .nineBall:
            self = .nineBall
        case .snooker:
            self = .snooker
        case .football(let isFiveAside, let state, _, _, _):
            let halfLengthSeconds = max(60, state.clock.halfLengthSeconds)
            self = isFiveAside
                ? .football5v5(halfLengthSeconds: halfLengthSeconds)
                : .football(halfLengthSeconds: halfLengthSeconds)
        case .basketballTraining(let mode, _, _):
            self = .basketballTraining(mode: mode)
        }
    }

    init?(linkedSetup: LinkedScoreboardSetup) {
        switch linkedSetup.gameType {
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
        case .shuttlecock:
            self = .shuttlecock(maxSets: linkedSetup.maxSets ?? 3)
        case .squash:
            self = .squash(maxSets: linkedSetup.maxSets ?? 5)
        case .foosball:
            self = .foosball(maxSets: linkedSetup.maxSets ?? 3)
        case .foosballDoubles:
            self = .foosballDoubles(maxSets: linkedSetup.maxSets ?? 3)
        case .archeryDual:
            self = .archery
        case .eightBall:
            self = .eightBall
        case .nineBall:
            self = .nineBall
        case .snooker:
            self = .snooker
        case .basketballTraining:
            guard let state = linkedSetup.initialSnapshot?.basketballTrainingState else { return nil }
            self = .basketballTraining(mode: WatchBasketballTrainingMode(linkedMode: state.mode))
        case .football:
            let halfLength = max(60, linkedSetup.initialSnapshot?.footballState?.timer.halfLengthSeconds ?? 45 * 60)
            self = .football(halfLengthSeconds: halfLength)
        case .football5v5:
            let halfLength = max(60, linkedSetup.initialSnapshot?.footballState?.timer.halfLengthSeconds ?? 20 * 60)
            self = .football5v5(halfLengthSeconds: halfLength)
        default:
            return nil
        }
    }
}
