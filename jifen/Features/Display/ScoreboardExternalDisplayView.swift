import SwiftUI

enum ScoreboardExternalTemplate: String, Equatable {
    case twoSide
    case doublesCourt
    case multiGrid
    case cardTwoTeam
    case cardThreePlayer
    case cardTwoSeat
    case trainingCounter

    static func resolve(state: ScoreboardDisplayState) -> Self {
        switch state.layoutKind {
        case .twoSide: return .twoSide
        case .doublesCourt: return .doublesCourt
        case .multiGrid: return .multiGrid
        case .trainingCounter: return .trainingCounter
        case .boardCard:
            switch state.gameType {
            case "guandan", "shengji": return .cardTwoTeam
            case "doudizhu": return .cardThreePlayer
            case "xiangqi", "go", "chess", "checkers": return .cardTwoSeat
            default: return (state.players?.count ?? 0) >= 3 ? .cardThreePlayer : .cardTwoTeam
            }
        }
    }
}

struct ScoreboardExternalDisplayRootView: View {
    @ObservedObject private var outputs = ScoreboardDisplayOutputs.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let state = outputs.displayState {
                ScoreboardExternalLiveView(state: state)
                    .id("\(state.gameType)-\(state.layoutKind.rawValue)")
            } else {
                ScoreboardExternalWaitingView()
            }

            if outputs.controllerAway, outputs.displayState != nil {
                controllerAwayOverlay
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("external_display_root")
    }

    private var controllerAwayOverlay: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "iphone.slash")
                Text(NSLocalizedString("cast_controller_away", value: "控制端暂离", comment: ""))
                    .fontWeight(.semibold)
            }
            .font(.system(size: 24))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(.black.opacity(0.72), in: Capsule())
            .padding(.top, 24)
            Spacer()
        }
    }
}

private struct ScoreboardExternalWaitingView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            GeometryReader { proxy in
                let scale = max(0.85, min(1.8, proxy.size.width / 1280))
                VStack(spacing: 18 * scale) {
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: 74 * scale, weight: .light))
                        .foregroundStyle(Color(hex: "30D158"))
                    Text(NSLocalizedString("cast_ready_title", value: "投屏已就绪", comment: ""))
                        .font(.system(size: 42 * scale, weight: .bold))
                    Text(NSLocalizedString("cast_ready_message", value: "请在控制端打开一个计分板", comment: ""))
                        .font(.system(size: 24 * scale, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                    VStack(spacing: 2) {
                        Text(context.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 58 * scale, weight: .medium, design: .monospaced))
                        Text(context.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 20 * scale, weight: .medium))
                            .foregroundStyle(.white.opacity(0.54))
                    }
                    .padding(.top, 18 * scale)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hex: "071017"))
            }
        }
        .accessibilityIdentifier("external_display_waiting")
    }
}

private struct ScoreboardExternalLiveView: View {
    let state: ScoreboardDisplayState

