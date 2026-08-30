import Foundation

enum BookingStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case completed
    case cancelled
    case noShow = "no_show"

    var id: String { rawValue }

    func isVisible(in tab: BookingStatus) -> Bool {
        switch tab {
        case .cancelled:
            return self == .cancelled || self == .noShow
        case .noShow:
            return self == .noShow
        default:
            return self == tab
        }
    }
}

enum BookingSportType: String, CaseIterable, Identifiable {
    case badminton
    /// New data uses Android's canonical value. The decoder still accepts legacy `pingpong`.
    case pingpong = "table_tennis"
    case basketball
    case tennis
    case football
    case volleyball
    case airVolleyball = "air_volleyball"
    case beachVolleyball = "beach_volleyball"
    case pickleball
    case billiards
    /// Read-only migration case; intentionally hidden when creating a booking.
    case other

    var id: String { rawValue }

    static let creatableCases: [BookingSportType] = [
        .badminton, .pingpong, .basketball, .tennis, .football,
        .volleyball, .airVolleyball, .beachVolleyball, .pickleball, .billiards
    ]

    var displayName: String {
        switch self {
        case .badminton:
            return NSLocalizedString("game_badminton", value: "羽毛球", comment: "")
        case .pingpong:
            return NSLocalizedString("game_pingpong", value: "乒乓球", comment: "")
        case .basketball:
            return NSLocalizedString("game_basketball", value: "篮球", comment: "")
        case .tennis:
            return NSLocalizedString("game_tennis", value: "网球", comment: "")
        case .football:
            return NSLocalizedString("game_football", value: "足球", comment: "")
        case .volleyball:
            return NSLocalizedString("game_volleyball", value: "排球", comment: "")
        case .airVolleyball:
            return NSLocalizedString("game_air_volleyball", value: "气排球", comment: "")
        case .beachVolleyball:
            return NSLocalizedString("game_beach_volleyball", value: "沙滩排球", comment: "")
        case .pickleball:
            return NSLocalizedString("game_pickleball", value: "匹克球", comment: "")
        case .billiards:
            return NSLocalizedString("game_billiards", value: "台球", comment: "")
        case .other:
            return NSLocalizedString("schedule_sport_other", value: "其他", comment: "")
        }
    }

    var icon: String {
        switch self {
        case .badminton: return "🏸"
        case .pingpong: return "🏓"
        case .basketball: return "🏀"
        case .tennis: return "🎾"
        case .football: return "⚽"
        case .volleyball, .airVolleyball, .beachVolleyball: return "🏐"
        case .pickleball: return "🥎"
        case .billiards: return "🎱"
        case .other: return "📅"
        }
    }

    var gameType: GameType? {
        switch self {
        case .badminton: return .badminton
        case .pingpong: return .pingpong
        case .basketball: return .basketball
        case .tennis: return .tennis
        case .football: return .football
        case .volleyball: return .volleyball
        case .airVolleyball: return .airVolleyball
        case .beachVolleyball: return .beachVolleyball
        case .pickleball: return .pickleball
        case .billiards: return .billiards
        case .other: return nil
        }
    }

    var supportsSinglesAndDoubles: Bool {
        switch self {
        case .badminton, .pingpong, .tennis, .pickleball: return true
        default: return false
        }
    }

    var usesTeamNames: Bool {
        switch self {
        case .basketball, .football, .volleyball, .airVolleyball, .beachVolleyball:
            return true
        default:
            return false
        }
    }
}

