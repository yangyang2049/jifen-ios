import SwiftUI
import WebKit

/// 应用内网页链接的统一收口入口；官网由设置页交给系统浏览器打开。
///
/// 一条宿主 = 一条 NavigationStack，两段配套挂（每个位置都实测踩过坑）：
///
/// ```swift
/// struct MeTab: View {
///     var body: some View {
///         SettingsView(isTabRoot: true)
///             .inAppWebLinks()          // ① 宿主挂在"读 action 的那个视图"之上
///     }
/// }
///
/// // SettingsView 内部：
/// NavigationStack {
///     RootContent()
///         .inAppWebLinkDestination()    // ② 注册必须写在栈内部
/// }
/// ```
///
/// - `.navigationDestination` 挂在 `NavigationStack { }` 外面不会 push（同层入口点了也没反应）；
/// - `.environment` 只挂在栈的根内容上不会传到 push 出来的页面，深层页面只能拿到默认空 action；
/// - `.inAppWebLinks()` 不能挂在读 action 的那个视图自己 body 的输出上（自我注入无效），
///   所以 Me 栈的宿主在 `MeTab`、弹窗的宿主在 `SettingsFormSheet`；
/// - 页面自己身上挂宿主又读同一个 key 也不行：读到的是外层宿主的 action，iPad 上网页
///   就会 push 到弹窗背后的主应用层。
///
/// sheet/弹窗自带一条栈，就自己配一套这两段，网页才会内嵌在弹窗里。
///
struct InAppWebLink: Identifiable, Hashable {
    let url: URL
    var title: String?

    var id: URL { url }
}

/// 一条栈一个路由：栈外的宿主持有，栈内的 destination 通过 environment 取同一个对象。
@Observable final class InAppWebLinkRouter {
    var activeLink: InAppWebLink?
}

private struct InAppWebLinkRouterKey: EnvironmentKey {
    static let defaultValue: InAppWebLinkRouter? = nil
}

private struct OpenInAppWebLinkKey: EnvironmentKey {
    static let defaultValue: (InAppWebLink) -> Void = { _ in }
}

extension EnvironmentValues {
    var openInAppWebLink: (InAppWebLink) -> Void {
        get { self[OpenInAppWebLinkKey.self] }
        set { self[OpenInAppWebLinkKey.self] = newValue }
    }

    fileprivate var inAppWebLinkRouter: InAppWebLinkRouter? {
        get { self[InAppWebLinkRouterKey.self] }
        set { self[InAppWebLinkRouterKey.self] = newValue }
    }
}

extension View {
    /// ① 挂在 `NavigationStack` 外面：注入 router 与打开 action。
    func inAppWebLinks() -> some View {
        modifier(InAppWebLinksHostModifier())
    }

    /// ② 挂在栈内部（根内容上）：注册网页 destination。
    func inAppWebLinkDestination() -> some View {
        modifier(InAppWebLinkDestinationModifier())
    }
}

private struct InAppWebLinksHostModifier: ViewModifier {
    @State private var router = InAppWebLinkRouter()

    func body(content: Content) -> some View {
        content
            .environment(\.inAppWebLinkRouter, router)
            .environment(\.openInAppWebLink, { link in router.activeLink = link })
    }
}

private struct InAppWebLinkDestinationModifier: ViewModifier {
    @Environment(\.inAppWebLinkRouter) private var router

    func body(content: Content) -> some View {
        if let router {
            content.modifier(WebLinkDestinationBinding(router: router))
        } else {
            content
        }
    }
}

/// 程序化入口的 navigationDestination(item:) 必须拿到 @Bindable 投影出的稳定绑定；
/// 已处于栈内的页面则使用同一类型的值路由继续 push，避免把中间页面一起替换掉。
private struct WebLinkDestinationBinding: ViewModifier {
    @Bindable var router: InAppWebLinkRouter

    func body(content: Content) -> some View {
        content
            // Nested pages such as About use value-driven NavigationLinks so the
            // web page is appended after the current page instead of replacing it.
            .navigationDestination(for: InAppWebLink.self) { link in
                webPage(for: link)
            }
            // Keep the programmatic route for buttons that are not NavigationLinks
            // (feedback attachments and other shared entry points).
            .navigationDestination(item: $router.activeLink) { link in
                webPage(for: link)
            }
    }

