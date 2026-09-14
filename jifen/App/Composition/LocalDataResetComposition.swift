import Foundation
import PersistenceCore

@MainActor
extension LocalDataResetCoordinator {
    static func live(
        appearance: AppAppearanceStore,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> Self {
        Self(steps: [
            LocalDataResetStep(category: .scoreboardRecords) {
                guard ScoreboardRecordManager.shared.clearAllRecords(),
                      ScoreboardRecordManager.shared.getAllRecordSummaries().isEmpty else {
                    throw LocalDataResetCompositionError.verificationFailed
                }
            },
            LocalDataResetStep(category: .timerRecords) {
                guard TimerRecordManager.shared.clearAllRecords(),
                      TimerRecordManager.shared.getRecords().isEmpty else {
                    throw LocalDataResetCompositionError.verificationFailed
                }
            },
            LocalDataResetStep(category: .bookingsAndNotifications) {
                CountdownNotificationManager.shared.cancel()
                guard await LocalBookingManager.shared.clearAllBookingsAndWaitForNotifications(),
                      LocalBookingManager.shared.getAllBookings().isEmpty else {
                    throw LocalDataResetCompositionError.verificationFailed
                }
            },
            LocalDataResetStep(category: .resumeSessions) {
                try await ResumeSessionRepository().clear()
            },
            LocalDataResetStep(category: .legacySyncData) {
                try AnonymousIdentityProvider.shared.clearLocalIdentity()
                try removeLegacyRecordSyncOutbox(fileManager: fileManager)
            },
            LocalDataResetStep(category: .localPreferencesAndTools) {
                PointsTableStorage.clear(defaults: defaults)
                TimerToolStateStore.clear(defaults: defaults)
                ScoreboardUsageHintStore(defaults: defaults).removeAllShownFlags()
                LocalPreferenceDataResetter.clear(defaults: defaults)

                PreferencesManager.shared.resetToOfflineReleaseDefaults()
                QuickStartConfigManager.shared.quickStartConfig = .defaultPhoneConfig
                appearance.mode = .system
            }
        ])
    }

    private static func removeLegacyRecordSyncOutbox(fileManager: FileManager) throws {
        let fileURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("jifen-v3", isDirectory: true)
        .appendingPathComponent("sync", isDirectory: true)
        .appendingPathComponent("record-outbox.json", isDirectory: false)

        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}

private enum LocalDataResetCompositionError: LocalizedError {
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .verificationFailed:
            NSLocalizedString(
                "clear_data_verification_failed",
                value: "清除后仍检测到本地数据",
                comment: ""
            )
        }
    }
}