    private var template: ScoreboardExternalTemplate {
        .resolve(state: state)
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = ScoreboardExternalMetrics(size: proxy.size)
            ZStack {
                Color(hex: state.appearance.backgroundHex)
                templateBody(metrics: metrics)

                VStack(spacing: metrics.smallGap) {
                    if let title = state.matchTitle, !title.isEmpty {
                        Text(title)
                            .font(displayFont(size: metrics.title, weight: .semibold))
                            .foregroundStyle(Color(hex: state.appearance.foregroundHex))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, metrics.padding)
                            .padding(.vertical, metrics.smallGap)
                            .background(.black.opacity(0.24), in: Capsule())
                    }
                    if let clock = state.clock, clock.visible {
                        ScoreboardExternalClockView(clock: clock, font: displayFont(size: metrics.secondaryScore))
                    }
                    if let shotClock = state.sportInt("shotClock") {
                        Text(String(format: NSLocalizedString("cast_shot_clock_format", value: "进攻 %d", comment: ""), shotClock))
                            .font(displayFont(size: metrics.detail, weight: .semibold))
                            .foregroundStyle(shotClock <= 5 ? Color.red : Color.white)
                            .padding(.horizontal, metrics.smallGap)
                            .padding(.vertical, metrics.smallGap * 0.45)
                            .background(.black.opacity(0.42), in: Capsule())
                    }
                    Spacer()
                }
                .padding(.top, metrics.smallGap)

                if let rest = state.rest {
                    ScoreboardExternalRestOverlay(rest: rest, metrics: metrics)
                }
                if state.result?.ended == true {
                    resultOverlay(metrics: metrics)
                }
            }
            .clipped()
        }
        .accessibilityIdentifier("external_display_live_\(state.layoutKind.rawValue)")
    }

    @ViewBuilder
    private func templateBody(metrics: ScoreboardExternalMetrics) -> some View {
        switch template {
        case .twoSide, .cardTwoTeam:
            twoSideLayout(metrics: metrics, cardStyle: template == .cardTwoTeam)
        case .doublesCourt:
            doublesLayout(metrics: metrics)
        case .multiGrid:
            multiGridLayout(metrics: metrics, cardStyle: false)
        case .cardThreePlayer:
            multiGridLayout(metrics: metrics, cardStyle: true)
        case .cardTwoSeat:
            twoSeatLayout(metrics: metrics)
        case .trainingCounter:
            trainingLayout(metrics: metrics)
        }
    }

    private func twoSideLayout(metrics: ScoreboardExternalMetrics, cardStyle: Bool) -> some View {
        HStack(spacing: 0) {
            sidePanel(index: 0, metrics: metrics, cardStyle: cardStyle)
            sidePanel(index: 1, metrics: metrics, cardStyle: cardStyle)
        }
    }

    private func sidePanel(index: Int, metrics: ScoreboardExternalMetrics, cardStyle: Bool) -> some View {
        let team = state.teams.indices.contains(index)
            ? state.teams[index]
            : ScoreboardDisplayTeam(id: "team_\(index)", name: "", score: 0, order: index)
        let isLeft = index == 0
        let panel = isLeft ? state.appearance.leftPanelHex : state.appearance.rightPanelHex
        let text = isLeft ? state.appearance.leftTextHex : state.appearance.rightTextHex
        return VStack(spacing: metrics.gap) {
            Spacer(minLength: metrics.title * 1.5)
            Text(team.name)
                .font(displayFont(size: metrics.name, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .padding(.horizontal, metrics.padding)
            Text(state.displayScore(forVisualIndex: index))
                .font(displayFont(size: cardStyle ? metrics.cardScore : metrics.score))
                .lineLimit(1)
                .minimumScaleFactor(0.32)
                .contentTransition(.numericText())
            if let detail = state.detail(forVisualIndex: index), !detail.isEmpty {
                Text(detail)
                    .font(displayFont(size: metrics.detail, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(hex: text).opacity(0.78))
            }
            keyPointBadge(side: isLeft ? "left" : "right", metrics: metrics)
            Spacer()
        }
        .foregroundStyle(Color(hex: text))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: team.color ?? panel))
    }

    private func doublesLayout(metrics: ScoreboardExternalMetrics) -> some View {
        HStack(spacing: 0) {
            doublesTeam(index: 0, metrics: metrics)
            doublesTeam(index: 1, metrics: metrics)
        }
    }

    private func doublesTeam(index: Int, metrics: ScoreboardExternalMetrics) -> some View {
        let team = state.teams.indices.contains(index)
            ? state.teams[index]
            : ScoreboardDisplayTeam(id: "team_\(index)", name: "", score: 0, order: index)
        let players = state.players?.filter { $0.teamID == team.id }.sorted { $0.order < $1.order } ?? []
        let names = players.isEmpty
            ? team.name.components(separatedBy: CharacterSet(charactersIn: "/、&"))
            : players.map(\.name)
        let panel = index == 0 ? state.appearance.leftPanelHex : state.appearance.rightPanelHex
        let text = index == 0 ? state.appearance.leftTextHex : state.appearance.rightTextHex
        return VStack(spacing: 0) {
            doublesPlayerName(names.first ?? team.name, server: players.first?.isServer == true, metrics: metrics)
            Divider().overlay(Color(hex: text).opacity(0.2))
            Text(state.displayScore(forVisualIndex: index))
                .font(displayFont(size: metrics.doublesScore))
                .minimumScaleFactor(0.35)
                .lineLimit(1)
                .frame(maxHeight: .infinity)
            if let detail = state.detail(forVisualIndex: index) {
                Text(detail)
                    .font(displayFont(size: metrics.detail, weight: .semibold))
                    .foregroundStyle(Color(hex: text).opacity(0.76))
                    .padding(.bottom, metrics.smallGap)
            }
            Divider().overlay(Color(hex: text).opacity(0.2))
            doublesPlayerName(names.dropFirst().first ?? team.name, server: players.dropFirst().first?.isServer == true, metrics: metrics)
        }
        .foregroundStyle(Color(hex: text))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: team.color ?? panel))
        .overlay(alignment: index == 0 ? .leading : .trailing) {
            keyPointBadge(side: index == 0 ? "left" : "right", metrics: metrics)
                .padding(.horizontal, metrics.smallGap)
        }
    }

    private func doublesPlayerName(_ name: String, server: Bool, metrics: ScoreboardExternalMetrics) -> some View {
        HStack(spacing: metrics.smallGap) {
            if server {
                Circle().fill(Color(hex: "30D158")).frame(width: metrics.detail * 0.45, height: metrics.detail * 0.45)
            }
            Text(name)
                .font(displayFont(size: metrics.name, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.45)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, metrics.padding)
    }

    private func multiGridLayout(metrics: ScoreboardExternalMetrics, cardStyle: Bool) -> some View {
        let players = resolvedPlayers
        let requestedColumns = state.sportInt("multiGridColumns")
        let columns = requestedColumns ?? (cardStyle ? 3 : (players.count <= 4 ? 2 : 3))
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: max(1, columns)),
            spacing: 0
        ) {
            ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                let slot = colorSlot(index: index)
                VStack(spacing: metrics.gap) {
                    Text(player.name)
                        .font(displayFont(size: metrics.name, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                    Text("\(player.score ?? 0)")
                        .font(displayFont(size: cardStyle ? metrics.cardScore : metrics.multiScore))
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                    if let rank = player.rank {
                        Text("#\(rank)")
                            .font(displayFont(size: metrics.detail, weight: .semibold))
                            .opacity(0.72)
                    }
                }
                .foregroundStyle(Color(hex: slot.text))
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .background(Color(hex: player.color ?? slot.panel))
            }
        }
        .padding(.top, metrics.title * 1.5)
    }

    private func twoSeatLayout(metrics: ScoreboardExternalMetrics) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<2, id: \.self) { index in
                let team = state.teams.indices.contains(index)
                    ? state.teams[index]
                    : ScoreboardDisplayTeam(id: "seat_\(index)", name: "", score: 0, order: index)
                let isLeft = index == 0
                VStack(spacing: metrics.gap) {
                    Text(team.name)
                        .font(displayFont(size: metrics.name, weight: .semibold))
                        .lineLimit(1)
                    Text(state.sportString(isLeft ? "leftClock" : "rightClock") ?? state.displayScore(forVisualIndex: index))
                        .font(displayFont(size: metrics.clock))
                        .minimumScaleFactor(0.3)
                        .lineLimit(1)
                    if state.sportString("activeSide") == (isLeft ? "left" : "right") {
                        Label(NSLocalizedString("cast_active_player", value: "计时中", comment: ""), systemImage: "play.fill")
                            .font(displayFont(size: metrics.detail, weight: .semibold))
                    }
                }
                .foregroundStyle(Color(hex: isLeft ? state.appearance.leftTextHex : state.appearance.rightTextHex))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hex: isLeft ? state.appearance.leftPanelHex : state.appearance.rightPanelHex))
            }
        }
    }

    private func trainingLayout(metrics: ScoreboardExternalMetrics) -> some View {
        VStack(spacing: metrics.gap) {
            Text(state.teams.first?.name ?? state.matchTitle ?? "")
                .font(displayFont(size: metrics.name, weight: .semibold))
            Text(state.displayScore(forVisualIndex: 0))
                .font(displayFont(size: metrics.score * 1.15))
                .minimumScaleFactor(0.3)
                .lineLimit(1)
        }
        .foregroundStyle(Color(hex: state.appearance.centerTextHex))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: state.appearance.centerPanelHex))
    }

    private var resolvedPlayers: [ScoreboardDisplayPlayer] {
        if let players = state.players, !players.isEmpty { return players.sorted { $0.order < $1.order } }
        return state.teams.map {
            ScoreboardDisplayPlayer(id: $0.id, name: $0.name, score: $0.score, order: $0.order, color: $0.color)
        }
    }

    private func colorSlot(index: Int) -> (panel: String, text: String) {
        switch index % 3 {
        case 0: (state.appearance.leftPanelHex, state.appearance.leftTextHex)
        case 1: (state.appearance.centerPanelHex, state.appearance.centerTextHex)
        default: (state.appearance.rightPanelHex, state.appearance.rightTextHex)
        }
    }

    @ViewBuilder
    private func keyPointBadge(side: String, metrics: ScoreboardExternalMetrics) -> some View {
        if state.keyPoint?.side == side, let kind = state.keyPoint?.kind {
            Text(keyPointTitle(kind))
                .font(displayFont(size: metrics.detail * 0.8, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, metrics.smallGap)
                .padding(.vertical, metrics.smallGap * 0.55)
                .background(.black.opacity(0.52), in: Capsule())
        }
    }

    private func keyPointTitle(_ kind: String) -> String {
        switch kind {
        case "game": NSLocalizedString("key_point_game", value: "局点", comment: "")
        case "set": NSLocalizedString("key_point_set", value: "盘点", comment: "")
        case "match": NSLocalizedString("key_point_match", value: "赛点", comment: "")
        default: kind
        }
    }

    private func resultOverlay(metrics: ScoreboardExternalMetrics) -> some View {
        let winnerID = state.result?.winnerID
        let winnerName = state.teams.first(where: { $0.id == winnerID })?.name
        return VStack(spacing: metrics.smallGap) {
            Text(NSLocalizedString("cast_match_finished", value: "比赛结束", comment: ""))
                .font(displayFont(size: metrics.title, weight: .bold))
            Text(winnerName.map {
                String(format: NSLocalizedString("cast_winner_format", value: "%@ 获胜", comment: ""), $0)
            } ?? NSLocalizedString("cast_result_draw", value: "比赛结果已确认", comment: ""))
                .font(displayFont(size: metrics.detail, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, metrics.padding * 1.6)
        .padding(.vertical, metrics.padding)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: metrics.smallGap * 1.5))
        .shadow(color: .black.opacity(0.4), radius: 24)
    }

    private func displayFont(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        (ScoreboardFont(rawValue: state.appearance.fontCode) ?? .default)
            .swiftUIFont(size: size, weight: weight)
    }
}

