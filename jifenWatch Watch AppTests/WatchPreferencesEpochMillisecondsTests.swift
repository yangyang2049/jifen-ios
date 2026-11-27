import XCTest
@testable import jifenWatch_Watch_App

/// Epoch-millisecond timestamps must survive arm64_32, where `Int` is 32 bits
/// wide and the previous `Int(epochMilliseconds)` conversion trapped.
final class WatchPreferencesEpochMillisecondsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var preferences: WatchPreferences!

    override func setUp() {
        super.setUp()
        suiteName = "WatchPreferencesEpochMillisecondsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        preferences = WatchPreferences(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        preferences = nil
        suiteName = nil
        super.tearDown()
    }

    func testRoundTripsValuesBeyondInt32WithoutNarrowing() {
        let value: Int64 = 1_792_000_000_123
        XCTAssertGreaterThan(value, Int64(Int32.max))

        preferences.setInt64(value, forKey: "lastCommunication")

        XCTAssertEqual(preferences.int64(forKey: "lastCommunication"), value)
        XCTAssertEqual((defaults.object(forKey: "lastCommunication") as? NSNumber)?.int64Value, value)
        // A reload from the same suite must read the same value back.
        XCTAssertEqual(WatchPreferences(defaults: defaults).int64(forKey: "lastCommunication"), value)
    }

    func testReadsLegacyIntegerValue() {
        defaults.set(1_700_000_000_000, forKey: "lastCommunication")
        XCTAssertEqual(preferences.int64(forKey: "lastCommunication"), 1_700_000_000_000)
    }

    func testMissingValueFallsBackToDefault() {
        XCTAssertEqual(preferences.int64(forKey: "missing"), 0)
        XCTAssertEqual(preferences.int64(forKey: "missing", defaultValue: 42), 42)
    }

    func testNonNumericValueFallsBackToDefault() {
        defaults.set("not a timestamp", forKey: "lastCommunication")
        XCTAssertEqual(preferences.int64(forKey: "lastCommunication", defaultValue: 7), 7)
    }
}
