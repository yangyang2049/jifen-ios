//
//  GameOverDialog.swift
//  jifen
//
//  Match-end dialog aligned with HarmonyOS / Android GameOverDialog:
//  New game / View records / Share / Exit.
//

import Photos
import SwiftUI
import UIKit

enum ScoreboardShareSupport {
    /// Capture the key window and save to Photos (same path as menu screenshot).
    static func present(text: String = "") {
        guard let image = captureKeyWindowImage() else {
            if !text.isEmpty {
                presentActivity([text])
            }
            return
        }
        saveScreenshotToPhotoLibrary(image)
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

    private static func saveScreenshotToPhotoLibrary(_ image: UIImage) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            performSave(image)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        performSave(image)
                    }
                }
            }
        default:
            presentActivity([image])
        }
    }

    private static func performSave(_ image: UIImage) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { success, _ in
            DispatchQueue.main.async {
                if !success {
                    presentActivity([image])
                }
            }
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

struct GameOverDialog: View {
    let winnerName: String
    var resultText: String? = nil
    var leftName: String? = nil
    var rightName: String? = nil
    var leftScore: Int? = nil
    var rightScore: Int? = nil
    var multiNames: [String] = []
    var multiScores: [Int] = []
    var newGameLabel: String? = nil
    var newGameDisabled: Bool = false

    let onNewGame: () -> Void
    let onRecords: () -> Void
    let onShare: () -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { /* block dismiss by background tap */ }

            VStack(spacing: 16) {
                Text(NSLocalizedString("game_over_title", value: "比赛结束", comment: ""))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)

                resultBlock

                Button(action: onNewGame) {
                    Text(newGameLabel ?? NSLocalizedString("play_again", value: "再来一局", comment: ""))
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(newGameDisabled)
                .opacity(newGameDisabled ? 0.5 : 1)

                HStack(spacing: 10) {
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
            .padding(20)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .padding(.horizontal, 24)
            .accessibilityIdentifier("game_over_dialog")
        }
    }

    @ViewBuilder
    private var resultBlock: some View {
        if !multiNames.isEmpty, multiNames.count == multiScores.count {
            VStack(spacing: 8) {
                ForEach(Array(multiNames.enumerated()), id: \.offset) { index, name in
                    HStack {
                        Text(name).lineLimit(1)
                        Spacer()
                        Text("\(multiScores[index])")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                    }
                }
            }
            .padding(.vertical, 4)
        } else if let leftName, let rightName, let leftScore, let rightScore {
            HStack(spacing: 12) {
                scoreSide(leftName, score: leftScore, highlight: !winnerName.isEmpty && winnerName == leftName)
                Text("-")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.secondary)
                scoreSide(rightName, score: rightScore, highlight: !winnerName.isEmpty && winnerName == rightName)
            }
        } else {
            Text(
                winnerName.isEmpty
                    ? NSLocalizedString("match_draw", value: "比赛平局", comment: "")
                    : String(
                        format: NSLocalizedString("game_winner_format", comment: "Winner overlay"),
                        winnerName
                    )
            )
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(Color.yellow)
            .multilineTextAlignment(.center)

            if let resultText, !resultText.isEmpty {
                Text(resultText)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func scoreSide(_ name: String, score: Int, highlight: Bool) -> some View {
        VStack(spacing: 4) {
            Text(name)
                .font(.subheadline)
                .lineLimit(1)
            Text("\(score)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(highlight ? Color.green : Color.primary)
        }
        .frame(maxWidth: .infinity)
    }

    private func secondaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
    }
}

#Preview {
    GameOverDialog(
        winnerName: "红队",
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
