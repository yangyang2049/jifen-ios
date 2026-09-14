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
    static func features(for gameType: GameType, isSingles: Bool) -> [SportsSetupMatchFeature] {
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
/// 标题 Secondary 居中；2/3 张卡片一行各占均分，单功能回退横条开关。
struct SportsSetupMatchFeaturesSection: View {
    @Environment(\.locale) private var locale

    let gameType: GameType
    @Binding var draft: SportsSetupDraft

    private let featureCardSpacing: CGFloat = 8

    private var features: [SportsSetupMatchFeature] {
        SportsSetupMatchFeature.features(for: gameType, isSingles: draft.isSingles)
    }

    var body: some View {
        if !features.isEmpty {
            VStack(spacing: 10) {
                Text(NSLocalizedString("sports_setup_match_features", value: "比赛功能", comment: ""))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)

                if features.count == 1 {
                    singleSwitch(features[0])
                } else {
                    GeometryReader { proxy in
                        let cardWidth = SportsSetupFeatureCardLayout.cardWidth(
                            availableWidth: proxy.size.width,
                            itemCount: features.count,
                            preferredMaxWidth: preferredFeatureCardWidth,
                            spacing: featureCardSpacing
                        )

                        HStack(spacing: featureCardSpacing) {
                            ForEach(features, id: \.self) { feature in
                                SportsSetupFeatureCard(
                                    feature: feature,
                                    isOn: isOn(feature)
                                ) {
                                    toggle(feature)
                                }
                                .frame(width: cardWidth)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: SportsSetupFeatureCardLayout.cardHeight)
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
            settingsToggleRow("voice_announcement", fallback: "语音播报", value: $draft.voiceAnnouncement)
        }
    }

    private func settingsToggleRow(_ key: String, fallback: String, value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            Text(NSLocalizedString(key, value: fallback, comment: ""))
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
        }
        .tint(Theme.primary)
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
        case .voiceAnnouncement: draft.voiceAnnouncement.toggle()
        }
    }
}

enum SportsSetupFeatureCardLayout {
    static let cardHeight: CGFloat = 74

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

/// 功能切换卡片（对齐安卓 SportsSetupFeatureCard）：
/// 74pt 高卡片（中文宽 74pt，其他语言最多 96pt）、圆角 14、图标 22 + 12pt 两行文字；
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
                    .font(.system(size: 22))
                Text(NSLocalizedString(feature.labelKey, value: feature.fallbackLabel, comment: ""))
                    .font(.system(size: 12, weight: isOn ? .medium : .regular))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    // 英文长词在最窄对话框内仍可能回落到接近 74pt，允许轻微缩字兜底。
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(contentColor)
            .frame(maxWidth: .infinity)
            .frame(height: SportsSetupFeatureCardLayout.cardHeight)
            .background(containerColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isOn ? 1.5 : 1)
            )
            .opacity(isEnabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
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
