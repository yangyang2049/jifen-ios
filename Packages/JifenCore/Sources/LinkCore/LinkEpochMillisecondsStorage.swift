import Foundation

/// Reads and writes epoch-millisecond values that live in `UserDefaults`.
///
/// watchOS still ships 32-bit `arm64_32` devices where `Int` is 32 bits wide.
/// Current epoch milliseconds (~1.8e12) overflow that `Int` and trap in both
/// directions, so every persisted timestamp is stored as an `NSNumber` backed
/// by `Int64` and read back through this helper. Older builds stored the same
/// key as `Int`/`NSNumber` (which `UserDefaults` also surfaces as `NSNumber`), so
/// the reader accepts those without narrowing.
public enum LinkEpochMillisecondsStorage {
    /// The value stored for `key`, or nil when absent or not numeric.
    public static func value(from object: Any?) -> Int64? {
        switch object {
        case let number as NSNumber:
            return number.int64Value
        case let value as Int64:
            return value
        case let value as Int:
            return Int64(value)
        default:
            return nil
        }
    }

    public static func value(forKey key: String, in defaults: UserDefaults) -> Int64? {
        value(from: defaults.object(forKey: key))
    }

    /// `NSNumber` keeps the full `Int64` range through `UserDefaults` on every
    /// architecture.
    public static func storable(_ value: Int64) -> NSNumber {
        NSNumber(value: value)
    }

    public static func set(_ value: Int64, forKey key: String, in defaults: UserDefaults) {
        defaults.set(storable(value), forKey: key)
    }
}