    private func webPage(for link: InAppWebLink) -> some View {
        InAppWebLinkPage(link: link)
            // 关于页等宿主页隐藏了 tab bar，push 出来的网页同样全屏无 tab bar，
            // 否则 iPhone 上网页底部会浮着 Tab bar（我的仍选中），看起来像没跳转。
            .toolbar(.hidden, for: .tabBar)
    }
}

/// Push 进宿主栈的一页，返回交给导航栈自带的返回按钮，所以不再放自定义叉。
struct InAppWebLinkPage: View {
    let link: InAppWebLink

    var body: some View {
        AppWebView(url: link.url)
            .background(Theme.backgroundColor)
            // Fill the home-indicator area with the webpage, while keeping the
            // top safe area and the navigation bar unchanged.
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationTitle(link.title ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("in_app_web_page")
            .appAnalyticsScreen(.legalWebPage)
    }
}

/// 应用内网页容器（原 LoginLegalWebView，登录协议/会员协议/关于页/反馈外链共用）。
/// 顶部细进度条 + 加载失败/无网覆盖层（系统图标 + 文案 + 重试）。
struct AppWebView: View {
    let url: URL

    @State private var progress: CGFloat = 0
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var reloadToken = 0
    #if DEBUG
    /// UI 测试：`-UITestWebFailOnce` 模拟加载失败，验证覆盖层与重试入口（真实网络失败无法在模拟器里稳定复现）。
    @State private var uiTestSimulateFailure = ProcessInfo.processInfo.arguments.contains("-UITestWebFailOnce")
    #endif

    var body: some View {
        ZStack {
            WebContainer(
                url: url,
                reloadToken: reloadToken,
                onProgress: { value in
                    progress = value
                    isLoading = value < 1
                },
                onFailure: { _ in
                    loadFailed = true
                    isLoading = false
                }
            )
            .ignoresSafeArea(edges: .bottom)

            if isLoading && progress > 0.02 && progress < 1 {
                VStack {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(Theme.accentColor)
                    Spacer()
                }
                .padding(.horizontal, 2)
            }

            if loadFailed {
                failureOverlay
            }
        }
        .background(Theme.backgroundColor)
        #if DEBUG
        .onAppear {
            if uiTestSimulateFailure {
                loadFailed = true
                isLoading = false
            }
        }
        #endif
        .onChange(of: url) { _, _ in
            loadFailed = false
            isLoading = true
            progress = 0
            reloadToken += 1
        }
    }

    private var failureOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
            Text(NSLocalizedString("web_load_failed", value: "网页加载失败，请检查网络后重试", comment: ""))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                #if DEBUG
                guard !uiTestSimulateFailure else { return }
                #endif
                loadFailed = false
                isLoading = true
                progress = 0
                reloadToken += 1
            } label: {
                Text(NSLocalizedString("retry", value: "重试", comment: ""))
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("web_load_retry_button")
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundColor)
    }
}

private struct WebContainer: UIViewRepresentable {
    let url: URL
    let reloadToken: Int
    let onProgress: (CGFloat) -> Void
    let onFailure: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onProgress: onProgress, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.observe(webView)
        context.coordinator.beginLoad(url)
        context.coordinator.reloadToken = reloadToken
        // makeUIView 处于 View update 周期内，加载动作延后一拍再触发。
        DispatchQueue.main.async { webView.load(URLRequest(url: url)) }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onProgress = onProgress
        coordinator.onFailure = onFailure
        if coordinator.lastURL != url {
            coordinator.beginLoad(url)
            webView.load(URLRequest(url: url))
        } else if coordinator.reloadToken != reloadToken {
            coordinator.reloadToken = reloadToken
            coordinator.beginLoad(url)
            webView.reloadFromOrigin()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onProgress: (CGFloat) -> Void
        var onFailure: (Error) -> Void
        var lastURL: URL?
        var reloadToken = -1
        private var progressObservation: NSKeyValueObservation?

        init(onProgress: @escaping (CGFloat) -> Void, onFailure: @escaping (Error) -> Void) {
            self.onProgress = onProgress
            self.onFailure = onFailure
        }

        func observe(_ webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
                let value = CGFloat(webView.estimatedProgress)
                Task { @MainActor [weak self] in self?.onProgress(value) }
            }
        }

        func beginLoad(_ url: URL) {
            lastURL = url
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor [weak self] in self?.onFailure(error) }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor [weak self] in self?.onFailure(error) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor [weak self] in self?.onProgress(1) }
        }
    }
}
