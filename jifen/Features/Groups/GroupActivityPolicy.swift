import Foundation

nonisolated enum GroupActivityPolicy {
    static let defaultJoinPolicy = "open"
    static let commonDurations = [20, 30, 45, 60]

    static func validText(title: String, place: String, note: String = "") -> Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count <= 40
            && place.utf16.count <= 80 && note.utf16.count <= 300
    }

    static func minimumCapacity(format: GroupFormat, registeredCount: Int = 0) -> Int {
        max(format.seatsPerSide * 2, registeredCount)
    }

    static func validCapacity(_ capacity: Int, format: GroupFormat, registeredCount: Int = 0) -> Bool {
        capacity >= minimumCapacity(format: format, registeredCount: registeredCount) && capacity <= 100
    }

    static func durationOptions(current: Int) -> [Int] {
        commonDurations.contains(current) ? commonDurations : (commonDurations + [current]).sorted()
    }
}

/// Keep action gates in the write boundary as well as the visible controls.
nonisolated enum GroupWriteCapability {
    static func required(for path: String, method: HTTPMethod) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        let last = parts.last ?? ""
        if parts.isEmpty { return method == .post ? "create_group" : nil }
        if parts.first == "by-number" { return method == .post && parts.last == "join" ? "join_group" : nil }
        guard parts.first != "join-requests" else { return nil }
        if parts.count == 1 { return method == .patch ? "manage_group" : nil }
        switch parts[1] {
        case "direct-lineups": return method == .post ? "create_activity" : nil
        case "activities":
            if parts.count == 2 { return method == .post ? "create_activity" : nil }
            if parts.count == 3 { return method == .patch ? "update_activity" : nil }
            if ["register", "unregister"].contains(last), method == .post { return "register_activity" }
            if last == "lineup", method == .put { return "update_activity" }
            return ["cancel", "complete"].contains(last) && method == .post ? "update_activity" : nil
        case "games": return parts.count == 2 && method == .post ? "start_game" : nil
        case "results":
            if parts.count == 2 { return method == .post ? "submit_result" : nil }
            guard method == .post else { return nil }
            if parts.last == "confirm" { return "confirm_result" }
            return parts.last == "void" ? "void_result" : nil
        case "members": return [.post, .patch].contains(method) ? "manage_members" : nil
        case "archive", "restore", "dissolve", "ownership-transfer": return method == .post ? "manage_group" : nil
        case "join-requests": return method == .post ? "manage_members" : nil
        default: return nil
        }
    }
}

nonisolated extension GroupDirectLineupBody {
    func anchored(now: Date) -> GroupDirectLineupBody {
        let current = Int64(now.timeIntervalSince1970 * 1000)
        guard startsAt <= current else { return self }
        let delta = current + 60_000 - startsAt
        var value = self
        value.startsAt += delta
        value.sessions = sessions.map { row in var shifted = row; shifted.startsAt += delta; return shifted }
        return value
    }
}

nonisolated extension GroupTrainingDraftSession {
    func body(orderNo: Int) -> GroupTrainingSessionBody {
        var seats: [GroupSeat] = []
        if memberIDs.count == 4 {
            for side in 0..<2 {
                for seat in 0..<format.seatsPerSide {
                    let id = memberIDs[side * 2 + seat]
                    if !id.isEmpty { seats.append(.init(memberId: id, side: side == 0 ? "A" : "B", seat: seat)) }
                }
            }
        }
        return .init(orderNo: orderNo, court: court.trimmingCharacters(in: .whitespacesAndNewlines),
                     startsAt: Int64(startsAt.timeIntervalSince1970 * 1000), format: format, seats: seats, id: serverID)
    }

    func matches(_ original: GroupActivitySession, orderNo: Int) -> Bool {
        let expected = GroupTrainingSessionBody(orderNo: original.orderNo, court: original.court,
            startsAt: original.startsAt, format: original.format,
            seats: original.seats.sorted { ($0.side, $0.seat) < ($1.side, $1.seat) }
                .map { .init(memberId: $0.memberId, side: $0.side, seat: $0.seat) }, id: original.id)
        return body(orderNo: orderNo) == expected
    }
}
