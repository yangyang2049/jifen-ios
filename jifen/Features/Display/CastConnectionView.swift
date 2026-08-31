import SwiftUI

/// 投屏连接页：1:1 对齐安卓 DisplayConnectionScreen.kt 的 CastEntryPanel
/// （说明卡可折叠在上 + 状态卡居中在下；iOS 无"云端同步"Tab，保持单页）。
struct CastConnectionView: View {
    @ObservedObject private var externalDisplay = ExternalDisplayCoordinator.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var usageExpanded = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                usageCard
                statusCard
            }
            .padding(.horizontal, Theme.pageHorizontalInset)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: Theme.secondaryPageContentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundColor.ignoresSafeArea())
        .navigationTitle(NSLocalizedString("cast_title", value: "投屏", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        // push 进入时系统自带返回按钮，避免重复。
        .analyticsScreen(.castPage, screenClass: "cast")
        .onAppear { externalDisplay.refreshStatus() }
        .accessibilityIdentifier("cast_connection_page")
    }

    // MARK: - 说明卡（安卓 CastUsageCard）

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    usageExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(NSLocalizedString("cast_intro_title", value: "投屏怎么用", comment: ""))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 0)
                    Text(NSLocalizedString(
                        usageExpanded ? "cast_intro_collapse" : "cast_intro_expand",
                        value: usageExpanded ? "收起" : "展开说明",
                        comment: ""
                    ))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.homeNeutralCardTextTertiary)
                    Image(systemName: usageExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.homeNeutralCardTextTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(NSLocalizedString(
                "cast_intro_overview",
                value: "建议优先使用系统“屏幕镜像”。连接成功并被检测到后，计分板会自动显示到大屏。",
                comment: ""
            ))
            .font(.system(size: 13))
            .lineSpacing(4)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            if usageExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Theme.primary)
                            .frame(width: 3, height: 18)
                        Text(NSLocalizedString("cast_intro_heading", value: "无线投屏步骤", comment: ""))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        usageStep(NSLocalizedString("cast_intro_step_1", value: "从控制中心打开“屏幕镜像”", comment: ""))
                        usageStep(NSLocalizedString("cast_intro_step_2", value: "检测到大屏后，计分板会自动显示", comment: ""))
                        usageStep(NSLocalizedString("cast_intro_step_3", value: "手机继续计分，大屏实时显示比分", comment: ""))
                    }

                    Text(NSLocalizedString(
                        "cast_intro_note",
                        value: "请先在系统里完成连接；App 一次只能使用一块已连接的屏幕，不能直接搜索电视或投影仪。断开系统投屏后，本次投屏也会结束。",
                        comment: ""
                    ))
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.homeNeutralCardTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                    Text(NSLocalizedString(
                        "display_cast_scope_hint",
                        value: "有线连接需手机接口支持视频输出，且显示器被系统识别为独立扩展屏；整屏镜像仍可显示手机计分板，但不会使用 App 专为大屏设计的独立界面。具体支持情况取决于手机、系统、显示设备和转接设备。",
                        comment: ""
                    ))
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.homeNeutralCardTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(20)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func usageStep(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.primary)
            Text(text)
                .font(.system(size: 13))
                .lineSpacing(4)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 状态卡（安卓 CastStatusCard）

    private var connected: Bool { externalDisplay.status != .disconnected }

    private var statusCard: some View {
        VStack(spacing: 10) {
            illustration

            Text(headline)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            if let resolutionText {
                Text(resolutionText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            } else if !connected {
                Text(NSLocalizedString(
                    "cast_display_waiting_hint",
                    value: "请从控制中心开启“屏幕镜像”",
                    comment: ""
                ))
                .font(.system(size: 12))
                .lineSpacing(3)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 7) {
                Circle()
                    .fill(Theme.primary)
                    .frame(width: 7, height: 7)
                Text(statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.primary)
            }

            if connected {
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)
                    .padding(.top, 8)

                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Theme.primary.opacity(colorScheme == .dark ? 0.16 : 0.10))
                            .frame(width: 34, height: 34)
                        Image(systemName: "wifi")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.primary)
                    }
                    Text(NSLocalizedString(
                        "cast_display_phone_control_hint",
                        value: "手机负责操作，大屏专注显示。",
                        comment: ""
                    ))
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("cast_status_\(externalDisplay.status.rawValue)")
    }

    /// 安卓 CastStatusIllustration：未连接为三层同心圆环 + Cast 图标；
    /// 已连接为浅色圆角底 + 图标。
    @ViewBuilder
    private var illustration: some View {
        if connected {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Theme.primary.opacity(colorScheme == .dark ? 0.16 : 0.10))
                    .frame(width: 56, height: 56)
                Image(systemName: "airplayvideo")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.primary)
            }
            .frame(width: 72, height: 72)
        } else {
            ZStack {
                ring(radius: 112, opacity: 0.22)
                ring(radius: 82, opacity: 0.32)
                ring(radius: 54, opacity: 0.45)
                Image(systemName: "airplayvideo")
                    .font(.system(size: 27))
                    .foregroundStyle(Theme.primary)
            }
            .frame(width: 112, height: 112)
        }
    }

    private func ring(radius: CGFloat, opacity: Double) -> some View {
        Circle()
            .strokeBorder(Theme.primary.opacity(opacity), lineWidth: 2)
            .frame(width: radius, height: radius)
    }

    // MARK: - 状态映射

    private var headline: String {
        switch externalDisplay.status {
        case .disconnected:
            NSLocalizedString("cast_display_waiting_title", value: "尚未检测到投屏设备", comment: "")
        case .mirroring:
            NSLocalizedString("cast_mirroring", value: "已连接 · 镜像模式", comment: "")
        case .dedicated:
            NSLocalizedString("cast_active", value: "投屏中", comment: "")
        }
    }

    private var statusText: String {
        switch externalDisplay.status {
        case .disconnected:
            NSLocalizedString("display_cast_status_waiting", value: "正在等待连接", comment: "")
        case .mirroring:
            NSLocalizedString("cast_mirroring", value: "已连接 · 镜像模式", comment: "")
        case .dedicated:
            NSLocalizedString("display_cast_status_active", value: "已连接", comment: "")
        }
    }

    private var resolutionText: String? {
        guard connected,
              let screen = UIScreen.screens.dropFirst().first else { return nil }
        return String(
            format: NSLocalizedString("display_cast_resolution", value: "分辨率：%d × %d", comment: ""),
            Int(screen.nativeBounds.width),
            Int(screen.nativeBounds.height)
        )
    }
}
