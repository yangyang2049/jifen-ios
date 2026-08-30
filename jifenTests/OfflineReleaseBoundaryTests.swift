import XCTest
@testable import jifen

@MainActor
final class OfflineReleaseBoundaryTests: XCTestCase {
    func testServerBackedProductionCapabilitiesStayDisabled() {
        XCTAssertFalse(AppFeatureFlags.accountFeaturesEnabled)
        XCTAssertFalse(AppFeatureFlags.feedbackEntryEnabled)
        XCTAssertFalse(AppFeatureFlags.lanPeerSyncEnabled)
        XCTAssertFalse(AppFeatureFlags.recordCrossDeviceSyncEnabled)
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
