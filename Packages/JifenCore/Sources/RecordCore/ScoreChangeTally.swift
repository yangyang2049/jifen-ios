private let scoreAdjustmentOperationCodes: Set<String> = [
    "adjust_points", "adjust_sets", "edit_score",
    "archery_adjust_arrow_sum", "archery_adjust_set_points",
    "eight_ball_admin_adjust", "nine_ball_adjust_total", "snooker_admin_correct"
]

public extension Sequence where Element == DetailedScoreAction {
    /// Counts score changes with the standalone Watch record's rules.
    /// Legacy actions may omit the delta. Only an explicit zero is excluded,
    /// except for archery attempts, which count even when they score zero.
    var scoreChangeCount: Int {
        reduce(into: 0) { count, action in
            switch action.type {
            case .scoreChanged:
                if action.scoreChange != 0
                    || action.operationCode == "archery_arrow"
                    || action.operationCode == "archery_miss" {
                    count += 1
                }
            case .stateChanged:
                if action.scoreChange != 0, let code = action.operationCode,
                   scoreAdjustmentOperationCodes.contains(code) {
                    count += 1
                }
            case .foul:
                if action.scoreChange != 0, action.operationCode?.hasPrefix("basketball_") != true {
                    count += 1
                }
            default:
                break
            }
        }
    }
}
