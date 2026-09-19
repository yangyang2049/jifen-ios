import Foundation

nonisolated enum FeedbackType: String, Codable, CaseIterable, Identifiable, Sendable {
    case feedback = "FEEDBACK"
    case featureRequest = "FEATURE_REQUEST"
    case bugReport = "BUG_REPORT"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .feedback: NSLocalizedString("feedback_type_feedback", value: "一般反馈", comment: "")
        case .featureRequest: NSLocalizedString("feedback_type_feature", value: "功能建议", comment: "")
        case .bugReport: NSLocalizedString("feedback_type_bug", value: "问题反馈", comment: "")
        }
    }
}

nonisolated struct FeedbackItem: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var type: FeedbackType
    var title: String
    var content: String
    var images: [String]
    var authorId: String?
    var authorName: String
    var authorAvatarUrl: String?
    var authorIsVip: Bool
    var status: String
    var likeCount: Int
    var reportCount: Int
    var commentCount: Int
    var createdAt: String
    var updatedAt: String
    var isLiked: Bool
    var isReported: Bool
    var clientPlatform: String?
    var moderationStatus: String? = nil
    var visibility: String? = nil
    var isVisibleToOthers: Bool? = nil
    var visibilityLabel: String? = nil
    var moderationReviewReason: String? = nil
}

nonisolated struct FeedbackComment: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var feedbackId: String
    var content: String
    var authorId: String?
    var authorName: String
    var authorAvatarUrl: String?
    var authorIsVip: Bool
    var createdAt: String
    var moderationStatus: String? = nil
    var visibility: String? = nil
    var isVisibleToOthers: Bool? = nil
    var visibilityLabel: String? = nil
    var moderationReviewReason: String? = nil
}

nonisolated struct FeedbackPage: Codable, Sendable {
    var items: [FeedbackItem]
    var total: Int
    var page: Int
    var pageSize: Int
    var hasMore: Bool
}

nonisolated struct FeedbackImageUpload: Decodable, Sendable { var url: String }
