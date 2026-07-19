import SwiftUI

struct UnfinishedGameBarView: View {
    let record: ScoreboardRecord
    var onContinue: () -> Void
    var onClose: () -> Void

    private let barPadding: CGFloat = 8
    private let closeButtonGap: CGFloat = 12
    private let iconSize: CGFloat = 52

    private var barHeight: CGFloat {
        barPadding + iconSize + barPadding
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(record.gameType.icon)
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .frame(width: iconSize, height: iconSize)
                    .background(iconBackgroundColor)
                    .clipShape(Circle())
                    .padding(.trailing, 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayScore)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(Theme.homeNeutralCardTextPrimary)
                        .lineLimit(1)

                    Text("\(record.team1Name)\(NSLocalizedString("vs_separator", value: " vs ", comment: ""))\(record.team2Name)")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.homeNeutralCardTextSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onContinue)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Theme.homeNeutralCardTextSecondary)
                    .frame(width: 36, height: 36)
                    .background(closeButtonBackgroundColor)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, closeButtonGap)

            Button(action: onContinue) {
                Image(systemName: "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Theme.textOnPrimary)
                    .frame(width: iconSize, height: iconSize)
                    .background(Theme.primary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(barPadding)
        .frame(height: barHeight)
        .background(Theme.homeNeutralCardBackground)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255).opacity(0.85), lineWidth: 1)
        )
        .shadow(color: Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255).opacity(0.22), radius: 8, x: 0, y: 0)
    }

    private var closeButtonBackgroundColor: Color {
        Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor.white.withAlphaComponent(0.12)
            }
            return .tertiarySystemFill
        })
    }

    private var iconBackgroundColor: Color {
        (getGameGradient(type: record.gameType).first ?? Color(hex: "#71717A")).opacity(0.5)
    }

    private var displayScore: String {
        let t1 = record.team1FinalScore
        let t2 = record.team2FinalScore
        let s1 = record.team1SetScore
        let s2 = record.team2SetScore
        let g1 = intFromExtra("leftGames") ?? intFromExtra("finalLeftGames")
        let g2 = intFromExtra("rightGames") ?? intFromExtra("finalRightGames")
        let p1 = intFromExtra("leftPoints") ?? intFromExtra("currentLeftScore")
        let p2 = intFromExtra("rightPoints") ?? intFromExtra("currentRightScore")
        let hasSetScore = (s1 != nil && s2 != nil)
        let hasGames = (g1 != nil && g2 != nil)
        let isTennis = record.gameType == .tennis

        if let s1, let s2, hasSetScore, (s1 != 0 || s2 != 0) {
            return "\(s1) : \(s2)"
        }
        if let g1, let g2, hasGames, (g1 != 0 || g2 != 0) {
            return "\(g1) : \(g2)"
        }
        if let p1, let p2 {
            if isTennis {
                return formatTennisPointScore(left: p1, right: p2)
            }
            return "\(p1) : \(p2)"
        }
        if isTennis, hasSetScore, (s1 ?? 0) == 0, (s2 ?? 0) == 0, hasGames, (g1 ?? 0) == 0, (g2 ?? 0) == 0 {
            return formatTennisPointScore(left: t1, right: t2)
        }
        return "\(t1) : \(t2)"
    }

    private func formatTennisPointScore(left: Int, right: Int) -> String {
        if left >= 4 && right == 3 { return "Ad : 40" }
        if right >= 4 && left == 3 { return "40 : Ad" }
        return "\(tennisPointString(left)) : \(tennisPointString(right))"
    }

    private func tennisPointString(_ point: Int) -> String {
        switch point {
        case 0: return "0"
        case 1: return "15"
        case 2: return "30"
        default: return "40"
        }
    }

    private func intFromExtra(_ key: String) -> Int? {
        guard let value = record.extraData?[key]?.value else { return nil }
        if let intValue = value as? Int { return intValue }
        if let doubleValue = value as? Double { return Int(doubleValue) }
        if let stringValue = value as? String { return Int(stringValue) }
        return nil
    }
}