private struct ScoreboardExternalClockView: View {
    let clock: ScoreboardDisplayClock
    let font: Font

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 10) {
                if let label = clock.label, !label.isEmpty {
                    Text(label).fontWeight(.semibold).opacity(0.72)
                }
                Text(formatted(clock.projectedMilliseconds(
                    atWallClockMilliseconds: Int64(context.date.timeIntervalSince1970 * 1_000)
                )))
                    .monospacedDigit()
            }
            .font(font)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(.black.opacity(0.42), in: Capsule())
        }
    }

    private func formatted(_ milliseconds: Int64) -> String {
        let total = max(0, milliseconds / 1_000)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct ScoreboardExternalRestOverlay: View {
    let rest: ScoreboardDisplayRest
    let metrics: ScoreboardExternalMetrics

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = rest.projectedRemainingSeconds(
                atWallClockMilliseconds: Int64(context.date.timeIntervalSince1970 * 1_000)
            )
            VStack(spacing: metrics.smallGap) {
                Text(NSLocalizedString("cast_official_break", value: "比赛休息", comment: ""))
                    .font(.system(size: metrics.title, weight: .bold))
                Text("\(remaining)")
                    .font(.system(size: metrics.score * 0.55, weight: .bold, design: .monospaced))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(.white)
            .padding(metrics.padding * 1.5)
            .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: metrics.gap))
        }
    }

}

private struct ScoreboardExternalMetrics {
    let size: CGSize

    private var scale: CGFloat { max(0.72, min(2.4, min(size.width / 1280, size.height / 720))) }
    var padding: CGFloat { 30 * scale }
    var gap: CGFloat { 18 * scale }
    var smallGap: CGFloat { 10 * scale }
    var title: CGFloat { 32 * scale }
    var name: CGFloat { 42 * scale }
    var score: CGFloat { 210 * scale }
    var doublesScore: CGFloat { 150 * scale }
    var multiScore: CGFloat { 112 * scale }
    var cardScore: CGFloat { 142 * scale }
    var clock: CGFloat { 112 * scale }
    var secondaryScore: CGFloat { 34 * scale }
    var detail: CGFloat { 30 * scale }
}
