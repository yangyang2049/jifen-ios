//
//  ScoreboardMenuConfirmState.swift
//  jifen
//
//  Scoreboard menu secondary-confirm state — aligned with HarmonyOS
//  ScoreboardMenuConfirmState (two-second confirmation window).
//

import Foundation
import Observation

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
        case ScoreboardMenuActionID.exchangeSide.rawValue: return .exchangeSide
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

    var localizedToast: String {
        NSLocalizedString(toastKey, comment: "Scoreboard menu confirmation toast")
    }
}

/// Single pending confirm at a time. First tap arms (button turns green + toast);
/// second tap on the same action executes. Auto-clears after 2 seconds.
@MainActor
@Observable
final class ScoreboardMenuConfirmState {
    private(set) var pending: ScoreboardMenuConfirmAction?
    @ObservationIgnored private let confirmationDuration: Duration
    private var dismissTask: Task<Void, Never>?

    init(confirmationDuration: Duration = .seconds(2)) {
        self.confirmationDuration = confirmationDuration
    }

    var resetConfirming: Bool { pending == .reset }
    var exchangeConfirming: Bool { pending == .exchangeSide }
    var finishConfirming: Bool { pending == .finish }
    var settleConfirming: Bool { pending == .settleMatch }
    var exitConfirming: Bool { pending == .exit }

    func clear() {
        pending = nil
        dismissTask?.cancel()
        dismissTask = nil
    }

    /// Clear pending when the user taps a different menu action.
    func prepare(forMenuAction action: String) {
        guard let confirm = ScoreboardMenuConfirmAction.fromMenuAction(action) else {
            pending = nil
            dismissTask?.cancel()
            dismissTask = nil
            return
        }
        if pending != confirm {
            pending = nil
            dismissTask?.cancel()
            dismissTask = nil
        }
    }

    /// - Returns: `true` if this is the confirming (second) tap and the action should run.
    func armOrConfirm(_ action: ScoreboardMenuConfirmAction) -> Bool {
        if pending == action {
            pending = nil
            dismissTask?.cancel()
            dismissTask = nil
            return true
        }
        pending = action
        dismissTask?.cancel()
        dismissTask = Task { [weak self, confirmationDuration] in
            do {
                try await Task.sleep(for: confirmationDuration)
            } catch {
                return
            }
            self?.pending = nil
        }
        return false
    }
}

/// Holds a terminal score snapshot for a short, cancellable presentation phase.
/// The scoring engine may already have advanced; views keep rendering `value`
/// until the release callback atomically reveals the next period.
@MainActor
@Observable
final class ScoreboardTerminalHold<Value> {
    private(set) var value: Value?
    @ObservationIgnored private let duration: Duration
    @ObservationIgnored private var releaseTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(duration: Duration = .seconds(1)) {
        self.duration = duration
    }

    // Keep destruction out of the Release inliner. Swift 6.3.3 can otherwise
    // crash while optimizing the synthesized generic deinitializer.
    @inline(never)
    deinit {
        releaseTask?.cancel()
    }

    func begin(_ value: Value, onRelease: @escaping @MainActor () -> Void) {
        generation += 1
        let expectedGeneration = generation
        releaseTask?.cancel()
        self.value = value
        releaseTask = Task { [weak self, duration] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            guard let self, self.generation == expectedGeneration else { return }
            self.value = nil
            self.releaseTask = nil
            onRelease()
        }
    }

    func cancel() {
        generation += 1
        releaseTask?.cancel()
        releaseTask = nil
        value = nil
    }
}
