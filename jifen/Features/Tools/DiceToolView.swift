//
//  DiceToolView.swift
//  jifen
//
//  Dice tool view aligned with Harmony implementation.
//

import SwiftUI
import WebKit

struct DiceToolView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hasRolled = false
    @State private var webVisible = false
    @State private var showHint = false
    @State private var showEnterToast = false
    @State private var showDiceCountDialog = false
    @State private var diceCount = 1

    private let hintShownKey = "dice_hint_shown"

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            DiceWebView(
                webVisible: $webVisible,
                diceCount: $diceCount,
                onSoundRequest: {
                    playDiceSound()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(webVisible ? 1 : 0)

            // Cover WKWebView until HTML/CSS first paint is ready to avoid white flash.
            if !webVisible {
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white.opacity(0.85))
                        .scaleEffect(1.15)
                }
                .transition(.opacity)
                .zIndex(2)
            }

            if !hasRolled && showHint {
                VStack {
                    Spacer()
                    Text(NSLocalizedString("tap_to_roll", value: "Tap to roll", comment: "Tap to roll dice"))
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.bottom, 80)
                }
            }

            if showEnterToast {
                ToastView(message: NSLocalizedString("tap_to_roll", value: "Tap to roll", comment: "Tap to roll dice"))
                    .transition(.opacity)
                    .zIndex(4)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: webVisible)
        // 骰子页无导航栏：悬浮返回与颗数选择器同排放置在顶部一行。
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            HStack {
                // 纯黑页面必须用显式亮色配色：自适应配色在浅色主题下解析为黑色，会隐入背景。
                FloatingBackButton(
                    iconColor: .white.opacity(0.85),
                    circleColor: Color.white.opacity(0.14)
                ) {
                    dismiss()
                }
                Spacer()
                diceCountButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            checkAndShowHint()
        }
        .onChange(of: webVisible) { _, visible in
            guard visible else { return }
            showEnterToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                showEnterToast = false
            }
        }
    }

    private var diceCountButton: some View {
        Button {
            showDiceCountDialog = true
        } label: {
            HStack(spacing: 4) {
                Text(diceCountLabel(diceCount))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            NSLocalizedString("dice_count_title", value: "骰子数量", comment: ""),
            isPresented: $showDiceCountDialog,
            titleVisibility: .visible
        ) {
            ForEach(1...3, id: \.self) { count in
                Button(diceCount == count ? "\(diceCountLabel(count)) ✓" : diceCountLabel(count)) {
                    selectDiceCount(count)
                }
            }
            Button(NSLocalizedString("cancel", value: "取消", comment: ""), role: .cancel) { }
        }
    }

    private func selectDiceCount(_ count: Int) {
            diceCount = count
            AppAnalytics.track(.toolAction, parameters: [
                .itemID: .string("dice"),
                .actionName: .string("setting_change"),
                .settingName: .string("dice_count"),
                .settingValue: .string(String(count))
            ])
    }

    private func diceCountLabel(_ count: Int) -> String {
        switch count {
        case 2:
            return NSLocalizedString("dice_count_2", value: "2 dice", comment: "Two dice")
        case 3:
            return NSLocalizedString("dice_count_3", value: "3 dice", comment: "Three dice")
        default:
            return NSLocalizedString("dice_count_1", value: "1 die", comment: "One die")
        }
    }

    private func checkAndShowHint() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: hintShownKey) {
            showHint = true
            defaults.set(true, forKey: hintShownKey)
        } else {
            showHint = false
        }
    }

    private func playDiceSound() {
        VibrationManager.shared.vibrateMedium()
        SoundManager.shared.playSound("dice")

        if !hasRolled {
            hasRolled = true
        }
        AppAnalytics.track(.toolAction, parameters: [
            .itemID: .string("dice"),
            .actionName: .string("roll"),
            .diceCount: .int(diceCount)
        ])
        AppAnalytics.track(.toolAction, parameters: [
            .itemID: .string("dice"),
            .actionName: .string("result"),
            .diceCount: .int(diceCount),
            .result: .string(AnalyticsResult.success.rawValue)
        ])
    }
}

struct DiceWebView: UIViewRepresentable {
    @Binding var webVisible: Bool
    @Binding var diceCount: Int
    let onSoundRequest: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let coordinator = context.coordinator
        // Reuses the webview preloaded by DiceWebEngine so the push transition
        // doesn't pay WKWebView cold-start.
        let webView = DiceWebEngine.shared.acquire(
            diceCount: diceCount,
            onSound: onSoundRequest,
            onReady: { coordinator.handleEngineReady() }
        )
        coordinator.attach(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        DiceWebEngine.shared.syncDiceCount(diceCount)
        // Keep UIKit visibility in sync with SwiftUI fade state.
        if webVisible, webView.isHidden {
            webView.isHidden = false
        } else if !webVisible, !webView.isHidden, !context.coordinator.hasRevealed {
            webView.isHidden = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(webVisible: $webVisible)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        // Keep the webview warm for the next visit; only detach callbacks.
        DiceWebEngine.shared.releaseForReuse()
    }

    final class Coordinator {
        private let webVisible: Binding<Bool>
        private weak var webView: WKWebView?
        private(set) var hasRevealed = false

        init(webVisible: Binding<Bool>) {
            self.webVisible = webVisible
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
        }

        func handleEngineReady() {
            guard !hasRevealed else { return }
            hasRevealed = true
            // One short beat after paint so the first CSS layout isn't shown mid-flash.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }
                self.webView?.isHidden = false
                withAnimation(.easeInOut(duration: 0.35)) {
                    self.webVisible.wrappedValue = true
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        DiceToolView()
    }
}
