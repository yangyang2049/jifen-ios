import Foundation
import LinkCore
import RecordCore
import ScoreCore

typealias WatchRecordParticipant = RecordParticipantScore

/// Watch presentation over the same canonical record stored on disk and sent to iPhone.
struct WatchScoreboardRecord: Codable, Identifiable {
    let canonical: CanonicalMatchRecord
    let gameType: WatchGameType

    var id: String { canonical.id }
    var startTime: Date { Date(timeIntervalSince1970: Double(canonical.startEpochMilliseconds) / 1_000) }
    var endTime: Date { Date(timeIntervalSince1970: Double(canonical.endEpochMilliseconds) / 1_000) }
    var duration: TimeInterval { canonical.durationSeconds }
    var team1Name: String { canonical.team1Name }
    var team2Name: String { canonical.team2Name }
    var team1FinalScore: Int { canonical.team1FinalScore }
    var team2FinalScore: Int { canonical.team2FinalScore }
    var team1SetScore: Int { canonical.team1SetScore ?? 0 }
    var team2SetScore: Int { canonical.team2SetScore ?? 0 }
    var winnerIdentity: ScoreboardWinnerIdentity? { canonical.winnerIdentity }
    var actions: [DetailedScoreAction] { canonical.detailedActions }
    var totalScoreChanges: Int { canonical.totalScoreChanges }
    var participants: [WatchRecordParticipant]? { canonical.participants }
    var projectConfiguration: [String: String]? { canonical.projectConfiguration.isEmpty ? nil : canonical.projectConfiguration }
    var basketballTrainingDetails: ScoreCore.ShotTrainingState? { canonical.basketballTraining }

    init?(canonical: CanonicalMatchRecord) {
        switch canonical.kind {
        case .counter:
            gameType = .counter
        case .sport(let type):
            guard let mapped = WatchGameType(scoreCoreGameType: type) else { return nil }
            gameType = mapped
        }
        self.canonical = canonical
    }

    init?(
        localSnapshot: LinkedScoreboardSnapshot,
        gameType: ScoreCore.GameType,
        id: String,
        startTime: Date,
        endTime: Date,
        participantNames: [String] = [],
        winnerSide: MatchSide? = nil,
        detailedActions: [DetailedScoreAction],
        totalScoreChanges: Int,
        additionalConfiguration: [String: String] = [:]
    ) {
        self.init(canonical: MatchRecordProjector.canonicalRecord(
            id: id, kind: .sport(gameType), source: .watchLocal,
            snapshot: localSnapshot, gameType: gameType, winnerSide: winnerSide,
            startEpochMilliseconds: Int64((startTime.timeIntervalSince1970 * 1_000).rounded()),
            endEpochMilliseconds: Int64((endTime.timeIntervalSince1970 * 1_000).rounded()),
            durationSeconds: endTime.timeIntervalSince(startTime), participantNames: participantNames,
            detailedActions: detailedActions, totalScoreChanges: totalScoreChanges,
            additionalConfiguration: additionalConfiguration
        ))
    }

    init(from decoder: Decoder) throws {
        let canonical = try CanonicalMatchRecord(from: decoder)
        guard canonical.schemaVersion == CanonicalMatchRecord.currentSchemaVersion,
              let record = Self(canonical: canonical) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "Unsupported Watch record schema or sport"
            ))
        }
        self = record
    }

    func encode(to encoder: Encoder) throws {
        try canonical.encode(to: encoder)
    }

    var winnerName: String? {
        switch winnerIdentity {
        case .team(.team0): return team1Name
        case .team(.team1): return team2Name
        case .participant(let index):
            guard let participants, participants.indices.contains(index) else { return nil }
            return participants[index].name
        case nil: return nil
        }
    }

    func isWinner(at position: Int) -> Bool {
        switch winnerIdentity {
        case .team(.team0): return position == 0
        case .team(.team1): return position == 1
        case .participant(let index): return position == index
        case nil: return false
        }
    }
}

struct WatchScoreboardRecordSummary: Identifiable, Codable, Equatable {
    let id: String
    let gameType: WatchGameType
    let timestamp: TimeInterval
    let dateText: String
    let timeText: String
    var duration: TimeInterval
    let team1Name: String
    let team2Name: String
    let team1FinalScore: Int
    let team2FinalScore: Int
    var team1SetScore: Int
    var team2SetScore: Int
    let winnerIdentity: ScoreboardWinnerIdentity?
    var participants: [WatchRecordParticipant]?
    var projectConfiguration: [String: String]?

    /// 静态缓存 formatter（DateFormatter 实例化代价高，init 每次新建会拖慢
    /// 列表首载）。DateFormatter 非线程安全，所有取用都在 NSLock 临界区内
    /// 完成格式切换与格式化，输出行为与每次新建时一致。
    private static let formatterLock = NSLock()
    private static let sharedFormatter = DateFormatter()

