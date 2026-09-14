import Foundation

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
