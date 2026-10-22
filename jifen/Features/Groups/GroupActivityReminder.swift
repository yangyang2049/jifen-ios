import Foundation
import Observation
import UserNotifications

nonisolated struct GroupReminderDestination: Identifiable, Equatable, Sendable {
    var id = UUID(); var accountID: String; var groupID: String; var activityID: String
}

@MainActor @Observable final class GroupActivityReminder {
    static let shared = GroupActivityReminder()
    var destination: GroupReminderDestination?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private struct Reminder: Codable {
        var accountID: String; var groupID: String; var activityID: String
        var title: String; var place: String; var startsAt: Int64
        var identifier: String { "group.activity." + Data("\(accountID):\(groupID):\(activityID)".utf8).base64EncodedString() }
    }
    private var rows: [Reminder] {
        get { (defaults.data(forKey: "groups.activityReminders").flatMap { try? JSONDecoder().decode([Reminder].self, from: $0) }) ?? [] }
        set { if let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: "groups.activityReminders") } }
    }
    func enabled(accountID: String, activityID: String) -> Bool { rows.contains { $0.accountID == accountID && $0.activityID == activityID } }
    func set(enabled: Bool, accountID: String, groupID: String, activity: GroupActivity) async throws {
        let store = GroupStore.shared, revision = GroupStore.shared.identityRevision
        guard store.accountID == accountID else { throw GroupFlowError.staleSession }
        let center = UNUserNotificationCenter.current()
        let row = Reminder(accountID: accountID, groupID: groupID, activityID: activity.id, title: activity.title, place: activity.place, startsAt: activity.startsAt)
        if enabled {
            guard activity.registrationOpen || activity.status == "recruiting" else { return }
            let settings = await center.notificationSettings()
            let granted = settings.authorizationStatus == .notDetermined ? try await center.requestAuthorization(options: [.alert, .sound]) : [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
            guard granted else { throw ReminderError.permission }
            guard store.matchesIdentity(accountID, revision: revision), SessionStore.shared.user?.id == accountID else { throw GroupFlowError.staleSession }
            let fire = Date(timeIntervalSince1970: Double(row.startsAt) / 1000 - 900)
            guard fire > Date() else { throw ReminderError.tooLate }
            try await schedule(row)
            guard store.matchesIdentity(accountID, revision: revision) else { center.removePendingNotificationRequests(withIdentifiers: [row.identifier]); throw GroupFlowError.staleSession }
            var current = rows; current.removeAll { $0.accountID == accountID && $0.activityID == activity.id }; current.append(row); rows = current
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [row.identifier])
            rows.removeAll { $0.accountID == accountID && $0.activityID == activity.id }
        }
    }
    private func schedule(_ row: Reminder) async throws {
        let store = GroupStore.shared, revision = GroupStore.shared.identityRevision
        guard store.accountID == row.accountID else { throw GroupFlowError.staleSession }
        let fire = Date(timeIntervalSince1970: Double(row.startsAt) / 1000 - 900)
        guard fire > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = row.title; content.body = groupText("reminder_body", "Your activity starts in 15 minutes.") + " " + row.place; content.sound = .default
        content.userInfo = ["groupAccountID": row.accountID, "groupID": row.groupID, "groupActivityID": row.activityID]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, fire.timeIntervalSinceNow), repeats: false)
        try await UNUserNotificationCenter.current().add(.init(identifier: row.identifier, content: content, trigger: trigger))
        guard store.matchesIdentity(row.accountID, revision: revision) else { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [row.identifier]); throw GroupFlowError.staleSession }
    }
    func synchronize(accountID: String, group: ScoreGroup, memberID: String, activities: [GroupActivity]?) {
        guard group.isActive else { clearGroup(group.id, accountID: accountID); return }
        guard let activities else { return }
        let old = rows.filter { $0.accountID == accountID && $0.groupID == group.id }
        for row in old {
            guard group.isActive, let activity = activities.first(where: { $0.id == row.activityID }), activity.status == "recruiting", activity.startsAt > Int64(Date().timeIntervalSince1970 * 1000), activity.registeredMemberIds.contains(memberID) else { remove(row); continue }
            if activity.startsAt != row.startsAt || activity.place != row.place || activity.title != row.title {
                let updated = Reminder(accountID: row.accountID, groupID: row.groupID, activityID: row.activityID,
                    title: activity.title, place: activity.place, startsAt: activity.startsAt)
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [row.identifier])
                rows = rows.filter { $0.identifier != row.identifier } + [updated]
                Task { try? await schedule(updated) }
            }
        }
    }
    private func remove(_ row: Reminder) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [row.identifier]); center.removeDeliveredNotifications(withIdentifiers: [row.identifier])
        rows.removeAll { $0.identifier == row.identifier }
    }
    func clearAccount(previous accountID: String?) {
        guard let accountID else { return }; for row in rows.filter({ $0.accountID == accountID }) { remove(row) }
        if destination?.accountID == accountID { destination = nil }
    }
    func clearGroup(_ groupID: String, accountID: String) { for row in rows.filter({ $0.accountID == accountID && $0.groupID == groupID }) { remove(row) } }
    func open(accountID: String, groupID: String, activityID: String) { destination = .init(accountID: accountID, groupID: groupID, activityID: activityID) }
    private enum ReminderError: LocalizedError {
        case permission, tooLate
        var errorDescription: String? { self == .permission ? groupText("reminder_permission", "Enable notifications for this app in Settings to receive reminders.") : groupText("reminder_too_late", "This activity starts in less than 15 minutes.") }
    }
}
