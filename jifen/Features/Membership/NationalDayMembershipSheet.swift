import StoreKit
import SwiftUI

// 国庆会员活动弹窗（对齐安卓 NationalDayMembershipSheet，1:1 移植）：
// 终身会员票券 + 红绸记分牌主视觉；仅展示给简体中文设备（见 NationalDayCampaignGate），
// 中文文案随 NationalDayCampaignPolicy 语言门控硬编码，i18n-exempt: national-day-zh-hans-only。
// iOS 购买走 StoreKit 终身商品（iscoreboard_lifetime_vip），不含微信游客购买链路。

private let ndInk = Color(hex: "302B24")
private let ndMuted = Color(hex: "6F6256")
private let ndGold = Color(hex: "935419")
private let ndGreen = Color(hex: "198447")
private let ndIvory = Color(hex: "FFF7E6")
private let ndVermilion = Color(hex: "D4472B")
private let ndRibbonRed = Color(hex: "E75838")
private let ndDeepRed = Color(hex: "8D241C")
private let ndBrightGold = Color(hex: "E9B449")

struct NationalDayMembershipSheet: View {
    var onDismiss: () -> Void
    /// 登录并同步会员：关闭弹窗后切到「我的」Tab 完成登录，登录会自动补验未确认的 StoreKit 交易。
    var onOpenAccount: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var manager = StoreKitPurchaseManager.shared
    @State private var showingBenefits = false
    @State private var agreementChecked = false
    @State private var agreementPage: MembershipAgreementPage?
    @State private var purchaseComplete = false
    @State private var purchasedWithAccount = false
    @State private var feedback: String?

    private var lifetimeProduct: Product? {
        manager.products.first { $0.id == StoreKitPurchaseManager.lifetimeProductID }
    }

    private var isBusy: Bool {
        switch manager.state {
        case .loading, .purchasing: return true
        default: return false
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ndDragHandle
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                    if purchaseComplete {
                        successContent
                    } else if showingBenefits {
                        benefitsContent
                    } else {
                        campaignContent
                    }
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            ModalCloseButton(placement: .standalone) {
                guard !isBusy else { return }
                onDismiss()
            }
            .accessibilityLabel(NSLocalizedString("close", value: "关闭", comment: ""))
            .accessibilityIdentifier("national_day_close")
            .padding(.trailing, 12)
            .padding(.top, 1)
            .disabled(isBusy)
        }
        .background(Color.white)
        .presentationDragIndicator(.hidden)
        .presentationDetents([.large])
        .interactiveDismissDisabled(isBusy)
        .task {
            // 已是会员（触发后被他人代付/兑换等边缘场景）：直接进成功态，与安卓游客权益分支一致。
            if manager.hasLocalEntitlement {
                purchaseComplete = true
                purchasedWithAccount = SessionStore.shared.isAuthenticated
            }
            if !manager.didLoadProducts || manager.products.isEmpty {
                await manager.loadProducts()
            }
        }
        .sheet(item: $agreementPage) { page in
            NavigationStack {
                AppWebView(url: page.url)
                    .background(Theme.backgroundColor)
                    .navigationTitle(page.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { ModalCloseButton { agreementPage = nil } } }
            }
        }
    }

    private var ndDragHandle: some View {
        Capsule()
            .fill(Color(hex: "DDD7CC"))
            .frame(width: 34, height: 3)
    }

    // MARK: - 主内容（活动页）

