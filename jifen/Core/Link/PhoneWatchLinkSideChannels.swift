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
        lastSyncedWatchRecordId = ingestWatchRecordData(data)
    }

    /// Decode + ingest a standalone watch record. Returns the synced record id, or nil on failure.
    /// Ingestion is idempotent (upsert by record id), so repeated calls for the same payload are safe.
    func ingestWatchRecordData(_ data: Data) -> String? {
        guard let payload = try? JSONDecoder().decode(WatchRecordTransferPayload.self, from: data) else {
            #if DEBUG
            print("[PhoneLink] ingestWatchRecordData: failed to decode payload")
            #endif
            return nil
        }
        do {
            let id = try WatchStandaloneRecordIngestor.ingest(payload)
            #if DEBUG
            print("[PhoneLink] ingest succeeded, record id=\(id)")
            #endif
            lastSyncedWatchRecordId = id
            return id
        } catch {
            #if DEBUG
            print("[PhoneLink] ingest failed: \(error.localizedDescription)")
            #endif
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }

    /// Phone side of the catch-up handshake: ingest records the watch just sent and
    /// tell the watch to drop the ones we successfully ingested.
    func receivePendingWatchRecords(_ datas: [Data]) {
        #if DEBUG
        print("[PhoneLink] receivePendingWatchRecords count=\(datas.count)")
        #endif
        guard !datas.isEmpty else { return }
        var ingestedIds: [String] = []
        for data in datas {
            if let id = ingestWatchRecordData(data) {
                ingestedIds.append(id)
            }
        }
        guard !ingestedIds.isEmpty else { return }
        transport.clearPendingWatchRecords(ids: ingestedIds)
        #if DEBUG
        print("[PhoneLink] cleared \(ingestedIds.count) pending records on watch")
        #endif
    }

    /// Ask the watch for any finished-record transfers it queued but we never received.
    /// Debounced so repeated connectivity changes don't spam the watch.
    func requestPendingWatchRecordsFromWatch() {
        guard !watchRecordCatchUpInFlight else { return }
        watchRecordCatchUpInFlight = true
        transport.requestPendingWatchRecords()
        #if DEBUG
        print("[PhoneLink] requested pending watch records (catch-up)")
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.watchRecordCatchUpInFlight = false
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
        requestPendingWatchRecordsFromWatch()
    }

    func requestStatusForActiveSession() {
        guard activeSession != nil else { return }
        Task {
            // 尽力而为的后台状态刷新。超时必须与手表确认/开局窗口（20s）对齐，
            // 否则手表尚在确认时手机会过早判定“状态响应超时”。该刷新失败属于
            // 非致命事件，不应弹出“联动失败”对话框——只有开局流程自身的 setup
            // 超时才会以红字内联显示在设置弹窗里（与手表端行为一致）。
            _ = try? await queryStatus(
                timeoutSeconds: PhoneWatchLinkService.statusQueryTimeoutSeconds
            )
        }
    }
}
