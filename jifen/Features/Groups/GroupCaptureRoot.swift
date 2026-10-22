#if DEBUG
import SwiftUI
import ScoreCore

/// A route adapter only: every visible element is supplied by an existing production component.
struct GroupCaptureRoot: View {
    var onStart: (GameType, SportsSetupResult, String) -> Void
    @State private var store = GroupStore.shared
    @State private var ready = false
    @State private var preparationStarted = false
    @State private var failure: String?
    private let scene = GroupCaptureFixture.scene
    private var nativeScene: String {
        let native = GroupCaptureFixture.nativeScene
        if GroupCaptureFixture.argument("-GroupCaptureRealActivityNavigation") == "true", ["activity", "activity-edit", "activity-registration", "lineup", "lineup-review", "lineup-frozen", "lineup-correction", "result-frozen", "activity-cancel", "activity-abandon", "result-abandon", "registration-draft", "lineup-clock", "lineup-finish", "lineup-conflict-reload", "activity-conflict"].contains(native) { return "detail-activities" }
        return native
    }
    static let supportedScenes: Set<String> = [
        "archived-list", "activity-registration", "lineup-direct", "members-removed",
        "activity",
        "activity-create",
        "activity-edit",
        "activity-registration-draft-discard",
        "admin",
        "coach",
        "create",
        "create-approval-selected",
        "detail-activities",
        "detail-admin",
        "detail-archived",
        "detail-dissolving",
        "detail-empty",
        "detail-failure",
        "detail-member",
        "detail-members",
        "detail-offline",
        "detail-overview",
        "detail-records",
        "detail-records-doubles",
        "dialog-archive",
        "dialog-common-name-import",
        "dialog-dissolve",
        "dialog-edit-group",
        "dialog-leave",
        "dialog-rename-member",
        "dialog-report",
        "dialog-restore",
        "dialog-temporary-member",
        "dialog-transfer-owner",
        "home",
        "inventory-activity-abandon",
        "inventory-activity-cancel",
        "inventory-activity-common-places",
        "inventory-activity-conflict-review",
        "inventory-activity-date-time",
        "inventory-activity-registration-deadline",
        "inventory-approve-join-confirm",
        "inventory-archive-confirm",
        "inventory-common-name-import",
        "inventory-dissolve-confirm",
        "inventory-edit-group",
        "inventory-edit-group-conflict",
        "inventory-leave-group-confirm",
        "inventory-lineup-clock",
        "inventory-lineup-finish",
        "inventory-lineup-reload-confirm",
        "inventory-management-actions",
        "inventory-member-actions",
        "inventory-member-report",
        "inventory-registration-draft-discard",
        "inventory-reject-join-confirm",
        "inventory-remove-member-confirm",
        "inventory-rename-temporary-member",
        "inventory-result-abandon",
        "inventory-result-actions",
        "inventory-result-authority-confirm-detail",
        "inventory-result-authority-confirm-list",
        "inventory-result-normal-confirm-detail",
        "inventory-result-played-at",
        "inventory-result-save-draft-return",
        "inventory-result-void-detail-confirmed",
        "inventory-result-void-detail-pending",
        "inventory-result-void-list",
        "inventory-temporary-members",
        "inventory-training-cancel",
        "inventory-training-clock-picker",
        "inventory-training-conflict-review",
        "inventory-training-date-picker",
        "inventory-training-leave",
        "inventory-training-sequence-preview",
        "inventory-transfer-confirm",
        "inventory-transfer-picker",
        "inventory-upload-discard-confirm",
        "inventory-visitor-report",
        "join",
        "join-approval",
        "join-empty",
        "lineup",
        "lineup-correction",
        "lineup-frozen",
        "lineup-review",
        "list",
        "member-results",
        "notices",
        "result",
        "result-detail",
        "result-detail-confirmed",
        "result-detail-pending",
        "result-detail-voided",
        "result-details-expansion",
        "result-frozen",
        "result-launch",
        "result-member-picker",
        "result-rules",
        "share",
        "share-readonly",
        "student",
        "training-notices",
        "training-plan",
        "training-plan-create",
        "training-plan-edit",
        "training-plan-frozen",
        "training-plan-review",
        "training-shift-preview",
    ]

