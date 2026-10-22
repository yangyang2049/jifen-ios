import Foundation

nonisolated enum GroupNoticeTarget: Equatable, Sendable {
    case group(tab: Int), activity(String), result(String), message

    static func resolve(kind: String, resourceID: String?) -> Self {
        let id = resourceID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch kind {
        case "member_removed", "join_rejected": return .message
        case "join_requested", "role_changed", "ownership_transferred": return .group(tab: 3)
        case "training_published", "training_changed", "training_cancelled", "leave_changed": return .group(tab: 1)
        case "activity_created", "activity_changed", "activity_cancelled": return id.isEmpty ? .group(tab: 0) : .activity(id)
        case "result_pending", "result_confirmed", "result_voided": return id.isEmpty ? .group(tab: 0) : .result(id)
        default: return .group(tab: 0)
        }
    }
}

nonisolated extension GroupNotification {
    var navigationTarget: GroupNoticeTarget { .resolve(kind: kind, resourceID: resourceId) }
}
