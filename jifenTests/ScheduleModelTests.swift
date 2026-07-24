import XCTest
@testable import jifen

@MainActor
final class ScheduleModelTests: XCTestCase {
    private let bookingsKey = "local_bookings_v1"
    private let commonPlacesKey = "jifen-v2.commonPlaces"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: bookingsKey)
        UserDefaults.standard.removeObject(forKey: commonPlacesKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: bookingsKey)
        UserDefaults.standard.removeObject(forKey: commonPlacesKey)
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

    func testPickleballUsesTableTennisIcon() {
        XCTAssertEqual(BookingSportType.pickleball.icon, BookingSportType.pingpong.icon)
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

    func testCommonPlacesNormalizeDeduplicateAndTrackUsage() throws {
        let manager = CommonPlacesManager.shared
        try manager.addPlace("  Center   Court  ")

        XCTAssertThrowsError(try manager.addPlace("center court")) { error in
            guard case CommonPlacesError.duplicateName = error else {
                return XCTFail("Expected duplicateName, got \(error)")
            }
        }

        manager.recordUsage("Center Court")
        manager.recordUsage("West Gym")
        manager.recordUsage("West Gym")

        let places = manager.getAllPlaces()
        XCTAssertEqual(places.map(\.name), ["West Gym", "Center Court"])
        XCTAssertEqual(places.map(\.useCount), [2, 1])
    }

    func testCommonPlacesKeepNewestUsedPlaceAtCapacity() throws {
        let manager = CommonPlacesManager.shared
        for index in 0..<50 {
            try manager.addPlace("Court \(index)")
        }

        manager.recordUsage("New Court")

        let places = manager.getAllPlaces()
        XCTAssertEqual(places.count, 50)
        XCTAssertEqual(places.first?.name, "New Court")
    }
}
