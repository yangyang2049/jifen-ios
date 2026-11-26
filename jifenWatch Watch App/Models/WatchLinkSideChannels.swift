import Foundation
import LinkCore
import Observation
import RecordCore
import ScoreCore

extension WatchLinkService {
    /// Large intent commits and repair checkpoints use the same receive route.
    func handleReceivedFile(_ data: Data, metadata: [String: Any]) {
        let kind = metadata[WatchConnectivityTransport.transferFileKindKey] as? String
        guard kind == nil || kind == WatchTransferFileKind.intentFrame.rawValue else { return }
        receive(data)
    }

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
        deliverStandaloneRecord(payload)
        flushPendingWatchRecords()
    }

    /// 统一管线（与联动完赛一致）：完整编码 → 按最终字节预算选通道 →
    /// 以手机 clearPendingWatchRecords 业务 ACK 为唯一出队依据。
    /// 独立开局可能从未握手：文件能力来自配对传输层（首发协议配对即同版本），
    /// 不依赖活跃比赛。常规保存、激活重试与手机拉取共用该口径。
    func deliverStandaloneRecord(_ payload: WatchRecordTransferPayload) {
        guard let data = try? JSONEncoder().encode(payload), !data.isEmpty else {
            lastLinkErrorMessage = "standalone record encode failed"
            return
        }
        switch LinkFinishedRouting.chooseDurableChannel(
            frameByteCount: data.count,
            peerSupportsFileTransfer: transport.supportsFileTransfer
        ) {
        case .userInfo:
            try? transport.transferWatchRecord(data)
        case .file:
            try? transport.transferFileData(data, metadata: [
                WatchConnectivityTransport.transferFileKindKey: WatchTransferFileKind.watchRecord.rawValue
            ])
        case .hold:
            break // 保留队列；重连后重试会再次选通道
        }
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
        // 快路径同样完整编码：只把 ≤60KB 的帧放进消息批，超限帧只走
        // deliverStandaloneRecord 的可靠通道，不在此处裁剪。
        let datas = pendingWatchRecords
            .compactMap { try? JSONEncoder().encode($0) }
            .filter { !$0.isEmpty && $0.count <= LinkFinishedRouting.realtimeBudgetBytes }
        #if DEBUG
        print("[WatchLink] pushed \(datas.count) pending records to phone (awaiting confirm)")
        #endif
        transport.sendPendingWatchRecords(datas)
    }

    func persistPendingWatchRecords() {
        if pendingWatchRecords.isEmpty {
            outboxStore.removeObject(forKey: pendingWatchRecordsKey)
        } else {
            do {
                let data = try JSONEncoder().encode(pendingWatchRecords)
                try outboxStore.setOrThrow(data, forKey: pendingWatchRecordsKey)
            } catch {
                reportPersistenceError(error)
            }
        }
    }

    /// Player-name usage now flows through the single `CommonNameMutation(.add)`
    /// channel (offline-capable via `transferUserInfo`), replacing the removed
    /// dedicated usage-event channel.
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

        flushPendingCommonNameMutations(force: true)
        if addedLocally {
            commonNamesDidChange()
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
            try transport.sendInteractive(LinkEnvelopeEncoding.encodedData(envelope))
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
            try transport.sendInteractive(LinkEnvelopeEncoding.encodedData(envelope))
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
        WatchPreferences.shared.setInt(Int(lastCommunicationAtEpochMilliseconds), forKey: lastCommunicationAtKey)
    }

}