extension BookingSportType: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch rawValue {
        case "table_tennis", "table tennis", "pingpong", "ping_pong": self = .pingpong
        case "badminton": self = .badminton
        case "basketball": self = .basketball
        case "tennis": self = .tennis
        case "football", "soccer": self = .football
        case "volleyball": self = .volleyball
        case "air_volleyball", "air volleyball": self = .airVolleyball
        case "beach_volleyball", "beach volleyball": self = .beachVolleyball
        case "pickleball": self = .pickleball
        case "billiards", "pool", "snooker", "eight_ball", "nine_ball": self = .billiards
        default: self = .other
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum BookingMatchMode: String, Codable, CaseIterable, Identifiable {
    case singles
    case doubles

    var id: String { rawValue }
}

enum BookingBilliardsFormat: String, Codable, CaseIterable, Identifiable {
    case standard = "billiards"
    case eightBall = "eight_ball"
    case nineBall = "nine_ball"
    case snooker

    var id: String { rawValue }

    init(normalizing value: String?) {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "eight_ball", "eight ball": self = .eightBall
        case "nine_ball", "nine ball", "chase": self = .nineBall
        case "snooker": self = .snooker
        default: self = .standard
        }
    }

    var displayName: String {
        switch self {
        case .standard:
            return NSLocalizedString("schedule_billiards_standard", value: "普通", comment: "")
        case .eightBall:
            return NSLocalizedString("schedule_billiards_eight_ball", value: "八球", comment: "")
        case .nineBall:
            return NSLocalizedString("schedule_billiards_nine_ball", value: "九球", comment: "")
        case .snooker:
            return NSLocalizedString("schedule_billiards_snooker", value: "斯诺克", comment: "")
        }
    }

    var gameType: GameType {
        switch self {
        case .standard: return .billiards
        case .eightBall: return .eightBall
        case .nineBall: return .nineBall
        case .snooker: return .snooker
        }
    }
}

struct BookingStartRequest: Equatable {
    let bookingId: String
    let gameType: GameType
    let setup: SportsSetupResult
}

struct LocalBooking: Identifiable, Codable, Equatable, Hashable {
    static let defaultDurationMinutes = 90
    static let minimumDurationMinutes = 30
    static let maximumDurationMinutes = 360
    static let durationStepMinutes = 15
    static let defaultReminderMinutes = [120, 15]
    static let reminderOptions = [120, 30, 15]
    static let maximumParticipants = 12

    let id: String
    var sportType: BookingSportType
    var dateTime: Date
    var durationMinutes: Int
    var location: String
    var locationLat: Double?
    var locationLng: Double?
    var gameFormat: String
    var matchMode: BookingMatchMode?
    var team1Name: String?
    var team2Name: String?
    var redTopName: String?
    var redBottomName: String?
    var blueTopName: String?
    var blueBottomName: String?
    var maxSets: Int?
    var pointsPerSet: Int?
    var tieBreakPoints: Int?
    var tennisDeuceMode: String?
    var participantNames: [String]
    var notes: String
    var reminderMinutes: [Int]
    var status: BookingStatus
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var calendarEventId: String?

    /// Source compatibility for the original iOS model. New storage uses `gameFormat`.
    var matchFormat: String {
        get { gameFormat }
        set { gameFormat = newValue }
    }

    var billiardsFormat: BookingBilliardsFormat {
        get { BookingBilliardsFormat(normalizing: gameFormat) }
        set { gameFormat = newValue.rawValue }
    }

    var displayName: String {
        sportType == .billiards ? billiardsFormat.displayName : sportType.displayName
    }

    var resolvedGameType: GameType? {
        sportType == .billiards ? billiardsFormat.gameType : sportType.gameType
    }

