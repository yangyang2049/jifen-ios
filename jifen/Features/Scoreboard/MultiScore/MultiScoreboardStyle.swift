import SwiftUI
import UIKit

/// Appearance is shared across orientations and kept separate from match rules and scores.
nonisolated struct MultiScoreboardStyle: Codable, Equatable, Sendable {
    enum Mode: String, Codable, CaseIterable, Sendable {
        case solid
        case colorful

        var title: String {
            NSLocalizedString("multi_score_style_\(rawValue)", comment: "Multi-player board color mode")
        }
    }

    enum SolidColor: String, Codable, CaseIterable, Sendable {
        case ink, graphite, paper, mist, forest, jade, navy, lake, violet, rose, clay, olive

        var hex: String {
            switch self {
            case .ink: return "16191D"
            case .graphite: return "434B56"
            case .paper: return "F4F3EF"
            case .mist: return "CFD9DD"
            case .forest: return "153A31"
            case .jade: return "237A67"
            case .navy: return "163853"
            case .lake: return "356CA5"
            case .violet: return "5D437F"
            case .rose: return "964858"
            case .clay: return "A05E3B"
            case .olive: return "796332"
            }
        }

        var title: String {
            NSLocalizedString("multi_score_color_\(rawValue)", comment: "Named solid scoreboard background")
        }

        var foregroundHex: String {
            let dark = "191D22"
            let light = "F7F8FA"
            return ScoreboardStyleColorMath.contrastRatio(dark, hex)
                > ScoreboardStyleColorMath.contrastRatio(light, hex) ? dark : light
        }
    }

    // Keep the existing appearance for users who have never selected a style.
    static let `default` = Self(mode: .colorful, solidColor: .ink)
    static let colorfulPalette = [
        "EF4444", "3B82F6", "22C55E", "F59E0B", "A855F7", "EC4899",
        "14B8A6", "F97316", "6366F1", "84CC16", "06B6D4", "E11D48"
    ]

    var mode: Mode
    var solidColor: SolidColor

    func backgroundHex(index: Int, theme: ScoreboardTheme) -> String {
        if mode == .solid { return solidColor.hex }
        if theme == .electronic || theme == .retro { return "000000" }
        return Self.colorfulPalette[max(0, index) % Self.colorfulPalette.count]
    }

    var foregroundHex: String { mode == .solid ? solidColor.foregroundHex : "FFFFFF" }

    /// Use existing V2 resolved panel/text colors, so receivers need no new protocol fields.
    @MainActor
    func displayStyle(appearance: ScoreboardDisplayAppearance, players: [ScoreboardDisplayPlayer]) -> ScoreboardDisplayStyle {
        var style = appearance.style ?? ScoreboardDisplayStyle(appearance: appearance)
        let theme = ScoreboardTheme(rawValue: appearance.theme) ?? .defaultTheme
        style.panels = players.enumerated().map { index, player in
            .init(slotKey: "player_\(index)", participantId: player.id,
                  backgroundColor: "#" + backgroundHex(index: index, theme: theme))
        }
        let colors = players.indices.map {
            ScoreboardDisplayStyle.TextColor(slotKey: "player_\($0)", color: "#" + foregroundHex)
        }
        style.elements = ["mainScore", "playerName", "teamName"].map {
            .init(elementKey: $0, textColors: colors)
        }
        return style
    }
}

struct MultiScoreboardStylePicker: View {
    @Binding var style: MultiScoreboardStyle
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geometry in
            AdaptiveSetupDialogLayout(maxHeight: geometry.size.height) {
                Text(NSLocalizedString("multi_score_style", comment: "Scoreboard style"))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            } content: { maxHeight in
                AdaptiveSetupDialogScrollView(maxHeight: maxHeight) {
                    VStack(spacing: Theme.md) {
                        Picker(NSLocalizedString("multi_score_style", comment: ""), selection: $style.mode) {
                            ForEach(MultiScoreboardStyle.Mode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                                    .accessibilityIdentifier("multi_score_style_mode_\(mode.rawValue)")
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("multi_score_style_modes")

                        preview

                        if style.mode == .solid {
                            Text(NSLocalizedString("style_background_color", comment: "Background color"))
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: paletteColumnCount(width: geometry.size.width)), spacing: 8) {
                                ForEach(MultiScoreboardStyle.SolidColor.allCases, id: \.self) { color in
                                    colorButton(color)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.lg)
                    .padding(.vertical, Theme.sm)
                }
            } actions: {
                Button { dismiss() } label: {
                    Text(NSLocalizedString("done", value: "完成", comment: "Done"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.textOnPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Theme.primary, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("multi_score_style_done")
                .padding(.horizontal, Theme.lg)
                .padding(.top, Theme.sm)
                .padding(.bottom, Theme.md)
                .background(Theme.dialogSurfaceBackground)
            }
        }
        .background(Theme.dialogSurfaceBackground)
        .presentationDetents([.height(620), .large])
        .presentationDragIndicator(.visible)
    }

    private func paletteColumnCount(width: CGFloat) -> Int {
        // Keep long localized words readable instead of orphaning their last letters.
        let longestWord = MultiScoreboardStyle.SolidColor.allCases
            .flatMap { $0.title.split(whereSeparator: { $0.isWhitespace || $0 == "-" }) }
            .map { (String($0) as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 12)]).width }
            .max() ?? 0
        let available = max(1, width - Theme.lg * 2)
        for count in stride(from: 4, through: 2, by: -1) {
            if (available - CGFloat(count - 1) * 6) / CGFloat(count) >= longestWord + 8 {
                return count
            }
        }
        return 2
    }

    private var preview: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
            ForEach(Array([8, 12, 6, 4, 9, 16, 7, 2, 11].enumerated()), id: \.offset) { index, score in
                Text("\(score)")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: style.foregroundHex))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(Color(hex: style.backgroundHex(index: index, theme: .defaultTheme)))
            }
        }
        .background(Color(hex: style.foregroundHex).opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(style.mode.title)
        .accessibilityIdentifier("multi_score_style_preview")
    }

    private func colorButton(_ color: MultiScoreboardStyle.SolidColor) -> some View {
        Button { style.solidColor = color } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(Color(hex: color.hex))
                    Circle().strokeBorder(Theme.textSecondary.opacity(0.25), lineWidth: 0.5)
                    if style.solidColor == color {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: color.foregroundHex))
                    }
                }
                .frame(width: 32, height: 32)
                .padding(4)
                .overlay {
                    Circle().strokeBorder(style.solidColor == color ? Theme.primary : .clear, lineWidth: 2)
                }
                Text(color.title)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.title)
        .accessibilityAddTraits(style.solidColor == color ? .isSelected : [])
        .accessibilityIdentifier("multi_score_style_color_\(color.rawValue)")
    }
}