    private var campaignContent: some View {
        // 对齐安卓 narrowScreen(<450dp)：手机两行、宽屏一行。
        let narrowScreen = horizontalSizeClass == .compact
        return VStack(spacing: 0) {
            CampaignArtwork()
                .padding(.top, 6)

            Text(narrowScreen ? "国庆聚一场，\n快乐不散场。" : "国庆聚一场，快乐不散场。")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(ndInk)
                .lineSpacing(11)
                .multilineTextAlignment(.center)
                .padding(.top, 2)

            Text("打球、桌游、朋友聚会。\n一次开通，永久享有会员权益。")
                .font(.system(size: 12))
                .foregroundColor(ndMuted)
                .lineSpacing(11)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            LifetimeTicket(price: lifetimeProduct?.displayPrice)
                .padding(.top, 22)
                .padding(.bottom, 19)

            agreementRow
                .padding(.bottom, 13)

            if let feedback {
                Text(feedback)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "AE4435"))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 9)
            }

            buyButton

            Button {
                showingBenefits = true
            } label: {
                Text("查看会员权益  ›")
                    .font(.system(size: 11))
                    .foregroundColor(ndMuted)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var agreementRow: some View {
        HStack(spacing: 7) {
            Button {
                agreementChecked.toggle()
            } label: {
                Image(systemName: agreementChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(agreementChecked ? ndGreen : ndMuted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            (Text("已阅读并同意").foregroundColor(ndMuted)
                + Text("《会员协议》").foregroundColor(ndGold).underline())
                .font(.system(size: 11))
                .onTapGesture {
                    agreementPage = MembershipAgreementPage(kind: .membership)
                }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var buyButton: some View {
        Button {
            startPurchase()
        } label: {
            Text(buyButtonText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Capsule().fill(ndGreen))
        }
        .buttonStyle(.plain)
        .disabled(isBusy || lifetimeProduct == nil)
    }

    private var buyButtonText: String {
        if manager.products.isEmpty && manager.state == .loading { return "正在加载" }
        if case .purchasing = manager.state { return "正在发起购买" }
        if case .loading = manager.state { return "正在加载" }
        let price = lifetimeProduct?.displayPrice ?? ""
        return "\(price) 直接购买"
    }

    private func startPurchase() {
        guard !isBusy, !purchaseComplete else { return }
        guard let lifetime = lifetimeProduct else { return }
        guard agreementChecked else {
            feedback = "请先阅读并同意《会员协议》"
            return
        }
        feedback = nil
        Task {
            await manager.purchase(lifetime)
            switch manager.state {
            case .succeeded:
                purchaseComplete = true
                purchasedWithAccount = SessionStore.shared.isAuthenticated
            case .cancelled:
                feedback = "支付未完成，可以稍后重试"
            case .failed(let message):
                feedback = message
            default:
                break
            }
        }
    }

    // MARK: - 成功页

    private var successContent: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 23)
            Image(systemName: "checkmark")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(ndGreen)
                .frame(height: 48)
            Text("终身会员已开通")
                .font(.system(size: 25, weight: .semibold))
                .foregroundColor(ndInk)
                .padding(.top, 9)
            Text(purchasedWithAccount
                ? "会员权益已保存到当前账号。"
                : "会员功能已在本机生效。登录绑定后，换设备也能找回权益。")
                .font(.system(size: 13))
                .foregroundColor(ndMuted)
                .lineSpacing(10)
                .multilineTextAlignment(.center)
                .padding(.top, 11)
                .padding(.bottom, 23)
            if purchasedWithAccount {
                ndPrimaryButton("开始使用") { onDismiss() }
            } else {
                ndPrimaryButton("登录并绑定会员") {
                    onOpenAccount()
                }
                Button {
                    onDismiss()
                } label: {
                    Text("稍后绑定，先使用")
                        .font(.system(size: 15))
                        .foregroundColor(ndMuted)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 权益页（对齐安卓 BenefitsContent）

    private var benefitsContent: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 16)
            Text("会员权益")
                .font(.system(size: 11))
                .foregroundColor(ndGold)
            Text("更完整的计分体验")
                .font(.system(size: 25, weight: .semibold))
                .foregroundColor(ndInk)
                .padding(.top, 12)
                .padding(.bottom, 16)

            ForEach(Array(ndCampaignBenefits.enumerated()), id: \.offset) { index, benefit in
                HStack(spacing: 10) {
                    Image(systemName: benefit.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(ndGreen)
                    Text(benefit.title)
                        .font(.system(size: 15))
                        .foregroundColor(ndInk)
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color(hex: "EEEAE3"))
                    .frame(height: 1)
                    .opacity(index == ndCampaignBenefits.count - 1 ? 0 : 1)
            }

            Text("云端同步需登录账号后使用")
                .font(.system(size: 11))
                .foregroundColor(ndMuted)
                .padding(.top, 12)
            Spacer().frame(height: 17)
            ndPrimaryButton("返回") { showingBenefits = false }
        }
        .frame(maxWidth: .infinity)
    }

    private func ndPrimaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Capsule().fill(ndGreen))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 4)
    }
}

/// 权益六项（文案与安卓一致，图标复用 iOS 会员页的 SF Symbols）。
private struct NDCampaignBenefit {
    let title: String
    let symbol: String
}

private let ndCampaignBenefits: [NDCampaignBenefit] = [
    NDCampaignBenefit(title: "高级统计", symbol: "chart.bar.xaxis"),
    NDCampaignBenefit(title: "专属主题", symbol: "paintpalette"),
    NDCampaignBenefit(title: "云端同步", symbol: "icloud.and.arrow.up"),
    NDCampaignBenefit(title: "无广告体验", symbol: "rectangle.badge.xmark"),
    NDCampaignBenefit(title: "优先体验", symbol: "sparkles"),
    NDCampaignBenefit(title: "专业投屏体验", symbol: "play.tv")
]

// MARK: - 终身会员票券（对齐安卓 LifetimeTicket：两侧内凹缺口 + 虚线分隔）

private struct LifetimeTicket: View {
    let price: String?

    private static let priceAreaWidth: CGFloat = 88
    private static let sidePadding: CGFloat = 18

    var body: some View {
        Canvas { context, size in
            let sidePadding = Self.sidePadding
            let priceAreaWidth = Self.priceAreaWidth
            let dividerX = size.width - (sidePadding + priceAreaWidth + 1)
            let inset: CGFloat = 0.5
            let left = inset
            let top = inset
            let right = size.width - inset
            let bottom = size.height - inset
            let corner: CGFloat = 12
            let cornerControl = corner * 0.448
            let notchHalf: CGFloat = 8
            let notchDepth: CGFloat = 5.5

            var outline = Path()
            outline.move(to: CGPoint(x: left + corner, y: top))
            outline.addLine(to: CGPoint(x: dividerX - notchHalf, y: top))
            outline.addCurve(
                to: CGPoint(x: dividerX, y: top + notchDepth),
                control1: CGPoint(x: dividerX - notchHalf * 0.5, y: top),
                control2: CGPoint(x: dividerX - notchHalf * 0.75, y: top + notchDepth)
            )
            outline.addCurve(
                to: CGPoint(x: dividerX + notchHalf, y: top),
                control1: CGPoint(x: dividerX + notchHalf * 0.75, y: top + notchDepth),
                control2: CGPoint(x: dividerX + notchHalf * 0.5, y: top)
            )
            outline.addLine(to: CGPoint(x: right - corner, y: top))
            outline.addCurve(
                to: CGPoint(x: right, y: top + corner),
                control1: CGPoint(x: right - cornerControl, y: top),
                control2: CGPoint(x: right, y: top + cornerControl)
            )
            outline.addLine(to: CGPoint(x: right, y: bottom - corner))
            outline.addCurve(
                to: CGPoint(x: right - corner, y: bottom),
                control1: CGPoint(x: right, y: bottom - cornerControl),
                control2: CGPoint(x: right - cornerControl, y: bottom)
            )
            outline.addLine(to: CGPoint(x: dividerX + notchHalf, y: bottom))
            outline.addCurve(
                to: CGPoint(x: dividerX, y: bottom - notchDepth),
                control1: CGPoint(x: dividerX + notchHalf * 0.5, y: bottom),
                control2: CGPoint(x: dividerX + notchHalf * 0.75, y: bottom - notchDepth)
            )
            outline.addCurve(
                to: CGPoint(x: dividerX - notchHalf, y: bottom),
                control1: CGPoint(x: dividerX - notchHalf * 0.75, y: bottom - notchDepth),
                control2: CGPoint(x: dividerX - notchHalf * 0.5, y: bottom)
            )
            outline.addLine(to: CGPoint(x: left + corner, y: bottom))
            outline.addCurve(
                to: CGPoint(x: left, y: bottom - corner),
                control1: CGPoint(x: left, y: bottom - cornerControl),
                control2: CGPoint(x: left + cornerControl, y: bottom)
            )
            outline.addLine(to: CGPoint(x: left, y: top + corner))
            outline.addCurve(
                to: CGPoint(x: left + corner, y: top),
                control1: CGPoint(x: left, y: top + cornerControl),
                control2: CGPoint(x: left + cornerControl, y: top)
            )
            outline.closeSubpath()

            context.fill(outline, with: .color(ndIvory))
            context.stroke(outline, with: .color(Color(hex: "C8903E")), lineWidth: 1)

            var divider = Path()
            divider.move(to: CGPoint(x: dividerX, y: 13))
            divider.addLine(to: CGPoint(x: dividerX, y: size.height - 13))
            context.stroke(
                divider,
                with: .color(Color(hex: "B77625")),
                style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [4, 4])
            )
        }
        .frame(height: 82)
        .overlay {
            HStack(spacing: 1) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("终身会员")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color(hex: "79431D"))
                    Text("一次购买 · 无需续费")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "795C3A"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Self.sidePadding)

                Text(price ?? "终身")
                    .font(.system(size: price == nil ? 22 : 33, weight: .semibold))
                    .foregroundColor(ndGold)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(width: Self.priceAreaWidth)
                    .padding(.trailing, 1)
            }
            .padding(.horizontal, Self.sidePadding - 1)
        }
    }
}

