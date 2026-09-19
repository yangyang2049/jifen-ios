//
//  DiceWebEngine.swift
//  jifen
//
//  Keeps one warm WKWebView for the dice tool. Creating a WKWebView and
//  loading dice.html during the navigation push stalls the transition on
//  slower devices, so the webview is built and loaded ahead of time and
//  reused on every entry.
//
//  Main thread only.
//

import SwiftUI
import WebKit

final class DiceWebEngine: NSObject {
    static let shared = DiceWebEngine()

    private var webView: WKWebView?
    private var isReady = false
    private var isWarmUpScheduled = false
    private var didRetryWithFileURL = false
    private var htmlURL: URL?
    private var pendingDiceCount = 1
    private var onSoundRequest: (() -> Void)?
    private var onReady: (() -> Void)?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    // MARK: - Warm-up

    /// Builds the dice webview and preloads dice.html off-screen. Call early
    /// (e.g. when the dice tool tile appears) so entering the page never pays
    /// WKWebView cold-start mid-transition.
    func warmUp(after delay: TimeInterval = 0) {
        guard webView == nil, !isWarmUpScheduled else { return }
        isWarmUpScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.isWarmUpScheduled = false
            guard self.webView == nil else { return }
            self.startWarmUp()
        }
    }

    /// Creates the webview, stores it as the warm instance and starts loading
    /// dice.html. Returns the created webview.
    @discardableResult
    private func startWarmUp() -> WKWebView {
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
        document.documentElement.style.background = '#000';
        if (document.body) { document.body.style.background = '#000'; }
        """
        userController.addUserScript(
            WKUserScript(source: bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        let relay = DiceSoundRelay()
        relay.engine = self
        userController.add(relay, name: "playSound")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isHidden = true
        webView.underPageBackgroundColor = .black
        self.webView = webView

        guard let htmlURL = Bundle.main.url(forResource: "dice", withExtension: "html") else {
            webView.loadHTMLString(Self.emptyPageHTML, baseURL: nil)
            return webView
        }
        self.htmlURL = htmlURL
        do {
            let html = try String(contentsOf: htmlURL, encoding: .utf8)
            webView.loadHTMLString(html, baseURL: htmlURL.deletingLastPathComponent())
        } catch {
            retryWithFileURL(in: webView)
        }
        return webView
    }

    // MARK: - Attach / detach

    /// Returns the warm webview for the dice page. Cold fallback (warm-up was
    /// never scheduled) builds synchronously, matching the old makeUIView cost.
    func acquire(
        diceCount: Int,
        onSound: @escaping () -> Void,
        onReady: @escaping () -> Void
    ) -> WKWebView {
        pendingDiceCount = min(3, max(1, diceCount))
        onSoundRequest = onSound

        guard let webView else {
            self.onReady = onReady
            return startWarmUp()
        }
        if isReady {
            resetForNextEntry(in: webView)
            applyDiceCount()
            DispatchQueue.main.async(execute: onReady)
        } else {
            self.onReady = onReady
        }
        return webView
    }

    /// The dice page was popped; keep the webview warm but drop its callbacks.
    func releaseForReuse() {
        onSoundRequest = nil
        onReady = nil
        if let webView, isReady {
            resetForNextEntry(in: webView)
        }
    }

    func syncDiceCount(_ diceCount: Int) {
        pendingDiceCount = min(3, max(1, diceCount))
        applyDiceCount()
    }

    func handleSoundRequest() {
        onSoundRequest?()
    }

    // MARK: - Page state

    private func applyDiceCount() {
        guard let webView else { return }
        let count = pendingDiceCount
        webView.evaluateJavaScript(
            "window.__nativeDiceCount = \(count); if (window.setDiceCount) { window.setDiceCount(\(count)); }",
            completionHandler: nil
        )
    }

    /// The page stays loaded between visits, so clear the previous roll before
    /// showing it again.
    private func resetForNextEntry(in webView: WKWebView) {
        webView.evaluateJavaScript(
            "if (window.resetDiceState) { window.resetDiceState(); }",
            completionHandler: nil
        )
    }

    private func fireOnReady() {
        let action = onReady
        onReady = nil
        action?()
    }

    // MARK: - Memory

    @objc private func handleMemoryWarning() {
        guard let webView, webView.window == nil else { return }
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "playSound")
        webView.navigationDelegate = nil
        self.webView = nil
        isReady = false
        isWarmUpScheduled = false
        didRetryWithFileURL = false
        htmlURL = nil
        onReady = nil
        onSoundRequest = nil
    }

    private static let emptyPageHTML = """
    <html><head><style>
    html, body { margin: 0; background: #000000; }
    </style></head><body></body></html>
    """
}

// MARK: - Sound bridge

private final class DiceSoundRelay: NSObject, WKScriptMessageHandler {
    weak var engine: DiceWebEngine?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        engine?.handleSoundRequest()
    }
}

// MARK: - Load lifecycle

extension DiceWebEngine: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView, !isReady else { return }
        let validationScript = "document.querySelectorAll('.dice-unit .dice').length"
        webView.evaluateJavaScript(validationScript) { value, error in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.webView === webView, !self.isReady else { return }
                if error == nil, (value as? NSNumber)?.intValue == 3 {
                    self.isReady = true
                    self.applyDiceCount()
                    self.fireOnReady()
                } else {
                    self.retryWithFileURL(in: webView)
                }
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

    private func retryWithFileURL(in webView: WKWebView) {
        guard !didRetryWithFileURL, let htmlURL else {
            // Nothing left to try: surface whatever rendered so the page never
            // gets stuck behind the spinner.
            isReady = true
            fireOnReady()
            return
        }
        didRetryWithFileURL = true
        webView.loadFileURL(
            htmlURL,
            allowingReadAccessTo: htmlURL.deletingLastPathComponent()
        )
    }
}