    init(
        id: String = UUID().uuidString,
        sportType: BookingSportType,
        dateTime: Date,
        durationMinutes: Int = LocalBooking.defaultDurationMinutes,
        location: String,
        matchFormat: String = "",
        gameFormat: String? = nil,
        locationLat: Double? = nil,
        locationLng: Double? = nil,
        matchMode: BookingMatchMode? = nil,
        team1Name: String? = nil,
        team2Name: String? = nil,
        redTopName: String? = nil,
        redBottomName: String? = nil,
        blueTopName: String? = nil,
        blueBottomName: String? = nil,
        maxSets: Int? = nil,
        pointsPerSet: Int? = nil,
        tieBreakPoints: Int? = nil,
        tennisDeuceMode: String? = nil,
        participantNames: [String] = [],
        notes: String = "",
        reminderMinutes: [Int] = LocalBooking.defaultReminderMinutes,
        status: BookingStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        calendarEventId: String? = nil
    ) {
        self.id = id
        self.sportType = sportType
        self.dateTime = dateTime
        self.durationMinutes = Self.normalizedDuration(durationMinutes)
        self.location = location
        self.locationLat = locationLat
        self.locationLng = locationLng
        let suppliedFormat = gameFormat ?? matchFormat
        self.gameFormat = sportType == .billiards
            ? BookingBilliardsFormat(normalizing: suppliedFormat).rawValue
            : suppliedFormat
        self.matchMode = sportType.supportsSinglesAndDoubles ? (matchMode ?? .singles) : nil
        self.team1Name = team1Name
        self.team2Name = team2Name
        self.redTopName = redTopName
        self.redBottomName = redBottomName
        self.blueTopName = blueTopName
        self.blueBottomName = blueBottomName
        self.maxSets = maxSets.flatMap { $0 > 0 ? $0 : nil }
        self.pointsPerSet = pointsPerSet.flatMap { $0 > 0 ? $0 : nil }
        self.tieBreakPoints = tieBreakPoints.flatMap { $0 > 0 ? $0 : nil }
        self.tennisDeuceMode = Self.normalizedTennisDeuceMode(tennisDeuceMode)
        self.participantNames = Self.normalizedParticipants(participantNames)
        self.notes = notes
        self.reminderMinutes = Self.normalizedReminders(reminderMinutes)
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.calendarEventId = calendarEventId
    }

    static func normalizedDuration(_ value: Int) -> Int {
        let clamped = min(maximumDurationMinutes, max(minimumDurationMinutes, value))
        let offset = clamped - minimumDurationMinutes
        return minimumDurationMinutes + Int(round(Double(offset) / Double(durationStepMinutes))) * durationStepMinutes
    }

