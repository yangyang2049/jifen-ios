import Foundation

/// Wire statuses are mapped explicitly so new server values never appear as raw enums.
nonisolated enum GroupStatusText {
    private static var unknown: String { NSLocalizedString("unknown", value: "Unknown", comment: "") }

    static func joinAvailability(_ status: String) -> String {
        switch status {
        case "available": groupText("lookup_available", "Open")
        case "full": groupText("lookup_full_short", "Full")
        case "closed": groupText("lookup_closed_short", "Closed")
        case "archived": groupText("lookup_archived_short", "Archived")
        case "dissolving", "dissolved": groupText("lookup_closing_short", "Closing")
        case "pending_approval": groupText("lookup_pending_short", "Pending")
        case "already_member": groupText("lookup_member_short", "Joined")
        default: groupText("lookup_unavailable_short", "Unavailable")
        }
    }

    static func group(_ status: String) -> String {
        switch status {
        case "active": groupText("status_active", "Active")
        case "archived": groupText("archived", "Archived")
        case "dissolving": groupText("dissolving", "Dissolving")
        case "dissolved": groupText("dissolved", "Dissolved")
        default: unknown
        }
    }

    static func activity(_ status: String) -> String {
        switch status {
        case "recruiting": groupText("recruiting", "Open for sign-ups")
        case "in_progress": groupText("in_progress", "In progress")
        case "completed": groupText("completed", "Completed")
        case "cancelled": groupText("cancelled", "Cancelled")
        default: unknown
        }
    }

    static func result(_ status: String) -> String {
        switch status {
        case "pending_confirmation": groupText("pending_confirmation", "Waiting for confirmation")
        case "confirmed": groupText("confirmed", "Confirmed")
        case "disputed": groupText("disputed", "Disputed")
        case "voided": groupText("voided", "Voided")
        case "pending_upload": groupText("pending_upload", "Waiting to upload")
        default: unknown
        }
    }

    static func report(_ status: String) -> String {
        switch status {
        case "pending": groupText("report_status_pending", "Pending")
        case "reviewing", "processing": groupText("report_status_reviewing", "In review")
        case "resolved": groupText("report_status_resolved", "Resolved")
        case "dismissed": groupText("report_status_dismissed", "Dismissed")
        default: unknown
        }
    }

    static func joinRequest(_ status: String) -> String {
        switch status {
        case "pending": groupText("pending_approval", "Waiting for approval")
        case "rejected": groupText("reject", "Reject")
        default: unknown
        }
    }

    static func trainingSession(_ status: String) -> String {
        status == "scheduled" ? groupText("activity_status_scheduled", "Ready to start") : activity(status)
    }

    static func leaveNotice(_ status: String) -> String {
        switch status {
        case "open": groupText("report_status_pending", "Pending")
        case "seen": groupText("read_notices", "Read notifications")
        default: unknown
        }
    }
}

nonisolated extension ScoreGroup {
    var statusLabel: String { GroupStatusText.group(status) }
}
nonisolated extension GroupActivity {
    var statusLabel: String { GroupStatusText.activity(status) }
}
nonisolated extension GroupResult {
    var statusLabel: String { GroupStatusText.result(status) }
}
nonisolated extension GroupReportStatus {
    var statusLabel: String { GroupStatusText.report(status) }
}
