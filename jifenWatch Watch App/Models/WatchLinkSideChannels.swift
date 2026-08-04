import Foundation
import LinkCore
import Observation
import RecordCore
import ScoreCore

extension WatchLinkService {
    /// Auto-queue a finished local watch record to the phone.
    func transferFinishedRecord(_ payload: WatchRecordTransferPayload) {
        #if DEBUG
        print("[WatchLink] transferFinishedRecord id=\(payload.id) (pending now \(pendingWatchRecords.count))")
        #endif
        if let index = pendingWatchRecords.firstIndex(where: { $0.id == payload.id }) {
            pendingWatchRecords[index] = payload
        } else {
            pendingWatchRecords.append(payload)
        }
        persistPendingWatchRecords()
        flushPendingWatchRecords()
    }

    func flushPendingWatchRecords() {
        #if DEBUG
        print("[WatchLink] flushPendingWatchRecords isActivated=\(transport.status.isActivated) reachable=\(transport.status.isReachable) pending=\(pendingWatchRecords.count)")
        #endif
        guard transport.status.isActivated, !pendingWatchRecords.isEmpty else {
            #if DEBUG
            print("[WatchLink] flush skipped: isActivated=\(transport.status.isActivated) pendingEmpty=\(pendingWatchRecords.isEmpty)")
            #endif
            return
        }
        guard transport.status.isReachable else {
            #if DEBUG
            print("[WatchLink] flush skipped: not reachable (phone will pull when reachable)")
            #endif
            return
        }
        let datas = pendingWatchRecords.compactMap { try? JSONEncoder().encode($0) }
        #if DEBUG
        print("[WatchLink] pushed \(datas.count) pending records to phone (awaiting confirm)")
        #endif
        transport.sendPendingWatchRecords(datas)
    }

