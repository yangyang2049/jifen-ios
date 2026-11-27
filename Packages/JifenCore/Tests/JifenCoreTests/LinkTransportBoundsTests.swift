import Foundation
import Testing
@testable import LinkCore

struct LinkApplicationContextCodecTests {
    @Test func binaryPlistAcceptsTheDataSnapshotPartition() throws {
        let context: [String: Any] = [
            "jifen.link.latest_snapshot": Data([0x4A, 0x46, 0x01, 0x09]),
            "jifen.common_names.v1": [
                "teams": ["红队"], "players": [], "updatedAt": NSNumber(value: Int64(1_800_000_000_123))
            ]
        ]
        // The previous JSON probe rejected every context that carried Data.
        #expect(!JSONSerialization.isValidJSONObject(context))
        let size = try #require(LinkApplicationContextCodec.encodedSize(context))
        #expect(size > 8)
        #expect(LinkApplicationContextCodec.fits(context))
        #expect(!LinkApplicationContextCodec.fits(context, maxBytes: size - 1))
    }

    @Test func rejectsValuesWatchConnectivityCannotCarry() {
        final class NotAPlistValue {}
        let context: [String: Any] = ["bad": NotAPlistValue()]
        #expect(LinkApplicationContextCodec.encodedSize(context) == nil)
        #expect(!LinkApplicationContextCodec.fits(context))
    }

    @Test func mergeReplacesOnlyTheKeysInTheUpdate() {
        let merged = LinkApplicationContextCodec.merged(
            base: ["names": 1, "snapshot": 2],
            update: ["snapshot": 3, "extra": 4]
        )
        #expect(merged["names"] as? Int == 1)
        #expect(merged["snapshot"] as? Int == 3)
        #expect(merged["extra"] as? Int == 4)
    }
}

struct LinkApplicationContextWriterTests {
    private final class SessionBox: @unchecked Sendable {
        private let lock = NSLock()
        private var context: [String: Any]

        init(_ context: [String: Any] = [:]) { self.context = context }

        var value: [String: Any] { lock.withLock { context } }
        func replace(with context: [String: Any]) { lock.withLock { self.context = context } }
    }

    @Test func successiveWritesComposeWithTheFreshSessionContext() throws {
        let box = SessionBox(["names": ["A"]])
        let writer = LinkApplicationContextWriter(read: { box.value }, write: { box.replace(with: $0) })

        try writer.merge(["snapshot": Data([1])])
        try writer.merge(["other": 2])

        let context = box.value
        #expect(context["names"] as? [String] == ["A"])
        #expect(context["snapshot"] as? Data == Data([1]))
        #expect(context["other"] as? Int == 2)
    }

    @Test func aRepairedSessionDoesNotRepublishThePreviousPeersKeys() throws {
        let box = SessionBox(["old-peer": true])
        let writer = LinkApplicationContextWriter(read: { box.value }, write: { box.replace(with: $0) })
        // A different Watch paired: WCSession now reports that peer's context.
        box.replace(with: ["new-peer": true])

        try writer.merge(["snapshot": Data([2])])

        #expect(box.value["old-peer"] == nil)
        #expect(box.value["new-peer"] as? Bool == true)
        #expect(box.value["snapshot"] as? Data == Data([2]))
    }

    @Test func rejectedDictionaryNeverTouchesTheSession() {
        let box = SessionBox(["keep": 1])
        let writer = LinkApplicationContextWriter(maxBytes: 256, read: { box.value }, write: { box.replace(with: $0) })

        #expect(throws: LinkApplicationContextError.self) {
            try writer.merge(["blob": Data(repeating: 0, count: 512)])
        }
        #expect(box.value["blob"] == nil)

        final class NotAPlistValue {}
        #expect(throws: LinkApplicationContextError.self) {
            try writer.merge(["bad": NotAPlistValue()])
        }
        #expect(box.value["keep"] as? Int == 1)
    }

    @Test func concurrentMergesKeepEveryKey() async throws {
        let box = SessionBox()
        let writer = LinkApplicationContextWriter(read: { box.value }, write: { box.replace(with: $0) })
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<64 {
                group.addTask { try writer.merge(["key-\(index)": index]) }
            }
            try await group.waitForAll()
        }
        #expect(box.value.count == 64)
    }
}

