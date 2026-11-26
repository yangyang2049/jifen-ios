import Foundation
import RecordCore

public enum LinkedShotTrainingMode: String, Codable, Sendable {
    case fixed1 = "fixed_1"
    case fixed2 = "fixed_2"
    case fixed3 = "fixed_3"
    case free

    public var fixedPoints: Int? {
        switch self {
        case .fixed1: return 1
        case .fixed2: return 2
        case .fixed3: return 3
        case .free: return nil
        }
    }
}

public struct LinkedShotTrainingShot: Equatable, Sendable {
    public let points: Int
    public let made: Bool
    public let timestamp: Date

    public init(points: Int, made: Bool, timestamp: Date) {
        self.points = min(3, max(1, points))
        self.made = made
        self.timestamp = timestamp
    }
}

public struct ShotTrainingCounts: Codable, Equatable, Sendable {
    public private(set) var oneMade = 0
    public private(set) var oneMiss = 0
    public private(set) var twoMade = 0
    public private(set) var twoMiss = 0
    public private(set) var threeMade = 0
    public private(set) var threeMiss = 0

    public init(
        oneMade: Int = 0, oneMiss: Int = 0,
        twoMade: Int = 0, twoMiss: Int = 0,
        threeMade: Int = 0, threeMiss: Int = 0
    ) {
        self.oneMade = max(0, oneMade)
        self.oneMiss = max(0, oneMiss)
        self.twoMade = max(0, twoMade)
        self.twoMiss = max(0, twoMiss)
        self.threeMade = max(0, threeMade)
        self.threeMiss = max(0, threeMiss)
    }

    public var made: Int { oneMade + twoMade + threeMade }
    public var missed: Int { oneMiss + twoMiss + threeMiss }
    public var attempts: Int { made + missed }
    public var points: Int { oneMade + twoMade * 2 + threeMade * 3 }
    public var rate: Int { attempts == 0 ? 0 : Int((Double(made) * 100 / Double(attempts)).rounded()) }

    public func count(points: Int, made: Bool) -> Int {
        switch (points, made) {
        case (1, true): return oneMade
        case (1, false): return oneMiss
        case (2, true): return twoMade
        case (2, false): return twoMiss
        default: return made ? threeMade : threeMiss
        }
    }

    public mutating func add(_ shot: LinkedShotTrainingShot) {
        switch (shot.points, shot.made) {
        case (1, true): oneMade += 1
        case (1, false): oneMiss += 1
        case (2, true): twoMade += 1
        case (2, false): twoMiss += 1
        case (3, true): threeMade += 1
        default: threeMiss += 1
        }
    }
}

public struct LinkedShotTrainingState: Codable, Equatable, Sendable {
    public let mode: LinkedShotTrainingMode
    public let startTime: Date
    public let finished: Bool
    public let earlierCounts: ShotTrainingCounts
    private let packedShots: [Int64]

    /// Leave room below the WatchConnectivity limit for the message envelope
    /// and keep the totals for earlier attempts even when the timeline is large.
    public static let maxDetailedShots = 2_048

    public init(
        mode: LinkedShotTrainingMode,
        startTime: Date = Date(),
        shots: [LinkedShotTrainingShot] = [],
        earlierCounts: ShotTrainingCounts = .init(),
        finished: Bool = false
    ) {
        self.mode = mode
        self.startTime = startTime
        self.finished = finished
        var prefix = earlierCounts
        let overflow = max(0, shots.count - Self.maxDetailedShots)
        for shot in shots.prefix(overflow) {
            prefix.add(shot)
        }
        self.earlierCounts = prefix
        packedShots = shots.dropFirst(overflow).map { shot in
            let milliseconds = Int64((shot.timestamp.timeIntervalSince1970 * 1_000).rounded())
            let outcome = Int64((shot.points - 1) * 2 + (shot.made ? 1 : 0))
            return milliseconds * 8 + outcome
        }
    }

    public var shots: [LinkedShotTrainingShot] {
        packedShots.map { value in
            let outcome = Int(value & 7)
            return LinkedShotTrainingShot(
                points: outcome / 2 + 1,
                made: outcome % 2 == 1,
                timestamp: Date(timeIntervalSince1970: Double(value >> 3) / 1_000)
            )
        }
    }

    public var counts: ShotTrainingCounts {
        shots.reduce(into: earlierCounts) { $0.add($1) }
    }

    public func detailedActions(endingAt endTime: Date) -> [DetailedScoreAction] {
        var running = earlierCounts
        var actions = shots.map { shot in
            running.add(shot)
            return DetailedScoreAction(
                type: .scoreChanged,
                epochMilliseconds: Int64((shot.timestamp.timeIntervalSince1970 * 1_000).rounded()),
                team: shot.made ? .team2 : .team1,
                scores: [running.missed, running.made],
                scoreChange: 1,
                operationCode: "training_\(shot.points)pt_\(shot.made ? "made" : "miss")"
            )
        }
        actions.append(DetailedScoreAction(
            type: .matchFinished,
            epochMilliseconds: Int64((endTime.timeIntervalSince1970 * 1_000).rounded()),
            scores: [running.missed, running.made],
            operationCode: "training_rate_\(running.rate)"
        ))
        return actions
    }
}
