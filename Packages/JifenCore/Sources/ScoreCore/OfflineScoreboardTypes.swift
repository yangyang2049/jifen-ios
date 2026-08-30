import Foundation

/// Stable setup format shared by the phone UI and persisted records.
public enum CompetitionFormat: String, Codable, CaseIterable, Sendable {
    case singles
    case doubles
    case mixedDoubles = "mixed_doubles"
    case team
}

public enum TennisFamilyRuleProfile: String, Codable, CaseIterable, Sendable {
    case tennis
    case softTennis = "soft_tennis"
    case padel
}

public enum PadelDeuceMode: String, Codable, CaseIterable, Sendable {
    case advantage
    case goldenPoint = "golden_point"
    case starPoint = "star_point"
}

public enum OfficialBreakSport: String, Codable, CaseIterable, Sendable {
    case badminton
    case pingpong
    case tennis
    case pickleball
    case squash
    case shuttlecock
    case softTennis = "soft_tennis"
    case padel
}

public enum OfficialBreakKind: String, Codable, Sendable {
    case midGame = "mid_game"
    case gameBreak = "game_break"
    case setBreak = "set_break"
    case changeover
    case timeout
    case medical

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "mid_set": self = .midGame
        case "between_sets": self = .gameBreak
        case "medical_timeout": self = .medical
        default:
            guard let value = Self(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown official break kind: \(rawValue)")
            }
            self = value
        }
    }
}

public enum OfficialBreakPhase: String, Codable, Sendable {
    case countdown
    case preparation
}

/// Identifies why an official-break overlay is active. Android 3.1 treats
/// table-tennis timeout/medical overlays as administrative actions: they use
/// the shared countdown UI, but never participate in official-break voice
/// announcements.
public enum OfficialBreakSource: String, Codable, Sendable {
    case official
    case administrative
}

/// Voice milestones emitted by Android 3.1's official-break host.
public enum OfficialBreakCue: String, Codable, Hashable, Sendable {
    case start
    case twentySeconds = "twenty_seconds"
    case halfTime = "half_time"
    case fifteenSeconds = "fifteen_seconds"
    case time
    case complete
    case earlyResume = "early_resume"
}

/// Returns only warnings crossed close enough to their threshold to still be
/// useful. A long background jump deliberately does not replay stale calls.
public func officialBreakCuesCrossed(
    sport: OfficialBreakSport,
    previousRemainingMilliseconds: Int64,
    currentRemainingMilliseconds: Int64,
    graceMilliseconds: Int64 = 1_500
) -> [OfficialBreakCue] {
    let thresholds: [(Int64, OfficialBreakCue)] = switch sport {
    case .badminton:
        [(20_000, .twentySeconds)]
    case .tennis, .padel:
        [(30_000, .time)]
    case .squash:
        [(45_000, .halfTime), (15_000, .fifteenSeconds)]
    case .pingpong, .pickleball, .shuttlecock, .softTennis:
        []
    }
    return thresholds.compactMap { threshold, cue in
        let crossed = previousRemainingMilliseconds > threshold
            && currentRemainingMilliseconds <= threshold
        let stillCurrent = currentRemainingMilliseconds >= threshold - max(0, graceMilliseconds)
        return crossed && stillCurrent ? cue : nil
    }
}

public enum OfficialBreakAfterAction: String, Codable, Sendable {
    case none
    case advancePeriod = "advance_period"
    case exchangeSides = "exchange_sides"
    case advanceAndExchange = "advance_and_exchange"
}

public struct OfficialBreakState: Codable, Equatable, Sendable {
    public var sport: OfficialBreakSport
    public var kind: OfficialBreakKind
    public var source: OfficialBreakSource
    public var phase: OfficialBreakPhase
    public var durationSeconds: Int
    public var remainingSeconds: Int
    public var isRunning: Bool
    public var startedWallClockMilliseconds: Int64
    public var updatedWallClockMilliseconds: Int64
    public var afterAction: OfficialBreakAfterAction
    /// Optional project-specific heading, for example “暂停 · 张三”.
    public var title: String?

