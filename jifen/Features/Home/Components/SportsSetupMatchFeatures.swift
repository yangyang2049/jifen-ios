import ScoreCore
import SwiftUI

/// Setup「比赛功能」矩阵（对齐安卓 SportsSetupMatchFeatures.kt）。
///
/// 功能卡片按固定顺序返回：自动换边 → 显示时间 → 语音播报。
/// 严格对齐安卓：仅乒乓球、拍类（羽毛球/网球/匹克球/毽球/壁球/软网/板网球）
/// 与排球类出现在矩阵中；篮球/拳击/射箭/桌上足球/台球/掼蛋/斗地主等
/// 在安卓端无功能区块（else -> emptyList），此处同样返回空数组。
enum SportsSetupMatchFeature: Equatable, CaseIterable {
    case autoChangeSides
    case showMatchTime
    case voiceAnnouncement

    var labelKey: String {
        switch self {
        case .autoChangeSides: return "auto_change_sides"
        case .showMatchTime: return "show_match_time"
        case .voiceAnnouncement: return "voice_announcement"
        }
    }

    var fallbackLabel: String {
        switch self {
        case .autoChangeSides: return "自动换边"
        case .showMatchTime: return "显示时间"
        case .voiceAnnouncement: return "语音播报"
        }
    }

    var iconSystemName: String {
        switch self {
        case .autoChangeSides: return "arrow.left.arrow.right"
        case .showMatchTime: return "timer"
        case .voiceAnnouncement: return "speaker.wave.2"
        }
    }

    /// 返回项目在当前模式下可用的比赛功能列表；无功能项目返回空数组。
    static func features(for gameType: GameType, isSingles: Bool, voiceSupported: Bool = true) -> [SportsSetupMatchFeature] {
        let available = baseFeatures(for: gameType, isSingles: isSingles)
        return voiceSupported ? available : available.filter { $0 != .voiceAnnouncement }
    }

    private static func baseFeatures(for gameType: GameType, isSingles: Bool) -> [SportsSetupMatchFeature] {
        switch gameType {
        case .pingpong:
            return isSingles
                ? [.autoChangeSides, .showMatchTime, .voiceAnnouncement]
                : [.autoChangeSides, .voiceAnnouncement]
        case .badminton, .tennis, .pickleball, .shuttlecock, .squash, .softTennis, .padel:
            return [.autoChangeSides, .voiceAnnouncement]
        case .volleyball, .beachVolleyball, .airVolleyball:
            return [.autoChangeSides, .showMatchTime, .voiceAnnouncement]
        default:
            return []
        }
    }
}

/// 「比赛功能」分组（对齐安卓 SportsSetupMatchFeaturesSection）：
/// 无分组抬头；2/3 张卡片一行各占均分，单功能回退横条开关。
struct SportsSetupMatchFeaturesSection: View {
    @Environment(\.locale) private var locale

    let gameType: GameType
    @Binding var draft: SportsSetupDraft
    @AppStorage("pingpongAnnounceServer") private var announceServer = true
    @State private var showServePopup = false
    @State private var servePopupRevision = 0

    private let featureCardSpacing: CGFloat = 8

    private var features: [SportsSetupMatchFeature] {
        SportsSetupMatchFeature.features(for: gameType, isSingles: draft.isSingles, voiceSupported: SportsVoiceSupport.isSupported)
    }

