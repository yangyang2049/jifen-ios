import Foundation
import LinkSync
import Testing

struct LinkStateHashTests {
    @Test func matchesPublishedFNV1a64Vectors() {
        // RFC 9923, Section 8.3. The block inputs include their trailing zero byte.
        // https://www.rfc-editor.org/rfc/rfc9923.html#section-8.3
        let helloBytes = Array("Hello!".utf8) + [0x01, 0xFF, 0xED]
        let vectors: [(bytes: [UInt8], stringHash: UInt64, blockHash: UInt64)] = [
            ([], 0xCBF2_9CE4_8422_2325, 0xAF63_BD4C_8601_B7DF),
            (Array("a".utf8), 0xAF63_DC4C_8601_EC8C, 0x089B_E207_B544_F1E4),
            (Array("foobar".utf8), 0x8594_4171_F739_67E8, 0x3453_1CA7_168B_8F38),
            (helloBytes, 0xBD51_EA70_94EE_6FA1, 0xA0A0_FE4D_1127_AE93),
        ]
        for vector in vectors {
            #expect(LinkStateHash.fnv1a64(vector.bytes) == vector.stringHash)
            #expect(LinkStateHash.fnv1a64(vector.bytes + [0]) == vector.blockHash)
        }
    }

    @Test func orderedJSONPinsNestedKeysDatesUnicodeAndArrayOrder() throws {
        struct Snapshot: LinkStateHashSnapshot {
            struct Stage: Encodable {
                let revision: Int
                let name: String
            }

            let time: Date
            let stage: Stage
            let points: [Int]
        }

        let time = Date(timeIntervalSince1970: 1.25)
        let stage = Snapshot.Stage(revision: 7, name: "甲/乙")
        let snapshot = Snapshot(time: time, stage: stage, points: [2, 1])
        let reorderedPoints = Snapshot(time: time, stage: stage, points: [1, 2])
        // {"points":[2,1],"stage":{"name":"甲/乙","revision":7},"time":1250}
        try #expect(LinkStateHash.fnv1a64(orderedJSON: snapshot) == 0x1429_3042_B94E_0B85)
        try #expect(LinkStateHash.fnv1a64(orderedJSON: reorderedPoints) == 0x98B9_B5F2_DD94_3255)
    }
}
