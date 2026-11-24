import Foundation

/// Match-minute label for a football goal: `53′` in normal play, `45+2′` once
/// the half has run past its regulation length.
///
/// The wording mirrors Android's `WearRecordDetailActionFormatter.footballGoalMinute`
/// and Harmony's `FootballMatchClockSession.goalMinuteLabel` so a record reads
/// the same on every platform.
/// Encodes the football match-clock snapshot into the line-score action string
/// (`...|scores||football:<period>:<elapsed>`) and back.
public enum FootballClockAnnotation {
    public static let prefix = "football"

    public static func encode(period: Int, elapsedSeconds: Int) -> String? {
        guard (1...4).contains(period), elapsedSeconds >= 0 else { return nil }
        return "\(prefix):\(period):\(elapsedSeconds)"
    }

    public static func decode(_ token: String) -> (period: Int, elapsedSeconds: Int)? {
        let parts = token.split(separator: ":")
        guard parts.count == 3,
              parts[0] == prefix,
              let period = Int(parts[1]),
              let elapsed = Int(parts[2]),
              (1...4).contains(period),
              elapsed >= 0 else {
            return nil
        }
        return (period, elapsed)
    }
}

public enum FootballGoalMinute {
    public static let regulationHalfMinutes = 45
    public static let defaultFiveASideHalfMinutes = 20
    public static let extraHalfMinutes = 15

    public static func label(
        isFiveAside: Bool,
        halfLengthSeconds: Int?,
        period: Int?,
        elapsedSeconds: Int?
    ) -> String? {
        guard let period, (1...4).contains(period) else { return nil }
        if isFiveAside, period > 2 { return nil }
        guard let elapsedSeconds, elapsedSeconds >= 0 else { return nil }

        let halfMinutes: Int
        if isFiveAside {
            let configured = halfLengthSeconds ?? (defaultFiveASideHalfMinutes * 60)
            halfMinutes = max(1, min(90, max(60, configured) / 60))
        } else {
            halfMinutes = regulationHalfMinutes
        }

        let periodMinutes = period >= 3 ? extraHalfMinutes : halfMinutes
        let baseMinutes: Int
        switch period {
        case 1: baseMinutes = 0
        case 2: baseMinutes = halfMinutes
        case 3: baseMinutes = 2 * halfMinutes
        default: baseMinutes = 2 * halfMinutes + extraHalfMinutes
        }

        if elapsedSeconds > periodMinutes * 60 {
            let injury = (elapsedSeconds - periodMinutes * 60 + 59) / 60
            return "\(baseMinutes + periodMinutes)+\(injury)′"
        }
        let minute = max(1, (elapsedSeconds + 59) / 60)
        return "\(baseMinutes + minute)′"
    }
}
