//
//  ScoreboardMenuConfirmState.swift
//  jifen
//
//  Scoreboard menu secondary-confirm state — aligned with HarmonyOS
//  ScoreboardMenuConfirmState (no auto-timeout; green until second tap /
//  other action / menu close).
//

import Foundation

enum ScoreboardMenuConfirmAction: String, Equatable {
    case reset
    case finish
    case settleMatch
    case exchangeSide
    case exit

    static func fromMenuAction(_ action: String) -> ScoreboardMenuConfirmAction? {
        switch action {
        case "reset": return .reset
        case "endGame", "finish": return .finish
        case "settleMatch": return .settleMatch
        case "exchangeSide": return .exchangeSide
        case "exit": return .exit
        default: return nil
        }
    }

    var toastKey: String {
        switch self {
        case .reset: return "click_again_to_reset"
        case .finish: return "click_again_to_finish"
        case .settleMatch: return "click_again_to_settle_match"
        case .exchangeSide: return "click_again_to_exchange_sides"
        case .exit: return "press_again_to_exit"
        }
    }

    var toastFallback: String {
        switch self {
        case .reset: return "再次点击重置"
        case .finish: return "再点一次结束比赛"
        case .settleMatch: return "再点一次结算比赛"
        case .exchangeSide: return "再次点击确认换边"
        case .exit: return "再按一次退出"
        }
    }

    var localizedToast: String {
        NSLocalizedString(toastKey, value: toastFallback, comment: "")
    }
}

/// Single pending confirm at a time. First tap arms (button turns green + toast);
/// second tap on the same action executes.
struct ScoreboardMenuConfirmState: Equatable {
    private(set) var pending: ScoreboardMenuConfirmAction?

    var resetConfirming: Bool { pending == .reset }
    var exchangeConfirming: Bool { pending == .exchangeSide }
    var finishConfirming: Bool { pending == .finish }
    var settleConfirming: Bool { pending == .settleMatch }
    var exitConfirming: Bool { pending == .exit }

    mutating func clear() {
        pending = nil
    }

    /// Clear pending when the user taps a different menu action.
    mutating func prepare(forMenuAction action: String) {
        guard let confirm = ScoreboardMenuConfirmAction.fromMenuAction(action) else {
            pending = nil
            return
        }
        if pending != confirm {
            pending = nil
        }
    }

    /// - Returns: `true` if this is the confirming (second) tap and the action should run.
    mutating func armOrConfirm(_ action: ScoreboardMenuConfirmAction) -> Bool {
        if pending == action {
            pending = nil
            return true
        }
        pending = action
        return false
    }
}
