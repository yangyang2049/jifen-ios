import SwiftUI
import ImageIO

/// Portable JPEG payload shared by Android, HarmonyOS and display endpoints.
nonisolated struct ScoreboardBackdrop: Codable, Equatable, Sendable {
    var imageData: String? = nil
    var dim: Double = 0.30
    var panelOpacity: Double = 0.84
    /// 图片内容摘要（FNV-1a 64）。图片在一局里极少变化，投屏帧只在**变更的那一次**携带
    /// `imageData`，其余帧只带 `digest`，接收端按 digest 复用缓存——避免每个得分点重传整张图。
    var digest: String? = nil

    /// 压暗/透明度钳制与图片数据无关，渲染期可逐帧取用而不触发 base64 校验。
    var resolvedDim: Double { dim.isFinite ? min(0.8, max(0, dim)) : 0.30 }
    var resolvedPanelOpacity: Double { panelOpacity.isFinite ? min(1, max(0.15, panelOpacity)) : 0.84 }

    /// data URI 字符上限。按「最坏一帧」倒推：后端实时消息硬上限
    /// `REALTIME_MAX_PAYLOAD_BYTES` = 512KB，而每个参与者各带一份完整 displayState，
    /// 双打帧会把同一张图片复制 4 份（`RemoteSyncController.mapDisplayStateToParticipants`）。
    /// 4 × 90,000 = 360,000 字符，加上队伍/球员/sportState 等字段仍有充裕余量；
    /// 4 × 200,000 = 800,000 会直接超帧，服务端 `ws` 以 1009 关闭连接（投屏整条断掉）。
    /// 与安卓 `SCOREBOARD_BACKGROUND_MAX_DATA_LENGTH`、鸿蒙 `scoreboardStyle.ts` 同为 90,000。
    static let imageDataCharacterLimit = 90_000

    /// 只做「合法性 + 钳制」，**不写 digest**：解码侧不得凭空造值，
    /// 否则同一份 profile 往返后不再相等。digest 只在投屏编码/发送路径计算。
    func normalized() -> Self {
        var value = self
        if let imageData {
            let prefix = "data:image/jpeg;base64,"
            let body = imageData.hasPrefix(prefix) ? imageData.dropFirst(prefix.count) : ""
            if imageData.count > Self.imageDataCharacterLimit || !Self.isBase64Body(body) {
                value.imageData = nil
                value.digest = nil
            }
        } else if let digest, !Self.isDigest(digest) {
            value.digest = nil
        }
        value.dim = resolvedDim
        value.panelOpacity = resolvedPanelOpacity
        return value
    }

    /// 投屏链路的图片摘要：始终由当前图片内容算出；无图时为 nil。
    var contentDigest: String? {
        imageData.map(Self.digest(of:))
    }

    /// digest 是传输层派生信息（图片内容相同的两个 backdrop 语义等价），
    /// 不参与相等判断，否则「本地构造」与「线上解码」的同一张图会被判为不同。
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.imageData == rhs.imageData && lhs.dim == rhs.dim && lhs.panelOpacity == rhs.panelOpacity
    }

    /// FNV-1a 64 位内容摘要（16 位小写十六进制）。
    /// 用无分配的 UTF-8 遍历，避免为 80KB 字符串再复制一份字节数组。
    static func digest(of imageData: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in imageData.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        var hex = String(hash, radix: 16, uppercase: false)
        if hex.count < 16 { hex = String(repeating: "0", count: 16 - hex.count) + hex }
        return hex
    }

    private static func isDigest(_ value: String) -> Bool {
        value.count == 16 && value.allSatisfy { $0.isHexDigit }
    }

    /// base64 结构校验：只检查字符集与填充，不分配解码后的字节数组，
    /// 因此可以安全地留在 Slider 拖动等每帧刷新的路径上。
    private static func isBase64Body(_ body: Substring) -> Bool {
        guard !body.isEmpty, body.count % 4 == 0 else { return false }
        var padding = 0
        for character in body {
            if character == "=" {
                padding += 1
                guard padding <= 2 else { return false }
            } else {
                guard padding == 0, character.isASCII,
                      character.isLetter || character.isNumber || character == "+" || character == "/" else { return false }
            }
        }
        return true
    }

    var image: UIImage? {
        guard let data = normalized().imageData?.split(separator: ",", maxSplits: 1).last,
              let bytes = Data(base64Encoded: String(data)) else { return nil }
        return Self.downsample(bytes, maximumPixel: 2048, rejectOversize: true)
    }

    static func downsample(_ bytes: Data, maximumPixel: Int = 1280, rejectOversize: Bool = false) -> UIImage? {
        guard bytes.count <= 12 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, !rejectOversize || (width <= 2048 && height <= 2048),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixel,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    /// Downsample before encoding, keeping projection messages below the shared limit.
    static func jpegDataURL(_ image: UIImage) -> String? {
        for edge in [1024.0, 800, 640, 480, 320] {
            let ratio = min(1, edge / max(image.size.width, image.size.height))
            let size = CGSize(width: max(1, image.size.width * ratio), height: max(1, image.size.height * ratio))
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let reduced = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            for quality in [0.82, 0.65, 0.48, 0.32] {
                guard let bytes = reduced.jpegData(compressionQuality: quality) else { continue }
                let source = "data:image/jpeg;base64," + bytes.base64EncodedString()
                if bytes.count <= 60 * 1024 { return source }
            }
        }
        return nil
    }
}