    var body: some View {
        if !features.isEmpty {
            VStack(spacing: 10) {
                if features.count == 1 {
                    singleSwitch(features[0])
                } else {
                    SportsSetupFeatureCardsLayout(
                        preferredMaxWidth: preferredFeatureCardWidth,
                        spacing: featureCardSpacing
                    ) {
                        ForEach(features, id: \.self) { feature in
                            SportsSetupFeatureCard(
                                feature: feature,
                                isOn: isOn(feature)
                            ) {
                                toggle(feature)
                            }
                            .overlay(alignment: .topTrailing) {
                                if feature == .voiceAnnouncement, gameType == .pingpong, draft.voiceAnnouncement {
                                    Button {
                                        servePopupRevision += 1
                                        showServePopup = true
                                    } label: {
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 10, weight: .semibold))
                                            .frame(width: 24, height: 28)
                                    }
                                    .accessibilityLabel(NSLocalizedString("voice_announce_server", comment: ""))
                                    .accessibilityIdentifier("setup_voice_options")
                                }
                            }
                            .popover(isPresented: Binding(
                                get: { feature == .voiceAnnouncement && showServePopup },
                                set: { showServePopup = $0 }
                            ), arrowEdge: .bottom) {
                                Toggle(NSLocalizedString("voice_announce_server", comment: ""), isOn: $announceServer)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Theme.textPrimary)
                                    .tint(Theme.primary)
                                    .frame(width: 248)
                                    .padding(16)
                                    .presentationCompactAdaptation(.popover)
                                    .accessibilityIdentifier("setup_announce_server_toggle")
                                    .onChange(of: announceServer) { _, _ in servePopupRevision += 1 }
                                    .task(id: servePopupRevision) {
                                        try? await Task.sleep(for: .seconds(5))
                                        if !Task.isCancelled { showServePopup = false }
                                    }
                            }
                        }
                    }
                }
            }
            .onChange(of: draft.voiceAnnouncement) { _, enabled in
                guard gameType == .pingpong else { return }
                showServePopup = enabled
                servePopupRevision += 1
            }
            .onAppear {
                if gameType == .pingpong && draft.voiceAnnouncement {
                    showServePopup = true
                    servePopupRevision += 1
                }
            }
        }
    }

    /// 中文保持 74pt 与安卓一致；其他语言最多放宽到 96pt，但窄屏会按
    /// 实际可用宽度等分收缩，避免三卡布局越出 Setup 对话框。
    private var preferredFeatureCardWidth: CGFloat {
        locale.language.languageCode?.identifier == "zh" ? 74 : 96
    }

    @ViewBuilder
    private func singleSwitch(_ feature: SportsSetupMatchFeature) -> some View {
        // 单功能保持横向开关条样式（对齐安卓 SwitchRow 回退）。
        switch feature {
        case .autoChangeSides:
            settingsToggleRow("auto_change_sides", fallback: "自动换边", value: $draft.autoChangeSides)
        case .showMatchTime:
            settingsToggleRow("show_match_time", fallback: "显示时间", value: $draft.showMatchTime)
                .accessibilityIdentifier("sports_setup_show_match_time")
        case .voiceAnnouncement:
            settingsToggleRow("voice_announcement", fallback: "语音播报", value: Binding(
                get: { draft.voiceAnnouncement },
                set: { value in draft.voiceAnnouncement = value && ScoreVoiceAnnouncer.shared.prepareToEnable() }
            ))
        }
    }

    private func settingsToggleRow(_ key: String, fallback: String, value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            Text(NSLocalizedString(key, value: fallback, comment: ""))
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
        }
        .tint(Theme.primary)
        .accessibilityIdentifier("setup_feature_\(key)")
    }

    private func isOn(_ feature: SportsSetupMatchFeature) -> Bool {
        switch feature {
        case .autoChangeSides: return draft.autoChangeSides
        case .showMatchTime: return draft.showMatchTime
        case .voiceAnnouncement: return draft.voiceAnnouncement
        }
    }

    private func toggle(_ feature: SportsSetupMatchFeature) {
        switch feature {
        case .autoChangeSides: draft.autoChangeSides.toggle()
        case .showMatchTime: draft.showMatchTime.toggle()
        case .voiceAnnouncement:
            if draft.voiceAnnouncement { draft.voiceAnnouncement = false }
            else { draft.voiceAnnouncement = ScoreVoiceAnnouncer.shared.prepareToEnable() }
        }
    }
}

enum SportsSetupFeatureCardLayout {
    static let minimumCardHeight: CGFloat = 74

    static func cardWidth(
        availableWidth: CGFloat,
        itemCount: Int,
        preferredMaxWidth: CGFloat,
        spacing: CGFloat
    ) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        let totalSpacing = spacing * CGFloat(max(0, itemCount - 1))
        let fittingWidth = max(0, availableWidth - totalSpacing) / CGFloat(itemCount)
        return min(max(0, preferredMaxWidth), fittingWidth)
    }
}

/// Measure labels at the actual card width, then give every card the height
/// of the tallest one. Long translations can wrap without a fixed-height clip.
private struct SportsSetupFeatureCardsLayout: Layout {
    let preferredMaxWidth: CGFloat
    let spacing: CGFloat

    private func cardWidth(_ availableWidth: CGFloat, count: Int) -> CGFloat {
        SportsSetupFeatureCardLayout.cardWidth(
            availableWidth: availableWidth, itemCount: count,
            preferredMaxWidth: preferredMaxWidth, spacing: spacing
        )
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let idealWidth = preferredMaxWidth * CGFloat(subviews.count) + spacing * CGFloat(subviews.count - 1)
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? idealWidth
        let itemWidth = cardWidth(width, count: subviews.count)
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let width = cardWidth(bounds.width, count: subviews.count)
        let totalWidth = width * CGFloat(subviews.count) + spacing * CGFloat(subviews.count - 1)
        let startX = bounds.minX + (bounds.width - totalWidth) / 2
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: startX + CGFloat(index) * (width + spacing), y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
        }
    }
}

/// 功能切换卡片（对齐安卓 SportsSetupFeatureCard）：
/// 最低 74pt 高卡片（中文宽 74pt，其他语言最多 96pt），完整显示多行标签；
/// 选中浅绿底 + 描边 1.5 + 强调色内容，未选中中性底，无勾选标记。
struct SportsSetupFeatureCard: View {
    let feature: SportsSetupMatchFeature
    let isOn: Bool
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: feature.iconSystemName)
                    .font(.system(size: feature == .voiceAnnouncement ? 24 : 22))
                    .frame(width: 32, height: 28)
                Text(NSLocalizedString(feature.labelKey, value: feature.fallbackLabel, comment: ""))
                    .font(.system(size: 12, weight: isOn ? .medium : .regular))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
            .foregroundStyle(contentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .frame(minHeight: SportsSetupFeatureCardLayout.minimumCardHeight, maxHeight: .infinity, alignment: .top)
            .background(containerColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isOn ? 1.5 : 1)
            )
            .opacity(isEnabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier("setup_feature_\(feature.labelKey)")
        .accessibilityAddTraits(isOn ? [.isToggle] : [])
        .accessibilityValue(isOn ? "1" : "0")
    }

    private var contentColor: Color {
        isOn ? Theme.primary : Theme.textSecondary
    }

    private var containerColor: Color {
        isOn ? Theme.primary.opacity(0.12) : Theme.dialogControlBackground
    }

    private var borderColor: Color {
        isOn ? Theme.primary : Theme.textSecondary.opacity(0.24)
    }
}