// MARK: - 主视觉（对齐安卓 CampaignArtwork：金光 + 红绸 + 闪烁装饰 + 记分牌）

private struct CampaignArtwork: View {
    var body: some View {
        ZStack {
            CampaignArtworkCanvas()
            CampaignSparkles()
            CampaignScoreboard()
        }
        .frame(maxWidth: 350)
        .frame(height: 148)
        .frame(maxWidth: .infinity)
    }
}

private struct CampaignArtworkCanvas: View {
    var body: some View {
        Canvas { context, size in
            let sx = size.width / 350
            let sy = size.height / 148
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * sx, y: y * sy)
            }
            func s(_ w: CGFloat, _ h: CGFloat) -> CGSize {
                CGSize(width: w * sx, height: h * sy)
            }

            // 金色光晕
            let glowCenter = p(176, 77)
            let glowRect = CGRect(origin: p(37, 4), size: s(276, 140))
            let glowPath = Path(ellipseIn: glowRect)
            context.fill(
                glowPath,
                with: .radialGradient(
                    Gradient(colors: [Color(hex: "FFD16D").opacity(0.44), .clear]),
                    center: glowCenter,
                    startRadius: 0,
                    endRadius: 138 * sx
                )
            )
            let ringRect = CGRect(origin: p(71, 16), size: s(208, 120))
            context.stroke(
                Path(ellipseIn: ringRect),
                with: .color(Color(hex: "D9A340").opacity(0.72)),
                lineWidth: 1.2 * sx
            )

