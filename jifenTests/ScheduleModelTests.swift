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

    func testBookingSportCatalogContainsTenCreatableTypesAndHidesLegacyOther() {
        XCTAssertEqual(BookingSportType.creatableCases.count, 10)
        XCTAssertFalse(BookingSportType.creatableCases.contains(.other))
        XCTAssertTrue(BookingSportType.allCases.contains(.other))
        XCTAssertEqual(Set(BookingSportType.creatableCases).count, 10)
    }

    func testBookingSportTypeGameTypeMapping() {
        XCTAssertEqual(BookingSportType.badminton.gameType, .badminton)
        XCTAssertEqual(BookingSportType.pingpong.gameType, .pingpong)
        XCTAssertEqual(BookingSportType.basketball.gameType, .basketball)
        XCTAssertEqual(BookingSportType.tennis.gameType, .tennis)
        XCTAssertEqual(BookingSportType.football.gameType, .football)
        XCTAssertEqual(BookingSportType.volleyball.gameType, .volleyball)
        XCTAssertEqual(BookingSportType.airVolleyball.gameType, .airVolleyball)
        XCTAssertEqual(BookingSportType.beachVolleyball.gameType, .beachVolleyball)
        XCTAssertEqual(BookingSportType.pickleball.gameType, .pickleball)
        XCTAssertEqual(BookingSportType.billiards.gameType, .billiards)
        XCTAssertNil(BookingSportType.other.gameType)
    }

    func testPingpongLegacyValueDecodesAndEncodesAsTableTennis() throws {
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(BookingSportType.self, from: Data("\"pingpong\"".utf8))
        XCTAssertEqual(decoded, .pingpong)

        let encoded = try JSONEncoder().encode(decoded)
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "\"table_tennis\"")
    }

    func testUnknownLegacySportRemainsReadableAsOther() throws {
        let decoded = try JSONDecoder().decode(BookingSportType.self, from: Data("\"custom_legacy\"".utf8))
        XCTAssertEqual(decoded, .other)
    }

    func testLegacySnookerSportOverridesStandardBilliardsFormat() throws {
        let payload = """
        {
          "id": "legacy-snooker",
          "sportType": "snooker",
          "dateTime": "2025-06-01T08:00:00Z",
          "durationMinutes": 90,
          "location": "Table 1",
          "gameFormat": "billiards",
          "reminderMinutes": [],
          "status": "pending",
          "createdAt": "2025-05-01T08:00:00Z",
          "updatedAt": "2025-05-01T08:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let booking = try decoder.decode(LocalBooking.self, from: Data(payload.utf8))
        XCTAssertEqual(booking.sportType, .billiards)
        XCTAssertEqual(booking.billiardsFormat, .snooker)
        XCTAssertEqual(booking.resolvedGameType, .snooker)
    }

    func testLocalBookingCodableRoundTripIncludesAndroidParityFields() throws {
        let booking = LocalBooking(
            id: "booking-1",
            sportType: .tennis,
            dateTime: Date(timeIntervalSince1970: 1_700_000_000),
            durationMinutes: 120,
            location: "Court A",
            locationLat: 31.2304,
            locationLng: 121.4737,
            matchMode: .doubles,
            team1Name: "Red Pair",
            team2Name: "Blue Pair",
            redTopName: "A",
            redBottomName: "B",
            blueTopName: "C",
            blueBottomName: "D",
            maxSets: 3,
            tieBreakPoints: 7,
            tennisDeuceMode: "no_ad",
            participantNames: ["A", "B", "C", "D"],
            notes: "Bring balls",
            reminderMinutes: [15, 120, 30],
            status: .completed,
            createdAt: Date(timeIntervalSince1970: 1_699_999_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            completedAt: Date(timeIntervalSince1970: 1_700_000_200),
            calendarEventId: "calendar-1"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(booking)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(LocalBooking.self, from: data), booking)
    }

    func testLegacyBookingPayloadGetsSafeDefaults() throws {
        let payload = """
        {
          "id": "legacy-1",
          "sportType": "pingpong",
          "dateTime": "2025-06-01T08:00:00Z",
          "durationMinutes": 91,
          "location": "Table 1",
          "matchFormat": "",
          "notes": "legacy",
          "reminderMinutes": [1440, 120, 15],
          "status": "pending",
          "createdAt": "2025-05-01T08:00:00Z",
          "updatedAt": "2025-05-01T08:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let booking = try decoder.decode(LocalBooking.self, from: Data(payload.utf8))

        XCTAssertEqual(booking.sportType, .pingpong)
        XCTAssertEqual(booking.durationMinutes, 90)
        XCTAssertEqual(booking.matchMode, .singles)
        XCTAssertEqual(booking.reminderMinutes, [120, 15])
        XCTAssertEqual(booking.participantNames, [])
        XCTAssertNil(booking.completedAt)
        XCTAssertNil(booking.locationLat)
        XCTAssertNil(booking.calendarEventId)
    }

    func testMissingReminderFieldAndNewBookingUseAndroidDefaults() throws {
        let payload = """
        {
          "id": "legacy-without-reminders",
          "sportType": "badminton",
          "dateTime": "2025-06-01T08:00:00Z",
          "location": "Court 1",
          "status": "pending"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(LocalBooking.self, from: Data(payload.utf8))
        let created = LocalBooking(
            sportType: .badminton,
            dateTime: Date(),
            location: "Court 1"
        )

        XCTAssertEqual(restored.reminderMinutes, LocalBooking.defaultReminderMinutes)
        XCTAssertEqual(created.reminderMinutes, LocalBooking.defaultReminderMinutes)
    }

    func testParticipantAndReminderNormalization() {
        let names = (0..<15).map { "P\($0)" } + ["P1", "  "]
        XCTAssertEqual(LocalBooking.normalizedParticipants(names).count, 12)
        XCTAssertEqual(LocalBooking.normalizedParticipants([" Alice ", "Alice", "Bob"]), ["Alice", "Bob"])
        XCTAssertEqual(LocalBooking.normalizedReminders([15, 120, 15, 1440, 10]), [120, 15])
        XCTAssertEqual(LocalBooking.normalizedDuration(29), 30)
        XCTAssertEqual(LocalBooking.normalizedDuration(91), 90)
        XCTAssertEqual(LocalBooking.normalizedDuration(999), 360)
    }

    func testNoShowAppearsInCancelledTabOnly() {
        XCTAssertTrue(BookingStatus.noShow.isVisible(in: .cancelled))
        XCTAssertFalse(BookingStatus.noShow.isVisible(in: .completed))
        XCTAssertTrue(BookingStatus.cancelled.isVisible(in: .cancelled))
    }

    func testBilliardsFormatsResolveToFourScoreboards() {
        let expected: [(BookingBilliardsFormat, GameType)] = [
            (.standard, .billiards),
            (.eightBall, .eightBall),
            (.nineBall, .nineBall),
            (.snooker, .snooker)
        ]
        for (format, gameType) in expected {
            let booking = LocalBooking(
                sportType: .billiards,
                dateTime: Date(),
                location: "Table",
                gameFormat: format.rawValue
            )
            XCTAssertEqual(booking.resolvedGameType, gameType)
            XCTAssertEqual(booking.makeStartRequest()?.gameType, gameType)
        }
    }

    func testDoublesBookingBuildsFullSportsSetupResult() throws {
        let booking = LocalBooking(
            id: "doubles-1",
            sportType: .tennis,
            dateTime: Date(),
            location: "Court",
            matchMode: .doubles,
            redTopName: "A",
            redBottomName: "B",
            blueTopName: "C",
            blueBottomName: "D",
            maxSets: 5,
            tieBreakPoints: 10,
            tennisDeuceMode: "no_ad"
        )

        let request = try XCTUnwrap(booking.makeStartRequest())
        XCTAssertEqual(request.bookingId, "doubles-1")
        XCTAssertEqual(request.gameType, .tennis)
        XCTAssertEqual(request.setup.isSingles, false)
        XCTAssertEqual(request.setup.team1Name, "A/B")
        XCTAssertEqual(request.setup.team2Name, "C/D")
        XCTAssertEqual(request.setup.team1Player1Name, "A")
        XCTAssertEqual(request.setup.team1Player2Name, "B")
        XCTAssertEqual(request.setup.team2Player1Name, "C")
        XCTAssertEqual(request.setup.team2Player2Name, "D")
        XCTAssertEqual(request.setup.maxSets, 5)
        XCTAssertEqual(request.setup.tieBreakPoints, 10)
        XCTAssertEqual(request.setup.tennisDeuceMode, "no_ad")
    }

    func testNineBallBookingCarriesUpToFourParticipantNamesIntoSetup() throws {
        let booking = LocalBooking(
            sportType: .billiards,
            dateTime: Date(),
            location: "Table",
            gameFormat: BookingBilliardsFormat.nineBall.rawValue,
            participantNames: ["A", "B", "C", "D", "E"]
        )
        let setup = try XCTUnwrap(booking.makeStartRequest()).setup
        XCTAssertEqual(setup.playerNames, ["A", "B", "C", "D"])
        XCTAssertEqual(setup.playerCount, 4)
    }

    func testDefaultBookingTimeSnapsAroundSixHoursAndUsesBusinessWindow() throws {
        let calendar = shanghaiCalendar()
        let first = try makeDate(2025, 6, 1, 10, 7, calendar: calendar)
        let second = try makeDate(2025, 6, 1, 10, 22, calendar: calendar)
        let evening = try makeDate(2025, 6, 1, 18, 0, calendar: calendar)

        assertDate(defaultBookingDateTime(now: first, calendar: calendar), equals: [2025, 6, 1, 16, 0], calendar: calendar)
        assertDate(defaultBookingDateTime(now: second, calendar: calendar), equals: [2025, 6, 1, 16, 30], calendar: calendar)
        assertDate(defaultBookingDateTime(now: evening, calendar: calendar), equals: [2025, 6, 2, 9, 0], calendar: calendar)
    }

    func testReconcileTodayMovesPastSelectionTwoHoursAhead() throws {
        let calendar = shanghaiCalendar()
        let now = try makeDate(2025, 6, 5, 10, 0, calendar: calendar)
        let selected = try makeDate(2025, 6, 5, 9, 0, calendar: calendar)
        assertDate(
            reconciledBookingDateTime(selected, now: now, calendar: calendar),
            equals: [2025, 6, 5, 12, 0],
            calendar: calendar
        )
    }

    func testUpcomingPendingBookingsIncludesTwoHourOverdueGraceAndSorts() {
        let suiteName = "ScheduleModelTests.upcoming.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = LocalBookingManager(userDefaults: defaults, schedulesNotifications: false)
        let now = Date()
        let seed: [LocalBooking] = [
            LocalBooking(id: "a", sportType: .badminton, dateTime: now.addingTimeInterval(3_600), location: "A"),
            LocalBooking(id: "b", sportType: .pingpong, dateTime: now.addingTimeInterval(-3_600), location: "B"),
            LocalBooking(id: "c", sportType: .tennis, dateTime: now.addingTimeInterval(7_200), location: "C", status: .completed),
            LocalBooking(id: "d", sportType: .basketball, dateTime: now.addingTimeInterval(5_400), location: "D"),
            LocalBooking(id: "e", sportType: .football, dateTime: now.addingTimeInterval(-10_800), location: "E")
        ]
        for booking in seed { XCTAssertTrue(manager.upsertBooking(booking)) }

        XCTAssertEqual(manager.getUpcomingPendingBookings(limit: 3, now: now).map(\.id), ["b", "a", "d"])
    }

    func testCompletionSetsCompletedAtAndBatchDeleteIsAtomic() throws {
        let suiteName = "ScheduleModelTests.manager.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = LocalBookingManager(userDefaults: defaults, schedulesNotifications: false)
        let bookingA = LocalBooking(id: "a", sportType: .badminton, dateTime: Date(), location: "A")
        let bookingB = LocalBooking(id: "b", sportType: .tennis, dateTime: Date(), location: "B")
        let bookingC = LocalBooking(id: "c", sportType: .football, dateTime: Date(), location: "C")
        XCTAssertTrue(manager.upsertBooking(bookingA))
        XCTAssertTrue(manager.upsertBooking(bookingB))
        XCTAssertTrue(manager.upsertBooking(bookingC))

        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(manager.markCompleted("a", at: completedAt))
        XCTAssertEqual(try XCTUnwrap(manager.getBooking(by: "a")).status, .completed)
        XCTAssertEqual(try XCTUnwrap(manager.getBooking(by: "a")).completedAt, completedAt)

        XCTAssertTrue(manager.deleteBookings(["a", "b", "missing"]))
        XCTAssertEqual(manager.getAllBookings().map(\.id), ["c"])
    }

    func testCorruptedBookingStorageIsReadableAsEmptyButNeverOverwrittenByMutations() async {
        let suiteName = "ScheduleModelTests.corrupt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = LocalBookingManager(userDefaults: defaults, schedulesNotifications: false)
        let originalBytes = Data("{not-a-booking-array}".utf8)
        defaults.set(originalBytes, forKey: bookingsKey)

        XCTAssertEqual(manager.getAllBookings(), [])
        XCTAssertFalse(manager.upsertBooking(
            LocalBooking(id: "new", sportType: .badminton, dateTime: Date(), location: "Court")
        ))
        XCTAssertFalse(manager.cancelBooking("new"))
        XCTAssertFalse(manager.markNoShow("new"))
        XCTAssertFalse(manager.markCompleted("new"))
        XCTAssertFalse(manager.deleteBooking("new"))
        XCTAssertFalse(manager.deleteBookings(["new"]))
        XCTAssertFalse(manager.clearAllBookings())
        let asyncClearResult = await manager.clearAllBookingsAndWaitForNotifications()
        XCTAssertFalse(asyncClearResult)
        XCTAssertEqual(defaults.data(forKey: bookingsKey), originalBytes)
    }

    func testAwaitedCompletionPersistsCompletedPayloadAfterResumeHandoff() async throws {
        let suiteName = "ScheduleModelTests.awaitedCompletion.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = LocalBookingManager(userDefaults: defaults, schedulesNotifications: false)
        let booking = LocalBooking(
            id: "ready-to-start",
            sportType: .tennis,
            dateTime: Date(timeIntervalSince1970: 1_700_000_000),
            location: "Court"
        )
        XCTAssertTrue(manager.upsertBooking(booking))

        let completedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let completed = await manager.markCompletedAndWaitForNotifications(
            booking.id,
            at: completedAt
        )

        XCTAssertTrue(completed)
        let restored = try XCTUnwrap(manager.getBooking(by: booking.id))
        XCTAssertEqual(restored.status, .completed)
        XCTAssertEqual(restored.completedAt, completedAt)
        XCTAssertEqual(restored.updatedAt, completedAt)
    }

    func testCommonPlacesNormalizeDeduplicateAndSaveNewPlacesOnly() throws {
        let manager = CommonPlacesManager.shared
        try manager.addPlace("  Center   Court  ")

        XCTAssertThrowsError(try manager.addPlace("center court")) { error in
            guard case CommonPlacesError.duplicateName = error else {
                return XCTFail("Expected duplicateName, got \(error)")
            }
        }

        manager.savePlaceIfNeeded("Center Court")
        manager.savePlaceIfNeeded("West Gym")
        manager.savePlaceIfNeeded("West Gym")

        let places = manager.getAllPlaces()
        XCTAssertEqual(places.map(\.name), ["West Gym", "Center Court"])
        XCTAssertEqual(places.count, 2)
    }

    func testCommonPlacesKeepNewestSavedPlaceAtCapacity() throws {
        let manager = CommonPlacesManager.shared
        for index in 0..<CommonPlacesManager.maxPlaces { try manager.addPlace("Court \(index)") }
        manager.savePlaceIfNeeded("New Court")
        XCTAssertEqual(manager.getAllPlaces().count, CommonPlacesManager.maxPlaces)
        XCTAssertEqual(manager.getAllPlaces().first?.name, "New Court")
    }

    func testCommonNamesSaveNewNamesWithoutReorderingExistingNames() async throws {
        let suiteName = "ScheduleModelTests.commonNames.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = CommonNamesManager(userDefaults: defaults)
        try manager.addName("Alice", type: .player)
        await manager.saveNameIfNeeded("Bob", .player)
        await manager.saveNameIfNeeded("Alice", .player)
        XCTAssertEqual(manager.getNames(type: .player), ["Bob", "Alice"])
    }

    private func shanghaiCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func makeDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: 0
        )))
    }

    private func assertDate(
        _ date: Date,
        equals expected: [Int],
        calendar: Calendar,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual(
            [components.year, components.month, components.day, components.hour, components.minute].compactMap { $0 },
            expected,
            file: file,
            line: line
        )
    }
}