    init(from record: WatchScoreboardRecord) {
        self.id = record.id
        self.gameType = record.gameType
        self.timestamp = record.startTime.timeIntervalSince1970
        self.duration = record.duration
        self.team1Name = record.team1Name
        self.team2Name = record.team2Name
        self.team1FinalScore = record.team1FinalScore
        self.team2FinalScore = record.team2FinalScore
        self.team1SetScore = record.team1SetScore
        self.team2SetScore = record.team2SetScore
        self.winnerIdentity = record.winnerIdentity
        self.participants = record.participants
        self.projectConfiguration = record.projectConfiguration

        let calendar = Calendar.current
        let sameYear = calendar.isDate(record.startTime, equalTo: Date(), toGranularity: .year)

        Self.formatterLock.lock()
        defer { Self.formatterLock.unlock() }
        let formatter = Self.sharedFormatter
        // Same year: format without year; different year: format with year.
        formatter.dateFormat = sameYear ? "MM-dd" : "yyyy-MM-dd"
        self.dateText = formatter.string(from: record.startTime)
        formatter.dateFormat = "HH:mm"
        self.timeText = formatter.string(from: record.startTime)
    }

    static func == (lhs: WatchScoreboardRecordSummary, rhs: WatchScoreboardRecordSummary) -> Bool {
        lhs.id == rhs.id
    }

    var doublesTeamNames: (left: String, right: String)? {
        watchDoublesTeamNames(gameType: gameType, participants: participants)
    }

    var listDisplayText: String {
        let usePointScore = watchRecordUsesPointScore(
            gameType: gameType,
            projectConfiguration: projectConfiguration,
            hasSetScore: team1SetScore != 0 || team2SetScore != 0
        )
        let leftScore = usePointScore ? team1FinalScore : team1SetScore
        let rightScore = usePointScore ? team2FinalScore : team2SetScore

        if let doublesTeamNames {
            return "\(doublesTeamNames.left) \(leftScore) - \(doublesTeamNames.right) \(rightScore)"
        }
        if let participants, participants.count > 2 {
            return participants
                .map { "\($0.name) \($0.score)" }
                .joined(separator: " · ")
        }
        return "\(team1Name) \(leftScore) - \(rightScore) \(team2Name)"
    }
}

extension WatchScoreboardRecord {
    var doublesTeamNames: (left: String, right: String)? {
        watchDoublesTeamNames(gameType: gameType, participants: participants)
    }

    var usesPointScoreForDisplay: Bool {
        watchRecordUsesPointScore(
            gameType: gameType,
            projectConfiguration: projectConfiguration,
            hasSetScore: team1SetScore != 0 || team2SetScore != 0
        )
    }
}

private func watchRecordUsesPointScore(
    gameType: WatchGameType,
    projectConfiguration: [String: String]?,
    hasSetScore: Bool
) -> Bool {
    if gameType.usesPointScoreInList
        || (gameType == .tennis && projectConfiguration?["setScoringMode"] == "tiebreak_only") {
        return true
    }
    switch gameType {
    case .badminton, .pingpong, .pickleball, .tennis, .shuttlecock, .squash, .foosball:
        return !hasSetScore
    default:
        return false
    }
}

private func watchDoublesTeamNames(
    gameType: WatchGameType,
    participants: [WatchRecordParticipant]?
) -> (left: String, right: String)? {
    guard gameType == .pingpong || gameType == .badminton ||
            gameType == .tennis || gameType == .pickleball,
          let participants,
          participants.count >= 4 else {
        return nil
    }
    return (
        "\(participants[0].name)/\(participants[2].name)",
        "\(participants[1].name)/\(participants[3].name)"
    )
}

func watchFormatDuration(_ duration: TimeInterval) -> String {

    let totalSeconds = Int(duration)

    let hours = totalSeconds / 3600

    let minutes = (totalSeconds % 3600) / 60

    let seconds = totalSeconds % 60

    

    let hourUnit = NSLocalizedString("unit_hour", value: "时", comment: "Hour unit")

    let minUnit = NSLocalizedString("unit_minute", value: "分", comment: "Minute unit")

    let secUnit = NSLocalizedString("unit_second", value: "秒", comment: "Second unit")

    

    if hours > 0 {

        return String(format: "%d%@%d%@%d%@", hours, hourUnit, minutes, minUnit, seconds, secUnit)

    }

    if minutes > 0 {

        return String(format: "%d%@%d%@", minutes, minUnit, seconds, secUnit)

    }

    return String(format: "%d%@", seconds, secUnit)

}



func watchFormatDisplayDate(_ dateStr: String) -> String {

    let formatter = DateFormatter()

    formatter.locale = Locale(identifier: "en_US_POSIX")

    formatter.dateFormat = "yyyy-MM-dd"

    guard let date = formatter.date(from: dateStr) else {

        return dateStr

    }

    let calendar = Calendar.current

    if calendar.isDateInToday(date) {

        return NSLocalizedString("today", value: "今天", comment: "Today")

    }

    if calendar.isDateInYesterday(date) {

        return NSLocalizedString("yesterday", value: "昨天", comment: "Yesterday")

    }

    

    return date.formatted(.dateTime.month(.defaultDigits).day())

}