    var body: some View {
        Group {
            if let failure { GroupNotice(text: failure) }
            else if !ready { ProgressView() }
            else { destination }
        }
        .preferredColorScheme(GroupCaptureFixture.argument("-GroupCaptureAppearance") == "Dark" ? .dark : .light)
        .environment(\.dynamicTypeSize, .large)
        .environment(\.locale, Locale(identifier: GroupCaptureFixture.argument("-GroupCaptureLocale") ?? "zh_CN"))
        .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
        .overlay(alignment: .topLeading) {
            // The identity is accessibility metadata only; no diagnostic text is drawn into screenshots.
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("group_capture_identity")
                .accessibilityLabel("group_capture_identity")
                .accessibilityValue(GroupCaptureFixture.metadata + ";ready=\(ready && failure == nil)")
                .allowsHitTesting(false)
        }
        .task {
            // Group forwards task to its conditional child; switching from loading to the page must not reseed local resumes.
            guard !preparationStarted else { return }; preparationStarted = true
            guard Self.supportedScenes.contains(scene) else { failure = "Unsupported capture scene: \(scene)"; return }
            await store.refresh()
            if let error = store.error { failure = error; return }
            do { _ = try GroupCaptureFixture.dataset(); try await GroupCaptureFixture.prepareNativeResume(); ready = true }
            catch { failure = error.localizedDescription }
        }
    }

    @ViewBuilder private var destination: some View {
        let groupID = GroupCaptureFixture.groupID
        if ["list", "create", "create-approval-selected", "join", "join-approval", "join-empty", "visitor-report", "archived-list"].contains(nativeScene) {
            GroupListView(onStart: onStart)
        } else if nativeScene == "detail-failure" {
            GroupDetailView(groupID: groupID, onStart: onStart)
        } else if let detail = store.cache.details[groupID] {
            if ["activity", "activity-edit", "activity-registration", "lineup", "lineup-review", "lineup-frozen", "lineup-correction", "result-frozen", "activity-cancel", "activity-abandon", "result-abandon", "registration-draft", "lineup-clock", "lineup-finish", "lineup-conflict-reload", "activity-conflict"].contains(nativeScene), let activity = detail.activities.first {
                GroupActivityView(detail: detail, activity: activity, onStart: onStart)
            } else if ["result-detail", "result-detail-confirmed", "result-detail-pending", "result-detail-voided"].contains(nativeScene) || ["result-authority", "result-normal", "result-void-pending", "result-void-confirmed", "result-void-list", "result-actions"].contains(nativeScene) {
                // A detail capture addresses its intended result, independently of the API list's newest-first order.
                if let result = detail.results.first(where: { $0.id == GroupCaptureFixture.resultDetailID }) { GroupResultDetailView(initial: result) }
                else { GroupNotice(text: "Capture target result missing: " + GroupCaptureFixture.resultDetailID) }
            } else if nativeScene == "member-results", let member = detail.members.first {
                GroupMemberResultsView(groupID: groupID, memberID: member.id, name: member.displayName, format: .doubles)
            } else if nativeScene == "share" || nativeScene == "share-readonly" {
                GroupShareView(group: detail.group)
            } else if nativeScene == "notices" {
                GroupDetailView(groupID: groupID, onStart: onStart, initialTab: 2)
            } else {
                let training = GroupCaptureFixture.trainingScene
                let activities = ["detail-activities", "lineup-direct", "activity-create", "activity-date", "activity-deadline", "activity-place"].contains(nativeScene)
                let records = ["detail-records", "detail-records-doubles", "records-authority", "upload-discard"].contains(nativeScene)
                let members = ["detail-members", "members-removed", "dialog-temporary-member", "dialog-rename-member", "dialog-common-name-import", "member-actions", "member-rename", "member-remove", "request-approve", "request-reject"].contains(nativeScene)
                GroupDetailView(groupID: groupID, onStart: onStart, initialTab: training || activities ? 1 : records ? 2 : members ? 3 : 0)
            }
        } else { GroupNotice(text: "Capture group missing: \(groupID)") }
    }
}
#endif
