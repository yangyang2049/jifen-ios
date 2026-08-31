import PhotosUI
import SwiftUI
import UIKit

struct FeedbackListView: View {
    @Environment(SessionStore.self) private var session
    @State private var items: [FeedbackItem] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreate = false

    var body: some View {
        Group {
            if items.isEmpty && isLoading {
                ProgressView()
            } else if items.isEmpty, let errorMessage {
                ContentUnavailableView(
                    NSLocalizedString("feedback_load_failed", value: "加载失败", comment: ""),
                    systemImage: "wifi.exclamationmark",
                    description: Text(errorMessage)
                )
            } else {
                List {
                    ForEach(items) { item in
                        NavigationLink { FeedbackDetailView(feedbackId: item.id) } label: {
                            FeedbackRow(item: item)
                        }
                    }
                    if hasMore {
                        Button(NSLocalizedString("feedback_load_more", value: "加载更多", comment: "")) {
                            Task { await load(reset: false) }
                        }
                        .disabled(isLoading)
                    }
                }
                .listStyle(.plain)
                .refreshable { await load(reset: true) }
            }
        }
        .navigationTitle(NSLocalizedString("feedback_title", value: "反馈与建议", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "square.and.pencil") }
                    .disabled(!session.isAuthenticated)
            }
        }
        .overlay(alignment: .bottom) {
            if !session.isAuthenticated {
                Text(NSLocalizedString("feedback_login_to_post", value: "登录后可以发布、点赞和评论", comment: ""))
                    .font(.footnote)
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .padding()
            }
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack { CreateFeedbackView { Task { await load(reset: true) } } }
        }
        .task { if items.isEmpty { await load(reset: true) } }
    }

    private func load(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let next = reset ? 1 : page + 1
            let result = try await FeedbackAPI.shared.list(page: next)
            items = reset ? result.items : items + result.items
            page = result.page
            hasMore = result.hasMore
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FeedbackRow: View {
    let item: FeedbackItem
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(item.type.title).font(.caption).foregroundStyle(Theme.accentColor)
                Spacer()
                Text(item.authorName).font(.caption).foregroundStyle(.secondary)
            }
            Text(item.title).font(.headline).lineLimit(2)
            Text(item.content).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            HStack(spacing: 16) {
                Label(String(item.likeCount), systemImage: item.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                Label(String(item.commentCount), systemImage: "bubble.left")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }
}

struct FeedbackDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let feedbackId: String
    @State private var item: FeedbackItem?
    @State private var comments: [FeedbackComment] = []
    @State private var commentText = ""
    @State private var errorMessage: String?
    @State private var showReport = false
    @State private var isActing = false

    var body: some View {
        ScrollView {
            if let item {
                VStack(alignment: .leading, spacing: 16) {
                    Text(item.title).font(.title2.bold())
                    Text(item.content).textSelection(.enabled)
                    imageGrid(item.images)
                    HStack {
                        Button {
                            Task { await toggleLike() }
                        } label: {
                            Label(String(item.likeCount), systemImage: item.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                        }
                        .disabled(!session.isAuthenticated || isActing)
                        Spacer()
                        Button(NSLocalizedString("feedback_report", value: "举报", comment: "")) { showReport = true }
                            .disabled(!session.isAuthenticated || isActing)
                    }
                    Divider()
                    Text(NSLocalizedString("feedback_comments", value: "评论", comment: "")).font(.headline)
                    if session.isAuthenticated {
                        HStack {
                            TextField(NSLocalizedString("feedback_comment_placeholder", value: "说说你的看法", comment: ""), text: $commentText)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: commentText) { _, value in
                                    if value.count > 2_000 { commentText = String(value.prefix(2_000)) }
                                }
                            Button(NSLocalizedString("feedback_send", value: "发送", comment: "")) {
                                Task { await sendComment() }
                            }
                            .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isActing)
                        }
                    }
                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(comment.authorName).font(.caption).foregroundStyle(.secondary)
                            Text(comment.content)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }
                }
                .padding()
            } else if let errorMessage {
                ContentUnavailableView("", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                ProgressView().padding()
            }
        }
        .navigationTitle(NSLocalizedString("feedback_detail", value: "反馈详情", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if item?.authorId == session.user?.id {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { Task { await deleteItem() } } label: { Image(systemName: "trash") }
                }
            }
        }
        .confirmationDialog(NSLocalizedString("feedback_report_reason", value: "举报原因", comment: ""), isPresented: $showReport) {
            Button(NSLocalizedString("feedback_report_spam", value: "垃圾广告", comment: "")) { Task { await report("SPAM") } }
            Button(NSLocalizedString("feedback_report_harassment", value: "骚扰或辱骂", comment: "")) { Task { await report("HARASSMENT") } }
            Button(NSLocalizedString("feedback_report_image", value: "图片违规", comment: "")) { Task { await report("IMAGE_VIOLATION") } }
            Button(NSLocalizedString("cancel", value: "取消", comment: ""), role: .cancel) {}
        }
        .task { await load() }
    }

    @ViewBuilder
    private func imageGrid(_ images: [String]) -> some View {
        if !images.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                ForEach(images, id: \.self) { path in
                    AsyncImage(url: FeedbackAPI.shared.absoluteImageURL(path)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: { ProgressView() }
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func load() async {
        do {
            async let detail = FeedbackAPI.shared.detail(id: feedbackId)
            async let loadedComments = FeedbackAPI.shared.comments(feedbackId: feedbackId)
            item = try await detail
            comments = try await loadedComments
        } catch { errorMessage = error.localizedDescription }
    }
    private func toggleLike() async {
        guard let item, !isActing else { return }
        isActing = true
        defer { isActing = false }
        do { self.item = try await FeedbackAPI.shared.setLiked(!item.isLiked, feedbackId: feedbackId) }
        catch { errorMessage = error.localizedDescription }
    }
    private func sendComment() async {
        let value = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !isActing else { return }
        isActing = true
        defer { isActing = false }
        do {
            let comment = try await FeedbackAPI.shared.comment(value, feedbackId: feedbackId)
            comments.insert(comment, at: 0)
            commentText = ""
        } catch { errorMessage = error.localizedDescription }
    }
    private func report(_ reason: String) async {
        guard !isActing else { return }
        isActing = true
        defer { isActing = false }
        do { try await FeedbackAPI.shared.report(feedbackId: feedbackId, reason: reason, detail: nil); item?.isReported = true }
        catch { errorMessage = error.localizedDescription }
    }
    private func deleteItem() async {
        guard !isActing else { return }
        isActing = true
        defer { isActing = false }
        do { try await FeedbackAPI.shared.delete(feedbackId: feedbackId); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct CreateFeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    let onCreated: () -> Void
    @State private var type: FeedbackType = .feedback
    @State private var title = ""
    @State private var content = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var images: [Data] = []
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Picker(NSLocalizedString("feedback_type", value: "类型", comment: ""), selection: $type) {
                ForEach(FeedbackType.allCases) { Text($0.title).tag($0) }
            }
            TextField(NSLocalizedString("feedback_title_placeholder", value: "标题（至少 5 个字）", comment: ""), text: $title)
                .onChange(of: title) { _, value in
                    if value.count > 200 { title = String(value.prefix(200)) }
                }
            TextField(NSLocalizedString("feedback_content_placeholder", value: "请详细描述（至少 10 个字）", comment: ""), text: $content, axis: .vertical)
                .lineLimit(5...12)
                .onChange(of: content) { _, value in
                    if value.count > 10_000 { content = String(value.prefix(10_000)) }
                }
            PhotosPicker(
                selection: $selectedPhotos,
                maxSelectionCount: 5,
                matching: .images
            ) {
                Label(NSLocalizedString("feedback_add_images", value: "添加图片（最多 5 张）", comment: ""), systemImage: "photo.on.rectangle")
            }
            if !images.isEmpty { Text(String(format: NSLocalizedString("feedback_images_selected", value: "已选择 %d 张", comment: ""), images.count)) }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
        }
        .navigationTitle(NSLocalizedString("feedback_create", value: "发布反馈", comment: ""))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(NSLocalizedString("cancel", value: "取消", comment: "")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(NSLocalizedString("publish", value: "发布", comment: "")) { Task { await submit() } }
                    .disabled(isSubmitting || normalizedTitle.count < 5 || normalizedContent.count < 10)
            }
        }
        .onChange(of: selectedPhotos) { _, items in
            Task { await loadImages(items) }
        }
    }

    private func loadImages(_ items: [PhotosPickerItem]) async {
        var loaded: [Data] = []
        var failed = 0
        for item in items.prefix(5) {
            guard let source = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: source),
                  let data = FeedbackImageCompressor.prepareJPEG(image)
            else { failed += 1; continue }
            loaded.append(data)
        }
        images = loaded
        errorMessage = failed > 0
            ? String(format: NSLocalizedString("feedback_image_prepare_failed", value: "%d 张图片无法处理，请换一张后重试", comment: ""), failed)
            : nil
    }

    private func submit() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            var urls: [String] = []
            for data in images { urls.append(try await FeedbackAPI.shared.uploadJPEG(data)) }
            _ = try await FeedbackAPI.shared.create(
                type: type,
                title: normalizedTitle,
                content: normalizedContent,
                imageURLs: urls
            )
            onCreated()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
enum FeedbackImageCompressor {
    static let maximumBytes = 2 * 1024 * 1024

    static func prepareJPEG(_ source: UIImage) -> Data? {
        guard source.size.width > 0, source.size.height > 0 else { return nil }
        var maximumSide: CGFloat = min(2_560, max(source.size.width, source.size.height))
        while maximumSide >= 640 {
            let image = resized(source, maximumSide: maximumSide)
            for quality in stride(from: CGFloat(0.88), through: CGFloat(0.20), by: -0.08) {
                if let data = image.jpegData(compressionQuality: quality), data.count <= maximumBytes {
                    return data
                }
            }
            maximumSide *= 0.75
        }
        return nil
    }

    private static func resized(_ image: UIImage, maximumSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maximumSide else { return image }
        let scale = maximumSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