/// 显示端按 `digest` 缓存最近收到过的背景图。
/// 发送端只在图片变更的那一帧携带 `imageData`，其余帧只带 `digest`；
/// 显示端据此复用缓存，既省带宽，又保证晚加入/短暂丢帧后仍能还原背景。
nonisolated final class ScoreboardBackdropImageCache: @unchecked Sendable {
    static let shared = ScoreboardBackdropImageCache()

    private let lock = NSLock()
    private var images: [String: String] = [:]
    private var recency: [String] = []
    /// 一局里最多只会有「当前图 + 撤销用的上一张」，留 4 个足够，也限制常驻内存。
    private let capacity = 4

    private init() {}

    func store(_ imageData: String, for digest: String) {
        guard !imageData.isEmpty, !digest.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        images[digest] = imageData
        recency.removeAll { $0 == digest }
        recency.append(digest)
        while recency.count > capacity {
            images[recency.removeFirst()] = nil
        }
    }

    func image(for digest: String) -> String? {
        guard !digest.isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        guard let imageData = images[digest] else { return nil }
        recency.removeAll { $0 == digest }
        recency.append(digest)
        return imageData
    }

    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        images.removeAll(); recency.removeAll()
    }
}

/// Undo replaces the image only, so intervening appearance adjustments remain intact.
struct ScoreboardPhotoImageUndo: Hashable {
    let imageData: String
    let deadline: Date

    init(imageData: String, now: Date = .now) {
        self.imageData = imageData
        self.deadline = now.addingTimeInterval(5)
    }

    func restoring(_ current: ScoreboardBackdrop, now: Date = .now) -> ScoreboardBackdrop? {
        guard now < deadline else { return nil }
        var restored = current
        restored.imageData = imageData
        return restored
    }
}

nonisolated enum ScoreboardNameFont {
    static func normalized(_ code: String?) -> String? {
        guard let code else { return nil }
        if code == "harmony_digit" { return "digital" }
        return ["default", "rounded", "serif", "digital", "seven_segment", "teko"].contains(code) ? code : nil
    }
    static func font(code: String?, inherited: ScoreboardFont, size: CGFloat, weight: Font.Weight = .bold) -> Font {
        switch normalized(code) {
        case "default": return .system(size: size, weight: weight)
        case "rounded": return .system(size: size, weight: weight, design: .rounded)
        case "serif": return .system(size: size, weight: weight, design: .serif)
        case .some(let value): return (ScoreboardFont(displayCode: value) ?? inherited).swiftUIFont(size: size, weight: weight)
        case nil: return inherited.swiftUIFont(size: size, weight: weight)
        }
    }
}

enum ScoreboardPhotoProjects {
    static let supported: Set<String> = [
        "pingpong", "pingpong_doubles", "badminton", "badminton_doubles",
        "volleyball", "air_volleyball", "beach_volleyball", "squash", "shuttlecock",
        "billiards", "football", "football_5v5", "simple_score"
    ]
    private static let withoutSets: Set<String> = ["billiards", "football", "football_5v5", "simple_score"]

    static func showsSets(_ game: String) -> Bool { !withoutSets.contains(game) }
    static func showsServer(_ game: String) -> Bool { showsSets(game) && game != "shuttlecock" }
    static func isDoubles(_ game: String) -> Bool { game == "pingpong_doubles" || game == "badminton_doubles" }

    static func artwork(_ game: String) -> String {
        switch game {
        case "badminton", "badminton_doubles": return "scoreboard_event_background_badminton"
        case "volleyball", "air_volleyball": return "scoreboard_event_background_volleyball"
        case "football", "football_5v5": return "scoreboard_event_background_football"
        case "simple_score": return "scoreboard_event_background_simple"
        case "beach_volleyball", "squash", "shuttlecock", "billiards":
            return "scoreboard_event_background_\(game)"
        default: return "scoreboard_event_background"
        }
    }
}

