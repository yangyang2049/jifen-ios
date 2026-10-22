import SwiftUI
import PhotosUI

private struct ReportImageDraft: Identifiable {
    let id = UUID()
    var local: Data?
    var uploaded: GroupReportEvidence?
    var uploading = false
    var failed = false
}

struct GroupEvidenceReportSheet: View {
    var groupID: String? = nil
    var groupNo: String? = nil
    @State private var store = GroupStore.shared
    @State private var reasonID: String? = GroupReportReason.spam.rawValue
    @State private var detail = ""
    @State private var current: GroupReportStatus?
    @State private var images: [ReportImageDraft] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var busy = false
    @State private var loading = true
    @State private var reportLoaded = false
    @State private var legacyReport = false
    @State private var loadingPhotos = false
    @State private var receipt = false
    @State private var evidenceEnabled = false
    @State private var error: String?
    @State private var preview: ReportImageDraft?
    @State private var generation = 0
    @State private var requestFingerprint = ""
    @State private var requestKey = UUID().uuidString
    @Environment(\.dismiss) private var dismiss
    private var reportPath: String { groupID.map { "/\($0)/report" } ?? "/by-number/\(groupNo ?? "")/report" }

    var body: some View {
        ReportSheet(
            title: groupText(receipt ? "report_status" : "report", receipt ? "Your report" : "Report group"),
            reasonTitle: groupText("report_reason", "Reason"),
            detailPlaceholder: groupText("report_detail", "Details (optional)"),
            submitTitle: groupText(receipt ? "report_supplement" : "report_submit", receipt ? "Add information" : "Submit report"),
            reasons: GroupReportReason.allCases.map { .init(id: $0.rawValue, title: $0.title) },
            selectedReasonID: $reasonID, detail: $detail,
            isSubmitting: busy || loading,
            canSubmit: reportLoaded && !loadingPhotos && !images.contains { $0.uploading || $0.failed },
            canEdit: reportLoaded,
            errorMessage: error,
            statusTitle: current.map { groupText("report_status", "Your report") + " · " + $0.statusLabel },
            statusDetail: current?.publicResolution,
            detailLimit: GroupInputValidation.reportDetailMax, detailLength: .utf16,
            accessibilityPrefix: groupID == nil ? "group_preview_report" : "group_report",
            usesTopAction: false, receiptMode: receipt, extraContent: AnyView(evidenceSection),
            onCancel: { dismiss() },
            onSubmit: { if receipt { receipt = false } else { Task { await submit() } } }
        )
        .groupAccountBoundary()
        .task { await reload() }
        .onDisappear { generation += 1 }
        .onChange(of: selectedPhotos) { _, photos in
            if !photos.isEmpty { loadingPhotos = true; Task { await loadPhotos(photos) } }
        }
        .sheet(item: $preview) { item in
            NavigationStack {
                imageView(item).scaledToFit().padding()
                    .navigationTitle(groupText("report_preview", "Evidence image"))
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(groupText("report_close", "Close")) { preview = nil } } }
            }.tint(Theme.primary)
        }
    }

    @ViewBuilder private var evidenceSection: some View {
        if current != nil || !reportLoaded {
            Button(groupText("report_refresh", "Refresh status")) { Task { await reload(preserveDraft: !receipt) } }
                .disabled(loading || busy)
        }
        if receipt, let reportID = current?.reportId { Text(reportID).font(.caption).foregroundStyle(Theme.textSecondary) }
        if evidenceEnabled || !images.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(groupText("report_evidence_title", "Image evidence (optional)")).font(.subheadline.weight(.semibold))
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(images) { item in
                            VStack {
                                ZStack(alignment: .topTrailing) {
                                    Button { preview = item } label: { imageView(item).frame(width: 76, height: 76).clipped() }
                                        .buttonStyle(.plain)
                                    if !receipt {
                                        Button { images.removeAll { $0.id == item.id } } label: {
                                            Image(systemName: "xmark.circle.fill").font(.title3).padding(8)
                                        }.accessibilityLabel(groupText("report_remove_image", "Remove image"))
                                    }
                                }
                                if item.uploading { ProgressView() }
                                if item.failed { Button(groupText("report_retry", "Retry")) { Task { await upload(item) } } }
                            }
                        }
                        if !receipt && images.count < 3 && evidenceEnabled {
                            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 3 - images.count, matching: .images) {
                                VStack(spacing: 5) {
                                    Image(systemName: "plus")
                                    Text(groupText("report_add_image", "Add image")).font(.caption)
                                }.frame(width: 76, height: 76).background(Theme.inputFieldBackground, in: RoundedRectangle(cornerRadius: 10))
                            }.disabled(loadingPhotos || !reportLoaded || busy)
                        }
                    }
                }
                Text(groupText("report_evidence_hint", "Up to 3 JPG or PNG images, 2 MB each. Visible only to you and the platform."))
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder private func imageView(_ item: ReportImageDraft) -> some View {
        if let data = item.local, let image = UIImage(data: data) { Image(uiImage: image).resizable() }
        else if let path = item.uploaded?.url {
            AsyncImage(url: URL(string: path, relativeTo: APIEnvironment.current.restBaseURL)) { phase in
                if let image = phase.image { image.resizable() }
                else { Image(systemName: "photo").foregroundStyle(Theme.textSecondary) }
            }
        } else { Image(systemName: "photo") }
    }

    private func reload(preserveDraft: Bool = false) async {
        let account = store.accountID, revision = store.identityRevision, epoch = generation
        let keepDraft = preserveDraft && current != nil
        loading = true; reportLoaded = false
        defer { if generation == epoch { loading = false } }
        do {
            let capabilities: GroupCapabilities = try await store.repository.read("/capabilities")
            guard generation == epoch, let account, store.matchesIdentity(account, revision: revision) else { return }
            evidenceEnabled = capabilities.groupReportEvidenceEnabled == true
            legacyReport = capabilities.groupReportEvidenceEnabled == nil
            if legacyReport {
                reportLoaded = true; error = nil
                return
            }
            let response: GroupCurrentReport = try await store.repository.read(reportPath)
            guard generation == epoch, store.matchesIdentity(account, revision: revision) else { return }
            current = response.report
            if let saved = response.report, !keepDraft {
                reasonID = saved.reason; detail = saved.detail ?? ""
                images = (saved.attachments ?? []).filter { $0.purged != true }.map { .init(uploaded: $0) }
                receipt = true
            }
            reportLoaded = true; error = nil
        } catch { if generation == epoch, let account, store.matchesIdentity(account, revision: revision) { self.error = groupErrorMessage(error) } }
    }

    private func loadPhotos(_ photos: [PhotosPickerItem]) async {
        let account = store.accountID, revision = store.identityRevision, epoch = generation
        defer { if generation == epoch { loadingPhotos = false } }
        for photo in photos.prefix(max(0, 3 - images.count)) {
            guard let data = try? await photo.loadTransferable(type: Data.self), data.count <= 20 * 1024 * 1024,
                  let image = UIImage(data: data), let compressed = FeedbackImageCompressor.prepareJPEG(image) else {
                error = groupText("report_image_error", "Unable to prepare the image. Try another JPG or PNG image."); continue
            }
            guard generation == epoch, let account, store.matchesIdentity(account, revision: revision), images.count < 3 else { return }
            let item = ReportImageDraft(local: compressed)
            images.append(item)
            await upload(item)
        }
        if generation == epoch { selectedPhotos = [] }
    }

    private func upload(_ item: ReportImageDraft) async {
        guard let data = item.local, let account = store.accountID, let index = images.firstIndex(where: { $0.id == item.id }) else { return }
        let revision = store.identityRevision, epoch = generation
        images[index].uploading = true; images[index].failed = false
        let authRevision = await APIClient.shared.authSessionRevision()
        guard generation == epoch, store.matchesIdentity(account, revision: revision) else { return }
        do {
            let boundary = "report-" + UUID().uuidString
            var body = Data()
            body.append(Data(("--" + boundary + "\r\nContent-Disposition: form-data; name=\"image\"; filename=\"evidence.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n").utf8))
            body.append(data); body.append(Data(("\r\n--" + boundary + "--\r\n").utf8))
            let result: GroupReportEvidence = try await APIClient.shared.upload("/api/groups/report-evidence", multipartBody: body, boundary: boundary, expectedAuthRevision: authRevision)
            guard generation == epoch, store.matchesIdentity(account, revision: revision), let index = images.firstIndex(where: { $0.id == item.id }) else { return }
            images[index].uploaded = result; images[index].uploading = false
        } catch {
            guard generation == epoch, store.matchesIdentity(account, revision: revision), let index = images.firstIndex(where: { $0.id == item.id }) else { return }
            images[index].uploading = false; images[index].failed = true; self.error = groupErrorMessage(error)
        }
    }

    private func submit() async {
        guard reportLoaded, !busy, !loading, !loadingPhotos, !images.contains(where: { $0.uploading || $0.failed }), let reasonID,
              let account = store.accountID else { return }
        let identity = store.identityRevision, epoch = generation
        nonisolated struct Body: Encodable, Sendable { var reason: String; var detail: String; var attachmentIds: [String]?; var expectedVersion: Int? }
        let body = Body(reason: reasonID, detail: detail,
                        attachmentIds: legacyReport ? nil : images.compactMap { $0.uploaded?.uploadId },
                        expectedVersion: legacyReport ? nil : (current?.version ?? 0))
        let fingerprint = reasonID + detail + (body.attachmentIds ?? []).joined(separator: ",") + String(body.expectedVersion ?? -1)
        if fingerprint != requestFingerprint { requestKey = UUID().uuidString; requestFingerprint = fingerprint }
        let authRevision = await APIClient.shared.authSessionRevision()
        guard generation == epoch, store.matchesIdentity(account, revision: identity) else { return }
        busy = true; error = nil
        defer { if generation == epoch { busy = false } }
        do {
            let _: EmptyResponse = try await store.repository.write(reportPath, body: body, key: requestKey, expectedAuthRevision: authRevision)
            guard generation == epoch, store.matchesIdentity(account, revision: identity) else { return }
            await reload()
        } catch { if generation == epoch, store.matchesIdentity(account, revision: identity) { self.error = groupErrorMessage(error) } }
    }
}