            // 左红绸
            var leftRibbon = Path()
            leftRibbon.move(to: p(9, 107))
            leftRibbon.addCurve(to: p(154, 86), control1: p(54, 70), control2: p(92, 76))
            leftRibbon.addLine(to: p(165, 111))
            leftRibbon.addCurve(to: p(22, 135), control1: p(103, 98), control2: p(65, 105))
            leftRibbon.addLine(to: p(27, 116))
            leftRibbon.closeSubpath()
            context.fill(
                leftRibbon,
                with: .linearGradient(
                    Gradient(colors: [ndRibbonRed, ndVermilion, ndDeepRed]),
                    startPoint: p(12, 78),
                    endPoint: p(155, 126)
                )
            )
            var leftFold = Path()
            leftFold.move(to: p(22, 135))
            leftFold.addLine(to: p(27, 116))
            leftFold.addLine(to: p(49, 107))
            leftFold.closeSubpath()
            context.fill(leftFold, with: .color(ndDeepRed))
            var leftHighlight = Path()
            leftHighlight.move(to: p(20, 106))
            leftHighlight.addCurve(to: p(148, 91), control1: p(65, 77), control2: p(102, 83))
            context.stroke(
                leftHighlight,
                with: .color(Color(hex: "FFA26A")),
                style: StrokeStyle(lineWidth: 2.2 * sx, lineCap: .round)
            )

            // 右红绸
            var rightRibbon = Path()
            rightRibbon.move(to: p(194, 62))
            rightRibbon.addCurve(to: p(341, 56), control1: p(250, 23), control2: p(292, 36))
            rightRibbon.addLine(to: p(323, 73))
            rightRibbon.addLine(to: p(339, 91))
            rightRibbon.addCurve(to: p(204, 91), control1: p(285, 70), control2: p(252, 62))
            rightRibbon.closeSubpath()
            context.fill(
                rightRibbon,
                with: .linearGradient(
                    Gradient(colors: [ndDeepRed, ndVermilion, ndRibbonRed]),
                    startPoint: p(195, 91),
                    endPoint: p(333, 43)
                )
            )
            var rightHighlight = Path()
            rightHighlight.move(to: p(208, 63))
            rightHighlight.addCurve(to: p(328, 57), control1: p(258, 38), control2: p(297, 43))
            context.stroke(
                rightHighlight,
                with: .color(Color(hex: "FFAA73")),
                style: StrokeStyle(lineWidth: 2 * sx, lineCap: .round)
            )
        }
    }
}