    public init(
        sport: OfficialBreakSport,
        kind: OfficialBreakKind,
        durationSeconds: Int,
        source: OfficialBreakSource = .official,
        afterAction: OfficialBreakAfterAction = .none,
        title: String? = nil,
        nowMilliseconds: Int64 = 0
    ) {
        self.sport = sport
        self.kind = kind
        self.source = source
        self.phase = .countdown
        self.durationSeconds = max(1, durationSeconds)
        self.remainingSeconds = max(1, durationSeconds)
        self.isRunning = true
        self.startedWallClockMilliseconds = max(0, nowMilliseconds)
        self.updatedWallClockMilliseconds = max(0, nowMilliseconds)
        self.afterAction = afterAction
        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = normalizedTitle?.isEmpty == false ? normalizedTitle : nil
    }

    private enum CodingKeys: String, CodingKey {
        case sport, kind, source, phase, durationSeconds, remainingSeconds
        case isRunning, startedWallClockMilliseconds, updatedWallClockMilliseconds
        case afterAction, title
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sport = try container.decode(OfficialBreakSport.self, forKey: .sport)
        kind = try container.decode(OfficialBreakKind.self, forKey: .kind)
        // Pre-source snapshots can still contain an in-progress ping-pong
        // timeout. Those two kinds have only ever represented administrative
        // actions, so migrate them to the silent source. All ordinary breaks
        // keep the legacy official behavior.
        source = try container.decodeIfPresent(OfficialBreakSource.self, forKey: .source)
            ?? (kind == .timeout || kind == .medical ? .administrative : .official)
        phase = try container.decode(OfficialBreakPhase.self, forKey: .phase)
        durationSeconds = try container.decode(Int.self, forKey: .durationSeconds)
        remainingSeconds = try container.decode(Int.self, forKey: .remainingSeconds)
        isRunning = try container.decode(Bool.self, forKey: .isRunning)
        startedWallClockMilliseconds = try container.decode(Int64.self, forKey: .startedWallClockMilliseconds)
        updatedWallClockMilliseconds = try container.decode(Int64.self, forKey: .updatedWallClockMilliseconds)
        afterAction = try container.decode(OfficialBreakAfterAction.self, forKey: .afterAction)
        title = try container.decodeIfPresent(String.self, forKey: .title)
    }
}

/// Shared official-break state machine. It is intentionally independent of a
/// scoreboard reducer: a break freezes score input, can be skipped or undone,
/// and can be reconstructed from a wall-clock anchor after suspension.
public struct OfficialBreakSession: Sendable {
    public private(set) var state: OfficialBreakState?
    private var history: [OfficialBreakState?] = []

    public init(state: OfficialBreakState? = nil) {
        self.state = state
        // A restored active break was originally entered from “no break”. Keep
        // that predecessor so the on-screen Undo action remains functional after
        // background/process restoration.
        if state != nil {
            history = [nil]
        }
    }

    public var inputFrozen: Bool { state?.isRunning == true }

    public mutating func begin(
        sport: OfficialBreakSport,
        kind: OfficialBreakKind,
        durationSeconds: Int,
        source: OfficialBreakSource = .official,
        afterAction: OfficialBreakAfterAction = .none,
        title: String? = nil,
        nowMilliseconds: Int64 = 0
    ) {
        history.append(state)
        state = OfficialBreakState(
            sport: sport,
            kind: kind,
            durationSeconds: durationSeconds,
            source: source,
            afterAction: afterAction,
            title: title,
            nowMilliseconds: nowMilliseconds
        )
    }

    /// Advances the state by elapsed wall-clock seconds. Returns true once the
    /// break has completed and input may be unfrozen.
    @discardableResult
    public mutating func advance(seconds: Int) -> Bool {
        guard seconds > 0, var current = state, current.isRunning else {
            return state?.isRunning == false
        }
        // Android 3.1 includes the final three-second preparation phase in the
        // advertised break duration instead of appending another three seconds.
        current.remainingSeconds = max(0, current.remainingSeconds - seconds)
        current.phase = current.remainingSeconds <= 3 ? .preparation : .countdown
        current.isRunning = current.remainingSeconds > 0
        state = current
        return !current.isRunning
    }

