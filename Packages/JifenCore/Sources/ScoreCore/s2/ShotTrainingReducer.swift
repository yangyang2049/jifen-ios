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

public struct ShotTrainingReducer: DomainReducer {
    public init() {}

    public func reduce(
        state: ShotTrainingState,
        intent: ShotTrainingIntent,
        at epochMilliseconds: Int64
    ) -> ReduceResult<ShotTrainingState, ShotTrainingEvent> {
        guard !state.finished || intent == .reset else {
            return .rejected(state: state, reason: "Already finished")
        }

        switch intent {
        case .recordShot(let points, let made):
            guard (1...3).contains(points), (state.mode.fixedPoints ?? points) == points else {
                return .rejected(state: state, reason: "Invalid points for training mode")
            }
            let timestamp = Date(timeIntervalSince1970: Double(epochMilliseconds) / 1_000)
            // The shared state packs rounded milliseconds with three outcome bits.
            // Reject timestamps the packer cannot represent exactly.
            guard (Int64.min / 8 ... Int64.max / 8).contains(epochMilliseconds),
                  Int64(exactly: (timestamp.timeIntervalSince1970 * 1_000).rounded()) == epochMilliseconds else {
                return .rejected(state: state, reason: "Invalid shot timestamp")
            }
            var shots = state.shots
            shots.append(ShotTrainingShot(points: points, made: made, timestamp: timestamp))
            let next = ShotTrainingState(
                mode: state.mode, startTime: state.startTime, shots: shots, earlierCounts: state.earlierCounts
            )
            return .init(state: next, events: [.shotRecorded(points: points, made: made, counts: next.counts)])
        case .undoLastShot:
            var shots = state.shots
            guard shots.popLast() != nil else {
                return .rejected(state: state, reason: "No retained shot to undo")
            }
            let next = ShotTrainingState(
                mode: state.mode, startTime: state.startTime, shots: shots, earlierCounts: state.earlierCounts
            )
            return .init(state: next, events: [.shotUndone(counts: next.counts)])
        case .finish:
            let next = ShotTrainingState(
                mode: state.mode, startTime: state.startTime, shots: state.shots,
                earlierCounts: state.earlierCounts, finished: true
            )
            return .init(state: next, events: [.finished(counts: next.counts)])
        case .reset:
            let startTime = Date(timeIntervalSince1970: Double(epochMilliseconds) / 1_000)
            let next = ShotTrainingState(mode: state.mode, startTime: startTime)
            return .init(state: next, events: [.reset])
        }
    }
}
