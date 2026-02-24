import Foundation

final class LocalBookingManager {
    static let shared = LocalBookingManager()

    private let bookingsKey = "local_bookings_v1"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func getAllBookings() -> [LocalBooking] {
        guard let data = UserDefaults.standard.data(forKey: bookingsKey) else {
            return []
        }

        do {
            let items = try decoder.decode([LocalBooking].self, from: data)
            return items.sorted { $0.dateTime > $1.dateTime }
        } catch {
            return []
        }
    }

    func getBookings(status: BookingStatus) -> [LocalBooking] {
        getAllBookings()
            .filter { $0.status == status }
            .sorted { $0.dateTime > $1.dateTime }
    }

    func getUpcomingPendingBookings(limit: Int = 2) -> [LocalBooking] {
        guard limit > 0 else { return [] }
        let now = Date()
        return getAllBookings()
            .filter { $0.status == .pending && $0.dateTime >= now }
            .sorted { $0.dateTime < $1.dateTime }
            .prefix(limit)
            .map { $0 }
    }

    func getBooking(by id: String) -> LocalBooking? {
        getAllBookings().first { $0.id == id }
    }

    @discardableResult
    func upsertBooking(_ booking: LocalBooking) -> Bool {
        var items = getAllBookings()
        items.removeAll { $0.id == booking.id }
        items.append(booking)
        let success = saveAll(items)
        if success {
            BookingNotificationManager.shared.syncNotifications(for: booking)
        }
        return success
    }

    @discardableResult
    func cancelBooking(_ id: String) -> Bool {
        guard var item = getBooking(by: id) else { return false }
        item.status = .cancelled
        item.updatedAt = Date()
        return upsertBooking(item)
    }

    @discardableResult
    func markCompleted(_ id: String) -> Bool {
        guard var item = getBooking(by: id) else { return false }
        item.status = .completed
        item.updatedAt = Date()
        return upsertBooking(item)
    }

    @discardableResult
    func deleteBooking(_ id: String) -> Bool {
        var items = getAllBookings()
        let originalCount = items.count
        items.removeAll { $0.id == id }
        guard items.count != originalCount else { return false }
        let success = saveAll(items)
        if success {
            BookingNotificationManager.shared.removeNotifications(for: id)
        }
        return success
    }

    @discardableResult
    func clearAllBookings() -> Bool {
        UserDefaults.standard.removeObject(forKey: bookingsKey)
        BookingNotificationManager.shared.removeAllBookingNotifications()
        return true
    }

    @discardableResult
    private func saveAll(_ bookings: [LocalBooking]) -> Bool {
        do {
            let data = try encoder.encode(bookings)
            UserDefaults.standard.set(data, forKey: bookingsKey)
            return true
        } catch {
            return false
        }
    }
}
