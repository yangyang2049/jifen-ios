import Foundation

final class LocalBookingManager {
    static let shared = LocalBookingManager()

    private let bookingsKey = "local_bookings_v1"
    private let userDefaults: UserDefaults
    private let schedulesNotifications: Bool
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(userDefaults: UserDefaults = .standard, schedulesNotifications: Bool = true) {
        self.userDefaults = userDefaults
        self.schedulesNotifications = schedulesNotifications
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func getAllBookings() -> [LocalBooking] {
        guard let items = loadBookingsForMutation() else { return [] }
        return items.sorted { $0.dateTime > $1.dateTime }
    }

    func getBookings(status: BookingStatus) -> [LocalBooking] {
        getAllBookings()
            .filter { $0.status.isVisible(in: status) }
            .sorted { $0.dateTime < $1.dateTime }
    }

    func getUpcomingPendingBookings(limit: Int = 2, now: Date = Date()) -> [LocalBooking] {
        guard limit > 0 else { return [] }
        let graceBoundary = now.addingTimeInterval(-2 * 60 * 60)
        return getAllBookings()
            .filter { $0.status == .pending && $0.dateTime >= graceBoundary }
            .sorted { $0.dateTime < $1.dateTime }
            .prefix(limit)
            .map { $0 }
    }

    func getBooking(by id: String) -> LocalBooking? {
        getAllBookings().first { $0.id == id }
    }

    @discardableResult
    func upsertBooking(_ booking: LocalBooking) -> Bool {
        // A present but undecodable value may contain recoverable user data.
        // Never turn that storage corruption into an apparently empty list and
        // overwrite the original bytes during an ordinary mutation.
        guard var items = loadBookingsForMutation() else { return false }
        items.removeAll { $0.id == booking.id }
        items.append(booking)
        let success = saveAll(items)
        if success, schedulesNotifications {
            BookingNotificationManager.shared.syncNotifications(for: booking)
        }
        return success
    }

    @discardableResult
    func cancelBooking(_ id: String) -> Bool {
        guard var item = getBooking(by: id) else { return false }
        item.status = .cancelled
        item.completedAt = nil
        item.updatedAt = Date()
        return upsertBooking(item)
    }

    @discardableResult
    func markNoShow(_ id: String, at date: Date = Date()) -> Bool {
        guard var item = getBooking(by: id) else { return false }
        item.status = .noShow
        item.completedAt = nil
        item.updatedAt = date
        return upsertBooking(item)
    }

    @discardableResult
    func markCompleted(_ id: String, at date: Date = Date()) -> Bool {
        guard var item = getBooking(by: id) else { return false }
        item.status = .completed
        item.completedAt = date
        item.updatedAt = date
        return upsertBooking(item)
    }

    /// Completes the persistence/notification handoff used after a scoreboard
    /// resume bundle has already been saved. The pending reminder is removed
    /// and verified first; only then is the booking marked completed. If the
    /// final local write fails, restore the original pending reminder so the
    /// user does not lose both the booking state and its notification.
    func markCompletedAndWaitForNotifications(
        _ id: String,
        at date: Date = Date()
    ) async -> Bool {
        guard var items = loadBookingsForMutation(),
              let index = items.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let original = items[index]
        if schedulesNotifications {
            let removed = await BookingNotificationManager.shared.removeNotificationsAndWait(for: id)
            guard removed else {
                if original.status == .pending {
                    BookingNotificationManager.shared.syncNotifications(for: original)
                }
                return false
            }

            // Do not write a snapshot loaded before the suspension point over
            // a concurrent mutation or a newly corrupted payload.
            guard let refreshed = loadBookingsForMutation(),
                  let refreshedIndex = refreshed.firstIndex(where: { $0.id == id }) else {
                if original.status == .pending {
                    BookingNotificationManager.shared.syncNotifications(for: original)
                }
                return false
            }
            items = refreshed
            let current = items[refreshedIndex]
            var completed = current
            completed.status = .completed
            completed.completedAt = date
            completed.updatedAt = date
            items[refreshedIndex] = completed
        } else {
            items[index].status = .completed
            items[index].completedAt = date
            items[index].updatedAt = date
        }

        guard saveAll(items) else {
            if schedulesNotifications, original.status == .pending {
                BookingNotificationManager.shared.syncNotifications(for: original)
            }
            return false
        }
        return true
    }

    @discardableResult
    func deleteBooking(_ id: String) -> Bool {
        guard var items = loadBookingsForMutation() else { return false }
        let originalCount = items.count
        items.removeAll { $0.id == id }
        guard items.count != originalCount else { return false }
        let success = saveAll(items)
        if success, schedulesNotifications {
            BookingNotificationManager.shared.removeNotifications(for: id)
        }
        return success
    }

    @discardableResult
    func deleteBookings(_ ids: Set<String>) -> Bool {
        guard !ids.isEmpty else { return false }
        guard var items = loadBookingsForMutation() else { return false }
        let existingIDs = Set(items.lazy.map(\.id)).intersection(ids)
        guard !existingIDs.isEmpty else { return false }
        items.removeAll { existingIDs.contains($0.id) }
        let success = saveAll(items)
        if success, schedulesNotifications {
            for id in existingIDs {
                BookingNotificationManager.shared.removeNotifications(for: id)
            }
        }
        return success
    }

    @discardableResult
    func clearAllBookings() -> Bool {
        guard loadBookingsForMutation() != nil else { return false }
        userDefaults.removeObject(forKey: bookingsKey)
        guard userDefaults.object(forKey: bookingsKey) == nil else { return false }
        if schedulesNotifications {
            BookingNotificationManager.shared.removeAllBookingNotifications()
        }
        return true
    }

    func clearAllBookingsAndWaitForNotifications() async -> Bool {
        guard loadBookingsForMutation() != nil else { return false }
        userDefaults.removeObject(forKey: bookingsKey)
        guard userDefaults.object(forKey: bookingsKey) == nil else { return false }
        guard schedulesNotifications else { return true }
        return await BookingNotificationManager.shared.removeAllBookingNotificationsAndWait()
    }

    /// Returns an empty array for genuinely missing storage, but returns `nil`
    /// when a stored payload cannot be decoded. Mutation paths must use this
    /// distinction so malformed data is never silently replaced by `[]`.
    private func loadBookingsForMutation() -> [LocalBooking]? {
        guard let data = userDefaults.data(forKey: bookingsKey) else { return [] }
        return try? decoder.decode([LocalBooking].self, from: data)
    }

    @discardableResult
    private func saveAll(_ bookings: [LocalBooking]) -> Bool {
        do {
            let data = try encoder.encode(bookings)
            userDefaults.set(data, forKey: bookingsKey)
            return userDefaults.data(forKey: bookingsKey) == data
        } catch {
            return false
        }
    }
}
