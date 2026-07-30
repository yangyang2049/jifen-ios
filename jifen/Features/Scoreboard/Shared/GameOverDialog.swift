//
//  GameOverDialog.swift
//  jifen
//
//  Match-end dialog aligned with HarmonyOS / Android GameOverDialog:
//  New game / View records / Share / Exit.
//

import SwiftUI
import UIKit

/// Two participants are rendered as two name/score groups with one centered separator.
struct TwoSideScoreResultRow: View {
    let leftName: String
    let rightName: String
    let leftScore: String
    let rightScore: String
    var leftNameColor: Color = .primary
    var rightNameColor: Color = .primary
    var leftScoreColor: Color = .primary
    var rightScoreColor: Color = .primary
    var separatorColor: Color = .secondary
    var nameFont: Font = .subheadline
    var scoreFont: Font = .system(size: 36, weight: .bold, design: .rounded)
    var separatorFont: Font = .title2.weight(.bold)
    var sideSpacing: CGFloat = 4
    var columnSpacing: CGFloat = 12

    var body: some View {
        HStack(alignment: .center, spacing: columnSpacing) {
            scoreSide(name: leftName, score: leftScore, nameColor: leftNameColor, scoreColor: leftScoreColor)

            Text("-")
                .font(separatorFont)
                .foregroundStyle(separatorColor)

            scoreSide(name: rightName, score: rightScore, nameColor: rightNameColor, scoreColor: rightScoreColor)
        }
    }

    private func scoreSide(name: String, score: String, nameColor: Color, scoreColor: Color) -> some View {
        VStack(spacing: sideSpacing) {
            Text(name)
                .font(nameFont)
                .foregroundStyle(nameColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .truncationMode(.tail)
            Text(score)
                .font(scoreFont)
                .foregroundStyle(scoreColor)
        }
        .frame(maxWidth: .infinity)
    }
}

enum ScoreboardShareSupport {
    /// Capture the key window and present the system share sheet.
    static func present(text: String = "") {
        guard let image = captureKeyWindowImage() else {
            if !text.isEmpty {
                presentActivity([text])
            }
            return
        }

        var items: [Any] = [image]
        if !text.isEmpty {
            items.append(text)
        }
        presentActivity(items)
    }

    private static func captureKeyWindowImage() -> UIImage? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first else {
            return nil
        }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    private static func presentActivity(_ items: [Any]) {
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        if let pop = activity.popoverPresentationController {
            pop.sourceView = presenter.view
            pop.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
        }
        presenter.present(activity, animated: true)
    }
}

enum GameOverWinnerResolver {
    static func indices(
        explicit: Set<Int>?,
        multiScores: [Int],
        leftScore: String?,
        rightScore: String?,
        participantNames: [String?],
        winnerName: String
    ) -> Set<Int> {
        if let explicit { return explicit }
        if multiScores.count > 2, let best = multiScores.max() {
            let indices = Set(multiScores.indices.filter { multiScores[$0] == best })
            return indices.count == multiScores.count ? [] : indices
        }
        if let left = leftScore.flatMap(Int.init),
           let right = rightScore.flatMap(Int.init) {
            if left == right { return [] }
            return [left > right ? 0 : 1]
        }
        let matches = participantNames.enumerated().compactMap { index, name in
            name == winnerName ? index : nil
        }
        return matches.count == 1 ? Set(matches) : []
    }
}

struct GameOverDialog: View {
    let winnerName: String
    var gameType: GameType = .simpleScore
    var resultText: String? = nil
    var leftName: String? = nil
    var rightName: String? = nil
    var leftScore: Int? = nil
    var rightScore: Int? = nil
    var leftScoreText: String? = nil
    var rightScoreText: String? = nil
    var multiNames: [String] = []
    var multiScores: [Int] = []
    /// Stable positional winner identity. When omitted, the dialog derives it
    /// from the displayed scores instead of comparing participant names.
    var winnerIndices: Set<Int>? = nil
    var newGameLabel: String? = nil
    var newGameDisabled: Bool = false

    let onNewGame: () -> Void
    let onRecords: () -> Void
    let onShare: () -> Void
    let onExit: () -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private let dialogBackground = Color(hex: "2C2C2E")
    private let cardBackground = Color(hex: "3A3A3C")
    private let disabledBackground = Color(hex: "48484A")
    private let primaryText = Color.white
    private let secondaryText = Color(hex: "98989D")
    private let winnerScoreColor = Color(hex: "34C759")

    private var usesTabletSpacing: Bool {
        Theme.usesPadLayout
    }

    private var isPhoneLandscape: Bool {
        !usesTabletSpacing && verticalSizeClass == .compact
    }

