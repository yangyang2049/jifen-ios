import PhotosUI
import SwiftUI
import UIKit

// MARK: - 反馈共享样式（对齐安卓 FeedbackUi.kt）

/// 与鸿蒙/安卓一致：印章与点赞激活色。
private let feedbackStampColor = Color(hex: "22C55E")
private let feedbackLikeActiveColor = Color(hex: "EF4444")

nonisolated enum FeedbackStatus: String, Sendable {
    case pending = "PENDING"
    case implemented = "IMPLEMENTED"
    case fixed = "FIXED"
    case released = "RELEASED"
    case rejected = "REJECTED"
}

extension FeedbackItem {
    var statusValue: FeedbackStatus { FeedbackStatus(rawValue: status) ?? .pending }
}

private func feedbackTypeColor(_ type: FeedbackType) -> Color {
    switch type {
    case .feedback: return Color(hex: "22C55E")
    case .featureRequest: return Color(hex: "3B82F6")
    case .bugReport: return Color(hex: "EF4444")
    }
}

/// 已实现/已修复/已上线 → 右上角旋转印章；其余状态不走印章。
private func showsFeedbackStamp(_ status: FeedbackStatus) -> Bool {
    status == .implemented || status == .fixed || status == .released
}

private func feedbackStampLabel(_ status: FeedbackStatus) -> String {
    status == .released
        ? NSLocalizedString("feedback_status_released", value: "已上线", comment: "")
        : NSLocalizedString("feedback_status_fixed", value: "已修复", comment: "")
}

private func feedbackStatusLabel(_ status: FeedbackStatus) -> String {
    switch status {
    case .pending: NSLocalizedString("feedback_status_pending", value: "待处理", comment: "")
    case .implemented: NSLocalizedString("feedback_status_implemented", value: "已实现", comment: "")
    case .fixed: NSLocalizedString("feedback_status_fixed", value: "已修复", comment: "")
    case .released: NSLocalizedString("feedback_status_released", value: "已上线", comment: "")
    case .rejected: NSLocalizedString("feedback_status_rejected", value: "已拒绝", comment: "")
    }
}

private func feedbackStatusColor(_ status: FeedbackStatus) -> Color {
    switch status {
    case .pending: return Color(hex: "F59E0B")
    case .rejected: return Color(hex: "6B7280")
    default: return feedbackStampColor
    }
}

private func feedbackPlatformLabel(_ platform: String) -> String {
    switch platform {
    case "android": NSLocalizedString("feedback_platform_android", value: "安卓", comment: "")
    case "harmony": NSLocalizedString("feedback_platform_harmony", value: "鸿蒙", comment: "")
    case "ios": NSLocalizedString("feedback_platform_ios", value: "iOS", comment: "")
    case "wechat_miniprogram": NSLocalizedString("feedback_platform_wechat_miniprogram", value: "小程序", comment: "")
    default: platform
    }
}

