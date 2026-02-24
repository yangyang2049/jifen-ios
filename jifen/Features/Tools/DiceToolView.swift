//
//  DiceToolView.swift
//  jifen
//
//  Dice tool view aligned with Harmony implementation.
//

import SwiftUI
import WebKit

struct DiceToolView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var hasRolled = false
    @State private var webVisible = false
    @State private var showHint = false
    @State private var showEnterToast = false
    @State private var showDiceCountDialog = false
    @State private var diceCount = 1

    private let hintShownKey = "dice_hint_shown"

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Theme.backgroundColor : Theme.homeBackgroundLight)
                .ignoresSafeArea()

            DiceWebView(
                webVisible: $webVisible,
                diceCount: $diceCount,
                onSoundRequest: {
                    playDiceSound()
                }
            )
            .opacity(webVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: webVisible)

            if !hasRolled && showHint {
                VStack {
                    Spacer()
                    Text(NSLocalizedString("tap_to_roll", value: "Tap to roll", comment: "Tap to roll dice"))
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.bottom, 80)
                }
            }

            diceCountSelectView

            if showDiceCountDialog {
                diceCountDialogView
                    .transition(.opacity)
                    .zIndex(1)
            }

            if showEnterToast {
                ToastView(message: NSLocalizedString("tap_to_roll", value: "Tap to roll", comment: "Tap to roll dice"))
                    .transition(.opacity)
            }
        }
        .navigationTitle(NSLocalizedString("dice_title", comment: "Dice title"))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear {
            checkAndShowHint()
            showEnterToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                showEnterToast = false
            }
        }
    }

    private var diceCountSelectView: some View {
        VStack {
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
            .padding(.top, 16)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDiceCountDialog = true
                }
            }

            Spacer()
        }
    }

    private var diceCountDialogView: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDiceCountDialog = false
                    }
                }

            VStack(spacing: 0) {
                diceCountOptionButton(1)
                dialogDivider
                diceCountOptionButton(2)
                dialogDivider
                diceCountOptionButton(3)
            }
            .frame(width: 220)
            .background(Color(red: 28.0 / 255.0, green: 28.0 / 255.0, blue: 30.0 / 255.0))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .padding(.top, 68)
        }
    }

    private var dialogDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(height: 1)
    }

    private func diceCountOptionButton(_ count: Int) -> some View {
        let isSelected = diceCount == count
        return Button {
            diceCount = count
            withAnimation(.easeInOut(duration: 0.2)) {
                showDiceCountDialog = false
            }
        } label: {
            Text(diceCountLabel(count))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .font(.system(size: 18, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? Color(red: 48.0 / 255.0, green: 209.0 / 255.0, blue: 88.0 / 255.0) : .white)
                .background(Color.white.opacity(0.08))
        }
        .buttonStyle(.plain)
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
    }
}

struct DiceWebView: UIViewRepresentable {
    @Binding var webVisible: Bool
    @Binding var diceCount: Int
    let onSoundRequest: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let userController = config.userContentController
        let bridgeScript = """
        window.__nativeDiceCount = window.__nativeDiceCount || 1;
        window.nativeInterface = window.nativeInterface || {};
        window.nativeInterface.playSound = function() {
            window.webkit.messageHandlers.playSound.postMessage({});
        };
        window.nativeInterface.getDiceCount = function() {
            return window.__nativeDiceCount || 1;
        };
        """
        let userScript = WKUserScript(source: bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        userController.addUserScript(userScript)
        userController.add(context.coordinator, name: "playSound")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false

        if let htmlURL = Bundle.main.url(forResource: "dice", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        } else {
            webView.loadHTMLString("<html><body style='margin:0;background:#000;'></body></html>", baseURL: nil)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            webVisible = true
        }

        context.coordinator.syncDiceCount(on: webView, diceCount: diceCount)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.syncDiceCount(on: webView, diceCount: diceCount)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSoundRequest: onSoundRequest)
    }

    class Coordinator: NSObject, WKScriptMessageHandler {
        private let onSoundRequest: () -> Void

        init(onSoundRequest: @escaping () -> Void) {
            self.onSoundRequest = onSoundRequest
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "playSound" {
                onSoundRequest()
            }
        }

        func syncDiceCount(on webView: WKWebView, diceCount: Int) {
            let safeCount = min(3, max(1, diceCount))
            let js = "window.__nativeDiceCount = \(safeCount); if (window.setDiceCount) { window.setDiceCount(\(safeCount)); }"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

#Preview {
    NavigationStack {
        DiceToolView()
    }
}
