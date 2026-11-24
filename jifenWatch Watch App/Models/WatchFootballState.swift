import Foundation
import ScoreCore

/// One undo frame of a watch-local football match: both goal counts plus the
/// clock snapshot captured before the mutation.
struct WatchFootballUndoState: Codable, Equatable, Sendable {
    let leftScore: Int
    let rightScore: Int
    let clock: FootballTimerStateV2
}

/// Full resumable football state. `clock` is the anchored
/// `FootballTimerStateV2`; live elapsed time is recomputed on restore.
struct WatchFootballState: Codable, Equatable, Sendable {
    var leftScore: Int
    var rightScore: Int
    var clock: FootballTimerStateV2
    /// 5-a-side keeps a pre-kick-off state where no time is shown. Optional so
    /// sessions written before the kick-off button existed still decode.
    var kickedOff: Bool?

    init(
        leftScore: Int = 0,
        rightScore: Int = 0,
        clock: FootballTimerStateV2 = .init(),
        kickedOff: Bool? = nil
    ) {
        self.leftScore = max(0, leftScore)
        self.rightScore = max(0, rightScore)
        self.clock = clock
        self.kickedOff = kickedOff
    }
}

/// Presentation helpers shared by the football board, the resume bar and tests.
enum WatchFootballRules {
    static func gameType(isFiveAside: Bool) -> GameType {
        isFiveAside ? .football5v5 : .football
    }

    static func watchGameType(isFiveAside: Bool) -> WatchGameType {
        isFiveAside ? .football5v5 : .football
    }

    /// Phone-aligned period badges: 1H/2H for regulation, 1T/2T for extra time.
    static func stageBadge(_ stage: Int) -> String {
        switch stage {
        case 1: return "1H"
        case 2: return "2H"
        case 3: return "1T"
        default: return "2T"
        }
    }

    static func stageTitle(_ stage: Int) -> String {
        switch stage {
        case 1: return NSLocalizedString("football_first_half", value: "上半场", comment: "")
        case 2: return NSLocalizedString("football_second_half", value: "下半场", comment: "")
        case 3: return NSLocalizedString("football_extra_time_first", value: "加时上半场", comment: "")
        default: return NSLocalizedString("football_extra_time_second", value: "加时下半场", comment: "")
        }
    }

    static func formattedClock(seconds: Int) -> String {
        let safe = max(0, seconds)
        return String(format: "%02d:%02d", safe / 60, safe % 60)
    }

    static func formattedStoppage(seconds: Int) -> String {
        "+" + formattedClock(seconds: seconds)
    }

    /// Goal label on the match clock, aligned with Harmony's
    /// `FootballMatchClockSession.goalMinuteLabel`: "53′" in normal play,
    /// "45+2′" once the half has run past its regulation length.
    static func goalMinuteLabel(
        isFiveAside: Bool,
        halfLengthSeconds: Int,
        period: Int?,
        elapsedSeconds: Int?
    ) -> String? {
        FootballGoalMinute.label(
            isFiveAside: isFiveAside,
            halfLengthSeconds: halfLengthSeconds,
            period: period,
            elapsedSeconds: elapsedSeconds
        )
    }
}
