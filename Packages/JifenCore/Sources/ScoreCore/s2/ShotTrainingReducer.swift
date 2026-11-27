import Foundation

public enum ShotTrainingIntent: Codable, Equatable, Sendable {
    case recordShot(points: Int, made: Bool)
    case undoLastShot
    case finish
    case reset
}

public enum ShotTrainingEvent: Codable, Equatable, Sendable {
    case shotRecorded(points: Int, made: Bool, counts: ShotTrainingCounts)
    case shotUndone(counts: ShotTrainingCounts)
    case finished(counts: ShotTrainingCounts)
    case reset
}

/// Full-detail state for the training rules. The linked snapshot packs this
/// state separately so transport limits do not truncate standalone history.
public struct ShotTrainingSession: Codable, Equatable, Sendable {
    public let mode: ShotTrainingMode
    public let startTime: Date
    public fileprivate(set) var shots: [ShotTrainingShot]
    public let earlierCounts: ShotTrainingCounts
    public fileprivate(set) var finished: Bool

    public init(
        mode: ShotTrainingMode,
        startTime: Date,
        shots: [ShotTrainingShot] = [],
        earlierCounts: ShotTrainingCounts = .init(),
        finished: Bool = false
    ) {
        self.mode = mode
        self.startTime = startTime
        self.shots = shots
        self.earlierCounts = earlierCounts
        self.finished = finished
    }

    public var counts: ShotTrainingCounts { .build(from: shots, earlier: earlierCounts) }
}

public struct ShotTrainingReducer: DomainReducer {
    public init() {}

    public func reduce(
        state: ShotTrainingState,
        intent: ShotTrainingIntent,
        at epochMilliseconds: Int64
    ) -> ReduceResult<ShotTrainingState, ShotTrainingEvent> {
        let session = ShotTrainingSession(
            mode: state.mode, startTime: state.startTime, shots: state.shots,
            earlierCounts: state.earlierCounts, finished: state.finished
        )
        let result = reduce(state: session, intent: intent, at: epochMilliseconds)
        guard result.accepted else {
            return .init(state: state, accepted: false, reason: result.reason)
        }
        let next = result.state
        return .init(
            state: ShotTrainingState(
                mode: next.mode, startTime: next.startTime, shots: next.shots,
                earlierCounts: next.earlierCounts, finished: next.finished
            ),
            events: result.events
        )
    }

    public func reduce(
        state: ShotTrainingSession,
        intent: ShotTrainingIntent,
        at epochMilliseconds: Int64,
        shotID: UUID? = nil,
        undoMade: Bool? = nil,
        undoPoints: Int? = nil
    ) -> ReduceResult<ShotTrainingSession, ShotTrainingEvent> {
        guard !state.finished || intent == .reset else {
            return .rejected(state: state, reason: "Already finished")
        }

        var next = state
        switch intent {
        case .recordShot(let points, let made):
            guard (1...3).contains(points), (state.mode.fixedPoints ?? points) == points else {
                return .rejected(state: state, reason: "Invalid points for training mode")
            }
            let timestamp = Date(timeIntervalSince1970: Double(epochMilliseconds) / 1_000)
            // The linked state packs rounded milliseconds with three outcome bits.
            guard (Int64.min / 8 ... Int64.max / 8).contains(epochMilliseconds),
                  Int64(exactly: (timestamp.timeIntervalSince1970 * 1_000).rounded()) == epochMilliseconds else {
                return .rejected(state: state, reason: "Invalid shot timestamp")
            }
            next.shots.append(ShotTrainingShot(id: shotID, points: points, made: made, timestamp: timestamp))
            return .init(state: next, events: [.shotRecorded(points: points, made: made, counts: next.counts)])
        case .undoLastShot:
            guard let index = next.shots.lastIndex(where: { shot in
                (undoMade == nil || shot.made == undoMade) && (undoPoints == nil || shot.points == undoPoints)
            }) else {
                return .rejected(state: state, reason: "No retained shot to undo")
            }
            next.shots.remove(at: index)
            return .init(state: next, events: [.shotUndone(counts: next.counts)])
        case .finish:
            next.finished = true
            return .init(state: next, events: [.finished(counts: next.counts)])
        case .reset:
            let startTime = Date(timeIntervalSince1970: Double(epochMilliseconds) / 1_000)
            return .init(state: ShotTrainingSession(mode: state.mode, startTime: startTime), events: [.reset])
        }
    }
}
