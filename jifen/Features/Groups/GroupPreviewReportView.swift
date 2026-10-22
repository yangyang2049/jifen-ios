import SwiftUI

struct GroupPreviewReportView: View {
    var groupNo: String
    var body: some View { GroupEvidenceReportSheet(groupNo: groupNo) }
}

struct GroupExistingUploadResultView: View {
    var upload: GroupPendingUpload
    @State private var matches: [GroupResult] = []
    @State private var error: String?
    var body: some View {
        List {
            ForEach(matches) { GroupResultLink(result: $0, showDisclosure: false) }
            if let error { GroupNotice(text: error) }
            if matches.isEmpty { Text(groupText("no_results", "No matching results yet.")) }
        }.expandedPhonePageContent(existingHorizontalInset: Theme.padding).background(Theme.backgroundColor).navigationTitle(groupText("match_detail", "Match details")).groupAccountBoundary().task {
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
