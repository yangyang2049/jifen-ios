import Foundation
import LinkCore
import ScoreCore

/// 抢分板与网球共用的续玩草稿口径。
///
/// 两块板的落盘条件一致：联动 handle 必须仍是当前场次、完赛后按草稿归属清理、
/// 没有比分时不保留草稿。各自的进度判定、比分文案、图标与 payload 仍由
/// 计分板自己提供。
@MainActor
enum WatchRacketResumeDraft {
    static func persist(
        into resumeStore: WatchResumeSessionStore,
        linkedSessionId: UUID?,
        handle: LinkedMatchHandle?,
        activeHandle: LinkedMatchHandle?,
        isFinished: Bool,
        didFinalizeFinish: Bool,
        hasProgress: Bool,
        startedAt: Date,
        scoreLine: String,
        emoji: String,
        actionLog: WatchScoreActionLog,
        payload: () -> WatchResumePayload
    ) {
        let linkHandle: LinkedMatchHandle?
        if linkedSessionId != nil {
            guard let handle, handle == activeHandle else { return }
            linkHandle = handle
        } else {
            linkHandle = nil
        }
        if isFinished {
            if didFinalizeFinish, resumeStore.session?.linkHandle == linkHandle { resumeStore.clear() }
            return
        }
        guard hasProgress else {
            resumeStore.clear()
            return
        }
        resumeStore.save(WatchResumeSession(
            startedAt: startedAt,
            scoreLine: scoreLine,
            emoji: emoji,
            payload: payload(),
            actionLog: actionLog,
            linkHandle: linkHandle
        ))
    }
}

/// 八球 / 九球 / 斯诺克共用的续玩草稿口径。
///
/// 三块板只在进度判定与 payload 上不同：联动草稿的归属（handle 与当前比赛
/// 记录 ID）、单机完赛后的清理、以及「待终局确认也算有进度」的判定一致。
@MainActor
enum WatchBilliardsResumeDraft {
    static func persist<R: DomainReducer>(
        store: WatchReducerSessionStore<R>,
        into resumeStore: WatchResumeSessionStore,
        linkedSessionId: UUID?,
        handle: LinkedMatchHandle?,
        activeHandle: LinkedMatchHandle?,
        resumeContext: WatchLinkResumeContext?,
        isFinished: Bool,
        hasProgress: Bool,
        startedAt: Date,
        payload: () -> WatchResumePayload
    ) where R.State: Equatable {
        let context: WatchLinkResumeContext?
        if linkedSessionId != nil {
            guard let handle, handle == activeHandle,
                  let resumeContext, resumeContext.handle == handle else { return }
            if store.savedRecordID == WatchLinkedMatchState.recordID(for: handle) {
                if resumeStore.session?.linkHandle == handle { resumeStore.clear() }
                return
            }
            context = resumeContext
        } else {
            if isFinished {
                if store.savedRecordID != nil, resumeStore.session?.linkHandle == nil { resumeStore.clear() }
                return
            }
            context = nil
        }
        guard hasProgress || store.isPendingLinkedFinish || store.isLinkedFinishConfirmed else {
            if linkedSessionId == nil, resumeStore.session?.linkHandle == nil { resumeStore.clear() }
            return
        }
        store.persistResumeSession(
            into: resumeStore,
            link: context,
            startedAt: startedAt,
            payload: payload()
        )
    }
}
