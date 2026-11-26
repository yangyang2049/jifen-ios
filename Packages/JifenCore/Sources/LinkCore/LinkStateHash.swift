import Foundation

/// A keyed snapshot that explicitly opts in to link-state hashing.
///
/// Conform only after auditing every field for deterministic encoding. Sort
/// unordered collections at the schema boundary before encoding them as
/// arrays. JSON key sorting preserves array order and cannot normalize a
/// synthesized `Set` or a dictionary encoded as an array.
public protocol LinkStateHashSnapshot: Encodable {}

public enum LinkStateHash {
    /// Computes the RFC 9923 FNV-1a 64-bit value of already canonical bytes.
    public static func fnv1a64(_ bytes: some Sequence<UInt8>) -> UInt64 {
        let prime: UInt64 = 0x0000_0100_0000_01B3
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }

    /// Sorts JSON object keys and preserves array order. Dates encode as
    /// milliseconds since the Unix epoch and forward slashes remain unescaped.
    public static func fnv1a64(orderedJSON snapshot: some LinkStateHashSnapshot) throws -> UInt64 {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return fnv1a64(try encoder.encode(snapshot))
    }
}