    @discardableResult
    public mutating func tick(nowMilliseconds: Int64) -> Bool {
        guard var current = state, current.isRunning else { return true }
        let elapsed = max(0, Int((nowMilliseconds - current.updatedWallClockMilliseconds) / 1_000))
        // Consume only complete seconds so sub-second refreshes do not discard
        // fractional time and gradually stretch the break.
        if elapsed > 0 {
            current.updatedWallClockMilliseconds += Int64(elapsed * 1_000)
        }
        state = current
        return advance(seconds: elapsed)
    }

    public mutating func skip() {
        guard var current = state else { return }
        history.append(state)
        current.phase = .preparation
        current.remainingSeconds = 0
        current.isRunning = false
        state = current
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = history.popLast() else { return false }
        state = previous
        return true
    }

    public mutating func reconcileAfterRestore(nowMilliseconds: Int64) {
        _ = tick(nowMilliseconds: nowMilliseconds)
    }
}

/// Versioned football clock state. `elapsedSeconds` is authoritative at the
/// last persistence anchor; the injected clock computes live elapsed time.
public struct FootballTimerStateV2: Codable, Equatable, Sendable {
    public var stage: Int
    public var halfLengthSeconds: Int
    public var extraHalfLengthSeconds: Int
    public var elapsedSeconds: Int
    public var isRunning: Bool
    public var savedWallClockMilliseconds: Int64
    public var stoppageSeconds: [Int]

    public init(
        stage: Int = 1,
        halfLengthSeconds: Int = 45 * 60,
        extraHalfLengthSeconds: Int = 15 * 60,
        elapsedSeconds: Int = 0,
        isRunning: Bool = false,
        savedWallClockMilliseconds: Int64 = 0,
        stoppageSeconds: [Int] = [0, 0, 0, 0]
    ) {
        self.stage = min(4, max(1, stage))
        self.halfLengthSeconds = min(90 * 60, max(60, halfLengthSeconds))
        self.extraHalfLengthSeconds = min(90 * 60, max(60, extraHalfLengthSeconds))
        self.elapsedSeconds = max(0, elapsedSeconds)
        self.isRunning = isRunning
        self.savedWallClockMilliseconds = max(0, savedWallClockMilliseconds)
        self.stoppageSeconds = Array(stoppageSeconds.prefix(4)) + Array(repeating: 0, count: max(0, 4 - stoppageSeconds.count))
    }
}

public extension RallyRuleSet {
    static func shuttlecock(
        maxSets: Int = 3,
        pointsPerSet: Int = 21,
        matchCompletionMode: MatchCompletionMode = .bestOf
    ) -> Self {
        .init(
            maxSets: maxSets,
            pointsToWinSet: pointsPerSet,
            pointCap: nil,
            winByTwo: true,
            decidingSetSideSwitchPoint: max(1, (pointsPerSet + 1) / 2),
            matchCompletionMode: matchCompletionMode
        )
    }

    static func squash(
        maxSets: Int = 5,
        matchCompletionMode: MatchCompletionMode = .bestOf
    ) -> Self {
        .init(
            maxSets: maxSets,
            pointsToWinSet: 11,
            pointCap: nil,
            winByTwo: true,
            autoChangeSides: true,
            matchCompletionMode: matchCompletionMode
        )
    }
}

public extension TennisRuleSet {
    static func softTennis(
        maxSets _: Int = 1,
        gamesPerSet: Int = 7,
        matchCompletionMode _: MatchCompletionMode = .bestOf,
        autoChangeSides: Bool = true
    ) -> Self {
        .init(
            maxSets: 1,
            tieBreakPoints: 7,
            gamesPerSet: 4,
            matchCompletionMode: .bestOf,
            usesNoAdScoring: false,
            autoChangeSides: autoChangeSides,
            familyProfile: .softTennis,
            softTennisMatchGames: gamesPerSet
        )
    }