extension ScoreboardStyleProfileV2 {
    static func supportsPhotoTheme(_ styleID: ScoreboardStyleID) -> Bool {
        ScoreboardPhotoProjects.supported.contains(styleID.rawValue)
    }
    var isPhotoTheme: Bool { themeCode == "event_background" }
    static func photoTheme(for styleID: ScoreboardStyleID) -> Self {
        var profile = Self.default(for: styleID)
        profile.themeCode = "event_background"
        profile = profile.withPanelBackground("C62828", for: .sideLeft).withPanelBackground("007AFF", for: .sideRight)
        profile.backdrop = ScoreboardBackdrop()
        return profile
    }
}

struct ScoreboardPhotoTitleField: View {
    @Binding var title: String

    var body: some View {
        TextField("", text: $title, prompt: Text("match_title_placeholder").foregroundStyle(.black.opacity(0.55)))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 360)
            .padding(.horizontal, 64)
            .accessibilityIdentifier("scoreboard_match_title_input")
            .onChange(of: title) { _, value in title = ScoreboardMatchTitlePolicy.limitInput(value) }
    }
}

struct ScoreboardPhotoBackground: View {
    let backdrop: ScoreboardBackdrop
    var gameType: String = "pingpong"
    @State private var decodedImage: UIImage?
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image = decodedImage { Image(uiImage: image).resizable() }
                else { Image(ScoreboardPhotoProjects.artwork(gameType)).resizable() }
            }
            .scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
            .overlay(Color.black.opacity(backdrop.resolvedDim))
        }
        .allowsHitTesting(false)
        .task(id: backdrop.imageData) {
            // ImageIO 解码与降采样放到主线程之外，避免大图在首帧或缩略图刷新时卡住界面。
            let source = backdrop
            let image = await Task.detached(priority: .userInitiated) { source.image }.value
            guard !Task.isCancelled else { return }
            decodedImage = image
        }
    }
}

/// Shared photo-theme scene: phone and projection use the same proportions and image crop.
struct ScoreboardPhotoScene: View {
    struct Team {
        var name: String
        var score: String
        var sets: String
        var color: Color
        var nameColor: Color = .white
        var scoreColor: Color = .white
        var setsColor: Color = .white
        var markers: TableTennisAdministrativeMarkerStatus = .init(timeoutUsed: false, hasYellowCard: false, redCardCount: 0)
        var badgeKind: String? = nil
    }
    let left: Team
    let right: Team
    var title: String? = nil
    let backdrop: ScoreboardBackdrop
    var servingLeft: Bool? = nil
    var servingColor: Color = Color(hex: "30D158")
    var indicatorStyle: String = "arrow"
    var gameType: String = "pingpong"
    var clock: ScoreboardDisplayClock? = nil
    var clockControls: AnyView? = nil
    var onTap: ((Bool) -> Void)? = nil
    var onSubtract: ((Bool) -> Void)? = nil
    var onUndo: (() -> Void)? = nil
    var touchGuard = false
    var allowsSwipeScoring = true

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let portrait = size.height > size.width
            let hasTitle = !(title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let top = size.height * (hasTitle ? 0.18 : 0.10)
            let bottom = size.height * (hasTitle ? 0.06 : 0.10)
            let gap = portrait ? size.height * 0.105 : size.width * 0.12
            ZStack {
                ScoreboardPhotoBackground(backdrop: backdrop, gameType: gameType)
                VStack(spacing: 0) {
                    if let clockControls {
                        clockControls.fixedSize(horizontal: false, vertical: true).padding(.bottom, 6)
                    }
                    if hasTitle {
                        Text(title ?? "").font(.system(size: min(48, max(18, size.width * (portrait ? 0.055 : 0.032))), weight: .bold))
                            .lineLimit(2).minimumScaleFactor(0.5).multilineTextAlignment(.center)
                            .frame(width: size.width * 0.84, height: top)
                    } else {
                        Spacer().frame(height: top)
                    }
                    Group {
                        if portrait {
                            VStack(spacing: 0) {
                                card(left, isLeft: true)
                                center(portrait: true, gap: gap, size: size).frame(height: gap)
                                card(right, isLeft: false)
                            }
                        } else {
                            HStack(spacing: 0) {
                                card(left, isLeft: true)
                                center(portrait: false, gap: gap, size: size).frame(width: gap)
                                card(right, isLeft: false)
                            }
                        }
                    }
                    .padding(.horizontal, size.width * 0.055).padding(.bottom, bottom)
                }
            }.foregroundStyle(.white)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("event_background_scoreboard")
    }

