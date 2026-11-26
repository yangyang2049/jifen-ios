import XCTest
import UIKit
@testable import jifen

/// 启动介绍弹层的状态机：只有 sheet 真正上屏才算「遮住首页」。
/// 否则 present 失败（同层已有模态）会把 isCoveringHome 卡在 true，
/// jifenApp 的 alertUnlessWatchLinkIntro 会永久静音保存失败等全局告警。
@MainActor
final class WatchLinkIntroPresentationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "WatchLinkIntroPresentationTests." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// -UITestWatchLinkIntro 会让 DEBUG 构建用占位图，从而把「弹层状态机」与
    /// 「素材是否就位」两件事分开测试（后者见 WatchLinkIntroArtworkTests）。
    private func makePresentation() -> WatchLinkIntroPresentation {
        WatchLinkIntroPresentation(
            defaults: defaults,
            arguments: ["-UITestWatchLinkIntro"]
        )
    }

    func testPresentRequestsPresentationButDoesNotCoverHomeUntilTheSheetAppears() throws {
        let presentation = makePresentation()
        XCTAssertTrue(presentation.hasLaunchPriority)

        presentation.present()
        XCTAssertTrue(presentation.isPresented)
        XCTAssertFalse(
            presentation.isCoveringHome,
            "present 只发出请求；未确认 sheet 上屏前不能压制首页其它弹层与全局告警"
        )

        presentation.sheetDidAppear()
        XCTAssertTrue(presentation.isCoveringHome)
    }

    func testFailedPresentationKeepsHomeUncoveredAndTheIntroRetryable() throws {
        let presentation = makePresentation()
        presentation.present()
        // 模拟 present 失败：sheet 始终没有 onAppear，也没有任何 onDismiss 回调。

        XCTAssertFalse(presentation.isCoveringHome, "卡在 true 会永久静音全局告警")
        XCTAssertFalse(presentation.wasDismissed, "present 失败不算用户已看过")
        XCTAssertFalse(defaults.bool(forKey: WatchLinkIntroPresentation.seenKey))
    }

    func testDismissClearsCoverAndRemembersTheLaunch() throws {
        let presentation = makePresentation()
        presentation.present()
        presentation.sheetDidAppear()

        presentation.dismiss()
        XCTAssertFalse(presentation.isCoveringHome)
        XCTAssertFalse(presentation.isPresented)
        XCTAssertTrue(presentation.wasDismissed)
        XCTAssertTrue(defaults.bool(forKey: WatchLinkIntroPresentation.seenKey))
    }

    func testDismissIsIdempotentAndPresentIsIgnoredAfterwards() throws {
        let presentation = makePresentation()
        presentation.present()
        presentation.sheetDidAppear()
        presentation.dismiss()
        presentation.dismiss()

        presentation.present()
        XCTAssertFalse(presentation.isPresented, "已经关掉过的启动介绍不应再次弹出")
        XCTAssertTrue(presentation.wasDismissed)
    }

    func testSheetAppearanceWithoutRequestIsIgnored() throws {
        let presentation = makePresentation()
        presentation.sheetDidAppear()
        XCTAssertFalse(presentation.isCoveringHome)
    }
}

/// 3.4.4 的启动介绍依赖三套真实素材；缺素材时 present 永远不会发生，
/// 而 DEBUG 的占位图会让 UI 测试照样通过。这里在版本号与 releaseVersion
/// 对齐时强制校验素材存在，把「静默不上线」变成一条明确的红。
final class WatchLinkIntroArtworkTests: XCTestCase {
    func testReleaseArtworkAssetsExistForEveryShippedLocale() throws {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard version == WatchLinkIntroPresentation.releaseVersion else {
            throw XCTSkip("版本号 \(version ?? "nil") 尚未对齐 \(WatchLinkIntroPresentation.releaseVersion)，暂不校验素材")
        }

        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("jifen/Assets.xcassets")
        let prefix = WatchLinkIntroPresentation.artworkNamePrefix
        for locale in ["en", "zh-Hans", "zh-Hant"] {
            let name = "\(prefix)\(locale)"
            let imageset = catalog.appendingPathComponent("\(name).imageset")
            let hint = "用 scripts/compose_watch_link_intro_artwork.py 合成后放入 jifen/Assets.xcassets，否则 3.4.4 的启动介绍永远不会出现"
            guard FileManager.default.fileExists(atPath: imageset.path) else {
                XCTFail("缺少启动介绍素材 \(name).imageset；\(hint)")
                continue
            }
            // 空壳 imageset 同样会让 UIImage(named:) 返回 nil，这里连内容一起校验。
            let contents = imageset.appendingPathComponent("Contents.json")
            var files: [String] = []
            if let data = try? Data(contentsOf: contents),
               let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let images = root["images"] as? [[String: Any]] {
                files = images.compactMap { $0["filename"] as? String }
            }
            XCTAssertFalse(files.isEmpty, "\(name).imageset 没有登记任何图片文件；\(hint)")
            for file in files {
                XCTAssertTrue(
                    FileManager.default.fileExists(atPath: imageset.appendingPathComponent(file).path),
                    "\(name).imageset 缺少登记的文件 \(file)；\(hint)"
                )
            }
        }
    }
}
