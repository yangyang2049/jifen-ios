import Foundation
import PersistenceCore

enum LocalDataResetCategory: String, CaseIterable, Sendable {
    case scoreboardRecords
    case timerRecords
    case bookingsAndNotifications
    case resumeSessions
    case localPreferencesAndTools
    case legacySyncData

    var localizedTitle: String {
        switch self {
        case .scoreboardRecords:
            NSLocalizedString("clear_data_category_scoreboard", value: "计分记录", comment: "")
        case .timerRecords:
            NSLocalizedString("clear_data_category_timer", value: "计时记录", comment: "")
        case .bookingsAndNotifications:
            NSLocalizedString("clear_data_category_bookings", value: "预约与提醒", comment: "")
        case .resumeSessions:
            NSLocalizedString("clear_data_category_resume", value: "续局与草稿", comment: "")
        case .localPreferencesAndTools:
            NSLocalizedString("clear_data_category_preferences", value: "设置与工具数据", comment: "")
        case .legacySyncData:
            NSLocalizedString("clear_data_category_legacy_sync", value: "旧同步数据", comment: "")
        }
    }
}

struct LocalDataResetFailure: Equatable, Sendable, Identifiable {
    let category: LocalDataResetCategory
    let message: String

    var id: String { category.rawValue }
}

struct LocalDataResetResult: Equatable, Sendable {
    let failures: [LocalDataResetFailure]

    var succeeded: Bool { failures.isEmpty }

    var localizedFailureSummary: String {
        failures.map { "\($0.category.localizedTitle)：\($0.message)" }
            .joined(separator: "\n")
    }
}

@MainActor
struct LocalDataResetStep {
    let category: LocalDataResetCategory
    let operation: @MainActor () async throws -> Void
}

/// Best-effort, category-aware local reset. Every step is independent, so a
/// failed run can be safely retried without recreating already-cleared data.
@MainActor
struct LocalDataResetCoordinator {
    let steps: [LocalDataResetStep]

    init(steps: [LocalDataResetStep]) {
        self.steps = steps
    }

    static func live(
        appearance: AppAppearanceStore,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> Self {
        Self(steps: [
            LocalDataResetStep(category: .scoreboardRecords) {
                guard ScoreboardRecordManager.shared.clearAllRecords(),
                      ScoreboardRecordManager.shared.getAllRecordSummaries().isEmpty else {
                    throw LocalDataResetError.verificationFailed
                }
            },
            LocalDataResetStep(category: .timerRecords) {
                guard TimerRecordManager.shared.clearAllRecords(),
                      TimerRecordManager.shared.getRecords().isEmpty else {
                    throw LocalDataResetError.verificationFailed
                }
            },
            LocalDataResetStep(category: .bookingsAndNotifications) {
                CountdownNotificationManager.shared.cancel()
                guard await LocalBookingManager.shared.clearAllBookingsAndWaitForNotifications(),
                      LocalBookingManager.shared.getAllBookings().isEmpty else {
                    throw LocalDataResetError.verificationFailed
                }
            },
            LocalDataResetStep(category: .resumeSessions) {
                try await ResumeSessionRepository().clear()
            },

            LocalDataResetStep(category: .legacySyncData) {
                try AnonymousIdentityProvider.shared.clearLocalIdentity()
                try LocalDataResetFileCleaner.removeLegacyRecordSyncOutbox(
                    fileManager: fileManager
                )
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

    func clearAll() async -> LocalDataResetResult {
        var failures: [LocalDataResetFailure] = []
        for step in steps {
            do {
                try await step.operation()
            } catch {
                failures.append(LocalDataResetFailure(
                    category: step.category,
                    message: error.localizedDescription
                ))
            }
        }
        return LocalDataResetResult(failures: failures)
    }
}

enum LocalPreferenceDataResetter {
    static let postResetInitializationKey = "scoreboard_double_tap_subtract_initialized_v1"

    /// Removes every app-owned UserDefaults value, then restores only the legal
    /// acknowledgement. System notification/photo permissions live outside
    /// UserDefaults and therefore remain untouched.
    static func clear(defaults: UserDefaults) {
        let acceptedLegalVersion = defaults.object(forKey: LegalConsent.acceptedVersionKey)
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
        if let acceptedLegalVersion {
            defaults.set(acceptedLegalVersion, forKey: LegalConsent.acceptedVersionKey)
        }
        // Legal consent is intentionally retained, so mark this as an explicit
        // fresh default to prevent the legacy migration from enabling it again.
        defaults.set(true, forKey: postResetInitializationKey)
    }
}

private enum LocalDataResetFileCleaner {
    static func removeLegacyRecordSyncOutbox(fileManager: FileManager) throws {
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

private enum LocalDataResetError: LocalizedError {
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
