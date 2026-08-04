import CoreGraphics
import Foundation
import RecordCore

struct ScoreboardRecordTrendPoint: Identifiable, Equatable {
    let id: String
    let left: Int
    let right: Int
}

struct ScoreboardRecordTrendTab: Identifiable, Equatable {
    let id: String
    let title: String
    let points: [ScoreboardRecordTrendPoint]
}

/// Produces one locally-normalized score series per reliable recap section.
/// Persisted records stay untouched; legacy repair is presentation-only.
enum ScoreboardRecordTrendBuilder {
    static func build(
        record: ScoreboardRecord,
        sections: [ScoreboardRecordRecapSection],
        policy: ScoreboardRecordProjectPolicy
    ) -> [ScoreboardRecordTrendTab] {
        guard policy.trendAllowed else { return [] }

        let participants = record.displayParticipants
        if policy.trendRequiresTwoPlayers,
           !participants.isEmpty,
           participants.count != 2 {
            return []
        }

        var tabs: [ScoreboardRecordTrendTab] = []
        for section in sections {
            for chunk in resetChunks(section.actions) {
                let resetGeneration = section.resetGeneration + chunk.resetOffset
                let tabID = "\(section.id)-trend-\(chunk.resetOffset)"
                let points = buildPoints(actions: chunk.actions, tabID: tabID)
                guard points.count >= 2 else { continue }

                tabs.append(ScoreboardRecordTrendTab(
                    id: tabID,
                    title: title(
                        base: section.title,
                        resetGeneration: resetGeneration
                    ),
                    points: points
                ))
            }
        }

        if policy.trendRequiresNonNegativeScores,
           tabs.contains(where: { tab in
               tab.points.contains { $0.left < 0 || $0.right < 0 }
           }) {
            return []
        }

        guard tabs.contains(where: { tab in
            tab.points.contains { $0.left > 0 || $0.right > 0 }
        }) else {
            return []
        }
        return tabs
    }

    private struct ResetChunk {
        let resetOffset: Int
        let actions: [DetailedScoreAction]
    }

    private static func resetChunks(_ actions: [DetailedScoreAction]) -> [ResetChunk] {
        var chunks: [ResetChunk] = []
        var current: [DetailedScoreAction] = []
        var resetOffset = 0

        for action in actions {
            if action.type == .reset {
                if !current.isEmpty {
                    chunks.append(.init(resetOffset: resetOffset, actions: current))
                    current.removeAll(keepingCapacity: true)
                }
                resetOffset += 1
            } else {
                current.append(action)
            }
        }
        if !current.isEmpty {
            chunks.append(.init(resetOffset: resetOffset, actions: current))
        }
        return chunks
    }

    private struct CandidatePoint {
        let action: DetailedScoreAction
        let left: Int
        let right: Int
    }

    private static func buildPoints(
        actions: [DetailedScoreAction],
        tabID: String
    ) -> [ScoreboardRecordTrendPoint] {
        var candidates: [CandidatePoint] = []
        var lastScore = (left: 0, right: 0)

        for action in actions {
            guard action.type != .matchStarted,
                  action.type != .reset,
                  action.scores.count >= 2 else {
                continue
            }
            let next = (left: action.scores[0], right: action.scores[1])
            guard next != lastScore else { continue }
            candidates.append(.init(action: action, left: next.left, right: next.right))
            lastScore = next
        }

        // A legacy Rally terminal event could be persisted as a positive
        // scoreChanged action whose snapshot had already been cleared to 0:0,
        // immediately followed by the authoritative finished snapshot. Remove
        // only that exact reset-shaped bridge; real undo/edit drops remain.
        var repairedCandidates: [CandidatePoint] = []
        for candidate in candidates {
            if candidate.action.type == .setFinished || candidate.action.type == .matchFinished,
               repairedCandidates.count >= 2,
               let resetLike = repairedCandidates.last,
               resetLike.left == 0,
               resetLike.right == 0,
               isLegacyTrailingResetDrop(resetLike.action) {
                repairedCandidates.removeLast()
            }
            if repairedCandidates.last?.left == candidate.left,
               repairedCandidates.last?.right == candidate.right {
                continue
            }
            repairedCandidates.append(candidate)
        }
        candidates = repairedCandidates

        // Some legacy Rally writers persisted a post-set 0:0-like snapshot as
        // the final positive scoring action. Do not let that reset become a
        // backwards terminal line; explicit undo and administrative edits stay.
        while candidates.count > 1,
              let last = candidates.last,
              let previous = candidates.dropLast().last,
              last.left < previous.left,
              last.right < previous.right,
              isLegacyTrailingResetDrop(last.action) {
            candidates.removeLast()
        }

        var points: [ScoreboardRecordTrendPoint] = [
            .init(id: "\(tabID)-origin", left: 0, right: 0)
        ]
        points.append(contentsOf: candidates.enumerated().map { index, candidate in
            .init(
                id: "\(tabID)-\(index)-\(candidate.action.id.uuidString)",
                left: candidate.left,
                right: candidate.right
            )
        })
        return points
    }

    private static func isLegacyTrailingResetDrop(_ action: DetailedScoreAction) -> Bool {
        switch action.type {
        case .setFinished, .matchFinished:
            return true
        case .scoreChanged:
            return (action.scoreChange ?? 0) > 0
        default:
            return false
        }
    }

    private static func title(base: String, resetGeneration: Int) -> String {
        guard resetGeneration > 0 else { return base }
        return String(
            format: NSLocalizedString(
                "score_trend_after_reset_format",
                value: "%@（重置后 %d）",
                comment: ""
            ),
            base,
            resetGeneration
        )
    }
}

enum ScoreboardTrendChartGeometry {
    static let horizontalInset: CGFloat = 8

    static func xPositions(
        pointCount: Int,
        width: CGFloat,
        horizontalInset: CGFloat = horizontalInset
    ) -> [CGFloat] {
        guard pointCount > 0 else { return [] }
        let inset = max(0, min(horizontalInset, width / 2))
        let usableWidth = max(0, width - inset * 2)
        guard pointCount > 1 else { return [inset] }
        return (0..<pointCount).map { index in
            inset + usableWidth * CGFloat(index) / CGFloat(pointCount - 1)
        }
    }
}