    private func persistPendingWatchRecords() {
        if pendingWatchRecords.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingWatchRecordsKey)
        } else {
            do {
                let data = try JSONEncoder().encode(pendingWatchRecords)
                UserDefaults.standard.set(data, forKey: pendingWatchRecordsKey)
            } catch {
                reportPersistenceError(error)
            }
        }
    }

    /// Uses `transferUserInfo`, so usage survives an offline phone/watch interval.
    func recordCommonNameUsage(_ names: [String]) {
        let normalized = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return }

        let store = WatchCommonNamesStore.shared
        var addedLocally = false
        for name in normalized where store.recordUsage(name, type: .player) {
            addedLocally = true
        }

        pendingCommonNameUsage.append(CommonNameUsagePayload(names: normalized))
        persistPendingCommonNameUsage()
        flushPendingCommonNameUsage()
        if addedLocally {
            commonNamesDidChange()
        }
    }

    func flushPendingCommonNameUsage() {
        guard transport.status.isActivated, !pendingCommonNameUsage.isEmpty else { return }
        var deliveredCount = 0
        for payload in pendingCommonNameUsage {
            do {
                let data = try JSONEncoder().encode(payload)
                try transport.transferCommonNameUsage(data)
                deliveredCount += 1
            } catch {
                lastLinkErrorMessage = error.localizedDescription
                break
            }
        }
        guard deliveredCount > 0 else { return }
        pendingCommonNameUsage.removeFirst(deliveredCount)
        persistPendingCommonNameUsage()
    }

    private func persistPendingCommonNameUsage() {
        if pendingCommonNameUsage.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingCommonNameUsageKey)
        } else {
            do {
                let data = try JSONEncoder().encode(pendingCommonNameUsage)
                UserDefaults.standard.set(data, forKey: pendingCommonNameUsageKey)
            } catch {
                reportPersistenceError(error)
            }
        }
    }

    func handleApplicationContext(_ context: [String: Any]) {
        guard let snapshot = CommonNamesSyncSnapshot.fromApplicationContextValue(
            context[WatchConnectivityTransport.commonNamesContextKey]
        ) else { return }
        guard WatchCommonNamesStore.shared.apply(snapshot) else { return }
        commonNamesSyncFailed = false
        markCommunication()
    }

    func refreshConnectivity() {
        transport.refreshStatus()
        connectivityStatus = transport.status
    }

    func commonNamesDidChange() {
        lastQueuedCommonNameMutationIDs = []
        flushPendingCommonNameMutations(force: false)
    }

    @discardableResult
    func syncCommonNamesNow() -> WatchCommonNamesSyncRequestResult {
        refreshConnectivity()
        commonNamesSyncFailed = false
        flushPendingCommonNameMutations(force: true)
        guard connectivityStatus.isActivated else {
            commonNamesSyncFailed = true
            return .connectionInactive
        }
        guard connectivityStatus.isReachable else {
            commonNamesSyncFailed = true
            return .queuedUntilPhoneAvailable
        }
        requestCommonNamesSnapshot()
        return commonNamesSyncFailed ? .failed : .requested
    }

    func startConnectivityTest() {
        probeTimeoutTask?.cancel()
        phoneLinkTestFailure = nil
        refreshConnectivity()
        guard connectivityStatus.isActivated else {
            phoneLinkTestState = .failed
            phoneLinkTestFailure = .inactive
            return
        }
        guard connectivityStatus.isReachable else {
            phoneLinkTestState = .failed
            phoneLinkTestFailure = .unreachable
            return
        }
        let probeID = UUID()
        probeTracker.start(probeID)
        phoneLinkTestState = .testing
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: probeID,
            kind: .connectivityProbe,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: 0,
            sentAtEpochMilliseconds: nowMs(),
            payload: ConnectivityProbePayload(probeId: probeID)
        )
        do {
            try transport.sendInteractive(JSONEncoder().encode(envelope))
        } catch {
            probeTracker.cancel()
            phoneLinkTestState = .failed
            phoneLinkTestFailure = .sendFailed
            return
        }
        probeTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(WatchPhoneLinkProbeTracker.timeoutSeconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.probeTracker.timeout(probeID) else { return }
                self.phoneLinkTestState = .failed
                self.phoneLinkTestFailure = .timedOut
            }
        }
    }

    func requestCommonNamesSnapshot() {
        guard connectivityStatus.isActivated, connectivityStatus.isReachable else {
            commonNamesSyncFailed = true
            return
        }
        let requestID = UUID()
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: requestID,
            kind: .commonNamesSyncRequest,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: 0,
            sentAtEpochMilliseconds: nowMs(),
            payload: CommonNamesSyncRequestPayload(requestId: requestID)
        )
        do {
            try transport.sendInteractive(JSONEncoder().encode(envelope))
        } catch {
            commonNamesSyncFailed = true
        }
    }

    func flushPendingCommonNameMutations(force: Bool) {
        guard transport.status.isActivated,
              let batch = WatchCommonNamesStore.shared.pendingBatch() else { return }
        let ids = batch.mutations.map(\.id)
        guard force || ids != lastQueuedCommonNameMutationIDs else { return }
        do {
            let data = try JSONEncoder().encode(batch)
            try transport.transferCommonNameMutations(data)
            lastQueuedCommonNameMutationIDs = ids
        } catch {
            commonNamesSyncFailed = true
            lastLinkErrorMessage = error.localizedDescription
        }
    }

    func handleCommonNameMutationAcknowledgement(_ data: Data) {
        guard let acknowledgement = try? JSONDecoder().decode(
            CommonNameMutationAcknowledgement.self,
            from: data
        ) else { return }
        WatchCommonNamesStore.shared.apply(acknowledgement)
        lastQueuedCommonNameMutationIDs = []
        commonNamesSyncFailed = false
        markCommunication()
        flushPendingCommonNameMutations(force: false)
    }

    func markCommunication() {
        lastCommunicationAtEpochMilliseconds = nowMs()
        UserDefaults.standard.set(Int(lastCommunicationAtEpochMilliseconds), forKey: lastCommunicationAtKey)
    }

}