/// 相对时间随系统语言切换（对齐安卓 FeedbackTimeFormatter）。
nonisolated enum FeedbackTimeFormatter {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plainFormatter = ISO8601DateFormatter()

    static func format(_ iso: String) -> String {
        let trimmed = iso.trimmingCharacters(in: .whitespaces)
        let date = fractionalFormatter.date(from: trimmed) ?? plainFormatter.date(from: trimmed)
        guard let date else { return "" }
        let diff = Date().timeIntervalSince(date)
        let minutes = Int(diff / 60)
        let hours = Int(diff / 3600)
        let days = Int(diff / 86400)
        if minutes < 1 {
            return NSLocalizedString("feedback_time_just_now", value: "刚刚", comment: "")
        }
        if minutes < 60 {
            return String(format: NSLocalizedString("feedback_time_minutes_ago", value: "%d分钟前", comment: ""), minutes)
        }
        if hours < 24 {
            return String(format: NSLocalizedString("feedback_time_hours_ago", value: "%d小时前", comment: ""), hours)
        }
        if days < 30 {
            return String(format: NSLocalizedString("feedback_time_days_ago", value: "%d天前", comment: ""), days)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - 共享组件（对齐安卓 FeedbackUi.kt）

/// 作者头像：圆形占位 + 右下角 VIP 金标（对齐安卓 FeedbackAuthorAvatar / FeedbackAuthorVipBadge）。
private struct FeedbackAuthorAvatarView: View {
    let avatarPath: String?
    let isVip: Bool
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let url = avatarPath.flatMap({ FeedbackAPI.shared.absoluteImageURL($0) }) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        placeholderGlyph
                    }
                } else {
                    placeholderGlyph
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())

            if isVip {
                vipBadge
            }
        }
        .frame(width: size, height: size)
    }

    private var placeholderGlyph: some View {
        ZStack {
            Circle().fill(Color(hex: "E5E7EB"))
            Image(systemName: "person.crop.circle")
                .font(.system(size: size <= 20 ? size * 0.7 : size * 0.52))
                .foregroundColor(Theme.textSecondary)
                .opacity(size <= 20 ? 0.75 : 1)
        }
    }

    private var vipBadge: some View {
        let badgeSize: CGFloat = size >= 44 ? 15 : size >= 36 ? 13 : 8
        let glyphSize: CGFloat = size >= 36 ? 9 : 6
        return Text("v")
            .font(.system(size: glyphSize, weight: .medium).italic())
            .foregroundColor(Color(hex: "422006"))
            .frame(width: badgeSize, height: badgeSize)
            .background(Circle().fill(Color(hex: "FBBF24")))
            .offset(x: 0.4, y: -0.2)
    }
}

/// 类型角标：11pt 白字、类型色底、圆角 4（对齐安卓 FeedbackTypeChip）。
private struct FeedbackTypeChipView: View {
    let type: FeedbackType

    var body: some View {
        Text(type.title)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(feedbackTypeColor(type)))
    }
}

/// 平台角标：11pt 次要字色、12% 灰底、圆角 4（对齐安卓 FeedbackPlatformChip）。
private struct FeedbackPlatformChipView: View {
    let platform: String

    var body: some View {
        Text(feedbackPlatformLabel(platform))
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.textSecondary.opacity(0.12)))
    }
}

/// 状态印章：整体旋转 12°、2pt 实线边框、圆角 2（对齐安卓 FeedbackStatusStamp）。
private struct FeedbackStatusStampView: View {
    let status: FeedbackStatus

    var body: some View {
        Text(feedbackStampLabel(status))
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(feedbackStampColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(feedbackStampColor, lineWidth: 2))
            .rotationEffect(.degrees(12))
    }
}

/// 加载失败状态（对齐安卓：😕 72 + 标题 22 Bold + 错误信息 14 + 重新加载按钮）。
private struct FeedbackErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("\u{1F615}")
                .font(.system(size: 72))
            Text(NSLocalizedString("feedback_load_failed", value: "加载失败", comment: ""))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .padding(.top, 20)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 8)
            Button(action: retry) {
                Text(NSLocalizedString("feedback_reload", value: "重新加载", comment: ""))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .background(Capsule().fill(Theme.accentColor))
            }
            .padding(.top, 20)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 空状态（对齐安卓：52 图标 + “暂无反馈”14 + 提示 13）。
private struct FeedbackEmptyStateView: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "tray")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(Theme.textSecondary)
                .frame(height: 52)
            Text(NSLocalizedString("feedback_no_feedback", value: "暂无反馈", comment: ""))
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
                .padding(.top, 14)
            Text(NSLocalizedString("feedback_empty_hint", value: "成为第一个发布反馈的用户吧！", comment: ""))
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 反馈列表（对齐安卓 FeedbackListScreen）

struct FeedbackListView: View {
    @Environment(SessionStore.self) private var session
    @State private var items: [FeedbackItem] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreate = false
    @State private var filterType: FeedbackType?
    @State private var hasAppearedOnce = false