    static func normalizedParticipants(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            result.append(normalized)
            if result.count == maximumParticipants { break }
        }
        return result
    }

    static func normalizedReminders(_ values: [Int]) -> [Int] {
        let supported = Set(reminderOptions)
        return Array(Set(values.filter { supported.contains($0) })).sorted(by: >)
    }

    func makeStartRequest() -> BookingStartRequest? {
        guard let gameType = resolvedGameType else { return nil }

        let isSingles = sportType.supportsSinglesAndDoubles ? matchMode != .doubles : true
        let participants = Self.normalizedParticipants(participantNames)
        let defaults = DefaultParticipantNames.resolve(for: gameType, isSingles: isSingles)
        let doublesDefaults = DefaultParticipantNames.doublesMembers

        func clean(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        func participant(_ index: Int) -> String? {
            participants.indices.contains(index) ? participants[index] : nil
        }

        var leftName = clean(team1Name) ?? participant(0) ?? defaults.left
        var rightName = clean(team2Name) ?? participant(1) ?? defaults.right
        var leftTop: String?
        var leftBottom: String?
        var rightTop: String?
        var rightBottom: String?

        if sportType.supportsSinglesAndDoubles, !isSingles {
            leftTop = clean(redTopName) ?? participant(0) ?? doublesDefaults[0]
            leftBottom = clean(redBottomName) ?? participant(1) ?? doublesDefaults[1]
            rightTop = clean(blueTopName) ?? participant(2) ?? doublesDefaults[2]
            rightBottom = clean(blueBottomName) ?? participant(3) ?? doublesDefaults[3]
            leftName = clean(team1Name) ?? "\(leftTop!)/\(leftBottom!)"
            rightName = clean(team2Name) ?? "\(rightTop!)/\(rightBottom!)"
        }

        var setup = SportsSetupResult(team1Name: leftName, team2Name: rightName)
        setup.maxSets = maxSets
        setup.pointsPerSet = pointsPerSet
        setup.tieBreakPoints = tieBreakPoints
        setup.tennisDeuceMode = Self.normalizedTennisDeuceMode(tennisDeuceMode)

        if sportType.supportsSinglesAndDoubles {
            setup.isSingles = isSingles
            setup.team1Player1Name = leftTop
            setup.team1Player2Name = leftBottom
            setup.team2Player1Name = rightTop
            setup.team2Player2Name = rightBottom
        }

        switch gameType {
        case .basketball:
            setup.basketballMode = "five_v_five"
        case .nineBall:
            let names = participants.isEmpty ? [leftName, rightName] : Array(participants.prefix(4))
            setup.playerNames = names
            setup.playerCount = min(4, max(2, names.count))
        default:
            break
        }

        return BookingStartRequest(bookingId: id, gameType: gameType, setup: setup)
    }

    private static func normalizedTennisDeuceMode(_ value: String?) -> String? {
        value == "advantage" || value == "no_ad" ? value : nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, sportType, dateTime, scheduledAt, durationMinutes, location
        case locationLat, locationLng, latitude, longitude
        case gameFormat, matchFormat, matchMode, team1Name, team2Name
        case redTopName, redBottomName, blueTopName, blueBottomName
        case maxSets, pointsPerSet, tieBreakPoints, tennisDeuceMode, participantNames
        case notes, note, reminderMinutes, status, createdAt, updatedAt, completedAt, calendarEventId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let legacySportValue = (try? container.decode(String.self, forKey: .sportType)) ?? "other"
        sportType = (try? container.decode(BookingSportType.self, forKey: .sportType)) ?? .other

        if let value = try? container.decode(Date.self, forKey: .dateTime) {
            dateTime = value
        } else if let value = try? container.decode(Date.self, forKey: .scheduledAt) {
            dateTime = value
        } else if let milliseconds = try? container.decode(Double.self, forKey: .scheduledAt) {
            dateTime = Date(timeIntervalSince1970: milliseconds / 1_000)
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.dateTime,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing booking date")
            )
        }

        durationMinutes = Self.normalizedDuration(
            (try? container.decode(Int.self, forKey: .durationMinutes)) ?? Self.defaultDurationMinutes
        )
        location = (try? container.decode(String.self, forKey: .location)) ?? ""
        locationLat = Self.decodeOptionalDouble(container, primary: .locationLat, fallback: .latitude)
        locationLng = Self.decodeOptionalDouble(container, primary: .locationLng, fallback: .longitude)

        let decodedFormat = Self.decodeOptionalString(container, primary: .gameFormat, fallback: .matchFormat)
        if sportType == .billiards {
            let formatFromField = BookingBilliardsFormat(normalizing: decodedFormat)
            let formatFromLegacySport = BookingBilliardsFormat(normalizing: legacySportValue)
            gameFormat = formatFromField == .standard && formatFromLegacySport != .standard
                ? formatFromLegacySport.rawValue
                : formatFromField.rawValue
        } else {
            gameFormat = decodedFormat ?? ""
        }

        let decodedMode = (try? container.decodeIfPresent(BookingMatchMode.self, forKey: .matchMode)) ?? nil
        matchMode = sportType.supportsSinglesAndDoubles ? (decodedMode ?? .singles) : nil
        team1Name = (try? container.decodeIfPresent(String.self, forKey: .team1Name)) ?? nil
        team2Name = (try? container.decodeIfPresent(String.self, forKey: .team2Name)) ?? nil
        redTopName = (try? container.decodeIfPresent(String.self, forKey: .redTopName)) ?? nil
        redBottomName = (try? container.decodeIfPresent(String.self, forKey: .redBottomName)) ?? nil
        blueTopName = (try? container.decodeIfPresent(String.self, forKey: .blueTopName)) ?? nil
        blueBottomName = (try? container.decodeIfPresent(String.self, forKey: .blueBottomName)) ?? nil
        maxSets = Self.decodePositiveInt(container, key: .maxSets)
        pointsPerSet = Self.decodePositiveInt(container, key: .pointsPerSet)
        tieBreakPoints = Self.decodePositiveInt(container, key: .tieBreakPoints)
        tennisDeuceMode = Self.normalizedTennisDeuceMode(
            (try? container.decodeIfPresent(String.self, forKey: .tennisDeuceMode)) ?? nil
        )
        participantNames = Self.normalizedParticipants(
            (try? container.decode([String].self, forKey: .participantNames)) ?? []
        )
        notes = Self.decodeOptionalString(container, primary: .notes, fallback: .note) ?? ""
        reminderMinutes = Self.normalizedReminders(
            (try? container.decodeIfPresent([Int].self, forKey: .reminderMinutes))
                ?? Self.defaultReminderMinutes
        )
        status = (try? container.decode(BookingStatus.self, forKey: .status)) ?? .pending
        createdAt = (try? container.decode(Date.self, forKey: .createdAt)) ?? dateTime
        updatedAt = (try? container.decode(Date.self, forKey: .updatedAt)) ?? createdAt
        completedAt = (try? container.decodeIfPresent(Date.self, forKey: .completedAt)) ?? nil
        calendarEventId = (try? container.decodeIfPresent(String.self, forKey: .calendarEventId)) ?? nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sportType, forKey: .sportType)
        try container.encode(dateTime, forKey: .dateTime)
        try container.encode(durationMinutes, forKey: .durationMinutes)
        try container.encode(location, forKey: .location)
        try container.encodeIfPresent(locationLat, forKey: .locationLat)
        try container.encodeIfPresent(locationLng, forKey: .locationLng)
        try container.encode(gameFormat, forKey: .gameFormat)
        try container.encode(gameFormat, forKey: .matchFormat)
        try container.encodeIfPresent(matchMode, forKey: .matchMode)
        try container.encodeIfPresent(team1Name, forKey: .team1Name)
        try container.encodeIfPresent(team2Name, forKey: .team2Name)
        try container.encodeIfPresent(redTopName, forKey: .redTopName)
        try container.encodeIfPresent(redBottomName, forKey: .redBottomName)
        try container.encodeIfPresent(blueTopName, forKey: .blueTopName)
        try container.encodeIfPresent(blueBottomName, forKey: .blueBottomName)
        try container.encodeIfPresent(maxSets, forKey: .maxSets)
        try container.encodeIfPresent(pointsPerSet, forKey: .pointsPerSet)
        try container.encodeIfPresent(tieBreakPoints, forKey: .tieBreakPoints)
        try container.encodeIfPresent(tennisDeuceMode, forKey: .tennisDeuceMode)
        try container.encode(participantNames, forKey: .participantNames)
        try container.encode(notes, forKey: .notes)
        try container.encode(notes, forKey: .note)
        try container.encode(reminderMinutes, forKey: .reminderMinutes)
        try container.encode(status, forKey: .status)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(calendarEventId, forKey: .calendarEventId)
    }

    private static func decodeOptionalString(
        _ container: KeyedDecodingContainer<CodingKeys>,
        primary: CodingKeys,
        fallback: CodingKeys
    ) -> String? {
        if let value = try? container.decode(String.self, forKey: primary) {
            return value
        }
        if let value = try? container.decode(String.self, forKey: fallback) {
            return value
        }
        return nil
    }

    private static func decodeOptionalDouble(
        _ container: KeyedDecodingContainer<CodingKeys>,
        primary: CodingKeys,
        fallback: CodingKeys
    ) -> Double? {
        if let value = try? container.decode(Double.self, forKey: primary) {
            return value
        }
        if let value = try? container.decode(Double.self, forKey: fallback) {
            return value
        }
        return nil
    }

    private static func decodePositiveInt(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Int? {
        guard let value = try? container.decode(Int.self, forKey: key),
              value > 0 else {
            return nil
        }
        return value
    }
}
