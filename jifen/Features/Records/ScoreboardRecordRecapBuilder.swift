import Foundation
import RecordCore

enum ScoreboardRecordRecapGroupingQuality: Equatable {
    /// The project intentionally presents one unsegmented event or ranking feed.
    case unsegmented
    /// Persisted segment numbers or explicit segment-finished actions are available.
    case explicit
    /// A stable project operation marks the boundary, but its number must be inferred.
    case inferred
    /// The record has actions, but not enough trustworthy evidence to invent segments.
    case overallFallback
}

struct ScoreboardRecordRecapBuildResult: Equatable {
    let sections: [ScoreboardRecordRecapSection]
    let quality: ScoreboardRecordRecapGroupingQuality
}

/// Pure presentation builder. It never mutates or rewrites a persisted record.
enum ScoreboardRecordRecapBuilder {
    private struct SectionDraft {
        let number: Int
        let resetGeneration: Int
        var actions: [DetailedScoreAction]
        var result: RecordSetResult?
    }

    static func build(
        record: ScoreboardRecord,
        actions: [DetailedScoreAction],
        policy: ScoreboardRecordProjectPolicy
    ) -> ScoreboardRecordRecapBuildResult {
        let setResults = record.setResults ?? []
        let hasPersistedActionEvidence = record.detailedActions?.isEmpty == false || !record.actions.isEmpty
        guard hasPersistedActionEvidence || !setResults.isEmpty else {
            return .init(sections: [], quality: .overallFallback)
        }

        let kind = policy.recapKind
        if kind == .events || kind == .ranking {
            return .init(
                sections: [overallSection(kind: kind, actions: actions)],
                quality: .unsegmented
            )
        }

        let explicitNumbers = Set(actions.compactMap { segmentNumber(for: $0, kind: kind) })
        let hasNumberedBoundary = actions.contains {
            isExplicitBoundary($0, kind: kind) && segmentNumber(for: $0, kind: kind) != nil
        }
        let hasUnnumberedBoundary = actions.contains {
            isExplicitBoundary($0, kind: kind) && segmentNumber(for: $0, kind: kind) == nil
        }
        let hasInferredBoundary = actions.contains { isInferredBoundary($0, kind: kind) }

        let quality: ScoreboardRecordRecapGroupingQuality
        if hasNumberedBoundary || explicitNumbers.count > 1 || !setResults.isEmpty {
            quality = .explicit
        } else if hasUnnumberedBoundary || hasInferredBoundary {
            quality = .inferred
        } else {
            return .init(
                sections: [overallFallbackSection(actions: actions)],
                quality: .overallFallback
            )
        }

        var drafts: [SectionDraft] = []
        var currentNumber = 1
        var resetGeneration = 0

        for (actionIndex, action) in actions.enumerated() {
            let explicitNumber = segmentNumber(for: action, kind: kind)
            // Some legacy Rally records stamped only the terminal score with the
            // already-advanced set number. Repair that one adjacent event pair;
            // never force every action sharing a timestamp into one segment.
            let adjacentBoundaryNumber = adjacentBoundaryNumber(
                for: actionIndex,
                in: actions,
                kind: kind
            )
            let lastNumberInGeneration = drafts.last(where: { $0.resetGeneration == resetGeneration })?.number
            let implicitNumber: Int
            if action.type == .matchFinished, let lastNumberInGeneration {
                implicitNumber = lastNumberInGeneration
            } else if action.type == .reset,
                      !drafts.contains(where: {
                          $0.resetGeneration == resetGeneration && $0.number == currentNumber
                      }),
                      let lastNumberInGeneration {
                implicitNumber = lastNumberInGeneration
            } else {
                implicitNumber = currentNumber
            }
            let assignedNumber: Int
            if action.type == .matchFinished, let lastNumberInGeneration {
                // The finish marker closes the current match; legacy writers
                // sometimes stamped it with the already-advanced next number.
                assignedNumber = lastNumberInGeneration
            } else {
                assignedNumber = max(1, adjacentBoundaryNumber ?? explicitNumber ?? implicitNumber)
            }

            if let index = drafts.firstIndex(where: {
                $0.number == assignedNumber && $0.resetGeneration == resetGeneration
            }) {
                drafts[index].actions.append(action)
            } else {
                drafts.append(.init(
                    number: assignedNumber,
                    resetGeneration: resetGeneration,
                    actions: [action],
                    result: nil
                ))
            }

            if action.type == .reset {
                resetGeneration += 1
                currentNumber = 1
            } else if isExplicitBoundary(action, kind: kind) || isInferredBoundary(action, kind: kind) {
                currentNumber = assignedNumber + 1
            } else if let explicitNumber {
                currentNumber = max(1, explicitNumber)
            }
        }

        // Results enrich existing sections. A missing unique number may create a
        // summary-only section, while duplicate legacy number=1 results are not
        // allowed to fabricate extra sections.
        for result in setResults {
            if let index = drafts.firstIndex(where: { $0.number == result.number && $0.result == nil }) {
                drafts[index].result = result
            } else if !drafts.contains(where: { $0.number == result.number }) {
                drafts.append(.init(
                    number: max(1, result.number),
                    resetGeneration: 0,
                    actions: [],
                    result: result
                ))
            }
        }

        let sections = drafts.map { draft in
            ScoreboardRecordRecapSection(
                id: "\(kind.rawValue)-\(draft.resetGeneration)-\(draft.number)",
                title: kind.title(number: draft.number),
                number: draft.number,
                resetGeneration: draft.resetGeneration,
                result: draft.result,
                actions: draft.actions
            )
        }
        return .init(sections: sections, quality: quality)
    }

