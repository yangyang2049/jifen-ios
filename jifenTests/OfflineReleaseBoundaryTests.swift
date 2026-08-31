import XCTest
@testable import jifen

@MainActor
final class OfflineReleaseBoundaryTests: XCTestCase {
    func testAPIDateParserAcceptsNodeISOString() {
        XCTAssertNotNil(APIDateParser.date(from: "2026-09-08T01:40:54.123Z"))
        XCTAssertNotNil(APIDateParser.date(from: "2026-09-08T01:40:54Z"))
        XCTAssertNil(APIDateParser.date(from: "not-a-date"))
    }

    func testServerBackedProductionCapabilitiesStayDisabled() {
        XCTAssertTrue(AppFeatureFlags.accountFeaturesEnabled)
        // 反馈功能已对全部语言开放（与安卓端一致）。
        XCTAssertTrue(AppFeatureFlags.feedbackEntryEnabled)
        XCTAssertFalse(AppFeatureFlags.lanPeerSyncEnabled)
        XCTAssertTrue(AppFeatureFlags.recordCrossDeviceSyncEnabled)
        XCTAssertTrue(AppFeatureFlags.systemExternalDisplayEnabled)
    }

    func testOfflineBuildDoesNotDeclareBonjourOrLocalNetworkPermission() {
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices"))
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription"))
    }

    func testLegacyLANEntryCannotStartAdvertisingOrBrowsing() async {
        let manager = LocalPeerRoomManager.shared

        await manager.createRoom()
        guard case .failed = manager.phase else {
            return XCTFail("Offline room creation must fail before Multipeer starts")
        }

        await manager.joinRoom(code: "123456", role: .display)
        guard case .failed = manager.phase else {
            return XCTFail("Offline room joining must fail before Multipeer starts")
        }
    }
}