    private func center(portrait: Bool, gap: CGFloat, size: CGSize) -> some View {
        let indicatorSize = min(max(30, min(size.width, size.height) * 0.11), min(72, gap * 0.38))
        return ZStack {
            if let clock {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let ms = clock.projectedMilliseconds(atWallClockMilliseconds: Int64(context.date.timeIntervalSince1970 * 1000))
                    Text(ScoreboardMatchClockSession.formatElapsed(Double(ms) / 1_000))
                        .font(.system(size: 18, weight: .semibold, design: .monospaced)).minimumScaleFactor(0.5).lineLimit(1)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: portrait ? .leading : .top)
            }
            if let servingLeft, ScoreboardPhotoProjects.showsServer(gameType) {
                ScoreboardServeSymbol(direction: portrait ? (servingLeft ? .top : .bottom) : (servingLeft ? .left : .right),
                    size: indicatorSize, color: servingColor, styleCode: indicatorStyle, gameType: gameType)
                    .offset(x: portrait ? gap * 0.28 : (servingLeft ? -1 : 1) * gap * 0.29,
                            y: portrait ? (servingLeft ? -1 : 1) * gap * 0.29 : 0)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func card(_ team: Team, isLeft: Bool) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let nameHeight = size.height * 0.18
            let showsSets = ScoreboardPhotoProjects.showsSets(gameType)
            let scoreHeight = showsSets ? size.height * 0.60 : size.height - nameHeight
            let dividerHeight = min(1, size.height * 0.01)
            let setsHeight = max(0, size.height - nameHeight - scoreHeight - dividerHeight)
            VStack(spacing: 0) {
                Text(team.name).font(.system(size: min(min(52, max(18, size.width * 0.085)), nameHeight * 0.72), weight: .semibold))
                    .foregroundStyle(team.nameColor)
                    .lineLimit(2).minimumScaleFactor(0.5).multilineTextAlignment(.center)
                    .frame(height: nameHeight).frame(maxWidth: .infinity).clipped()
                Text(team.score).font(.system(size: min(size.width * 0.68, scoreHeight * 0.82), weight: .bold))
                    .foregroundStyle(team.scoreColor)
                    .lineLimit(1).minimumScaleFactor(0.1).frame(height: scoreHeight).frame(maxWidth: .infinity).clipped()
                    .overlay(alignment: isLeft ? .topTrailing : .topLeading) {
                        if let kind = team.badgeKind { photoKeyPointBadge(kind: kind, maxWidth: size.width * 0.35).padding(4) }
                    }
                    .contentShape(Rectangle()).modifier(ScoreboardPhotoTapSurface(active: touchGuard) { onTap?(isLeft) })
                if showsSets {
                    Divider().frame(height: dividerHeight).overlay(.white.opacity(0.24))
                    Text(team.sets).font(.system(size: min(104, setsHeight * 0.82), weight: .bold))
                        .foregroundStyle(team.setsColor)
                        .lineLimit(1).minimumScaleFactor(0.1)
                        .frame(height: setsHeight).frame(maxWidth: .infinity)
                        .overlay { TableTennisAdministrativeCards(status: team.markers, alignment: isLeft ? .trailing : .leading, scale: 0.85).padding(.horizontal, 6) }
                        .clipped()
                }
            }
            .padding(.horizontal, 10).frame(width: size.width, height: size.height)
            .background(team.color.opacity(backdrop.resolvedPanelOpacity), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.2), lineWidth: 1))
            .contentShape(Rectangle()).modifier(ScoreboardPhotoTapSurface(active: !touchGuard) { onTap?(isLeft) })
            .gesture(DragGesture(minimumDistance: 50).onEnded { value in
                guard allowsSwipeScoring, allowsGesture(startingAt: value.startLocation, in: size) else { return }
                if value.translation.width < -50 && abs(value.translation.height) < 50 { onUndo?() }
                else if value.translation.height < -50 && abs(value.translation.width) < 50 { onTap?(isLeft) }
                else if value.translation.height > 50 && abs(value.translation.width) < 50 { onSubtract?(isLeft) }
            })
        }
    }

    /// 防误触开启时只有落在大分区域（卡片中部 60% 高度）的手势才结算，
    /// 与卡片单击守卫保持同一判据，撤销/减分滑动同样受约束。
    private func allowsGesture(startingAt location: CGPoint, in size: CGSize) -> Bool {
        guard touchGuard else { return true }
        let scoreBottom: CGFloat = ScoreboardPhotoProjects.showsSets(gameType) ? 0.78 : 1
        return location.y >= size.height * 0.18 && location.y <= size.height * scoreBottom
    }

    private func photoKeyPointBadge(kind: String, maxWidth: CGFloat) -> some View {
        let label = ScoreboardKeyPointBadgePresentation.label(kind: kind, gameType: gameType)
        let naturalWidth = (label as NSString).size(withAttributes: [.font: UIFont.boldSystemFont(ofSize: 11)]).width + 12
        return Text(label).font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: "111111"))
            .lineLimit(1).minimumScaleFactor(0.3)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .frame(width: min(maxWidth, naturalWidth), height: 18)
            .background(ScoreboardKeyPointBadgePresentation.background(kind: kind, gameType: gameType),
                in: RoundedRectangle(cornerRadius: 4))
    }
}