/// 闪烁装饰（对齐安卓 CampaignSparkles：1 个光芒 + 1 个十字 + 3 个圆点，呼吸节奏错开）。
private struct CampaignSparkles: View {
    private struct Decoration {
        let kind: Kind
        let xRatio: CGFloat
        let y: CGFloat
        let size: CGFloat
        let color: Color
        let phaseOffset: TimeInterval

        enum Kind { case burst, plus, dot }
    }

    private let decorations: [Decoration] = [
        Decoration(kind: .burst, xRatio: 48 / 350, y: 44, size: 34, color: Color(hex: "D59A2E"), phaseOffset: 0),
        Decoration(kind: .plus, xRatio: 302 / 350, y: 112, size: 20, color: ndBrightGold, phaseOffset: 0.65),
        Decoration(kind: .dot, xRatio: 79 / 350, y: 26, size: 5.4, color: ndBrightGold, phaseOffset: 1.1),
        Decoration(kind: .dot, xRatio: 283 / 350, y: 24, size: 4.6, color: Color(hex: "C87D2C"), phaseOffset: 0.35),
        Decoration(kind: .dot, xRatio: 69 / 350, y: 125, size: 3.6, color: ndBrightGold, phaseOffset: 1.55)
    ]

    private static let pulsePeriod: TimeInterval = 1.1

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                for decoration in decorations {
                    let progress = (now + decoration.phaseOffset) / Self.pulsePeriod
                    let fraction = progress - floor(progress)
                    let triangle = abs(fraction * 2 - 1)
                    let glow = 1 - triangle
                    let alpha = 0.16 + 0.84 * glow
                    let scale = 0.86 + 0.2 * glow

                    let center = CGPoint(
                        x: size.width * decoration.xRatio,
                        y: decoration.y
                    )
                    let half = decoration.size * scale / 2

                    var path = Path()
                    switch decoration.kind {
                    case .burst:
                        let rayLength = decoration.size * 0.23
                        for ray in 0..<8 {
                            let angle = CGFloat(ray) * 45 * .pi / 180
                            let inner = CGPoint(x: 0, y: -half)
                            let outer = CGPoint(x: 0, y: -half + rayLength)
                            let rotatedInner = rotate(inner, angle: angle)
                            let rotatedOuter = rotate(outer, angle: angle)
                            var rayPath = Path()
                            rayPath.move(to: CGPoint(x: center.x + rotatedInner.x, y: center.y + rotatedInner.y))
                            rayPath.addLine(to: CGPoint(x: center.x + rotatedOuter.x, y: center.y + rotatedOuter.y))
                            context.stroke(
                                rayPath,
                                with: .color(decoration.color.opacity(alpha)),
                                style: StrokeStyle(lineWidth: 1.3, lineCap: .round)
                            )
                        }
                        continue
                    case .plus:
                        path.move(to: CGPoint(x: center.x - half, y: center.y))
                        path.addLine(to: CGPoint(x: center.x + half, y: center.y))
                        path.move(to: CGPoint(x: center.x, y: center.y - half))
                        path.addLine(to: CGPoint(x: center.x, y: center.y + half))
                        context.stroke(
                            path,
                            with: .color(decoration.color.opacity(alpha)),
                            style: StrokeStyle(lineWidth: 1.3, lineCap: .round)
                        )
                        continue
                    case .dot:
                        path.addEllipse(in: CGRect(
                            x: center.x - half,
                            y: center.y - half,
                            width: half * 2,
                            height: half * 2
                        ))
                        context.fill(path, with: .color(decoration.color.opacity(alpha)))
                        continue
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func rotate(_ point: CGPoint, angle: CGFloat) -> CGPoint {
        CGPoint(
            x: point.x * cos(angle) - point.y * sin(angle),
            y: point.x * sin(angle) + point.y * cos(angle)
        )
    }
}

/// 翻牌记分牌（对齐安卓 CampaignScoreboard：-5° 倾斜，数字 1 0 0 1）。
private struct CampaignScoreboard: View {
    var body: some View {
        ZStack {
            scoreboardCanvas
            HStack(spacing: 0) {
                flipCard("1")
                Spacer().frame(width: 3)
                flipCard("0")
                Spacer().frame(width: 10)
                flipCard("0")
                Spacer().frame(width: 3)
                flipCard("1")
            }
            .padding(.horizontal, 15)
            .padding(.top, 9)
        }
        .frame(width: 208, height: 106)
        .rotationEffect(.degrees(-5))
    }

    private func flipCard(_ value: String) -> some View {
        ZStack {
            flipCardCanvas
            Text(value)
                .font(.system(size: 37, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "FFF4DA"))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 82)
        .frame(maxWidth: .infinity)
    }

    private var scoreboardCanvas: some View {
        Canvas { context, size in
            context.fill(
                Path(ellipseIn: CGRect(x: 9, y: 97, width: 193, height: 8)),
                with: .color(Color(hex: "582B19").opacity(0.13))
            )

            var stand = Path()
            stand.move(to: CGPoint(x: 18, y: 21))
            stand.addLine(to: CGPoint(x: 190, y: 21))
            stand.addLine(to: CGPoint(x: 199, y: 98))
            stand.addLine(to: CGPoint(x: 9, y: 98))
            stand.closeSubpath()
            context.fill(
                stand,
                with: .linearGradient(
                    Gradient(colors: [ndVermilion, ndDeepRed]),
                    startPoint: CGPoint(x: 0, y: 21),
                    endPoint: CGPoint(x: 0, y: 98)
                )
            )
            context.stroke(stand, with: .color(ndBrightGold), lineWidth: 1.2)

            context.fill(
                Path(roundedRect: CGRect(x: 5, y: 96, width: 198, height: 6), cornerRadius: 2),
                with: .color(Color(hex: "76251C"))
            )
            var baseLine = Path()
            baseLine.move(to: CGPoint(x: 7, y: 96))
            baseLine.addLine(to: CGPoint(x: 201, y: 96))
            context.stroke(
                baseLine,
                with: .color(ndBrightGold),
                style: StrokeStyle(lineWidth: 1.1, lineCap: .round)
            )
        }
    }

    private var flipCardCanvas: some View {
        Canvas { context, size in
            let inset: CGFloat = 1
            let top: CGFloat = 15
            let cardHeight: CGFloat = 62
            let cardWidth = size.width - inset * 2
            let corner: CGFloat = 3

            context.fill(
                Path(roundedRect: CGRect(x: inset, y: top + 3, width: cardWidth, height: cardHeight), cornerRadius: corner),
                with: .color(Color(hex: "B8875C"))
            )
            context.fill(
                Path(roundedRect: CGRect(x: inset, y: top + 1.5, width: cardWidth, height: cardHeight), cornerRadius: corner),
                with: .color(Color(hex: "E2B77F"))
            )
            context.fill(
                Path(roundedRect: CGRect(x: inset, y: top, width: cardWidth, height: cardHeight), cornerRadius: corner),
                with: .linearGradient(
                    Gradient(colors: [Color(hex: "61372B"), Color(hex: "38211D")]),
                    startPoint: CGPoint(x: 0, y: top),
                    endPoint: CGPoint(x: 0, y: top + cardHeight)
                )
            )
            context.stroke(
                Path(roundedRect: CGRect(x: inset, y: top, width: cardWidth, height: cardHeight), cornerRadius: corner),
                with: .color(Color(hex: "BD8150")),
                lineWidth: 0.6
            )
            var highlight = Path()
            highlight.move(to: CGPoint(x: 4, y: top + 1))
            highlight.addLine(to: CGPoint(x: size.width - 4, y: top + 1))
            context.stroke(
                highlight,
                with: .color(Color(hex: "86513A")),
                lineWidth: 0.7
            )

            // 翻牌顶部的金属环
            context.fill(
                Path(ellipseIn: CGRect(x: size.width / 2 - 2.7, y: 20 - 2.7, width: 5.4, height: 5.4)),
                with: .color(Color(hex: "221815"))
            )
            let ringWidth: CGFloat = 5
            let ringHeight: CGFloat = 17
            let ringX = (size.width - ringWidth) / 2
            context.stroke(
                Path(roundedRect: CGRect(x: ringX + 0.6, y: 5, width: ringWidth, height: ringHeight), cornerRadius: ringWidth / 2),
                with: .color(Color(hex: "8B5B31")),
                lineWidth: 2.2
            )
            context.stroke(
                Path(roundedRect: CGRect(x: ringX, y: 4, width: ringWidth, height: ringHeight), cornerRadius: ringWidth / 2),
                with: .color(Color(hex: "F4CE84")),
                lineWidth: 1.3
            )
        }
    }
}
