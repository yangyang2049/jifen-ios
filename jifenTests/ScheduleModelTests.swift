import XCTest
@testable import jifen

@MainActor
final class ScheduleModelTests: XCTestCase {
    private let bookingsKey = "local_bookings_v1"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: bookingsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: bookingsKey)
        super.tearDown()
    }

    func testBookingSportTypeGameTypeMapping() {
        XCTAssertEqual(BookingSportType.badminton.gameType, .badminton)
        XCTAssertEqual(BookingSportType.pingpong.gameType, .pingpong)
        XCTAssertEqual(BookingSportType.basketball.gameType, .basketball)
        XCTAssertEqual(BookingSportType.tennis.gameType, .tennis)
        XCTAssertEqual(BookingSportType.football.gameType, .football)
        XCTAssertEqual(BookingSportType.volleyball.gameType, .volleyball)
        XCTAssertEqual(BookingSportType.pickleball.gameType, .pickleball)
        XCTAssertNil(BookingSportType.other.gameType)
    }

    func testLocalBookingCodableRoundTrip() throws {
        let booking = LocalBooking(
            id: "booking-1",
            sportType: .badminton,
            dateTime: Date(timeIntervalSince1970: 1_700_000_000),
            durationMinutes: 120,
            location: "Court A",
            matchFormat: "BO3",
            notes: "Bring shuttles",
            reminderMinutes: [10, 30],
            status: .pending,
            createdAt: Date(timeIntervalSince1970: 1_699_999_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(booking)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LocalBooking.self, from: data)

        XCTAssertEqual(decoded, booking)
    }

    func testUpcomingPendingBookingsSortAndLimit() throws {
        let now = Date()
        let future1 = now.addingTimeInterval(60 * 60)
        let future2 = now.addingTimeInterval(2 * 60 * 60)
        let future3 = now.addingTimeInterval(3 * 60 * 60)
        let past = now.addingTimeInterval(-60 * 60)

        let seed: [LocalBooking] = [
            LocalBooking(id: "a", sportType: .badminton, dateTime: future3, durationMinutes: 60, location: "A", status: .pending),
            LocalBooking(id: "b", sportType: .pingpong, dateTime: future1, durationMinutes: 60, location: "B", status: .pending),
            LocalBooking(id: "c", sportType: .tennis, dateTime: future2, durationMinutes: 60, location: "C", status: .completed),
            LocalBooking(id: "d", sportType: .basketball, dateTime: future2, durationMinutes: 60, location: "D", status: .pending),
            LocalBooking(id: "e", sportType: .football, dateTime: past, durationMinutes: 60, location: "E", status: .pending)
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        UserDefaults.standard.set(try encoder.encode(seed), forKey: bookingsKey)

        let results = LocalBookingManager.shared.getUpcomingPendingBookings(limit: 2)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.map(\.id), ["b", "d"])
    }
}