    var body: some View {
        Group {
            if items.isEmpty && isLoading && errorMessage == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty, let errorMessage {
                FeedbackErrorStateView(message: errorMessage) {
                    Task { await load(reset: true) }
                }
            } else if items.isEmpty {
                FeedbackEmptyStateView()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        filterRow
                        LazyVStack(spacing: 12) {
                            ForEach(items) { item in
                                NavigationLink {
                                    FeedbackDetailView(feedbackId: item.id) {
                                        Task { await load(reset: true) }
                                    }
                                } label: {
                                    FeedbackListCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                            if hasMore {
                                loadMoreRow
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
                .refreshable { await load(reset: true) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundColor.ignoresSafeArea())
        .navigationTitle(NSLocalizedString("feedback_title", value: "反馈", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!session.isAuthenticated)
                .accessibilityLabel(NSLocalizedString("feedback_new", value: "新建反馈", comment: ""))
            }
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack { CreateFeedbackView { Task { await load(reset: true) } } }
        }
        .task { if items.isEmpty { await load(reset: true) } }
        .onAppear {
            // 从详情/发布返回时刷新（对齐安卓 ON_RESUME 刷新）。
            if hasAppearedOnce { Task { await load(reset: true) } }
            hasAppearedOnce = true
        }
    }

    /// 筛选行：右侧下拉筛选（全部/一般反馈/功能建议/问题反馈），对齐安卓 FeedbackFilterRow。
    private var filterRow: some View {
        HStack {
            Spacer()
            Menu {
                Picker(
                    NSLocalizedString("feedback_filter", value: "筛选", comment: ""),
                    selection: $filterType
                ) {
                    Text(NSLocalizedString("all", value: "全部", comment: "")).tag(FeedbackType?.none)
                    ForEach(FeedbackType.allCases) { type in
                        Text(type.title).tag(FeedbackType?.some(type))
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(filterType?.title ?? NSLocalizedString("all", value: "全部", comment: ""))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.leading, 8)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .padding(.top, 12)
        .onChange(of: filterType) { _, _ in
            Task { await load(reset: true) }
        }
    }

    /// “加载更多”行：60 高，加载中显示进度圈（对齐安卓）。
    private var loadMoreRow: some View {
        Button {
            guard !isLoading else { return }
            Task { await load(reset: false) }
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(width: 32, height: 32)
                } else {
                    Text(NSLocalizedString("feedback_load_more", value: "加载更多", comment: ""))
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private func load(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let next = reset ? 1 : page + 1
            let result = try await FeedbackAPI.shared.list(page: next, type: filterType)
            items = reset ? result.items : items + result.items
            page = result.page
            hasMore = result.hasMore
            errorMessage = nil
        } catch {
            if items.isEmpty { errorMessage = error.localizedDescription }
        }
    }
}

/// 列表卡片（对齐安卓 FeedbackListCard）：标题 2 行 → 正文 3 行 → 头像/昵称 + 点赞，右上角状态印章。
private struct FeedbackListCard: View {
    let item: FeedbackItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(2)
            Text(item.content)
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
                .lineSpacing(6)
                .lineLimit(3)
                .padding(.top, 12)
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    FeedbackAuthorAvatarView(avatarPath: item.authorAvatarUrl, isVip: item.authorIsVip, size: 18)
                    Text(item.authorName)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: item.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 15))
                        .foregroundColor(item.isLiked ? feedbackLikeActiveColor : Theme.textSecondary)
                    Text(String(item.likeCount))
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .padding(.top, 12)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.appCardBackground))
        .overlay(alignment: .topTrailing) {
            if showsFeedbackStamp(item.statusValue) {
                FeedbackStatusStampView(status: item.statusValue)
                    .padding(.top, 12)
                    .padding(.trailing, 12)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - 反馈详情（对齐安卓 FeedbackDetailScreen）

struct FeedbackDetailView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let feedbackId: String
    var onDeleted: () -> Void = {}

    @State private var item: FeedbackItem?
    @State private var comments: [FeedbackComment] = []
    @State private var commentText = ""
    @State private var errorMessage: String?
    @State private var isActing = false
    @State private var showDeleteConfirm = false
    @State private var showReport = false
    @State private var previewImages: [String] = []
    @State private var previewStartPage = 0

    private var isAuthor: Bool {
        guard let authorId = item?.authorId, !authorId.isEmpty else { return false }
        return authorId == session.user?.id
    }

    /// 溢出菜单是否显示“举报”：非作者且已登录（对齐安卓 FeedbackDetailOverflowMenu；
    /// 与安卓唯一差异：未登录直接隐藏入口，避免点击后才提示登录）。
    private var canShowReportAction: Bool {
        !isAuthor && session.isAuthenticated && item?.authorId.isNullableNonBlank == true
    }

    var body: some View {
        Group {
            if item == nil && isActing == false {
                if let errorMessage {
                    FeedbackErrorStateView(message: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if let item {
                detailContent(item)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.backgroundColor.ignoresSafeArea())
        .navigationTitle(NSLocalizedString("feedback_detail", value: "反馈详情", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if item != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    overflowMenu
                }
            }
        }
        .task { await load() }
        .overlay {
            if showDeleteConfirm {
                CustomConfirmDialog(
                    title: NSLocalizedString("feedback_delete_dialog_title", value: "删除反馈", comment: ""),
                    message: NSLocalizedString(
                        "feedback_delete_confirm_message",
                        value: "确定要删除这条反馈吗？删除后不可恢复。",
                        comment: ""
                    ),
                    confirmText: NSLocalizedString("feedback_delete_button", value: "删除", comment: ""),
                    cancelText: NSLocalizedString("cancel", value: "取消", comment: ""),
                    onConfirm: { Task { await deleteItem() } },
                    onDismiss: { showDeleteConfirm = false }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if showReport {
                FeedbackReportDialog(
                    feedbackId: feedbackId,
                    onSubmitted: { Task { await load() } },
                    onDismiss: { showReport = false }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showDeleteConfirm)
        .animation(.easeInOut(duration: 0.2), value: showReport)
        .fullScreenCover(isPresented: Binding(
            get: { !previewImages.isEmpty },
            set: { if !$0 { previewImages = [] } }
        )) {
            FeedbackImagePreviewPage(
                images: previewImages,
                startPage: previewStartPage,
                onClose: { previewImages = [] }
            )
        }
    }

    /// 右上角溢出菜单：作者仅删除；非作者举报 / 已举报态（对齐安卓 FeedbackDetailOverflowMenu）。
    @ViewBuilder
    private var overflowMenu: some View {
        Menu {
            if isAuthor {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label(
                        NSLocalizedString("feedback_delete_button", value: "删除", comment: ""),
                        systemImage: "trash"
                    )
                }
            } else if canShowReportAction {
                if item?.isReported == true {
                    Text(NSLocalizedString("feedback_reported_badge", value: "已举报", comment: ""))
                } else {
                    Button {
                        showReport = true
                    } label: {
                        Label(
                            NSLocalizedString("feedback_report_btn", value: "举报", comment: ""),
                            systemImage: "exclamationmark.shield"
                        )
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(NSLocalizedString("more", value: "更多", comment: ""))
    }

    private func detailContent(_ item: FeedbackItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                mainCard(item)
                commentsSection(comments)
            }
            .frame(maxWidth: Theme.focusedContentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .hideKeyboardOnTap()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            commentInputBar
        }
    }

    /// 正文卡（对齐安卓详情首屏）：头像行 → 标题 → 正文 → 图片 → 状态 → 点赞/评论操作行。
    private func mainCard(_ item: FeedbackItem) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    FeedbackAuthorAvatarView(avatarPath: item.authorAvatarUrl, isVip: item.authorIsVip, size: 44)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.authorName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            Text(FeedbackTimeFormatter.format(item.createdAt))
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textSecondary)
                            FeedbackTypeChipView(type: item.type)
                            if let platform = item.clientPlatform, !platform.isEmpty {
                                FeedbackPlatformChipView(platform: platform)
                            }
                        }
                        .padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                }

                Text(item.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.top, 16)

                Text(item.content)
                    .font(.system(size: 16))
                    .foregroundColor(Theme.textPrimary)
                    .lineSpacing(10)
                    .textSelection(.enabled)
                    .padding(.top, 12)

                feedbackImages(item.images)

                // 非印章状态且非待处理（即已拒绝）→ 显示状态胶囊（对齐安卓）。
                if !showsFeedbackStamp(item.statusValue) && item.statusValue != .pending {
                    Text(feedbackStatusLabel(item.statusValue))
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(feedbackStatusColor(item.statusValue)))
                        .padding(.top, 12)
                }

                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)
                    .padding(.top, 20)

                HStack(spacing: 32) {
                    Button {
                        Task { await toggleLike() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 17))
                                .foregroundColor(item.isLiked ? feedbackLikeActiveColor : Theme.textSecondary)
                            Text(String(item.likeCount))
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isActing)

                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 17))
                            .foregroundColor(Theme.textSecondary)
                        Text(String(max(item.commentCount, comments.count)))
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .padding(.top, 16)
            }
            .padding(16)

            if showsFeedbackStamp(item.statusValue) {
                FeedbackStatusStampView(status: item.statusValue)
                    .padding(.top, 16)
                    .padding(.trailing, 16)
            }
        }
        .padding(.top, 12)
    }

    /// 图片九宫格：120 方块、圆角 8，点击进入全屏翻页预览（对齐安卓 FlowRow + 预览弹窗）。
    @ViewBuilder
    private func feedbackImages(_ images: [String]) -> some View {
        if !images.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, path in
                    Button {
                        previewStartPage = index
                        previewImages = images
                    } label: {
                        AsyncImage(url: FeedbackAPI.shared.absoluteImageURL(path)) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Theme.controlBackground
                        }
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 12)
        }
    }

    /// 评论区（对齐安卓）：标题 + 每条评论以分隔线起始。
    @ViewBuilder
    private func commentsSection(_ comments: [FeedbackComment]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(
                format: NSLocalizedString("feedback_comment_count_label", value: "评论（%d）", comment: ""),
                comments.count
            ))
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(Theme.textPrimary)
            .padding(.bottom, 12)

            ForEach(comments) { comment in
                FeedbackCommentRow(comment: comment)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    /// 底部评论输入条：胶囊输入框 + 发送按钮（有内容变绿，对齐安卓）。
    private var commentInputBar: some View {
        HStack(spacing: 12) {
            TextField(
                NSLocalizedString("feedback_comment_placeholder", value: "写一条评论…", comment: ""),
                text: $commentText
            )
            .font(.system(size: 15))
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Capsule().fill(Theme.controlBackground))
            .onChange(of: commentText) { _, value in
                if value.count > 2_000 { commentText = String(value.prefix(2_000)) }
            }

            Button {
                Task { await sendComment() }
            } label: {
                Text(NSLocalizedString("feedback_comment_send", value: "发送", comment: ""))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.textSecondary : .white)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Capsule().fill(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.controlBackground : Theme.accentColor))
            }
            .buttonStyle(.plain)
            .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isActing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Theme.backgroundColor)
    }

    private func load() async {
        do {
            async let detail = FeedbackAPI.shared.detail(id: feedbackId)
            async let loadedComments = FeedbackAPI.shared.comments(feedbackId: feedbackId)
            item = try await detail
            comments = try await loadedComments
            errorMessage = nil
        } catch {
            if item == nil { errorMessage = error.localizedDescription }
        }
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

    private func deleteItem() async {
        guard !isActing else { return }
        isActing = true
        defer { isActing = false }
        do {
            try await FeedbackAPI.shared.delete(feedbackId: feedbackId)
            showDeleteConfirm = false
            onDeleted()
            dismiss()
        } catch {
            showDeleteConfirm = false
            errorMessage = error.localizedDescription
        }
    }
}

extension Optional where Wrapped == String {
    /// 安卓 canShowReportAction 判定：authorId 非空才可举报。
    var isNullableNonBlank: Bool {
        switch self {
        case .none: return false
        case .some(let value): return !value.isEmpty
        }
    }
}

/// 评论行（对齐安卓 CommentItem）：分隔线 + 头像 36 + 昵称/时间 + 正文。
private struct FeedbackCommentRow: View {
    let comment: FeedbackComment

    var body: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 1)
        HStack(alignment: .top, spacing: 12) {
            FeedbackAuthorAvatarView(avatarPath: comment.authorAvatarUrl, isVip: comment.authorIsVip, size: 36)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(comment.authorName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    Text(FeedbackTimeFormatter.format(comment.createdAt))
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                Text(comment.content)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.textPrimary)
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }
}

/// 图片全屏预览：黑色背景 + 翻页浏览 + 右上角关闭（对齐安卓预览弹窗）。
private struct FeedbackImagePreviewPage: View {
    let images: [String]
    let startPage: Int
    let onClose: () -> Void
    @State private var page = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $page) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, path in
                    AsyncImage(url: FeedbackAPI.shared.absoluteImageURL(path)) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView().tint(.white)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
            .padding(.trailing, 12)
            .padding(.top, 12)
            .accessibilityLabel(NSLocalizedString("close", value: "关闭", comment: ""))
        }
        .onAppear { page = startPage }
    }
}