struct LinkCommonNameControlBudgetTests {
    private func batch(_ count: Int) -> CommonNameMutationBatch {
        CommonNameMutationBatch(mutations: (0..<count).map {
            CommonNameMutation(kind: .add, nameType: .team, newName: "Team-\($0)")
        })
    }

    @Test func oversizedMutationBatchKeepsADeliverablePrefix() throws {
        let original = batch(8)
        let mutations = original.mutations
        let full = try JSONEncoder().encode(original)
        let budget = full.count / 2
        let prefix = try #require(original.fittingPrefix(maxBytes: budget))

        #expect(!prefix.mutations.isEmpty)
        #expect(prefix.mutations.count < mutations.count)
        #expect(prefix.mutations == Array(mutations.prefix(prefix.mutations.count)))
        #expect(try JSONEncoder().encode(prefix).count <= budget)
    }

    @Test func emptyOrSingleOversizedBatchHasNoFittingPrefix() {
        #expect(batch(0).fittingPrefix() == nil)
        let oversized = CommonNameMutationBatch(mutations: [
            CommonNameMutation(kind: .add, nameType: .team, newName: String(repeating: "x", count: 2_000))
        ])
        #expect(oversized.fittingPrefix(maxBytes: 64) == nil)
    }

    @Test func controlChannelSharesTheBackgroundUserInfoBudget() {
        #expect(LinkCommonNameControlBudget.bodyBudgetBytes == 32_000)
        #expect(LinkCommonNameControlBudget.bodyBudgetBytes < LinkPayloadBudget.maxBytes)
        #expect(LinkCommonNameControlBudget.fits(Data(repeating: 0, count: 32_000)))
        #expect(!LinkCommonNameControlBudget.fits(Data(repeating: 0, count: 32_001)))
        // The terminal-frame ladder uses the same dictionary budget.
        #expect(LinkFinishedRouting.userInfoBudgetBytes == LinkCommonNameControlBudget.bodyBudgetBytes)
    }
}

struct CommonNameAcknowledgementBudgetTests {
    private func snapshot(nameCount: Int) -> CommonNamesSyncSnapshot {
        let names = (0..<nameCount).map { "选手名字很长很长很长很长-\($0)" }
        return CommonNamesSyncSnapshot(teams: names, players: names, updatedAtEpochMilliseconds: 1_800_000_000_123, revision: 7)
    }

    private func acknowledgement(
        snapshot: CommonNamesSyncSnapshot, results: Int
    ) -> CommonNameMutationAcknowledgement {
        CommonNameMutationAcknowledgement(
            snapshot: snapshot,
            results: (0..<results).map {
                CommonNameMutationResult(
                    mutationId: UUID(),
                    status: $0.isMultiple(of: 2) ? .applied : .conflict
                )
            }
        )
    }

    @Test func aSmallAcknowledgementIsSentUnchanged() throws {
        let value = acknowledgement(snapshot: snapshot(nameCount: 3), results: 2)
        let data = try value.encodedWithinControlBudget()
        #expect(try JSONDecoder().decode(CommonNameMutationAcknowledgement.self, from: data) == value)
    }

    @Test func anOversizedAcknowledgementKeepsEveryResultAndTrimsOnlyTheSnapshot() throws {
        let original = acknowledgement(snapshot: snapshot(nameCount: 400), results: 20)
        let data = try original.encodedWithinControlBudget(maxBytes: 4_000)
        #expect(data.count <= 4_000)

        let decoded = try JSONDecoder().decode(CommonNameMutationAcknowledgement.self, from: data)
        // The Watch dequeues by mutationId: every result must survive.
        #expect(decoded.results == original.results)
        #expect(decoded.snapshot.teams.count < original.snapshot.teams.count)
        #expect(decoded.snapshot.revision == original.snapshot.revision)
        // A bare snapshot (the old fallback) would have no results to dequeue.
        #expect(!decoded.results.isEmpty)
    }

    @Test func anImpossibleBudgetFailsInsteadOfDroppingResults() {
        let value = acknowledgement(snapshot: snapshot(nameCount: 10), results: 20)
        #expect(throws: LinkCommonNameControlError.self) {
            try value.encodedWithinControlBudget(maxBytes: 64)
        }
    }
}
