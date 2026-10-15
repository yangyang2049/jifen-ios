import Foundation

nonisolated func groupErrorMessage(_ error: Error) -> String {
    if let context = error as? APIClientServerContextError { return groupErrorMessage(context.underlying) }
    guard case APIClientError.server(_, let code, let message, _) = error else { return error.localizedDescription }
    let keys = [
        "GROUP_NOT_FOUND": "lookup_not_found", "INVALID_GROUP_NUMBER": "invalid_qr",
        "GROUP_FULL": "unavailable", "GROUP_JOIN_CLOSED": "unavailable", "GROUP_ARCHIVED": "archive_readonly",
        "GROUP_DISSOLVING": "dissolving", "REVISION_CONFLICT": "reload_version", "REVISION_REQUIRED": "reload_version",
        "INVALID_RULES": "invalid_rules", "INVALID_RESULT": "invalid_result", "INVALID_MATCH_RESULT": "invalid_result",
        "INVALID_SET_SCORE": "invalid_result", "INVALID_SET_DETAILS": "invalid_result", "LINEUP_CONFLICT": "lineup_conflict",
        "MEMBER_SESSION_LIMIT": "lineup_member_limit", "INVALID_LINEUP": "lineup_invalid", "GAME_EXISTS": "frozen_match_hint",
        "GAME_NOT_FOUND": "game_unavailable", "GAME_ABANDONED": "game_unavailable", "ACTIVITY_SESSION_REQUIRED": "activity_lineup",
        "ACTIVITY_NOT_OPEN": "unavailable", "REGISTRATION_CLOSED": "registration_closes", "ACTION_DISABLED": "capabilities_missing",
        "INVALID_TEMPORARY_NAME": "invalid_member_name",
        // ---- 安卓 2026-10-14 新增：防刷配额与限流（GroupUi.kt GroupErrors.codeRes）----
        "RATE_LIMITED": "rate_limited", "TOO_MANY_REQUESTS": "rate_limited",
        "CREATE_GROUP_DAILY_LIMIT": "create_daily_limit", "JOIN_DAILY_LIMIT": "join_daily_limit",
        "PENDING_REQUEST_LIMIT": "pending_request_limit", "JOIN_REQUEST_DAILY_LIMIT": "request_daily_limit",
        "JOIN_REQUEST_COOLDOWN": "join_cooldown",
        "RESULT_GROUP_DAILY_LIMIT": "result_group_daily_limit", "RESULT_SUBMITTER_DAILY_LIMIT": "result_submitter_daily_limit",
        // ---- 训练组 / 教练排期（PRD §6.14）----
        "NOT_COACH": "not_coach"
    ]
    if let key = code.flatMap({ keys[$0] }) { return groupText(key, message ?? key) }
    if Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en").language.languageCode?.identifier == "zh", let message { return message }
    return NSLocalizedString("network_request_failed", value: "Request failed. Please try again.", comment: "")
}
