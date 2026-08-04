import Foundation
import LinkCore
import Observation
import RecordCore
import ScoreCore
import UIKit


extension PhoneWatchLinkService {
    /// Force a connectivity status refresh for the Watch Link settings page.
    func refreshConnectivity() {
        transport.refreshStatus()
        connectivityStatus = transport.status
        pushCommonNamesToWatch()
    }

    /// Interactive setup cannot wake the Watch app. Refresh immediately before
    /// creating a linked session so an unavailable Watch never receives a queued
    /// setup request that appears later without the user's context.
    func validateInteractiveWatchAvailability() throws {
        transport.refreshStatus()
        connectivityStatus = transport.status
        guard connectivityStatus.isSupported,
              connectivityStatus.isActivated,
              connectivityStatus.isPaired,
              connectivityStatus.isWatchAppInstalled else {
            throw InteractiveStartError.watchUnavailable
        }
        guard connectivityStatus.isReachable else {
            throw InteractiveStartError.watchAppNotForeground
        }
    }

    /// Push current phone common names to the watch via application context (always-latest).
    func pushCommonNamesToWatch() {
        guard connectivityStatus.isSupported,
              connectivityStatus.isActivated,
              connectivityStatus.isPaired,
              connectivityStatus.isWatchAppInstalled else { return }
        let snapshot = CommonNamesManager.shared.currentSyncSnapshot()
        let context: [String: Any] = [
            WatchConnectivityTransport.commonNamesContextKey: snapshot.applicationContextValue()
        ]
        do {
            try transport.updateApplicationContext(context)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func handleWatchRecordTransfer(_ data: Data) {
        guard let payload = try? JSONDecoder().decode(WatchRecordTransferPayload.self, from: data) else {
            return
        }
        do {
            lastSyncedWatchRecordId = try WatchStandaloneRecordIngestor.ingest(payload)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func handleCommonNameUsage(_ data: Data) {
        guard let payload = try? JSONDecoder().decode(CommonNameUsagePayload.self, from: data),
              payload.nameType == "player" else { return }
        Task { @MainActor [weak self] in
            for name in payload.names {
                await CommonNamesManager.shared.saveNameIfNeeded(name, .player)
            }
            self?.pushCommonNamesToWatch()
        }
    }

    func handleCommonNameMutations(_ data: Data) {
        guard let batch = try? JSONDecoder().decode(CommonNameMutationBatch.self, from: data),
              !batch.mutations.isEmpty else { return }
        let acknowledgement = CommonNamesManager.shared.applyWatchMutations(batch.mutations)
        do {
            let acknowledgementData = try JSONEncoder().encode(acknowledgement)
            try transport.transferCommonNameMutationAcknowledgement(acknowledgementData)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        if !acknowledgement.results.contains(where: { $0.status == .applied }) {
            pushCommonNamesToWatch()
        }
    }

    func handleConnectivityStatusChange(_ status: WatchConnectivityStatus) {
        connectivityStatus = status
        pushCommonNamesToWatch()
        guard status.isReachable else { return }
        flushPendingSessionEnds()
        requestStatusForActiveSession()
    }

    func requestStatusForActiveSession() {
        guard activeSession != nil else { return }
        Task {
            do {
                _ = try await queryStatus(timeoutSeconds: 3)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }
}
