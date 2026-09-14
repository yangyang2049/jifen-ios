import Foundation

/// Android 3.0/3.1 S3 multi-participant scoreboard state. UNO and the generic
/// multi-scoreboard intentionally share this reducer; UNO's target score and
/// automatic finish decision belong to the session/controller layer.
public struct MultiParticipant: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var score: Int

    public init(id: String, name: String, score: Int = 0) {
        self.id = id
        self.name = name
        self.score = score
    }
}

public struct MultiParticipantState: Codable, Equatable, Sendable {
    public static let minimumScore = -9_999
    public static let maximumScore = 9_999

    public var participants: [MultiParticipant]
    public var finished: Bool
    /// Android rejects removal of a scored participant unless this policy is
    /// explicitly enabled by a future product specification.
    public var allowRemoveWhileHasScore: Bool
    public var minScore: Int
    public var maxScore: Int

    public init(
        participants: [MultiParticipant],
        finished: Bool = false,
        allowRemoveWhileHasScore: Bool = false,
        minScore: Int = minimumScore,
        maxScore: Int = maximumScore
    ) {
        self.participants = participants
        self.finished = finished
        self.allowRemoveWhileHasScore = allowRemoveWhileHasScore
        self.minScore = minScore
        self.maxScore = maxScore
    }

    private enum CodingKeys: String, CodingKey {
        case participants, finished, allowRemoveWhileHasScore, minScore, maxScore
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            participants: try container.decode([MultiParticipant].self, forKey: .participants),
            finished: try container.decodeIfPresent(Bool.self, forKey: .finished) ?? false,
            allowRemoveWhileHasScore: try container.decodeIfPresent(
                Bool.self,
                forKey: .allowRemoveWhileHasScore
            ) ?? false,
            minScore: try container.decodeIfPresent(Int.self, forKey: .minScore) ?? Self.minimumScore,
            maxScore: try container.decodeIfPresent(Int.self, forKey: .maxScore) ?? Self.maximumScore
        )
    }
}

public enum MultiParticipantIntent: Codable, Equatable, Sendable {
    case addParticipant(id: String, name: String)
    case removeParticipant(id: String)
    case renameParticipant(id: String, newName: String)
    case editParticipant(id: String, newName: String, score: Int)
    case adjustScore(id: String, delta: Int)
    case setScore(id: String, score: Int)
    case reset
    case finish
}

public enum MultiParticipantEvent: Codable, Equatable, Sendable {
    case participantAdded(id: String, at: Int64)
    case participantRemoved(id: String, at: Int64)
    case renamed(id: String, at: Int64)
    case scoreChanged(id: String, at: Int64)
    case finished
    case reset
}

/// Direct port of Android 3.0 `MultiParticipantReducer`; Android 3.1 does not
/// modify this score-engine contract.
public struct MultiParticipantReducer: DomainReducer {
    public init() {}

    public func reduce(
        state: MultiParticipantState,
        intent: MultiParticipantIntent,
        at epochMilliseconds: Int64
    ) -> ReduceResult<MultiParticipantState, MultiParticipantEvent> {
        if state.finished, intent != .reset {
            return .rejected(state: state, reason: "Already finished")
        }

        switch intent {
        case .addParticipant(let id, let name):
            guard !state.participants.contains(where: { $0.id == id }) else {
                return .rejected(state: state, reason: "ID already exists")
            }
            var next = state
            next.participants.append(.init(id: id, name: name))
            return .init(
                state: next,
                events: [.participantAdded(id: id, at: epochMilliseconds)]
            )

        case .removeParticipant(let id):
            guard let participant = state.participants.first(where: { $0.id == id }) else {
                return .rejected(state: state, reason: "Participant not found")
            }
            guard participant.score == 0 || state.allowRemoveWhileHasScore else {
                return .rejected(
                    state: state,
                    reason: "Cannot remove a participant with a score"
                )
            }
            var next = state
            next.participants.removeAll { $0.id == id }
            return .init(
                state: next,
                events: [.participantRemoved(id: id, at: epochMilliseconds)]
            )

        case .renameParticipant(let id, let newName):
            guard let index = state.participants.firstIndex(where: { $0.id == id }) else {
                return .rejected(state: state, reason: "Participant not found")
            }
            var next = state
            next.participants[index].name = newName
            return .init(
                state: next,
                events: [.renamed(id: id, at: epochMilliseconds)]
            )

        case .editParticipant(let id, let newName, let score):
            guard let index = state.participants.firstIndex(where: { $0.id == id }) else {
                return .rejected(state: state, reason: "Participant not found")
            }
            let normalizedScore = clamped(score, state: state)
            let nameChanged = state.participants[index].name != newName
            let scoreChanged = state.participants[index].score != normalizedScore
            var next = state
            next.participants[index].name = newName
            next.participants[index].score = normalizedScore
            var events: [MultiParticipantEvent] = []
            if nameChanged {
                events.append(.renamed(id: id, at: epochMilliseconds))
            }
            if scoreChanged {
                events.append(.scoreChanged(id: id, at: epochMilliseconds))
            }
            return .init(state: next, events: events)

        case .adjustScore(let id, let delta):
            guard let index = state.participants.firstIndex(where: { $0.id == id }) else {
                return .rejected(state: state, reason: "Participant not found")
            }
            var next = state
            next.participants[index].score = clampedAdding(
                state.participants[index].score,
                delta,
                state: state
            )
            return .init(
                state: next,
                events: [.scoreChanged(id: id, at: epochMilliseconds)]
            )

        case .setScore(let id, let score):
            guard let index = state.participants.firstIndex(where: { $0.id == id }) else {
                return .rejected(state: state, reason: "Participant not found")
            }
            var next = state
            next.participants[index].score = clamped(score, state: state)
            return .init(
                state: next,
                events: [.scoreChanged(id: id, at: epochMilliseconds)]
            )

        case .reset:
            var next = state
            next.participants = next.participants.map {
                .init(id: $0.id, name: $0.name, score: 0)
            }
            next.finished = false
            return .init(state: next, events: [.reset])

        case .finish:
            var next = state
            next.finished = true
            return .init(state: next, events: [.finished])
        }
    }

    private func clamped(_ score: Int, state: MultiParticipantState) -> Int {
        min(state.maxScore, max(state.minScore, score))
    }

    private func clampedAdding(
        _ score: Int,
        _ delta: Int,
        state: MultiParticipantState
    ) -> Int {
        let (sum, overflow) = score.addingReportingOverflow(delta)
        if overflow {
            return delta >= 0 ? state.maxScore : state.minScore
        }
        return clamped(sum, state: state)
    }
}
