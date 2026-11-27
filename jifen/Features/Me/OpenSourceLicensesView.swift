import SwiftUI

/// 开源许可页：把包内的 `Resources/licenses/*.txt` 逐条原样展示。
///
/// 与安卓 `OpenSourceLicensesActivity`（`assets/licenses/`）同一套做法：
/// 新增一个第三方依赖或素材时，只需把许可全文丢进 `Resources/licenses/`，
/// 页面自动多出一条，不用改代码、不用改本地化。正文保留英文原文（OFL / CC 要求
/// 保留原始声明），只有页面标题走 47 语种。
///
/// 入口：设置 → 关于我们 → 开源许可证。
struct OpenSourceLicensesView: View {
    @State private var entries: [LicenseEntry] = []

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.lg) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: Theme.sm) {
                            Text(entry.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)
                            Text(entry.body)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Theme.textSecondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: Theme.meTabContentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.pageHorizontalInset)
                .padding(.vertical, Theme.md)
            }
        }
        .navigationTitle(NSLocalizedString("open_source_licenses_title", value: "Open source licenses", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { entries = LicenseCatalog.load() }
        .accessibilityIdentifier("settings_open_source_licenses_screen")
    }
}

struct LicenseEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
}

/// 枚举包内 `licenses` 目录。目录与文件名都以小写形式排序，
/// 与安卓按文件名排序的展示顺序一致。
enum LicenseCatalog {
    /// Xcode 会把 `Resources/licenses/` 里的文件**压平**到 bundle 根目录（实测 `jifen.app/teko-OFL.txt`），
    /// 所以不能按子目录取，改用统一前缀识别。新增许可文本时文件名必须以它开头。
    static let bundleFilePrefix = "license-"
    /// 源码目录，供单测直接读取仓库文件。
    static let sourceDirectory = "jifen/Resources/licenses"

    static func load(bundle: Bundle = .main) -> [LicenseEntry] {
        let urls = (bundle.urls(forResourcesWithExtension: "txt", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.lowercased().hasPrefix(bundleFilePrefix) }
        return entries(from: urls)
    }

    /// 单测用：从构建产物的 app bundle 读取，验证「Xcode 压平后仍能识别」这条真实路径。
    static func loadFromBundle(_ bundle: Bundle) -> [LicenseEntry] {
        load(bundle: bundle)
    }

    /// 单测用：直接读源码目录，不依赖构建产物。
    static func loadFromSource(repositoryRoot: URL) -> [LicenseEntry] {
        let directory = repositoryRoot.appendingPathComponent(sourceDirectory)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return entries(from: urls.filter { $0.pathExtension.lowercased() == "txt" })
    }

    static func entries(from urls: [URL]) -> [LicenseEntry] {
        urls
            .sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
            .compactMap { url in
                guard let body = try? String(contentsOf: url, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !body.isEmpty else { return nil }
                let name = url.deletingPathExtension().lastPathComponent
                let displayName = name.hasPrefix(bundleFilePrefix)
                    ? String(name.dropFirst(bundleFilePrefix.count))
                    : name
                return LicenseEntry(id: displayName, title: title(for: displayName), body: body)
            }
    }

    /// `teko-OFL` → `Teko OFL`，与安卓 `toLicenseTitle()` 同一规则。
    static func title(for fileName: String) -> String {
        if fileName == "revenuecat" { return "RevenueCat" }
        return fileName
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { part in part.prefix(1).uppercased() + part.dropFirst() }
            .joined(separator: " ")
    }
}
