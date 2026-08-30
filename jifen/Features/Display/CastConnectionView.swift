import SwiftUI

struct CastConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var externalDisplay = ExternalDisplayCoordinator.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                statusCard
                guideCard
                compatibilityCard
            }
            .padding(.horizontal, Theme.pageHorizontalInset)
            .padding(.top, Theme.sectionSpacing)
            .padding(.bottom, 40)
        }
        .background(Theme.backgroundColor.ignoresSafeArea())
        .navigationTitle(NSLocalizedString("cast_title", value: "投屏", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel(NSLocalizedString("back", value: "返回", comment: ""))
            }
        }
        .analyticsScreen(.castPage, screenClass: "cast")
        .onAppear { externalDisplay.refreshStatus() }
        .accessibilityIdentifier("cast_connection_page")
    }

    private var statusCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.14))
                    .frame(width: 52, height: 52)
                Image(systemName: statusIcon)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(statusTitle)
                    .font(.system(size: Theme.fontH5, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(statusMessage)
                    .font(.system(size: Theme.fontCaption, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityIdentifier("cast_status_\(externalDisplay.status.rawValue)")
    }

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(
                NSLocalizedString("cast_how_to", value: "如何投屏", comment: ""),
                systemImage: "airplayvideo"
            )
            .font(.system(size: Theme.fontH5, weight: .bold))
            .foregroundStyle(Theme.textPrimary)

            guideStep(1, NSLocalizedString("cast_step_same_wifi", value: "确认 iPhone 和电视连接同一 Wi-Fi。", comment: ""))
            guideStep(2, NSLocalizedString("cast_step_control_center", value: "打开控制中心，点击“屏幕镜像”。", comment: ""))
            guideStep(3, NSLocalizedString("cast_step_select_tv", value: "选择电视或海信“Hi投屏”；连接后电视会自动切换为专用计分屏。", comment: ""))
        }
        .padding(18)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private var compatibilityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                NSLocalizedString("cast_supported_methods", value: "支持方式", comment: ""),
                systemImage: "cable.connector"
            )
            .font(.system(size: Theme.fontH5, weight: .bold))
            .foregroundStyle(Theme.textPrimary)
            Text(NSLocalizedString(
                "cast_supported_methods_detail",
                value: "支持 AirPlay 兼容电视、Apple TV，以及 USB-C/Lightning 转 HDMI 有线外屏。部分第三方接收器只支持普通镜像，此时仍可继续使用，但不会显示专用布局。",
                comment: ""
            ))
            .font(.system(size: Theme.fontCaption))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private func guideStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 25, height: 25)
                .background(Theme.primary, in: Circle())
            Text(text)
                .font(.system(size: Theme.fontBody1))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusColor: Color {
        switch externalDisplay.status {
        case .disconnected: Theme.textSecondary
        case .mirroring: Color(hex: "FF9F0A")
        case .dedicated: Color(hex: "30D158")
        }
    }

    private var statusIcon: String {
        switch externalDisplay.status {
        case .disconnected: "rectangle.on.rectangle.slash"
        case .mirroring: "rectangle.on.rectangle"
        case .dedicated: "checkmark.rectangle.stack.fill"
        }
    }

    private var statusTitle: String {
        switch externalDisplay.status {
        case .disconnected: NSLocalizedString("cast_disconnected", value: "未连接", comment: "")
        case .mirroring: NSLocalizedString("cast_mirroring", value: "已连接 · 镜像模式", comment: "")
        case .dedicated: NSLocalizedString("cast_active", value: "投屏中", comment: "")
        }
    }

    private var statusMessage: String {
        switch externalDisplay.status {
        case .disconnected:
            NSLocalizedString("cast_disconnected_message", value: "请从控制中心连接电视或外接显示器。", comment: "")
        case .mirroring:
            NSLocalizedString("cast_mirroring_message", value: "当前接收器只提供普通镜像，手机画面会原样显示在电视上。", comment: "")
        case .dedicated:
            NSLocalizedString("cast_dedicated_message", value: "电视正在显示专用计分屏，手机可继续操作。", comment: "")
        }
    }
}
