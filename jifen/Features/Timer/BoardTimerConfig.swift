//
//  BoardTimerConfig.swift
//  jifen
//
//  Board-game timer config aligned with Harmony boardTimerConfigHelper.
//

import Foundation

/// Current-language defaults for new board-timer sessions. Records keep their saved labels.
enum BoardTimerParticipantNames {
    static func name(for gameType: GameType, playerID: Int, bundle: Bundle = .main) -> String {
        if let key = nameKey(for: gameType, playerID: playerID) {
            return bundle.localizedString(forKey: key, value: englishNames[key], table: nil)
        }
        let player = bundle.localizedString(forKey: "dual_timer_player", value: "Player", table: nil)
        return "\(player) \(playerID)"
    }

    private static func nameKey(for gameType: GameType, playerID: Int) -> String? {
        guard (1...2).contains(playerID) else { return nil }
        switch gameType {
        case .go: return playerID == 1 ? "timer_black_player" : "timer_white_player"
        case .xiangqi, .checkers: return playerID == 1 ? "timer_red_player" : "timer_black_player"
        case .chess: return playerID == 1 ? "timer_white_player" : "timer_black_player"
        default: return nil
        }
    }

    private static let englishNames = [
        "timer_black_player": "Black", "timer_white_player": "White", "timer_red_player": "Red"
    ]
}

enum BoardTimeMode: String, CaseIterable, Identifiable, Equatable {
    case countdown
    case increment
    case byoyomi
    case delay

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .countdown:
            return NSLocalizedString("timer_mode_countdown", value: "包干", comment: "Absolute / sudden death")
        case .increment:
            return NSLocalizedString("timer_increment", value: "加秒", comment: "Increment")
        case .byoyomi:
            return NSLocalizedString("timer_byoyomi", value: "读秒", comment: "Byoyomi")
        case .delay:
            return NSLocalizedString("timer_mode_delay", value: "延迟", comment: "Delay")
        }
    }
}

struct BoardTimerConfig: Equatable {
    var gameType: GameType
    var timeMode: BoardTimeMode

    var mainMinutes: Int
    var mainSeconds: Int

    var incrementSeconds: Int
    var byoyomiSeconds: Int
    var byoyomiPeriods: Int
    var delaySeconds: Int

    var voiceEnabled: Bool
    var vibrationEnabled: Bool

    static let minMainTimeSeconds = 30

    static func availableModes(for gameType: GameType) -> [BoardTimeMode] {
        switch gameType {
        case .go:
            return [.countdown, .byoyomi]
        case .chess:
            return [.countdown, .increment, .delay]
        case .xiangqi, .checkers:
            return [.countdown, .increment]
        default:
            return [.countdown, .increment]
        }
    }

    static func defaultMode(for gameType: GameType) -> BoardTimeMode {
        gameType == .go ? .byoyomi : .increment
    }

    static func `default`(for gameType: GameType) -> BoardTimerConfig {
        modeDefaults(for: gameType, mode: defaultMode(for: gameType))
    }

    /// Defaults when switching to a mode (Harmony `getBoardTimerModeDefaults`).
    static func modeDefaults(for gameType: GameType, mode: BoardTimeMode) -> BoardTimerConfig {
        let resolved = availableModes(for: gameType).contains(mode) ? mode : defaultMode(for: gameType)
        let values = defaultValues(for: gameType, mode: resolved)
        return BoardTimerConfig(
            gameType: gameType,
            timeMode: resolved,
            mainMinutes: values.mainMinutes,
            mainSeconds: values.mainSeconds,
            incrementSeconds: values.incrementSeconds,
            byoyomiSeconds: values.byoyomiSeconds,
            byoyomiPeriods: values.byoyomiPeriods,
            delaySeconds: values.delaySeconds,
            voiceEnabled: true,
            vibrationEnabled: true
        )
    }

    var totalMainSeconds: Double {
        Double(max(0, mainMinutes) * 60 + max(0, min(59, mainSeconds)))
    }

    /// Apply mode switch fill rules (Harmony `onTimeModeChange`).
    mutating func applyTimeMode(_ mode: BoardTimeMode) {
        guard BoardTimerConfig.availableModes(for: gameType).contains(mode) else { return }
        timeMode = mode
        let defaults = BoardTimerConfig.modeDefaults(for: gameType, mode: mode)
        switch mode {
        case .increment:
            if incrementSeconds <= 0 {
                incrementSeconds = max(1, defaults.incrementSeconds)
            }
        case .byoyomi:
            if byoyomiSeconds <= 0 {
                byoyomiSeconds = max(1, defaults.byoyomiSeconds)
            }
            if byoyomiPeriods <= 0 {
                byoyomiPeriods = max(1, defaults.byoyomiPeriods)
            }
        case .delay:
            if delaySeconds <= 0 {
                delaySeconds = max(1, defaults.delaySeconds)
            }
        case .countdown:
            break
        }
        normalize()
    }

