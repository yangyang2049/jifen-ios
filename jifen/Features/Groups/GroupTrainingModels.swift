import Foundation

nonisolated struct GroupTrainingSession: Codable, Identifiable, Sendable {
    var id: String; var planId: String; var groupId: String; var orderNo: Int
    var court: String; var startsAt: Int64; var endsAt: Int64; var format: GroupFormat
    var status: String; var resultId: String; var seats: [GroupSeat]; var mySide: String?
    var startedGameId: String? = nil
    var resultID: String? { resultId.isEmpty ? nil : resultId }
    var date: Date { Date(timeIntervalSince1970: Double(startsAt) / 1000) }
}

/// 排期草案保存时服务端回传的软提示（对齐安卓 `GroupTrainingWarning`）。
nonisolated struct GroupTrainingWarning: Codable, Sendable {
    var kind: String
    var sessionOrderNo: Int?
    var message: String?
}

nonisolated struct GroupTrainingPlan: Codable, Identifiable, Sendable {
    var id: String; var groupId: String; var creatorMemberId: String
    var trainingDate: Int64; var startsAt: Int64; var endsAt: Int64; var sessionMinutes: Int
    var place: String; var note: String; var status: String; var cancelReason: String
    var publishedAt: Int64; var sessionCount: Int; var mySessionCount: Int
    var sessions: [GroupTrainingSession]; var createdAt: Int64; var revision: Int64
    var placeLocked: Bool? = nil
    var warnings: [GroupTrainingWarning]? = nil
}

nonisolated struct GroupLeaveNotice: Codable, Identifiable, Sendable {
    var id: String; var groupId: String; var planId: String; var sessionId: String
    var memberId: String; var reason: String; var status: String; var createdAt: Int64
    var sessionStartsAt: Int64? = nil
    var sessionOrderNo: Int? = nil
    var court: String? = nil
    var displayName: String? = nil
    var invalidated: Bool? = nil
    var updatedAt: Int64? = nil
}

nonisolated struct GroupTrainingSessionBody: Codable, Sendable, Equatable {
    var orderNo: Int; var court: String; var startsAt: Int64; var format: GroupFormat
    var seats: [GroupSeat]
    var id: String? = nil
}

nonisolated struct GroupTrainingPlanBody: Encodable, Sendable {
    var trainingDate: Int64; var sessionMinutes: Int; var place: String; var note: String
    var sessions: [GroupTrainingSessionBody]
}

nonisolated struct GroupTrainingPlanPatch: Encodable, Sendable {
    var place: String; var note: String; var sessionMinutes: Int?
    var sessions: [GroupTrainingSessionBody]?
    var trainingDate: Int64? = nil
    init(place: String, note: String, minutes: Int, sessions: [GroupTrainingSessionBody], hasResults: Bool) {
        self.place = place; self.note = note
        self.sessionMinutes = hasResults ? nil : minutes
        self.sessions = hasResults ? nil : sessions
    }
}

nonisolated enum GroupReportReason: String, CaseIterable, Identifiable, Sendable {
    case spam = "SPAM", harassment = "HARASSMENT", inappropriate = "INAPPROPRIATE"
    case fraud = "FRAUD", illegal = "ILLEGAL", impersonation = "IMPERSONATION", other = "OTHER"
    var id: String { rawValue }
    var title: String { groupText("report_" + rawValue.lowercased(), rawValue.capitalized) }
}

/// The direct editor and submission share raw draft times; only submission clamps a past date.
nonisolated struct GroupDirectScheduleDraft {
    var date: Date {
        didSet { sessions = GroupTrainingValidation.shiftAll(sessions, by: date.timeIntervalSince(oldValue)) }
    }
    var timingMode = "sequence"
    var minutes = 30
    var sessions: [GroupTrainingDraftSession]

    init(date: Date = Date().addingTimeInterval(600)) {
        self.date = date
        var first = GroupTrainingDraftSession(); first.startsAt = date
        sessions = [first]
    }
    mutating func add(format: GroupFormat) {
        var next = GroupTrainingDraftSession(); next.format = format
        next.startsAt = sessions.map { $0.startsAt.addingTimeInterval(Double(minutes) * 60) }.max() ?? date
        sessions.append(next)
    }
    func scheduled(now: Date) -> (startsAt: Date, sessions: [GroupTrainingDraftSession]) {
        GroupTrainingValidation.anchored(sessions, startsAt: date, now: now)
    }
}
