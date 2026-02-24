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
        guard let center else {
            completion?()
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
            completion?()
        }
    }

    func removeAllBookingNotifications() {
        guard let center else { return }

        center.getPendingNotificationRequests { [idPrefix] requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }

        center.getDeliveredNotifications { [idPrefix] notifications in
            let ids = notifications.map { $0.request.identifier }.filter { $0.hasPrefix(idPrefix) }
            if !ids.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: ids)
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
