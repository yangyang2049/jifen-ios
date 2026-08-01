import LinkCore
import SwiftUI

struct WatchPhoneLinkView: View {
    @Environment(WatchLinkService.self) private var linkService

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                introCard
                statusCard
                stepsCard
                helpCard
                testButton
            }
            .padding(.horizontal, WatchLayout.pageHorizontalPadding)
            .padding(.bottom, 12)
        }
        .background(WatchTheme.background)
        .navigationTitle(NSLocalizedString("watch_phone_link_title", value: "手机联动", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            linkService.refreshConnectivity()
        }
    }

    private var introCard: some View {
        VStack(spacing: 7) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(WatchTheme.accent)
            Text(NSLocalizedString("watch_phone_link_intro", value: "由手机发起，手表主控计分", comment: ""))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(WatchTheme.primaryText)
                .multilineTextAlignment(.center)
            Text(NSLocalizedString(
                "watch_phone_link_support",
                value: "支持四类球拍项目的单打与双打，以及射箭、黑八、追分和斯诺克。",
                comment: ""
            ))
            .font(.system(size: 10))
            .foregroundStyle(WatchTheme.accent)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(WatchLayout.cardContentPadding)
        .background(WatchTheme.listItemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(NSLocalizedString("watch_phone_link_status", value: "连接状态", comment: ""))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WatchTheme.primaryText)
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                Text(statusTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WatchTheme.primaryText)
            }
            Text(statusDetail)
                .font(.system(size: 10))
                .foregroundStyle(WatchTheme.secondaryText)
                .lineLimit(3)
            Text(lastCommunicationText)
                .font(.system(size: 10))
                .foregroundStyle(WatchTheme.secondaryText.opacity(0.85))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WatchLayout.cardContentPadding)
        .background(WatchTheme.listItemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("watch_phone_link_steps", value: "使用步骤", comment: ""))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WatchTheme.primaryText)
            step("1", NSLocalizedString("watch_phone_link_step_1", value: "在手机选择比赛并完成设置", comment: ""))
            step("2", NSLocalizedString("watch_phone_link_step_2", value: "点击“在手表开始”", comment: ""))
            step("3", NSLocalizedString("watch_phone_link_step_3", value: "在手表确认后开始计分", comment: ""))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WatchLayout.cardContentPadding)
        .background(WatchTheme.listItemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func step(_ index: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text(index)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WatchTheme.accent)
                .frame(width: 20, height: 20)
                .background(WatchTheme.accent.opacity(0.14))
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(WatchTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var helpCard: some View {
        Text(NSLocalizedString(
            "watch_phone_link_help",
            value: "连接失败时，请确认手机和手表已配对、两端应用均已安装，并在测试时打开手机端全能计分器。",
            comment: ""
        ))
        .font(.system(size: 10))
        .foregroundStyle(WatchTheme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WatchLayout.cardContentPadding)
        .background(WatchTheme.listItemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var testButton: some View {
        Button {
            linkService.startConnectivityTest()
        } label: {
            Text(testButtonTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(WatchTheme.accent.opacity(linkService.phoneLinkTestState == .testing ? 0.55 : 1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(linkService.phoneLinkTestState == .testing)
    }

    private var statusTitle: String {
        switch linkService.phoneLinkTestState {
        case .testing:
            return NSLocalizedString("watch_phone_link_testing", value: "正在测试", comment: "")
        case .success:
            return NSLocalizedString("watch_phone_link_normal", value: "连接正常", comment: "")
        case .failed:
            return NSLocalizedString("watch_phone_link_failed", value: "连接失败", comment: "")
        case .idle:
            if linkService.connectivityStatus.isReachable {
                return NSLocalizedString("watch_phone_link_reachable", value: "手机可达", comment: "")
            }
            if linkService.connectivityStatus.isActivated {
                return NSLocalizedString("watch_phone_link_waiting", value: "等待手机", comment: "")
            }
            return NSLocalizedString("watch_phone_link_inactive", value: "尚未激活", comment: "")
        }
    }

    private var statusDetail: String {
        switch linkService.phoneLinkTestState {
        case .testing:
            return NSLocalizedString("watch_phone_link_testing_detail", value: "正在等待手机应用应答…", comment: "")
        case .success:
            return NSLocalizedString("watch_phone_link_normal_detail", value: "手机应用已成功响应，可以使用联动计分。", comment: "")
        case .failed:
            switch linkService.phoneLinkTestFailure {
            case .inactive:
                return NSLocalizedString("watch_phone_link_failed_inactive", value: "手表连接服务尚未激活，请稍后重试。", comment: "")
            case .unreachable:
                return NSLocalizedString("watch_phone_link_failed_unreachable", value: "手机当前不可达，请打开手机端全能计分器后重试。", comment: "")
            case .sendFailed:
                return NSLocalizedString("watch_phone_link_failed_send", value: "测试请求发送失败，请检查连接后重试。", comment: "")
            case .timedOut, .none:
                return NSLocalizedString("watch_phone_link_failed_detail", value: "8 秒内未收到手机应答，请按下方提示检查。", comment: "")
            }
        case .idle:
            return linkService.connectivityStatus.isReachable
                ? NSLocalizedString("watch_phone_link_reachable_detail", value: "可点击下方按钮验证手机应用是否响应。", comment: "")
                : NSLocalizedString("watch_phone_link_waiting_detail", value: "请打开手机端全能计分器后重试。", comment: "")
        }
    }

    private var statusColor: Color {
        switch linkService.phoneLinkTestState {
        case .success: return WatchTheme.accent
        case .failed: return .red
        case .testing: return .cyan
        case .idle: return linkService.connectivityStatus.isReachable ? WatchTheme.accent : .gray
        }
    }

    private var testButtonTitle: String {
        switch linkService.phoneLinkTestState {
        case .testing:
            return NSLocalizedString("watch_phone_link_test_waiting", value: "等待手机…", comment: "")
        case .success, .failed:
            return NSLocalizedString("watch_phone_link_test_retry", value: "重新测试", comment: "")
        case .idle:
            return NSLocalizedString("watch_phone_link_test", value: "测试连接", comment: "")
        }
    }

    private var lastCommunicationText: String {
        guard linkService.lastCommunicationAtEpochMilliseconds > 0 else {
            return NSLocalizedString("watch_phone_link_last_empty", value: "暂无通信记录", comment: "")
        }
        let date = Date(
            timeIntervalSince1970: TimeInterval(linkService.lastCommunicationAtEpochMilliseconds) / 1_000
        )
        return String(format: NSLocalizedString(
            "watch_phone_link_last_time",
            value: "最近通信 %@",
            comment: ""
        ), date.formatted(date: .omitted, time: .standard))
    }
}