/// 按条件**挂载**单击手势：未激活时完全不附加手势，避免内层手势吞掉外层的卡片单击。
private struct ScoreboardPhotoTapSurface: ViewModifier {
    let active: Bool
    let action: () -> Void

    @ViewBuilder func body(content: Content) -> some View {
        if active { content.onTapGesture(perform: action) } else { content }
    }
}

/// Keeps Android logical-team frames and legacy iOS visual-order frames equivalent.
enum ScoreboardPhotoProjection {
    private static func boolValue(_ value: ScoreboardDisplayValue?) -> Bool? {
        if case .boolean(let result) = value { return result }; return nil
    }
    static func team(_ state: ScoreboardDisplayState, visualIndex: Int) -> ScoreboardPhotoScene.Team {
        let logical0 = (state.sportString("team0ScreenSide") == "right") != (visualIndex == 0)
        let id = logical0 ? "team_0" : "team_1"
        let team = state.teams.first { $0.id == id }
        let roster = state.players?.filter { $0.teamID == id }.sorted { $0.order < $1.order } ?? []
        let name = roster.isEmpty ? (team?.name ?? "") : roster.map(\.name).joined(separator: " / ")
        let slot = visualIndex == 0 ? "side_left" : "side_right"
        let prefix = logical0 ? "tableTennisTeam0" : "tableTennisTeam1"
        let style = state.appearance.style
        let nameKey = ScoreboardPhotoProjects.isDoubles(state.gameType) ? "playerName" : "teamName"
        let setsKey = ScoreboardPhotoProjects.isDoubles(state.gameType) ? "setGameScore" : "setScore"
        let score = state.sportString(visualIndex == 0 ? "leftDisplayScore" : "rightDisplayScore") ?? "\(team?.score ?? 0)"
        let badge = state.result?.ended != true && state.keyPoint?.side == (visualIndex == 0 ? "left" : "right") ? state.keyPoint?.kind : nil
        return .init(name: name, score: score, sets: "\(team?.sets ?? 0)",
            color: Color(hex: style?.panelColor(slot: slot) ?? (visualIndex == 0 ? state.appearance.leftPanelHex : state.appearance.rightPanelHex)),
            nameColor: Color(hex: style?.renderColor(nameKey, slot: slot) ?? "FFFFFF"),
            scoreColor: Color(hex: style?.renderColor("mainScore", slot: slot) ?? "FFFFFF"),
            setsColor: Color(hex: style?.renderColor(setsKey, slot: slot) ?? "FFFFFF"),
            markers: .init(timeoutUsed: boolValue(state.sportState?["\(prefix)TimeoutUsed"]) ?? false,
                hasYellowCard: boolValue(state.sportState?["\(prefix)Yellow"]) ?? false, redCardCount: state.sportInt("\(prefix)RedCount") ?? 0),
            badgeKind: badge)
    }

    static func servingLeft(_ state: ScoreboardDisplayState) -> Bool? {
        guard state.appearance.style?.serverIndicatorHidden != true, state.result?.ended != true else { return nil }
        if let side = state.sportString("servingSide") { return side == "left" }
        let server = state.sportString("servingTeam")
            ?? state.players?.first(where: { $0.isServer == true })?.teamID
        guard let server else { return nil }
        let logical0: Bool
        if ["team_0", "0", "team0"].contains(server) { logical0 = true }
        else if ["team_1", "1", "team1"].contains(server) { logical0 = false }
        else { return nil }
        return logical0 != (state.sportString("team0ScreenSide") == "right")
    }
}
