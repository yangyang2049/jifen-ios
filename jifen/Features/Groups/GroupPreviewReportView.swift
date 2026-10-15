import SwiftUI

struct GroupPreviewReportView: View {
    var groupNo: String
    @State private var store = GroupStore.shared
    @State private var reason = GroupReportReason.spam
    @State private var explanation = ""
    @State private var current: GroupReportStatus?
    @State private var busy = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                if let current { Section { Text(groupText("report_status", "Your report") + " · " + groupText(current.status, current.status)); if let detail = current.detail { Text(detail) } } }
                Picker(groupText("report_reason", "Reason"), selection: $reason) { ForEach(GroupReportReason.allCases) { Text($0.title).tag($0) } }
                TextField(groupText("report_detail", "Details (optional)"), text: $explanation, axis: .vertical)
                if let error = error ?? store.error { GroupNotice(text: error) }
                Button(groupText("report_submit", "Submit report")) { Task { await submit() } }.disabled(busy || explanation.unicodeScalars.count > 500 || current?.status == "pending")
            }.disabled(busy)
                // 对齐安卓 GroupReportForm：已经举报过就不是「举报」而是「更新举报」。
                .navigationTitle(groupText(current == nil ? "report" : "update_report", current == nil ? "Report group" : "Update report"))
                .groupAccountBoundary().interactiveDismissDisabled(busy)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(groupText("close", "Close")) { dismiss() }.disabled(busy) } }
                .task { await reload() }
        }
    }
    private func reload() async {
        guard let account = store.accountID else { return }; let revision = store.identityRevision
        do { let report: GroupCurrentReport = try await store.repository.read("/by-number/\(groupNo)/report"); if store.matchesIdentity(account, revision: revision) { current = report.report } }
        catch { if store.matchesIdentity(account, revision: revision) { self.error = groupErrorMessage(error) } }
    }
    private func submit() async {
        busy = true; defer { busy = false }
        nonisolated struct Body: Encodable, Sendable { var reason: String; var detail: String }
        nonisolated struct Response: Decodable, Sendable { var reportId: String }
        if await store.perform({ let _: Response = try await store.repository.write("/by-number/\(groupNo)/report", body: Body(reason: reason.rawValue, detail: explanation)) }) { await reload() }
        else { error = store.error }
    }
}

struct GroupExistingUploadResultView: View {
    var upload: GroupPendingUpload
    @State private var matches: [GroupResult] = []
    @State private var error: String?
    var body: some View {
        List {
            ForEach(matches) { GroupResultLink(result: $0) }
            if let error { GroupNotice(text: error) }
            if matches.isEmpty { Text(groupText("no_results", "No matching results yet.")) }
        }.navigationTitle(groupText("match_detail", "Match details")).groupAccountBoundary().task {
            let store = GroupStore.shared; let revision = store.identityRevision
            do {
                if let id = upload.existingResultID {
                    let row: GroupResult = try await store.repository.read("/\(upload.groupID)/results/\(id)")
                    if store.matchesIdentity(upload.accountID, revision: revision) { matches = [row] }; return
                }
                let rows: [GroupResult] = try await store.repository.allPages("/\(upload.groupID)/results")
                if store.matchesIdentity(upload.accountID, revision: revision) { matches = rows.filter { $0.gameId == upload.body.gameId || $0.id == upload.existingResultID } }
            } catch { if store.matchesIdentity(upload.accountID, revision: revision) { self.error = groupErrorMessage(error) } }
        }
    }
}