/// 举报弹窗（对齐安卓举报 Dialog）：原因单选 + 补充说明 + 取消/提交。
private struct FeedbackReportDialog: View {
    let feedbackId: String
    let onSubmitted: () -> Void
    let onDismiss: () -> Void

    private struct ReportReason: Identifiable, Hashable {
        let apiValue: String
        let label: String
        var id: String { apiValue }
    }

    @State private var reason: ReportReason?
    @State private var detail = ""
    @State private var isSubmitting = false
    @State private var errorText: String?

    private let reasons: [ReportReason] = [
        ReportReason(apiValue: "IMAGE_VIOLATION", label: NSLocalizedString("feedback_report_image", value: "图片违规", comment: "")),
        ReportReason(apiValue: "SPAM", label: NSLocalizedString("feedback_report_spam", value: "垃圾广告", comment: "")),
        ReportReason(apiValue: "HARASSMENT", label: NSLocalizedString("feedback_report_harassment", value: "骚扰或辱骂", comment: "")),
        ReportReason(apiValue: "OTHER", label: NSLocalizedString("feedback_report_other", value: "其他问题", comment: "")),
    ]

    var body: some View {
        ZStack {
            Theme.scoreboardDialogScrim
                .ignoresSafeArea()
                .onTapGesture { if !isSubmitting { onDismiss() } }

            VStack(spacing: 0) {
                Text(NSLocalizedString("feedback_report_btn", value: "举报", comment: ""))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(NSLocalizedString("feedback_report_reason_hint", value: "请选择举报原因", comment: ""))
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)

                VStack(spacing: 12) {
                    ForEach(reasons) { item in
                        FeedbackReportReasonRow(label: item.label, isSelected: reason == item) {
                            reason = item
                        }
                    }
                }
                .padding(.top, 16)

                TextField(
                    NSLocalizedString("feedback_report_detail_placeholder", value: "补充说明（选填）", comment: ""),
                    text: $detail,
                    axis: .vertical
                )
                .font(.system(size: 15))
                .lineLimit(4...6)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.controlBackground))
                .padding(.top, 16)
                .onChange(of: detail) { _, value in
                    if value.count > 500 { detail = String(value.prefix(500)) }
                }