    /// Harmony `normalizeBoardTimerSettings` + `resolveTimeMode`.
    mutating func normalize() {
        timeMode = resolvedTimeMode()

        mainMinutes = max(0, mainMinutes)
        mainSeconds = max(0, min(59, mainSeconds))
        if mainMinutes == 0 && mainSeconds < Self.minMainTimeSeconds {
            mainSeconds = Self.minMainTimeSeconds
        }

        delaySeconds = max(0, delaySeconds)

        switch timeMode {
        case .byoyomi:
            incrementSeconds = 0
            byoyomiSeconds = max(0, byoyomiSeconds)
            byoyomiPeriods = max(0, byoyomiPeriods)
            delaySeconds = 0
        case .increment:
            incrementSeconds = max(0, incrementSeconds)
            byoyomiSeconds = 0
            byoyomiPeriods = 0
            delaySeconds = 0
        case .delay:
            incrementSeconds = 0
            byoyomiSeconds = 0
            byoyomiPeriods = 0
            delaySeconds = max(0, delaySeconds)
        case .countdown:
            incrementSeconds = 0
            byoyomiSeconds = 0
            byoyomiPeriods = 0
            delaySeconds = 0
        }
    }

    private func resolvedTimeMode() -> BoardTimeMode {
        guard BoardTimerConfig.availableModes(for: gameType).contains(timeMode) else {
            return BoardTimerConfig.defaultMode(for: gameType)
        }

        switch gameType {
        case .go:
            if timeMode == .byoyomi && byoyomiSeconds > 0 && byoyomiPeriods > 0 {
                return .byoyomi
            }
            return .countdown
        case .chess:
            if timeMode == .delay && delaySeconds > 0 {
                return .delay
            }
            if timeMode == .increment && incrementSeconds > 0 {
                return .increment
            }
            return .countdown
        default:
            if timeMode == .increment && incrementSeconds > 0 {
                return .increment
            }
            return .countdown
        }
    }

    private struct ValueFields {
        var mainMinutes: Int
        var mainSeconds: Int
        var incrementSeconds: Int
        var byoyomiSeconds: Int
        var byoyomiPeriods: Int
        var delaySeconds: Int
    }

    private static func defaultValues(for gameType: GameType, mode: BoardTimeMode) -> ValueFields {
        switch gameType {
        case .go:
            if mode == .byoyomi {
                return ValueFields(mainMinutes: 60, mainSeconds: 0, incrementSeconds: 0, byoyomiSeconds: 30, byoyomiPeriods: 3, delaySeconds: 0)
            }
            return ValueFields(mainMinutes: 60, mainSeconds: 0, incrementSeconds: 0, byoyomiSeconds: 0, byoyomiPeriods: 0, delaySeconds: 0)

        case .xiangqi:
            if mode == .increment {
                return ValueFields(mainMinutes: 10, mainSeconds: 0, incrementSeconds: 10, byoyomiSeconds: 0, byoyomiPeriods: 0, delaySeconds: 0)
            }
            return ValueFields(mainMinutes: 10, mainSeconds: 0, incrementSeconds: 0, byoyomiSeconds: 0, byoyomiPeriods: 0, delaySeconds: 0)

        case .chess:
            if mode == .delay {
                return ValueFields(mainMinutes: 15, mainSeconds: 0, incrementSeconds: 0, byoyomiSeconds: 0, byoyomiPeriods: 0, delaySeconds: 5)
            }
            if mode == .increment {
                return ValueFields(mainMinutes: 15, mainSeconds: 0, incrementSeconds: 10, byoyomiSeconds: 0, byoyomiPeriods: 0, delaySeconds: 0)
            }
            return ValueFields(mainMinutes: 15, mainSeconds: 0, incrementSeconds: 0, byoyomiSeconds: 0, byoyomiPeriods: 0, delaySeconds: 0)

        case .checkers:
            if mode == .increment {
                return ValueFields(mainMinutes: 15, mainSeconds: 0, incrementSeconds: 10, byoyomiSeconds: 0, byoyomiPeriods: 0, delaySeconds: 0)
            }
            return ValueFields(mainMinutes: 15, mainSeconds: 0, incrementSeconds: 0, byoyomiSeconds: 0, byoyomiPeriods: 0, delaySeconds: 0)

        default:
            return ValueFields(mainMinutes: 10, mainSeconds: 0, incrementSeconds: 0, byoyomiSeconds: 0, byoyomiPeriods: 0, delaySeconds: 0)
        }
    }
}
