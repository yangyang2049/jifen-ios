import Foundation

/// The raw values are persisted in the iPhone draft.
public enum ShotTrainingMode: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case fixed1 = "fixed_1"
    case fixed2 = "fixed_2"
    case fixed3 = "fixed_3"
    case free

    public var id: String { rawValue }

    public var fixedPoints: Int? {
        switch self {
        case .fixed1: return 1
        case .fixed2: return 2
        case .fixed3: return 3
        case .free: return nil
        }
    }
}

public struct ShotTrainingShot: Codable, Hashable, Sendable {
    /// Local history identity. The packed scoreboard state carries shot outcomes and times.
    public let id: UUID?
    public let points: Int
    public let made: Bool
    public let timestamp: Date

    public init(id: UUID? = nil, points: Int, made: Bool, timestamp: Date) {
        self.id = id
        self.points = min(3, max(1, points))
        self.made = made
        self.timestamp = timestamp
    }
}

public struct ShotTrainingCounts: Codable, Hashable, Sendable {
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

    public static func build(from shots: [ShotTrainingShot], earlier: Self = .init()) -> Self {
        shots.reduce(into: earlier) { $0.add($1) }
    }

    public mutating func add(_ shot: ShotTrainingShot) {
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

/// Canonical training state. Each packed value holds the millisecond timestamp,
/// points and result of one attempt.
public struct ShotTrainingState: Codable, Hashable, Sendable {
    public let mode: ShotTrainingMode
    public let startTime: Date
    public let finished: Bool
    public let earlierCounts: ShotTrainingCounts
    private let packedShots: [Int64]

    /// Leave room below the WatchConnectivity limit for the message envelope
    /// and keep the totals for earlier attempts even when the timeline is large.
    public static let maxDetailedShots = 2_048

    public init(
        mode: ShotTrainingMode,
        startTime: Date = Date(),
        shots: [ShotTrainingShot] = [],
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

    public var shots: [ShotTrainingShot] {
        packedShots.map { value in
            let outcome = Int(value & 7)
            return ShotTrainingShot(
                points: outcome / 2 + 1,
                made: outcome % 2 == 1,
                timestamp: Date(timeIntervalSince1970: Double(value >> 3) / 1_000)
            )
        }
    }

    public var counts: ShotTrainingCounts {
        .build(from: shots, earlier: earlierCounts)
    }
}