    private static func segmentNumber(
        for action: DetailedScoreAction,
        kind: ScoreboardRecordProjectPolicy.RecapKind
    ) -> Int? {
        let number: Int?
        switch kind {
        case .sets, .tennisSets:
            number = action.setNumber ?? action.gameNumber
        case .periods:
            number = action.periodNumber
        case .rounds, .cardRounds:
            number = action.roundNumber
        case .frames:
            number = action.gameNumber ?? action.setNumber
        case .events, .ranking:
            number = nil
        }
        return number.flatMap { $0 > 0 ? $0 : nil }
    }

    private static func adjacentBoundaryNumber(
        for index: Int,
        in actions: [DetailedScoreAction],
        kind: ScoreboardRecordProjectPolicy.RecapKind
    ) -> Int? {
        guard actions[index].type == .scoreChanged,
              actions.indices.contains(index + 1) else {
            return nil
        }
        let boundary = actions[index + 1]
        guard isExplicitBoundary(boundary, kind: kind),
              actions[index].epochMilliseconds == boundary.epochMilliseconds else {
            return nil
        }
        return segmentNumber(for: boundary, kind: kind)
    }

    private static func isExplicitBoundary(
        _ action: DetailedScoreAction,
        kind: ScoreboardRecordProjectPolicy.RecapKind
    ) -> Bool {
        switch kind {
        case .sets, .tennisSets, .frames:
            return action.type == .setFinished
        case .periods:
            return action.type == .periodFinished
        case .rounds, .cardRounds:
            return action.type == .roundFinished
        case .events, .ranking:
            return false
        }
    }

    private static func isInferredBoundary(
        _ action: DetailedScoreAction,
        kind: ScoreboardRecordProjectPolicy.RecapKind
    ) -> Bool {
        let code = action.operationCode?
            .lowercased()
            .replacingOccurrences(of: "_", with: "") ?? ""
        switch kind {
        case .frames:
            return code == "eightballrack"
        case .cardRounds:
            return code.contains("resolveround") || code.contains("settleround")
        default:
            return false
        }
    }

    private static func overallSection(
        kind: ScoreboardRecordProjectPolicy.RecapKind,
        actions: [DetailedScoreAction]
    ) -> ScoreboardRecordRecapSection {
        ScoreboardRecordRecapSection(
            id: "overall-\(kind.rawValue)",
            title: kind.title(number: nil),
            number: nil,
            resetGeneration: 0,
            result: nil,
            actions: actions
        )
    }

    private static func overallFallbackSection(
        actions: [DetailedScoreAction]
    ) -> ScoreboardRecordRecapSection {
        ScoreboardRecordRecapSection(
            id: "overall-recap",
            title: NSLocalizedString("record_recap_overall", value: "全场复盘", comment: ""),
            number: nil,
            resetGeneration: 0,
            result: nil,
            actions: actions
        )
    }
}

private extension ScoreboardRecordProjectPolicy.RecapKind {
    func title(number: Int?) -> String {
        switch self {
        case .sets:
            return String(format: NSLocalizedString("record_recap_set_format", value: "第 %d 局", comment: ""), number ?? 1)
        case .tennisSets:
            return String(format: NSLocalizedString("record_recap_tennis_set_format", value: "第 %d 盘", comment: ""), number ?? 1)
        case .periods:
            return String(format: NSLocalizedString("record_recap_period_format", value: "第 %d 节", comment: ""), number ?? 1)
        case .rounds, .cardRounds:
            return String(format: NSLocalizedString("record_recap_round_format", value: "第 %d 回合", comment: ""), number ?? 1)
        case .frames:
            return String(format: NSLocalizedString("record_recap_frame_format", value: "第 %d 局", comment: ""), number ?? 1)
        case .events:
            return NSLocalizedString("record_recap_full_match", value: "全场事件", comment: "")
        case .ranking:
            return NSLocalizedString("record_recap_adjustments", value: "调整明细", comment: "")
        }
    }
}
