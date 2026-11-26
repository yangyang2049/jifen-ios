import LinkCore
import SwiftUI

struct WatchLinkedSetupConfirmationLayout: Equatable {
    enum Tier: Equatable {
        case compact   // 40 / 41mm
        case medium    // 42 / 44 / 45mm
        case large     // 46 / 49mm
    }

    let tier: Tier
    let topInset: CGFloat
    let bottomInset: CGFloat
    let horizontalPadding: CGFloat
    let iconSize: CGFloat
    let phoneBadgeSize: CGFloat
    let summaryFontSize: CGFloat
    let nameFontSize: CGFloat
    let vsFontSize: CGFloat
    let accentBarHeightSingle: CGFloat
    let accentBarHeightDoubles: CGFloat
    let sectionSpacing: CGFloat
    let headerSpacing: CGFloat
    let nameRowSpacing: CGFloat
    let opponentSpacing: CGFloat
    let gridRowSpacing: CGFloat
    let upperBottomPadding: CGFloat
    let actionDiameter: CGFloat
    let actionSpacing: CGFloat

    static func resolve(screenSize: CGSize) -> Self {
        let width = screenSize.width
        let height = screenSize.height
        if width <= 176 || height <= 212 {
            return Self(
                tier: .compact,
                topInset: 27,
                bottomInset: 14,
                horizontalPadding: 11,
                iconSize: 36,
                phoneBadgeSize: 13,
                summaryFontSize: 12,
                nameFontSize: 13,
                vsFontSize: 10,
                accentBarHeightSingle: 16,
                accentBarHeightDoubles: 28,
                sectionSpacing: 11,
                headerSpacing: 5,
                nameRowSpacing: 2,
                opponentSpacing: 5,
                gridRowSpacing: 6,
                upperBottomPadding: 6,
                actionDiameter: 44,
                actionSpacing: 21
            )
        }
        if width <= 198 && height < 245 {
            return Self(
                tier: .medium,
                topInset: 30,
                bottomInset: 16,
                horizontalPadding: 15,
                iconSize: 41,
                phoneBadgeSize: 14,
                summaryFontSize: 13,
                nameFontSize: 14.5,
                vsFontSize: 10.5,
                accentBarHeightSingle: 18,
                accentBarHeightDoubles: 32,
                sectionSpacing: 12,
                headerSpacing: 5,
                nameRowSpacing: 3,
                opponentSpacing: 6,
                gridRowSpacing: 6,
                upperBottomPadding: 7,
                actionDiameter: 50,
                actionSpacing: 24
            )
        }
        return Self(
            tier: .large,
            topInset: 34,
            bottomInset: 18,
            horizontalPadding: 18,
            iconSize: 46,
            phoneBadgeSize: 16,
            summaryFontSize: 14,
            nameFontSize: 16,
            vsFontSize: 11,
            accentBarHeightSingle: 20,
            accentBarHeightDoubles: 36,
            sectionSpacing: 14,
            headerSpacing: 6,
            nameRowSpacing: 3,
            opponentSpacing: 6,
            gridRowSpacing: 7,
            upperBottomPadding: 8,
            actionDiameter: 56,
            actionSpacing: 27
        )
    }
}

/// 联动确认倒计时的唯一口径：presenter 提供 deadline 时以其为准；没有提供时
/// 以本视图首次构建时刻 + timeout 兜底。冷启动时手机侧的 setup 可能在本视图
/// 被构建时就已经处于 pending（父视图的 onChange 不会再触发），若此时仍按
/// deadline == nil 处理：圆环会停在满格、remaining == 0 永不成立，遮罩只能靠
/// 用户手动点 ✕/✓ 才能关掉，而且超时之后仍然允许 accept。
nonisolated enum LinkedSetupConfirmDeadline {
    static func resolve(deadline: Date?, startedAt: Date, timeout: TimeInterval) -> Date {
        deadline ?? startedAt.addingTimeInterval(max(1, timeout))
    }
}

struct WatchLinkedSetupConfirmationView: View {
    let setup: LinkedScoreboardSetup
    let deadline: Date?
    let timeout: TimeInterval
    let onDecline: () -> Void
    let onAccept: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 本视图（而不是 presenter）持有的起算时刻，用途见 LinkedSetupConfirmDeadline。
    @State private var firstRenderAt = Date()

    private var resolvedTimeout: TimeInterval { max(1, timeout) }

    private var resolvedDeadline: Date {
        LinkedSetupConfirmDeadline.resolve(
            deadline: deadline,
            startedAt: firstRenderAt,
            timeout: timeout
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let fullWidth = geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing
            let fullHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            let layout = WatchLinkedSetupConfirmationLayout.resolve(
                screenSize: CGSize(width: fullWidth, height: fullHeight)
            )

            ZStack {
                WatchTheme.background

                countdown
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    VStack(spacing: layout.sectionSpacing) {
                        header(layout: layout)
                        participantNames(layout: layout)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, layout.upperBottomPadding)

                    actions(layout: layout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.top, layout.topInset)
                .padding(.bottom, layout.bottomInset)
            }
            .frame(width: fullWidth, height: fullHeight)
            .offset(x: -geometry.safeAreaInsets.leading, y: -geometry.safeAreaInsets.top)
        }
        .ignoresSafeArea()
    }

    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let remaining = max(0, resolvedDeadline.timeIntervalSince(context.date))
            let consumed = 1 - min(remaining / resolvedTimeout, 1)
            let outline = LinkedSetupCountdownOutline()
            let stroke = StrokeStyle(lineWidth: 3, lineCap: .round)

