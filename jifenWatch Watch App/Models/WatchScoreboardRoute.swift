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
    case basketballTraining(mode: ShotTrainingMode)
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
        case .football(let isFiveAside, let bundle):
            let halfLengthSeconds = max(60, bundle.currentSession.state.timer.halfLengthSeconds)
            self = isFiveAside
                ? .football5v5(halfLengthSeconds: halfLengthSeconds)
                : .football(halfLengthSeconds: halfLengthSeconds)
        case .basketballTraining(let bundle):
            self = .basketballTraining(mode: bundle.currentSession.state.mode)
        }
    }

    init?(linkedSetup: LinkedScoreboardSetup) {
        guard let sport = WatchSportRegistry.descriptor(for: linkedSetup.gameType),
              WatchSportRegistry.isValidLinkedSetup(linkedSetup) else { return nil }
        let maxSets = linkedSetup.maxSets ?? sport.defaultMaxSets

        switch (linkedSetup.gameType, maxSets) {
        case (.pingpong, let sets?):
            self = .pingpong(maxSets: sets)
        case (.pingpongDoubles, let sets?):
            self = .pingpongDoubles(maxSets: sets)
        case (.badminton, let sets?):
            self = .badminton(maxSets: sets)
        case (.badmintonDoubles, let sets?):
            self = .badmintonDoubles(maxSets: sets)
        case (.tennis, let sets?):
            self = .tennis(maxSets: sets)
        case (.tennisDoubles, let sets?):
            self = .tennisDoubles(maxSets: sets)
        case (.pickleball, let sets?):
            self = .pickleball(maxSets: sets)
        case (.pickleballDoubles, let sets?):
            self = .pickleballDoubles(maxSets: sets)
        case (.shuttlecock, let sets?):
            self = .shuttlecock(maxSets: sets)
        case (.squash, let sets?):
            self = .squash(maxSets: sets)
        case (.foosball, let sets?):
            self = .foosball(maxSets: sets)
        case (.foosballDoubles, let sets?):
            self = .foosballDoubles(maxSets: sets)
        case (.archeryDual, _):
            self = .archery
        case (.eightBall, _):
            self = .eightBall
        case (.nineBall, _):
            self = .nineBall
        case (.snooker, _):
            self = .snooker
        case (.basketballTraining, _):
            guard let state = linkedSetup.initialSnapshot?.basketballTrainingState else { return nil }
            self = .basketballTraining(mode: state.mode)
        case (.football, _), (.football5v5, _):
            guard let length = linkedSetup.initialSnapshot?.footballState?.timer.halfLengthSeconds
                ?? sport.defaultFootballHalfLengthSeconds else { return nil }
            let halfLength = max(60, length)
            self = linkedSetup.gameType == .football5v5
                ? .football5v5(halfLengthSeconds: halfLength)
                : .football(halfLengthSeconds: halfLength)
        default:
            return nil
        }
    }
}
