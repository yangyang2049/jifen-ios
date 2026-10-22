import XCTest
import Security
import UIKit
import UserNotifications
@testable import jifen

/// Opt-in, real APNs registration. Run only on a disposable simulator or a designated test phone.
@MainActor final class GroupPushAPNsProbeTests: XCTestCase {
    func testRegisterWithAPNsSandbox() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["JIFEN_RUN_APNS_PROBE"] == "1" || environment["TEST_RUNNER_JIFEN_RUN_APNS_PROBE"] == "1" else {
            throw XCTSkip("Real APNs probe is opt-in")
        }
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        XCTAssertTrue(granted, "Allow notifications on the designated test device")
        guard granted else { return }
        // Exercise the app delegate's production callback and Keychain persistence.
        let registrationRevision = GroupPushManager.shared.tokenRegistrationRevision
        UIApplication.shared.registerForRemoteNotifications()
        for _ in 0..<60 {
            if GroupPushManager.shared.tokenRegistrationRevision > registrationRevision,
               let token = storedToken(), !token.isEmpty {
                await SessionStore.shared.restore()
                for _ in 0..<20 where SessionStore.shared.state == .restoring {
                    try await Task.sleep(for: .milliseconds(250))
                }
                await GroupPushManager.shared.synchronize().value
                let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let file = directory.appending(path: "group-push-apns-probe.json")
                let settings = await center.notificationSettings()
                let deliveredProbes = await center.deliveredNotifications().filter { $0.request.content.userInfo["probe"] as? Bool == true }
                let data = try JSONSerialization.data(withJSONObject: [
                    "token": token, "environment": "sandbox", "applicationId": Bundle.main.bundleIdentifier ?? "",
                    "registeredAt": Date().timeIntervalSince1970,
                    "accountId": SessionStore.shared.user?.id ?? "",
                    "pushAccountId": GroupPushManager.shared.accountID ?? "",
                    "registrationStatus": GroupPushManager.shared.registrationStatus,
                    "notificationSettings": [
                        "authorizationStatus": settings.authorizationStatus.rawValue,
                        "alertSetting": settings.alertSetting.rawValue,
                        "alertStyle": settings.alertStyle.rawValue,
                        "lockScreenSetting": settings.lockScreenSetting.rawValue,
                        "notificationCenterSetting": settings.notificationCenterSetting.rawValue,
                        "soundSetting": settings.soundSetting.rawValue,
                        "scheduledDeliverySetting": settings.scheduledDeliverySetting.rawValue
                    ],
                    "deliveredProbes": deliveredProbes.map { ["id": $0.request.identifier, "date": $0.date.timeIntervalSince1970] }
                ])
                try data.write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                return
            }
            try await Task.sleep(for: .seconds(1))
        }
        XCTFail("APNs registration callback did not persist a token within 60 seconds")
    }

    private func storedToken() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.douhua.jifen.ios.group-push", kSecAttrAccount as String: "installation", kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              let identity = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return identity["token"] as? String
    }
}
