import Foundation
import LinkCore
import ScoreCore

/// Rally、网球与台球从当前 service 和 store 读取联动资格。
@MainActor
struct WatchLinkedMatchState {
    enum Board {
        case racket
        case billiards
    }

    private let board: Board
    private let linkedSessionId: UUID?
    private let handle: LinkedMatchHandle?
    private let linkService: WatchLinkService
    private let appliedSnapshotHandle: LinkedMatchHandle?
    private let isPendingFinish: () -> Bool
    private let isLinkedFinishConfirmed: Bool
    private let savedRecordID: String?

    init<R: DomainReducer>(
        board: Board,
        linkedSessionId: UUID?,
        handle: LinkedMatchHandle?,
        linkService: WatchLinkService,
        store: WatchReducerSessionStore<R>
    ) where R.State: Equatable {
        self.board = board
        self.linkedSessionId = linkedSessionId
        self.handle = handle
        self.linkService = linkService
        appliedSnapshotHandle = store.linkedIntentUpdate?.handle
        isPendingFinish = { store.isPendingLinkedFinish }
        isLinkedFinishConfirmed = store.isLinkedFinishConfirmed
        savedRecordID = store.savedRecordID
    }

    var isUnavailable: Bool {
        guard linkedSessionId != nil else { return false }
        guard let handle, handle == linkService.activeHandle else { return true }
        if board == .billiards, appliedSnapshotHandle != handle { return true }
        return !linkService.canEditLinkedMatch
    }

    var scoringLocked: Bool {
        isUnavailable || isPendingFinish() || isLinkedFinishConfirmed
    }

    var canPlayAgain: Bool {
        guard linkedSessionId != nil else { return board == .racket ? !scoringLocked : true }
        guard let handle, !isUnavailable, isLinkedFinishConfirmed else { return false }
        switch board {
        case .racket:
            guard savedRecordID != nil else { return false }
        case .billiards:
            guard savedRecordID == Self.recordID(for: handle) else { return false }
        }
        return !linkService.intentSync.hasPendingOperations(for: handle)
    }

    static func recordID(for handle: LinkedMatchHandle) -> String {
        "w_\(handle.matchId.uuidString)"
    }

    func menuActions(closeMenu: @escaping () -> Void) -> [WatchMenuExtraAction] {
        guard handle != nil, board == .racket || linkedSessionId != nil, !isUnavailable else { return [] }
        return [
            WatchMenuExtraAction(
                id: "sync-linked-scores",
                title: NSLocalizedString("linked_score_resync", value: "Sync score", comment: ""),
                systemImage: "arrow.triangle.2.circlepath"
            ) {
                closeMenu()
                linkService.syncLinkedScores()
            },
            WatchMenuExtraAction(
                id: "end-score-link",
                title: NSLocalizedString("linked_score_end", value: "End link", comment: ""),
                systemImage: "link.badge.minus"
            ) {
                // 选择菜单项时可能已有新的待确认终局。
                guard !isPendingFinish() else { return }
                closeMenu()
                linkService.leaveSession()
            }
        ]
    }
}