    private var resolvedLeftScore: String? {
        leftScoreText ?? leftScore.map(String.init)
    }

    private var resolvedRightScore: String? {
        rightScoreText ?? rightScore.map(String.init)
    }

    private var isDraw: Bool {
        resolvedWinnerIndices.isEmpty && hasComparableResult
    }

    private var hasComparableResult: Bool {
        if winnerIndices != nil { return true }
        if multiNames.count > 2, multiNames.count == multiScores.count { return !multiScores.isEmpty }
        return resolvedLeftScore != nil && resolvedRightScore != nil
    }

    private var resolvedWinnerIndices: Set<Int> {
        GameOverWinnerResolver.indices(
            explicit: winnerIndices,
            multiScores: multiNames.count == multiScores.count ? multiScores : [],
            leftScore: resolvedLeftScore,
            rightScore: resolvedRightScore,
            participantNames: [leftName, rightName],
            winnerName: winnerName
        )
    }

    private var resultAreaHeight: CGFloat {
        let base: CGFloat = usesTabletSpacing ? 154 : (isPhoneLandscape ? 96 : 124)
        guard multiNames.count > 3, multiNames.count == multiScores.count else { return base }
        let rows = CGFloat((multiNames.count + 1) / 2)
        let rowHeight = multiParticipantRowHeight
        let gridHeight = rows * rowHeight + max(0, rows - 1) * 8
        let visibleGridHeight = isPhoneLandscape ? min(gridHeight, 136) : gridHeight
        return max(base, visibleGridHeight + (usesTabletSpacing ? 24 : 8))
    }

