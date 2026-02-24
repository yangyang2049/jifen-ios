//
//  BoardTimerConfig.swift
//  jifen
//
//  Shared configuration model for Go/Xiangqi/Chess timers.
//

import Foundation

enum BoardTimerPresetMode: String, CaseIterable, Identifiable {
    case slow
    case fast
    case custom

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .slow:
            return NSLocalizedString("timer_mode_slow", value: "慢棋", comment: "Slow mode")
        case .fast:
            return NSLocalizedString("timer_mode_fast", value: "快棋", comment: "Fast mode")
        case .custom:
            return NSLocalizedString("timer_mode_custom", value: "自定义", comment: "Custom mode")
        }
    }
}

struct BoardTimerConfig: Equatable {
    var gameType: GameType
    var presetMode: BoardTimerPresetMode

    var mainMinutes: Int
    var mainSeconds: Int

    // Go only
    var byoyomiEnabled: Bool
    var byoyomiSeconds: Int
    var byoyomiPeriods: Int

    // Xiangqi / Chess
    var incrementEnabled: Bool
    var incrementSeconds: Int

    // Mirrors Harmony settings switches.
    var voiceEnabled: Bool
    var vibrationEnabled: Bool

    static func `default`(for gameType: GameType) -> BoardTimerConfig {
        switch gameType {
        case .go:
            return BoardTimerConfig(
                gameType: .go,
                presetMode: .fast,
                mainMinutes: 10,
                mainSeconds: 0,
                byoyomiEnabled: true,
                byoyomiSeconds: 30,
                byoyomiPeriods: 3,
                incrementEnabled: false,
                incrementSeconds: 0,
                voiceEnabled: true,
                vibrationEnabled: true
            )
        case .xiangqi:
            return BoardTimerConfig(
                gameType: .xiangqi,
                presetMode: .fast,
                mainMinutes: 10,
                mainSeconds: 0,
                byoyomiEnabled: false,
                byoyomiSeconds: 0,
                byoyomiPeriods: 0,
                incrementEnabled: true,
                incrementSeconds: 10,
                voiceEnabled: true,
                vibrationEnabled: true
            )
        case .chess:
            return BoardTimerConfig(
                gameType: .chess,
                presetMode: .fast,
                mainMinutes: 15,
                mainSeconds: 0,
                byoyomiEnabled: false,
                byoyomiSeconds: 0,
                byoyomiPeriods: 0,
                incrementEnabled: true,
                incrementSeconds: 10,
                voiceEnabled: true,
                vibrationEnabled: true
            )
        default:
            return BoardTimerConfig(
                gameType: gameType,
                presetMode: .fast,
                mainMinutes: 10,
                mainSeconds: 0,
                byoyomiEnabled: false,
                byoyomiSeconds: 0,
                byoyomiPeriods: 0,
                incrementEnabled: false,
                incrementSeconds: 0,
                voiceEnabled: true,
                vibrationEnabled: true
            )
        }
    }

    var totalMainSeconds: Double {
        Double(max(0, mainMinutes) * 60 + max(0, min(59, mainSeconds)))
    }

    mutating func applyPreset(_ mode: BoardTimerPresetMode) {
        presetMode = mode
        guard mode != .custom else { return }

        switch gameType {
        case .go:
            if mode == .slow {
                mainMinutes = 120
                mainSeconds = 0
                byoyomiEnabled = true
                byoyomiSeconds = 60
                byoyomiPeriods = 5
            } else {
                mainMinutes = 10
                mainSeconds = 0
                byoyomiEnabled = true
                byoyomiSeconds = 30
                byoyomiPeriods = 3
            }
            incrementEnabled = false
            incrementSeconds = 0

        case .xiangqi:
            if mode == .slow {
                mainMinutes = 120
                mainSeconds = 0
                incrementEnabled = true
                incrementSeconds = 30
            } else {
                mainMinutes = 10
                mainSeconds = 0
                incrementEnabled = true
                incrementSeconds = 10
            }
            byoyomiEnabled = false
            byoyomiSeconds = 0
            byoyomiPeriods = 0

        case .chess:
            if mode == .slow {
                mainMinutes = 120
                mainSeconds = 0
                incrementEnabled = true
                incrementSeconds = 30
            } else {
                mainMinutes = 15
                mainSeconds = 0
                incrementEnabled = true
                incrementSeconds = 10
            }
            byoyomiEnabled = false
            byoyomiSeconds = 0
            byoyomiPeriods = 0

        default:
            break
        }
    }

    mutating func normalizeInput() {
        mainMinutes = max(0, mainMinutes)
        mainSeconds = max(0, min(59, mainSeconds))

        if mainMinutes == 0 && mainSeconds < 30 {
            mainSeconds = 30
        }

        byoyomiSeconds = max(0, byoyomiSeconds)
        byoyomiPeriods = max(0, byoyomiPeriods)
        incrementSeconds = max(0, incrementSeconds)

        if gameType == .go {
            if !byoyomiEnabled {
                byoyomiSeconds = 0
                byoyomiPeriods = 0
            } else {
                if byoyomiSeconds == 0 { byoyomiSeconds = 30 }
                if byoyomiPeriods == 0 { byoyomiPeriods = 3 }
            }
        } else {
            if !incrementEnabled {
                incrementSeconds = 0
            } else if incrementSeconds == 0 {
                incrementSeconds = 10
            }
        }
    }
}
