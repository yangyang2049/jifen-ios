//
//  DiceToolView.swift
//  jifen
//
//  Dice tool view aligned with Harmony implementation.
//

import SwiftUI
import WebKit

struct DiceToolView: View {
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

            diceCountSelectView

            if showDiceCountDialog {
                diceCountDialogView
                    .transition(.opacity)
                    .zIndex(3)
            }

            if showEnterToast {
                ToastView(message: NSLocalizedString("tap_to_roll", value: "Tap to roll", comment: "Tap to roll dice"))
                    .transition(.opacity)
                    .zIndex(4)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: webVisible)
        .navigationTitle(NSLocalizedString("dice_title", comment: "Dice title"))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
            .background(Color(hex: "1C1C1E"))
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
                .font(.system(size: 18, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? Theme.accentColor : .white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
                .contentShape(Rectangle())
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

    /// Shared process pool keeps subsequent opens warmer.
    private static let processPool = WKProcessPool()

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.processPool = Self.processPool
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
        document.documentElement.style.background = '#000';
        if (document.body) { document.body.style.background = '#000'; }
        """
        let userScript = WKUserScript(source: bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        userController.addUserScript(userScript)
        userController.add(context.coordinator, name: "playSound")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isHidden = true
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = .black
        }

        if let htmlURL = Bundle.main.url(forResource: "dice", withExtension: "html") {
            context.coordinator.load(htmlURL, in: webView)
        } else {
            context.coordinator.loadFallback(in: webView)
        }

        context.coordinator.syncDiceCount(on: webView, diceCount: diceCount)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.syncDiceCount(on: webView, diceCount: diceCount)
        // Keep UIKit visibility in sync with SwiftUI fade state.
        if webVisible, webView.isHidden {
            webView.isHidden = false
        } else if !webVisible, !webView.isHidden, !context.coordinator.hasRevealed {
            webView.isHidden = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(webVisible: $webVisible, onSoundRequest: onSoundRequest)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "playSound")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let webVisible: Binding<Bool>
        private let onSoundRequest: () -> Void
        private var pendingDiceCount = 1
        private var didRetryWithFileURL = false
        private var htmlURL: URL?
        private(set) var hasRevealed = false

        init(webVisible: Binding<Bool>, onSoundRequest: @escaping () -> Void) {
            self.webVisible = webVisible
            self.onSoundRequest = onSoundRequest
        }

        func load(_ htmlURL: URL, in webView: WKWebView) {
            self.htmlURL = htmlURL

            do {
                let html = try String(contentsOf: htmlURL, encoding: .utf8)
                webView.loadHTMLString(html, baseURL: htmlURL.deletingLastPathComponent())
            } catch {
                retryWithFileURL(in: webView)
            }
        }

        func loadFallback(in webView: WKWebView) {
            webView.loadHTMLString(
                """
                <html><head><style>
                html, body { margin: 0; background: #000000; }
                </style></head><body></body></html>
                """,
                baseURL: nil
            )
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "playSound" {
                onSoundRequest()
            }
        }

        func syncDiceCount(on webView: WKWebView, diceCount: Int) {
            let safeCount = min(3, max(1, diceCount))
            pendingDiceCount = safeCount
            let js = "window.__nativeDiceCount = \(safeCount); if (window.setDiceCount) { window.setDiceCount(\(safeCount)); }"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let validationScript = "document.querySelectorAll('.dice-unit .dice').length"
            webView.evaluateJavaScript(validationScript) { [weak self, weak webView] value, error in
                guard let self, let webView else { return }

                if error == nil, (value as? NSNumber)?.intValue == 3 {
                    self.syncDiceCount(on: webView, diceCount: self.pendingDiceCount)
                    self.reveal(webView)
                } else {
                    self.retryWithFileURL(in: webView)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            retryWithFileURL(in: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            retryWithFileURL(in: webView)
        }

        private func reveal(_ webView: WKWebView) {
            guard !hasRevealed else { return }
            hasRevealed = true
            // One short beat after paint so the first CSS layout isn't shown mid-flash.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                webView.isHidden = false
                withAnimation(.easeInOut(duration: 0.35)) {
                    self.webVisible.wrappedValue = true
                }
            }
        }

        private func retryWithFileURL(in webView: WKWebView) {
            guard !didRetryWithFileURL, let htmlURL else {
                reveal(webView)
                return
            }

            didRetryWithFileURL = true
            webView.loadFileURL(
                htmlURL,
                allowingReadAccessTo: htmlURL.deletingLastPathComponent()
            )
        }
    }
}

#Preview {
    NavigationStack {
        DiceToolView()
    }
}
