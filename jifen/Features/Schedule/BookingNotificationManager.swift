import Foundation
import UserNotifications

final class BookingNotificationManager {
    static let shared = BookingNotificationManager()

    private let idPrefix = "booking.reminder."

    private init() {}

    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    func syncNotifications(for booking: LocalBooking) {
        removeNotifications(for: booking.id) { [weak self] in
            guard booking.status == .pending else { return }

            let reminderMinutes = Array(Set(booking.reminderMinutes.filter { $0 > 0 })).sorted(by: >)
            guard !reminderMinutes.isEmpty else { return }

            self?.ensureAuthorization { [weak self] granted in
                guard granted, let self else { return }
                for minute in reminderMinutes {
                    self.scheduleReminder(for: booking, minuteBefore: minute)
                }
            }
        }
    }

    func removeNotifications(for bookingId: String, completion: (() -> Void)? = nil) {
        removeNotificationsVerified(for: bookingId) { _ in
            completion?()
        }
    }

    /// Removes both pending and already delivered reminders, then reads the
    /// notification center again before reporting success. Completion flows
    /// such as "start scheduled match" must await this method before they mark
    /// a booking completed or navigate away.
    func removeNotificationsAndWait(for bookingId: String) async -> Bool {
        await withCheckedContinuation { continuation in
            removeNotificationsVerified(for: bookingId) { success in
                continuation.resume(returning: success)
            }
        }
    }

    private func removeNotificationsVerified(
        for bookingId: String,
        completion: @escaping (Bool) -> Void
    ) {
        guard let center else {
            completion(true)
            return
        }

        let prefix = "\(idPrefix)\(bookingId)."
        let group = DispatchGroup()

        group.enter()
        center.getPendingNotificationRequests { requests in
            defer { group.leave() }
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }

        group.enter()
        center.getDeliveredNotifications { notifications in
            defer { group.leave() }
            let ids = notifications.map { $0.request.identifier }.filter { $0.hasPrefix(prefix) }
            if !ids.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: ids)
            }
        }

        group.notify(queue: .main) {
            center.getPendingNotificationRequests { pendingAfter in
                center.getDeliveredNotifications { deliveredAfter in
                    let pendingRemoved = pendingAfter.allSatisfy {
                        !$0.identifier.hasPrefix(prefix)
                    }
                    let deliveredRemoved = deliveredAfter.allSatisfy {
                        !$0.request.identifier.hasPrefix(prefix)
                    }
                    DispatchQueue.main.async {
                        completion(pendingRemoved && deliveredRemoved)
                    }
                }
            }
        }
    }

    func removeAllBookingNotifications(completion: ((Bool) -> Void)? = nil) {
        guard let center else {
            completion?(true)
            return
        }

        // Resolve removals and then query the notification center again. The
        // data-reset flow can therefore report a real failure instead of
        // treating this asynchronous operation as completed immediately.
        center.getPendingNotificationRequests { [idPrefix] requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
            center.getDeliveredNotifications { notifications in
                let ids = notifications.map { $0.request.identifier }.filter { $0.hasPrefix(idPrefix) }
                if !ids.isEmpty {
                    center.removeDeliveredNotifications(withIdentifiers: ids)
                }
                center.getPendingNotificationRequests { pendingAfter in
                    center.getDeliveredNotifications { deliveredAfter in
                        let pendingRemoved = pendingAfter.allSatisfy {
                            !$0.identifier.hasPrefix(idPrefix)
                        }
                        let deliveredRemoved = deliveredAfter.allSatisfy {
                            !$0.request.identifier.hasPrefix(idPrefix)
                        }
                        DispatchQueue.main.async {
                            completion?(pendingRemoved && deliveredRemoved)
                        }
                    }
                }
            }
        }
    }

    func removeAllBookingNotificationsAndWait() async -> Bool {
        await withCheckedContinuation { continuation in
            removeAllBookingNotifications { success in
                continuation.resume(returning: success)
            }
        }
    }

    private func scheduleReminder(for booking: LocalBooking, minuteBefore: Int) {
        guard let center else { return }

        let triggerDate = booking.dateTime.addingTimeInterval(TimeInterval(-minuteBefore * 60))
        guard triggerDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("schedule_notification_title", value: "球局提醒", comment: "Schedule reminder notification title")
        content.body = reminderBody(for: booking)
        content.sound = .default
        content.userInfo = ["bookingId": booking.id]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = notificationId(bookingId: booking.id, minuteBefore: minuteBefore)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    private func notificationId(bookingId: String, minuteBefore: Int) -> String {
        "\(idPrefix)\(bookingId).\(minuteBefore)"
    }

    private func reminderBody(for booking: LocalBooking) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let timeText = formatter.string(from: booking.dateTime)

        let trimmedLocation = booking.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLocation.isEmpty {
            return String(
                format: NSLocalizedString(
                    "schedule_notification_body",
                    value: "%@ %@ 即将开始",
                    comment: "Schedule reminder notification body without location"
                ),
                booking.sportType.displayName,
                timeText
            )
        }

        return String(
            format: NSLocalizedString(
                "schedule_notification_body_with_location",
                value: "%@ %@ 即将开始，地点：%@",
                comment: "Schedule reminder notification body with location"
            ),
            booking.sportType.displayName,
            timeText,
            trimmedLocation
        )
    }

    private func ensureAuthorization(_ completion: @escaping (Bool) -> Void) {
        guard let center else {
            completion(false)
            return
        }

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                completion(true)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    completion(granted)
                }
            case .denied:
                completion(false)
            @unknown default:
                completion(false)
            }
        }
    }
}
