import SwiftUI
import WebKit

/// A reusable, transparent renderer. The native tool owns the toss and result.
final class CoinWebEngine: NSObject, WKNavigationDelegate {
    static let shared = CoinWebEngine()

    private var webView: WKWebView?
    private var htmlURL: URL?
    private var isReady = false
    private var didRetryWithFileURL = false
    private var pendingRotationAngle = 0.0
    private var lastAppliedAngle: Double?
    private var isApplyingRotation = false

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    func acquire(rotationAngle: Double) -> WKWebView {
        pendingRotationAngle = rotationAngle
        if let webView {
            applyRotation()
            return webView
        }

        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.underPageBackgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isUserInteractionEnabled = false
        webView.isHidden = true
        self.webView = webView

        htmlURL = Bundle.main.url(forResource: "coin", withExtension: "html")
        loadRenderer(in: webView)
        return webView
    }

    func syncRotation(_ rotationAngle: Double) {
        pendingRotationAngle = rotationAngle
        applyRotation()
    }

    func releaseForReuse() {
        webView?.isHidden = true
    }

    private func loadRenderer(in webView: WKWebView) {
        guard let htmlURL else { return }
        do {
            let html = try String(contentsOf: htmlURL, encoding: .utf8)
            webView.loadHTMLString(html, baseURL: htmlURL.deletingLastPathComponent())
        } catch {
            retryWithFileURL(in: webView)
        }
    }

    private func applyRotation() {
        guard isReady, let webView, !isApplyingRotation else { return }
        let angle = pendingRotationAngle
        guard angle != lastAppliedAngle else {
            webView.isHidden = false
            return
        }
        isApplyingRotation = true
        webView.evaluateJavaScript(
            "if (window.coin3d) { window.coin3d.setRotation(\(angle)); }"
        ) { [weak self, weak webView] _, error in
            guard let self, let webView, self.webView === webView else { return }
            self.isApplyingRotation = false
            guard error == nil else { return }
            self.lastAppliedAngle = angle
            webView.isHidden = false
            // Coalesce animation ticks while WebKit is drawing and always catch
            // up to the latest native angle, including a toss begun during load.
            if self.pendingRotationAngle != angle {
                self.applyRotation()
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard self.webView === webView, !isReady else { return }
        webView.evaluateJavaScript("typeof window.coin3d?.setRotation === 'function'") { [weak self] value, error in
            guard let self, self.webView === webView, !self.isReady else { return }
            if error == nil, (value as? Bool) == true {
                self.isReady = true
                self.applyRotation()
            } else {
                self.retryWithFileURL(in: webView)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        retryWithFileURL(in: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        retryWithFileURL(in: webView)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard self.webView === webView else { return }
        isReady = false
        isApplyingRotation = false
        lastAppliedAngle = nil
        didRetryWithFileURL = false
        webView.isHidden = true
        loadRenderer(in: webView)
    }

    private func retryWithFileURL(in webView: WKWebView) {
        guard self.webView === webView, !didRetryWithFileURL, let htmlURL else { return }
        didRetryWithFileURL = true
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
    }

    @objc private func handleMemoryWarning() {
        guard let webView, webView.window == nil else { return }
        webView.stopLoading()
        webView.navigationDelegate = nil
        self.webView = nil
        htmlURL = nil
        isReady = false
        isApplyingRotation = false
        lastAppliedAngle = nil
        didRetryWithFileURL = false
    }
}

struct CoinWebView: UIViewRepresentable {
    let rotationAngle: Double

    func makeUIView(context: Context) -> WKWebView {
        CoinWebEngine.shared.acquire(rotationAngle: rotationAngle)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        CoinWebEngine.shared.syncRotation(rotationAngle)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: ()) {
        CoinWebEngine.shared.releaseForReuse()
    }
}