    private var multiParticipantRowHeight: CGFloat {
        if isPhoneLandscape {
            if multiNames.count >= 9 { return 40 }
            if multiNames.count >= 7 { return 42 }
            return 46
        }
        if multiNames.count >= 9 { return usesTabletSpacing ? 52 : 46 }
        if multiNames.count >= 7 { return usesTabletSpacing ? 56 : 50 }
        return usesTabletSpacing ? 62 : 56
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { /* block dismiss by background tap */ }

            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    Text(isDraw
                         ? NSLocalizedString("game_over_draw", value: "比赛平局", comment: "")
                         : NSLocalizedString("game_over_title", value: "比赛结束", comment: ""))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(primaryText)
                        .padding(.top, usesTabletSpacing ? 28 : 16)
                        .padding(.bottom, usesTabletSpacing ? 12 : 4)

                    HStack(spacing: 8) {
                        Text(gameType.icon)
                            .font(.system(size: 18))
                        Text(gameType.displayName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(secondaryText)
                    }
                    .padding(.bottom, usesTabletSpacing ? 16 : 8)

                    resultBlock
                        .padding(.horizontal, usesTabletSpacing ? 28 : 20)
                        .padding(.vertical, usesTabletSpacing ? 12 : 4)
                        .frame(height: resultAreaHeight)
                        .padding(.horizontal, usesTabletSpacing ? 28 : 20)
                        .padding(.bottom, usesTabletSpacing ? 20 : 10)

                    VStack(spacing: usesTabletSpacing ? 18 : 10) {
                        Button(action: onNewGame) {
                            Text(newGameLabel ?? NSLocalizedString("play_again", value: "再来一场", comment: ""))
                                .font(.system(size: newGameDisabled ? (usesTabletSpacing ? 14 : 13) : 16, weight: .medium))
                                .foregroundStyle(newGameDisabled ? secondaryText : Color.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(newGameDisabled ? 2 : 1)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .buttonStyle(.plain)
                        .frame(height: usesTabletSpacing ? 52 : 44)
                        .background(newGameDisabled ? disabledBackground : Theme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .disabled(newGameDisabled)

                        HStack(spacing: usesTabletSpacing ? 12 : 8) {
                            secondaryButton(
                                title: NSLocalizedString("game_over_records", value: "查看记录", comment: ""),
                                action: onRecords
                            )
                            secondaryButton(
                                title: NSLocalizedString("share", value: "分享", comment: ""),
                                action: onShare
                            )
                            secondaryButton(
                                title: NSLocalizedString("exit", value: "退出", comment: ""),
                                action: onExit
                            )
                        }
                    }
                    .padding(.horizontal, usesTabletSpacing ? 28 : 20)
                    .padding(.bottom, usesTabletSpacing ? 28 : 16)
                }
                .frame(maxWidth: Theme.dialogPreferredWidth(role: .gameOver))
                .background(dialogBackground)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .accessibilityIdentifier("game_over_dialog")

                Button(action: onExit) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(primaryText)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .padding(10)
                .accessibilityLabel(NSLocalizedString("close", value: "关闭", comment: ""))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var resultBlock: some View {
        if multiNames.count > 2, multiNames.count == multiScores.count {
            if gameType == .doudizhu, multiNames.count == 3 {
                tripleResultRow
            } else {
                multiParticipantGrid
            }
        } else if let leftName, let rightName,
                  let leftScore = resolvedLeftScore,
                  let rightScore = resolvedRightScore {
            twoTeamResultRow(
                leftName: leftName,
                rightName: rightName,
                leftScore: leftScore,
                rightScore: rightScore
            )
        } else {
            VStack(spacing: usesTabletSpacing ? 10 : 4) {
                if let leftName, let rightName {
                    Text("\(leftName) vs \(rightName)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(primaryText)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                } else if !winnerName.isEmpty {
                    Text(winnerName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(primaryText)
                }
                if let resultText, !resultText.isEmpty {
                    Text(resultText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(primaryText)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private func twoTeamResultRow(
        leftName: String,
        rightName: String,
        leftScore: String,
        rightScore: String
    ) -> some View {
        HStack(spacing: 6) {
            resultColumn(name: leftName, score: leftScore, isWinner: resolvedWinnerIndices.contains(0))
            Text("-")
                .font(.system(size: 20))
                .foregroundStyle(secondaryText)
                .padding(.horizontal, 4)
            resultColumn(name: rightName, score: rightScore, isWinner: resolvedWinnerIndices.contains(1))
        }
        .padding(.vertical, usesTabletSpacing ? 12 : 4)
    }

    private var tripleResultRow: some View {
        HStack(spacing: 4) {
            ForEach(Array(multiNames.indices), id: \.self) { index in
                if index > 0 {
                    Text("-")
                        .font(.system(size: usesTabletSpacing ? 20 : 18))
                        .foregroundStyle(secondaryText)
                }
                resultColumn(
                    name: multiNames[index],
                    score: "\(multiScores[index])",
                    isWinner: resolvedWinnerIndices.contains(index),
                    nameFontSize: usesTabletSpacing ? 13 : 12,
                    scoreFontSize: usesTabletSpacing ? 30 : (isPhoneLandscape ? 28 : 29)
                )
            }
        }
        .padding(.vertical, usesTabletSpacing ? 12 : 4)
    }

    @ViewBuilder
    private var multiParticipantGrid: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 8),
            count: multiNames.count >= 4 ? 2 : 3
        )
        let rows = CGFloat((multiNames.count + (multiNames.count >= 4 ? 1 : 2)) / (multiNames.count >= 4 ? 2 : 3))
        let fullHeight = rows * multiParticipantRowHeight + max(0, rows - 1) * 8
        if isPhoneLandscape, fullHeight > 136 {
            ScrollView(.vertical) {
                multiParticipantGridContent(columns: columns)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 136)
        } else {
            multiParticipantGridContent(columns: columns)
                .frame(height: fullHeight)
        }
    }

    private func multiParticipantGridContent(columns: [GridItem]) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(multiNames.indices), id: \.self) { index in
                resultColumn(
                    name: multiNames[index],
                    score: "\(multiScores[index])",
                    isWinner: resolvedWinnerIndices.contains(index),
                    nameFontSize: usesTabletSpacing ? 13 : 12,
                    scoreFontSize: multiParticipantScoreFontSize
                )
                .frame(height: multiParticipantRowHeight)
            }
        }
    }

    private var multiParticipantScoreFontSize: CGFloat {
        if usesTabletSpacing { return multiNames.count >= 7 ? 26 : 30 }
        if multiNames.count >= 9 { return 22 }
        if multiNames.count >= 7 { return 24 }
        return multiNames.count >= 4 ? 26 : 29
    }

    private func resultColumn(
        name: String,
        score: String,
        isWinner: Bool,
        nameFontSize: CGFloat = 12,
        scoreFontSize: CGFloat = 30
    ) -> some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.system(size: nameFontSize))
                .foregroundStyle(primaryText)
                .lineLimit(gameType == .doudizhu ? 1 : 2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Text(score)
                .font(.system(size: scoreFontSize, weight: .bold))
                .foregroundStyle(isWinner ? winnerScoreColor : primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private func secondaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .frame(height: usesTabletSpacing ? 46 : 40)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    GameOverDialog(
        winnerName: "红队",
        gameType: .pingpong,
        leftName: "红队",
        rightName: "蓝队",
        leftScore: 21,
        rightScore: 18,
        onNewGame: {},
        onRecords: {},
        onShare: {},
        onExit: {}
    )
}
