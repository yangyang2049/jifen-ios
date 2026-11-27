import XCTest
@testable import jifen

/// 开源许可页的守门测试。
///
/// 只加页面不加登记是本项目最容易漏的合规问题（iOS 已经出现过「引了 OFL 字体但没有许可页」），
/// 所以这里用「包内素材 ↔ 许可文本」双向对账：新增字体或背景图却忘记写许可，测试直接红。
final class OpenSourceLicensesTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // jifenTests
            .deletingLastPathComponent()   // repo root
    }

    private var resourcesDirectory: URL {
        repositoryRoot.appendingPathComponent("jifen/Resources")
    }

    /// 字体文件名 → 许可文本文件名。新增字体时必须在这里登记。
    private let fontLicenseMap: [String: String] = [
        "teko.ttf": "teko-OFL",
        "7segment.ttf": "seven-segment-OFL"
    ]

    func testCatalogLoadsEveryLicenseTextInSourceOrder() throws {
        let entries = LicenseCatalog.loadFromSource(repositoryRoot: repositoryRoot)
        XCTAssertFalse(entries.isEmpty, "licenses 目录为空，关于页会是一张白页")
        XCTAssertEqual(
            entries.map(\.id),
            entries.map(\.id).sorted { $0.lowercased() < $1.lowercased() },
            "许可条目必须按文件名排序，否则三端顺序不一致"
        )
        for entry in entries {
            XCTAssertFalse(entry.body.isEmpty, "\(entry.id) 正文为空")
            XCTAssertFalse(entry.title.isEmpty, "\(entry.id) 标题为空")
            XCTAssertTrue(
                entry.body.contains("License") || entry.body.contains("licen") || entry.body.contains("許可"),
                "\(entry.id) 看起来不像许可全文（找不到 License 字样）"
            )
        }
    }

    /// Xcode 会把 `Resources/licenses/*` 压平到 bundle 根目录；这条用例守住「压平后页面仍有内容」。
    func testBundleFlatteningStillYieldsEveryLicense() throws {
        // 测试宿主是 app 本体，Bundle.main 才是 jifen.app（Bundle(for:) 是 xctest 包，里面没有资源）
        let entries = LicenseCatalog.loadFromBundle(Bundle.main)
        XCTAssertFalse(
            entries.isEmpty,
            "app bundle 里找不到 license-*.txt —— 资源没被打进包，或文件名丢了 license- 前缀"
        )
        let ids = Set(entries.map(\.id))
        for expected in ["teko-OFL", "seven-segment-OFL", "lucide", "scoreboard-backgrounds", "revenuecat"] {
            XCTAssertTrue(ids.contains(expected), "bundle 里缺少 \(expected)（id 应去掉 license- 前缀）")
        }
        for entry in entries {
            XCTAssertFalse(entry.title.hasPrefix("License"), "\(entry.id) 的标题把前缀也带上了：\(entry.title)")
        }
    }

    func testLicenseTitlesFollowTheAndroidNamingRule() {
        XCTAssertEqual(LicenseCatalog.title(for: "teko-OFL"), "Teko OFL")
        XCTAssertEqual(LicenseCatalog.title(for: "seven-segment-OFL"), "Seven Segment OFL")
        XCTAssertEqual(LicenseCatalog.title(for: "lucide"), "Lucide")
        XCTAssertEqual(LicenseCatalog.title(for: "revenuecat"), "RevenueCat")
        XCTAssertEqual(LicenseCatalog.title(for: "scoreboard-backgrounds"), "Scoreboard Backgrounds")
    }

    func testEveryBundledFontHasALicenseText() throws {
        let fonts = try FileManager.default
            .contentsOfDirectory(at: resourcesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "ttf" || $0.pathExtension.lowercased() == "otf" }
            .map(\.lastPathComponent)
            .sorted()
        XCTAssertFalse(fonts.isEmpty, "没有找到任何随包字体，检查 Resources 目录")

        let ids = Set(LicenseCatalog.loadFromSource(repositoryRoot: repositoryRoot).map(\.id))
        for font in fonts {
            let expected = try XCTUnwrap(
                fontLicenseMap[font],
                "\(font) 是新加的字体，但没有在 fontLicenseMap 里登记对应的许可文本"
            )
            XCTAssertTrue(ids.contains(expected), "\(font) 的许可文本 \(expected).txt 不存在")
        }
        // 反向：登记表里不能留下已删除字体的僵尸条目
        for (font, _) in fontLicenseMap {
            XCTAssertTrue(fonts.contains(font), "\(font) 已不在包内，请从 fontLicenseMap 删除")
        }
    }

    func testEveryScoreboardBackgroundHasACreditEntry() throws {
        let assets = repositoryRoot.appendingPathComponent("jifen/Assets.xcassets")
        let backgrounds = try FileManager.default
            .contentsOfDirectory(at: assets, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("scoreboard_event_background") }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
        XCTAssertFalse(backgrounds.isEmpty, "没有找到背景图素材集")

        let credits = try XCTUnwrap(
            LicenseCatalog.loadFromSource(repositoryRoot: repositoryRoot).first { $0.id == "scoreboard-backgrounds" },
            "缺少 scoreboard-backgrounds.txt"
        )
        for asset in backgrounds {
            XCTAssertTrue(
                credits.body.contains(asset),
                "背景图 \(asset) 没有在 scoreboard-backgrounds.txt 里写明来源与授权"
            )
        }
    }

    func testLicenseKeysExistInEveryPromotedLocale() throws {
        for locale in LocalizationTestSupport.promotedLocales {
            let values = try LocalizationTestSupport.valuesByKey(
                relativePath: LocalizationTestSupport.localizablePaths[locale]!
            )
            for key in ["about_open_source_licenses", "open_source_licenses_title"] {
                let value = try XCTUnwrap(values[key], "\(locale) 缺少 \(key)")
                XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "\(locale)/\(key) 为空")
            }
        }
    }
}