            ZStack {
                outline.stroke(WatchTheme.subtleFill, style: stroke)
                if consumed < 1 {
                    outline.trim(from: consumed, to: 1)
                        .stroke(WatchTheme.accent.opacity(0.82), style: stroke)
                }
            }
            .animation(reduceMotion ? nil : .linear(duration: 0.1), value: consumed)
            .onChange(of: remaining == 0, initial: true) { _, expired in
                if expired { onDecline() }
            }
        }
    }

    private func header(layout: WatchLinkedSetupConfirmationLayout) -> some View {
        VStack(spacing: layout.headerSpacing) {
            HStack(spacing: 7) {
                Color.clear.frame(width: layout.phoneBadgeSize, height: 1)
                    .accessibilityHidden(true)
                if let gameType = WatchGameType(scoreCoreGameType: setup.gameType) {
                    WatchCatalogIcon(gameType: gameType, size: layout.iconSize)
                }
                Image(systemName: "iphone")
                    .font(.system(size: layout.phoneBadgeSize, weight: .medium))
                    .foregroundStyle(WatchTheme.secondaryText)
                    .frame(width: layout.phoneBadgeSize)
                    .accessibilityLabel(NSLocalizedString(
                        "linked_score_phone_started_scoreboard",
                        value: "手机已发起计分",
                        comment: ""
                    ))
            }

            Text(LinkedSetupConfirmCopy.summary(for: setup))
                .font(.system(size: layout.summaryFontSize, weight: .semibold))
                .foregroundStyle(WatchTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("watch_link_confirmation_summary")
        }
    }

    @ViewBuilder
    private func participantNames(layout: WatchLinkedSetupConfirmationLayout) -> some View {
        switch LinkedSetupConfirmCopy.participants(for: setup) {
        case .none:
            EmptyView()
        case .opponents(let left, let right):
            HStack(spacing: layout.opponentSpacing) {
                nameColumn(left, accent: WatchTheme.teamRed, layout: layout)
                Text(verbatim: "·")
                    .font(.system(size: layout.vsFontSize, weight: .medium))
                    .foregroundStyle(WatchTheme.secondaryText)
                    .accessibilityHidden(true)
                nameColumn(right, accent: WatchTheme.teamBlue, layout: layout)
            }
        case .players(let names):
            let accents: [Color] = [WatchTheme.teamRed, WatchTheme.teamBlue, WatchTheme.accent, .purple]
            LazyVGrid(columns: [
                GridItem(.flexible(minimum: 0), spacing: 8),
                GridItem(.flexible(minimum: 0), spacing: 0)
            ], spacing: layout.gridRowSpacing) {
                ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                    nameColumn([name], accent: accents[index], layout: layout)
                }
            }
            .accessibilityIdentifier("watch_link_confirmation_players")
        }
    }

    private func nameColumn(
        _ names: [String],
        accent: Color,
        layout: WatchLinkedSetupConfirmationLayout
    ) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(accent.opacity(0.85))
                .frame(
                    width: 3,
                    height: names.count > 1 ? layout.accentBarHeightDoubles : layout.accentBarHeightSingle
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: layout.nameRowSpacing) {
                ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .font(.system(size: layout.nameFontSize, weight: .semibold))
                        .foregroundStyle(WatchTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.80)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actions(layout: WatchLinkedSetupConfirmationLayout) -> some View {
        let size = layout.actionDiameter
        return HStack(spacing: layout.actionSpacing) {
            Button(action: onDecline) {
                Image(systemName: "xmark")
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(WatchTheme.listItemBackground, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("linked_score_reject", value: "拒绝", comment: ""))

            Button {
                if Date() >= resolvedDeadline {
                    onDecline()
                } else {
                    onAccept()
                }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.43, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(WatchTheme.accent, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("linked_score_accept", value: "接受", comment: ""))
        }
    }
}

private struct LinkedSetupCountdownOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: 2, dy: 2)
        guard bounds.width > 0, bounds.height > 0 else { return Path() }
        let radius = min(bounds.width, bounds.height) * 0.28
        let top = CGPoint(x: bounds.midX, y: bounds.minY)
        let topRight = CGPoint(x: bounds.maxX, y: bounds.minY)
        let bottomRight = CGPoint(x: bounds.maxX, y: bounds.maxY)
        let bottomLeft = CGPoint(x: bounds.minX, y: bounds.maxY)
        let topLeft = CGPoint(x: bounds.minX, y: bounds.minY)

        // Sweep clockwise from 12 o'clock so the remaining arc ends at the top.
        var path = Path()
        path.move(to: top)
        path.addArc(tangent1End: topRight, tangent2End: bottomRight, radius: radius)
        path.addArc(tangent1End: bottomRight, tangent2End: bottomLeft, radius: radius)
        path.addArc(tangent1End: bottomLeft, tangent2End: topLeft, radius: radius)
        path.addArc(tangent1End: topLeft, tangent2End: top, radius: radius)
        path.closeSubpath()
        return path
    }
}