                HStack(spacing: 12) {
                    Button {
                        onDismiss()
                    } label: {
                        Text(NSLocalizedString("cancel", value: "取消", comment: ""))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Capsule().fill(Theme.controlBackground))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)

                    Button {
                        Task { await submit() }
                    } label: {
                        Text(isSubmitting
                            ? NSLocalizedString("feedback_report_submitting", value: "提交中…", comment: "")
                            : NSLocalizedString("feedback_report_submit", value: "提交", comment: ""))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Capsule().fill(Theme.accentColor.opacity(isSubmitting ? 0.5 : 1)))
                    }
                    .buttonStyle(.plain)
                    .disabled(reason == nil || isSubmitting)
                }
                .padding(.top, 16)

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                }
            }
            .hideKeyboardOnTap()
            .padding(20)
            .frame(maxWidth: Theme.usesPadLayout ? 400 : 280)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.cardBackground))
            .padding(.horizontal, 24)
        }
    }

    private func submit() async {
        guard let reason, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            try await FeedbackAPI.shared.report(
                feedbackId: feedbackId,
                reason: reason.apiValue,
                detail: trimmed.isEmpty ? nil : trimmed
            )
            onDismiss()
            onSubmitted()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// 举报原因行（对齐安卓 FeedbackSelectionRow）：8 圆角、控制底色、行尾绿勾。
private struct FeedbackReportReasonRow: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(label)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(feedbackStampColor)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.controlBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 发布反馈（对齐安卓 CreateFeedbackScreen）

private struct CreateFeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    let onCreated: () -> Void

    private static let maxImages = 5

    @State private var type: FeedbackType = .feedback
    @State private var title = ""
    @State private var content = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var validationMessage: String?

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    typeButtonRow
                    inputFields
                    imageSection
                    guideSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: Theme.focusedContentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboardInteractively()

            if isSubmitting {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.4)
                    Text(NSLocalizedString("feedback_publishing", value: "发布中…", comment: ""))
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.5).ignoresSafeArea())
            }
        }
        .hideKeyboardOnTap()
        .navigationTitle(NSLocalizedString("feedback_create", value: "发布反馈", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(NSLocalizedString("cancel", value: "取消", comment: "")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(NSLocalizedString("publish", value: "发布", comment: "")) {
                    Task { await submit() }
                }
                .disabled(isSubmitting)
            }
        }
        .onChange(of: selectedPhotos) { _, items in
            Task { await loadImages(items) }
        }
        .alert(
            validationMessage ?? "",
            isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )
        ) {}
    }

    /// 类型选择行：💬 一般反馈 / 🚀 功能建议 / 🐛 问题反馈，选中用类型色底 + 白字（对齐安卓 CreateTypeButton）。
    private var typeButtonRow: some View {
        HStack(spacing: 8) {
            createTypeButton(.feedback, emoji: "\u{1F4AC}")
            createTypeButton(.featureRequest, emoji: "\u{1F680}")
            createTypeButton(.bugReport, emoji: "\u{1F41B}")
        }
    }

    private func createTypeButton(_ feedbackType: FeedbackType, emoji: String) -> some View {
        let isSelected = type == feedbackType
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { type = feedbackType }
        } label: {
            VStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 24))
                Text(feedbackType.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : Theme.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(RoundedRectangle(cornerRadius: 12).fill(isSelected ? feedbackTypeColor(feedbackType) : Theme.controlBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 标题 + 正文输入（对齐安卓 FeedbackInputField：8 圆角、控制底色）。
    private var inputFields: some View {
        VStack(spacing: 16) {
            TextField(
                NSLocalizedString("feedback_form_title_placeholder", value: "请输入反馈标题", comment: ""),
                text: $title
            )
            .font(.system(size: 15))
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.controlBackground))
            .onChange(of: title) { _, value in
                if value.count > 200 { title = String(value.prefix(200)) }
            }

            TextField(
                NSLocalizedString("feedback_form_content_placeholder", value: "请详细描述您的反馈内容…", comment: ""),
                text: $content,
                axis: .vertical
            )
            .font(.system(size: 15))
            .lineSpacing(6)
            .lineLimit(8...14)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.controlBackground))
            .onChange(of: content) { _, value in
                if value.count > 10_000 { content = String(value.prefix(10_000)) }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 24)
    }

    /// 添加图片区：72 方块网格 + 右上角删除（对齐安卓 FlowRow 布局）。
    private var imageSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(NSLocalizedString("feedback_form_add_images", value: "添加图片", comment: ""))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Theme.textPrimary)
            FlowLayout(spacing: 8) {
                if images.count < Self.maxImages {
                    PhotosPicker(selection: $selectedPhotos, maxSelectionCount: Self.maxImages, matching: .images) {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(Theme.textPrimary.opacity(0.6))
                            .frame(width: 72, height: 72)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.controlBackground))
                            .contentShape(Rectangle())
                    }
                }
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                images.remove(at: index)
                                selectedPhotos.remove(at: min(index, selectedPhotos.count - 1))
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white.opacity(0.9))
                                    .shadow(color: .black.opacity(0.4), radius: 2)
                            }
                            .padding(2)
                        }
                }
            }
            .padding(.top, 8)
        }
        .padding(.top, 24)
    }

    /// 发布须知（对齐安卓：📝 标题 + 要点文案）。
    private var guideSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(Text("\u{1F4DD}")) \(NSLocalizedString("feedback_form_guide_title", value: "发布须知", comment: ""))")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textPrimary)
            Text(NSLocalizedString(
                "feedback_form_guide_text",
                value: "• 请确保反馈内容真实、有建设性\n• 功能建议请详细描述使用场景\n• 问题反馈请包含复现步骤\n• 我们会认真对待每一条反馈",
                comment: ""
            ))
            .font(.system(size: 13))
            .foregroundColor(Theme.textSecondary)
            .lineSpacing(7)
            .padding(.top, 8)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadImages(_ items: [PhotosPickerItem]) async {
        var loaded: [UIImage] = []
        var failed = 0
        for item in items.prefix(Self.maxImages - images.count) {
            guard let source = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: source)
            else { failed += 1; continue }
            loaded.append(image)
        }
        images.append(contentsOf: loaded)
        if failed > 0 {
            errorMessage = String(
                format: NSLocalizedString("feedback_image_prepare_failed", value: "%d 张图片无法处理，请换一张后重试", comment: ""),
                failed
            )
        }
    }

    private func submit() async {
        guard !isSubmitting else { return }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTitle.count >= 5 else {
            validationMessage = NSLocalizedString("feedback_title_min_toast", value: "标题至少 5 个字", comment: "")
            return
        }
        guard normalizedContent.count >= 10 else {
            validationMessage = NSLocalizedString("feedback_content_min_toast", value: "详细描述至少 10 个字", comment: "")
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            var urls: [String] = []
            for image in images {
                // 压缩只做一次：走 FeedbackImageCompressor（限制尺寸 + ≤2MB）。
                guard let data = FeedbackImageCompressor.prepareJPEG(image) else { continue }
                urls.append(try await FeedbackAPI.shared.uploadJPEG(data))
            }
            _ = try await FeedbackAPI.shared.create(
                type: type,
                title: normalizedTitle,
                content: normalizedContent,
                imageURLs: urls
            )
            onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 流式布局（对齐安卓 FlowRow：水平换行）

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

extension View {
    /// 滚动时交互式收起键盘。
    @ViewBuilder
    func scrollDismissesKeyboardInteractively() -> some View {
        if #available(iOS 17.0, *) {
            scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
    }

    /// 点击空白处收起键盘（resignFirstResponder；子按钮点击不受影响）。
    func hideKeyboardOnTap() -> some View {
        onTapGesture {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
        }
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