    static func padel(
        maxSets: Int = 3,
        deuceMode: PadelDeuceMode = .starPoint,
        autoChangeSides: Bool = true
    ) -> Self {
        .init(
            maxSets: maxSets,
            tieBreakPoints: 7,
            gamesPerSet: 6,
            autoChangeSides: autoChangeSides,
            familyProfile: .padel,
            padelDeuceMode: deuceMode
        )
    }
}

/// A deterministic, injectable clock used by football production code and
/// tests. Monotonic time is used while active; wall time is only used to
/// reconcile a saved running state after background/process restoration.
public protocol FootballClock: Sendable {
    func monotonicSeconds() -> Int64
    func wallClockMilliseconds() -> Int64
}

public struct SystemFootballClock: FootballClock {
    public init() {}

    public func monotonicSeconds() -> Int64 {
        Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000_000)
    }

    public func wallClockMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }
}

public struct FootballMatchClockSession: Sendable {
    public private(set) var state: FootballTimerStateV2
    private var monotonicAnchor: Int64?
    private let clock: any FootballClock
    public let gameType: GameType

    public init(
        state: FootballTimerStateV2 = .init(),
        gameType: GameType = .football,
        clock: any FootballClock = SystemFootballClock()
    ) {
        self.state = state
        self.gameType = gameType
        self.clock = clock
        self.monotonicAnchor = state.isRunning ? clock.monotonicSeconds() : nil
    }

    public var allowsManualPause: Bool { gameType == .football5v5 }
    public var allowsStoppageTime: Bool { gameType == .football }
    public var allowsExtraTime: Bool { gameType == .football }

    public var currentPeriodLengthSeconds: Int {
        state.stage >= 3 ? state.extraHalfLengthSeconds : state.halfLengthSeconds
    }

    public var currentStoppageSeconds: Int {
        guard state.stoppageSeconds.indices.contains(state.stage - 1) else { return 0 }
        return state.stoppageSeconds[state.stage - 1]
    }

    public var mainDisplaySeconds: Int {
        min(currentElapsedSeconds(), currentPeriodLengthSeconds)
    }

    public var elapsedStoppageSeconds: Int {
        max(0, currentElapsedSeconds() - currentPeriodLengthSeconds)
    }

    public var periodCompleted: Bool {
        !state.isRunning && currentElapsedSeconds() >= targetSeconds
    }

    public mutating func start() {
        settle()
        guard !state.isRunning, state.elapsedSeconds < targetSeconds else { return }
        state.isRunning = true
        state.savedWallClockMilliseconds = clock.wallClockMilliseconds()
        monotonicAnchor = clock.monotonicSeconds()
    }

    public mutating func pause() {
        settle()
        guard state.isRunning else { return }
        state.isRunning = false
        state.savedWallClockMilliseconds = clock.wallClockMilliseconds()
        monotonicAnchor = nil
    }

    public mutating func toggleRunning() {
        guard allowsManualPause else { return }
        state.isRunning ? pause() : start()
    }

    public mutating func advanceStage() -> Bool {
        switch state.stage {
        case 1: return switchToSecondHalf()
        case 2: return enterExtraTime()
        case 3: return switchToSecondExtraTimeHalf()
        default: return false
        }
    }

    public mutating func setStage(_ stage: Int) -> Bool {
        guard (1...4).contains(stage) else { return false }
        settle()
        state.isRunning = false
        monotonicAnchor = nil
        state.stage = stage
        state.elapsedSeconds = 0
        state.savedWallClockMilliseconds = clock.wallClockMilliseconds()
        return true
    }

    public mutating func switchToSecondHalf() -> Bool {
        settle()
        guard state.stage == 1 else { return false }
        beginStage(2)
        if gameType == .football { start() }
        return true
    }

    public mutating func enterExtraTime() -> Bool {
        settle()
        guard allowsExtraTime, state.stage == 2, periodCompleted else { return false }
        beginStage(3)
        start()
        return true
    }

    public mutating func switchToSecondExtraTimeHalf() -> Bool {
        settle()
        guard allowsExtraTime, state.stage == 3, periodCompleted else { return false }
        beginStage(4)
        start()
        return true
    }

    public mutating func addStoppageSeconds(_ seconds: Int) -> Bool {
        guard allowsStoppageTime,
              seconds > 0,
              state.stoppageSeconds.indices.contains(state.stage - 1) else { return false }
        settle()
        state.stoppageSeconds[state.stage - 1] += seconds
        if state.elapsedSeconds < targetSeconds, !state.isRunning {
            start()
        }
        return true
    }

    public mutating func undoStoppageSeconds(_ seconds: Int) -> Bool {
        guard allowsStoppageTime,
              seconds > 0,
              state.stoppageSeconds.indices.contains(state.stage - 1) else { return false }
        settle()
        let index = state.stage - 1
        guard state.stoppageSeconds[index] >= seconds else { return false }
        let next = state.stoppageSeconds[index] - seconds
        guard next >= elapsedStoppageSeconds else { return false }
        state.stoppageSeconds[index] = next
        return true
    }

    public mutating func reconcileAfterRestore() {
        let wasRunning = state.isRunning
        if wasRunning, state.savedWallClockMilliseconds > 0 {
            let elapsedWallSeconds = max(0, Int((clock.wallClockMilliseconds() - state.savedWallClockMilliseconds) / 1_000))
            state.elapsedSeconds = min(targetSeconds, state.elapsedSeconds + elapsedWallSeconds)
        } else {
            state.elapsedSeconds = min(targetSeconds, state.elapsedSeconds)
        }
        state.isRunning = if gameType == .football {
            state.elapsedSeconds < targetSeconds
        } else {
            wasRunning && state.elapsedSeconds < targetSeconds
        }
        state.savedWallClockMilliseconds = clock.wallClockMilliseconds()
        monotonicAnchor = state.isRunning ? clock.monotonicSeconds() : nil
    }

    /// Materializes the current elapsed value for persistence while keeping a
    /// running match running. The next read continues from this fresh anchor.
    public mutating func snapshot() -> FootballTimerStateV2 {
        settle()
        return state
    }

    /// Materializes live time and reports whether the current period reached
    /// its regulation-plus-stoppage limit.
    @discardableResult
    public mutating func refresh() -> Bool {
        settle()
        return periodCompleted
    }

    public mutating func resetForNewGame(halfLengthSeconds: Int? = nil) {
        let length = halfLengthSeconds ?? state.halfLengthSeconds
        state = FootballTimerStateV2(
            halfLengthSeconds: length,
            extraHalfLengthSeconds: state.extraHalfLengthSeconds,
            savedWallClockMilliseconds: clock.wallClockMilliseconds()
        )
        monotonicAnchor = nil
        if gameType == .football { start() }
    }

    public func elapsedSecondsNow() -> Int {
        currentElapsedSeconds()
    }

    public func isTimeUp() -> Bool {
        currentElapsedSeconds() >= targetSeconds
    }

    public var targetSeconds: Int {
        state.stage >= 3 ? state.extraHalfLengthSeconds + state.stoppageSeconds[state.stage - 1] : state.halfLengthSeconds + state.stoppageSeconds[state.stage - 1]
    }

    private func currentElapsedSeconds() -> Int {
        guard state.isRunning, let monotonicAnchor else { return min(state.elapsedSeconds, targetSeconds) }
        return min(targetSeconds, state.elapsedSeconds + max(0, Int(clock.monotonicSeconds() - monotonicAnchor)))
    }

    private mutating func settle() {
        guard state.isRunning, monotonicAnchor != nil else {
            state.elapsedSeconds = min(state.elapsedSeconds, targetSeconds)
            return
        }
        let elapsed = currentElapsedSeconds()
        state.elapsedSeconds = elapsed
        state.savedWallClockMilliseconds = clock.wallClockMilliseconds()
        if elapsed >= targetSeconds {
            state.isRunning = false
            self.monotonicAnchor = nil
        } else {
            self.monotonicAnchor = clock.monotonicSeconds()
        }
    }

    private mutating func beginStage(_ stage: Int) {
        state.stage = stage
        state.elapsedSeconds = 0
        state.isRunning = false
        state.savedWallClockMilliseconds = clock.wallClockMilliseconds()
        monotonicAnchor = nil
    }
}
