//
//  ScoreboardStyleV2ModelTests.swift
//  jifen
//
//  阶段 1 模型升级测试：向后兼容解码、槽位化读写、传播、归一化、能力注册表、颜色数学。
//

import XCTest
@testable import jifen

final class ScoreboardStyleV2ModelTests: XCTestCase {
    // MARK: - 向后兼容解码

    func testDecodingLegacyFlatJSONKeepsNilV2Fields() throws {
        let legacyJSON = """
        {"themeCode":"default","team0Hex":"FF3B30","team1Hex":"007AFF","centerHex":"4CAF50",
         "team0TextHex":"FFFFFF","team1TextHex":"FFFFFF","centerTextHex":"FFFFFF",
         "foregroundHex":"FFFFFF","backgroundHex":"000000","autoContrast":true}
        """.data(using: .utf8)!
        let profile = try JSONDecoder().decode(ScoreboardStyleProfileV2.self, from: legacyJSON)
        XCTAssertNil(profile.panels)
        XCTAssertNil(profile.elements)
        XCTAssertNil(profile.serverIndicatorColorHex)
        XCTAssertFalse(profile.hasV2StyleData)
        XCTAssertEqual(profile.team0Hex, "FF3B30")
    }

    func testRoundTripKeepsSlotData() throws {
        let base = ScoreboardStyleProfileV2.default(for: ScoreboardStyleID(rawValue: "pingpong"))
            .withPanelBackground("112233", for: .sideLeft)
            .withElementTextColor(.mainScore, slotKey: .sideRight, mode: .manual, colorHex: "#00ff88")
            .withServerIndicatorColor("30D158")
        let data = try JSONEncoder().encode(base)
        let decoded = try JSONDecoder().decode(ScoreboardStyleProfileV2.self, from: data)
        XCTAssertEqual(decoded, base)
        XCTAssertEqual(decoded.slotBackgroundHex(.sideLeft), "112233")
        XCTAssertEqual(
            decoded.resolvedElementTextHex(.mainScore, slotKey: .sideRight),
            "00FF88"
        )
        XCTAssertEqual(decoded.serverIndicatorColorHex, "30D158")
    }

    func testInvalidColorsDroppedOnDecodeAndNormalize() throws {
        let json = """
        {"themeCode":"default","team0Hex":"FF3B30","team1Hex":"007AFF","centerHex":"4CAF50",
         "team0TextHex":"FFFFFF","team1TextHex":"FFFFFF","centerTextHex":"FFFFFF",
         "panels":[{"slotKey":"side_left","backgroundColor":"ZZZZZZ"},
                    {"slotKey":"side_right","backgroundColor":"00ff88"}],
         "elements":[{"elementKey":"main_score","textColors":[
            {"slotKey":"side_left","colorMode":"manual","colorHex":"nothex"},
            {"slotKey":"side_right","colorMode":"manual","colorHex":"FFFFFF"}]}]}
        """.data(using: .utf8)!
        var profile = try JSONDecoder().decode(ScoreboardStyleProfileV2.self, from: json)
        profile = profile.normalized()
        XCTAssertEqual(profile.panels?.count, 1)
        XCTAssertEqual(profile.panels?.first?.backgroundColorHex, "00FF88")
        XCTAssertEqual(profile.elements?.first?.textColors.count, 1)
        XCTAssertEqual(profile.elements?.first?.textColors.first?.colorHex, "FFFFFF")
    }

    // MARK: - 槽位化读写与回落

    func testSlotBackgroundFallsBackToLegacyFields() {
        // 无 V2 panels 的旧扁平数据形态：槽位回落旧字段。
        var profile = ScoreboardStyleProfileV2.default(for: ScoreboardStyleID(rawValue: "pingpong"))
        profile.panels = nil
        profile.team0Hex = "ABCDEF"
        XCTAssertEqual(profile.slotBackgroundHex(.sideLeft), "ABCDEF")
        XCTAssertEqual(profile.slotBackgroundHex(.sideCenter), "1B5E20")
    }

    func testPanelBackgroundMirrorsLegacyFlatFields() {
        let profile = ScoreboardStyleProfileV2.default(for: ScoreboardStyleID(rawValue: "pingpong"))
            .withPanelBackground("112233", for: .sideLeft)
        XCTAssertEqual(profile.team0Hex, "112233")
        // 默认样式已含左右两个 V2 面板，编辑只改对应槽位。
        XCTAssertEqual(profile.panels?.count, 2)
    }

    func testElementTextAutoModeResolvesFromPanelBackground() {
        var profile = ScoreboardStyleProfileV2.default(for: ScoreboardStyleID(rawValue: "pingpong"))
        profile = profile.withPanelBackground("000000", for: .sideRight)
            .withElementTextColor(.mainScore, slotKey: .sideRight, mode: .auto, colorHex: "FFFFFF")
        XCTAssertEqual(
            profile.resolvedElementTextHex(.mainScore, slotKey: .sideRight),
            "FFFFFF" // 黑底自动 → 白
        )
        XCTAssertEqual(
            profile.resolvedElementTextHex(.teamName, slotKey: .sideRight),
            "FFFFFF"
        )
    }

    func testTextColorPropagationWritesSameSideElements() {
        let capabilities = ScoreboardStyleEditCapabilities.capabilities(
            elementKeys: [.teamName, .mainScore, .setScore]
        )
        let profile = ScoreboardStyleProfileV2.default(for: ScoreboardStyleID(rawValue: "pingpong"))
            .withElementTextColor(.mainScore, slotKey: .sideLeft, mode: .manual, colorHex: "FF0000")
            .applyingTextColorToSameSide(elementKey: .mainScore, slotKey: .sideLeft, capabilities: capabilities)
        for key in capabilities.sideElementKeys where key != .mainScore {
            XCTAssertEqual(profile.resolvedElementTextHex(key, slotKey: .sideLeft), "FF0000")
        }
        // 右侧槽位不受影响
        XCTAssertNotEqual(
            profile.resolvedElementTextHex(.mainScore, slotKey: .sideRight),
            "FF0000"
        )
    }

    // MARK: - 默认样式 1:1 复刻（对齐安卓 defaultScoreboardStyleProfileV2）

    func testGenericDefaultProfileReplicatesAndroidThemeColors() {
        let profile = ScoreboardStyleProfileV2.default(for: ScoreboardStyleID(rawValue: "pingpong"))
        // 面板取主题基色（对齐安卓 scoreboardThemeByName("default")）。
        XCTAssertEqual(profile.panels?.first(where: { $0.slotKey == .sideLeft })?.backgroundColorHex, "C62828")
        XCTAssertEqual(profile.panels?.first(where: { $0.slotKey == .sideRight })?.backgroundColorHex, "007AFF")
        // default 主题左右面板基色上固定白字（安卓 resolvedAutoTextColor 特例）。
        XCTAssertEqual(profile.resolvedElementTextHex(.mainScore, slotKey: .sideLeft), "FFFFFF")
        XCTAssertEqual(profile.resolvedElementTextHex(.mainScore, slotKey: .sideRight), "FFFFFF")
        // 元素走 AUTO 模式，自定义背景后恢复 WCAG 自动对比。
        let entry = profile.elements?.first(where: { $0.elementKey == .mainScore })
        XCTAssertEqual(entry?.textColors.first(where: { $0.slotKey == .sideLeft })?.colorMode, .auto)
        let custom = profile.withPanelBackground("112233", for: .sideLeft)
        XCTAssertEqual(
            custom.resolvedElementTextHex(.mainScore, slotKey: .sideLeft),
            ScoreboardStyleProfileV2.autoTextHex(for: "112233")
        )
    }

    func testLegacyDefaultPanelsKeepWhiteTextWithoutDisablingCustomAutoContrast() {
        for id in ["basketball", "three_basketball", "nine_ball", "multi_scoreboard", "uno"] {
            var profile = ScoreboardStyleProfileV2.default(for: ScoreboardStyleID(rawValue: id))
            XCTAssertEqual(profile.resolvedTextHex(for: .team0), "FFFFFF", id)
            XCTAssertEqual(profile.resolvedTextHex(for: .center), "FFFFFF", id)
            profile.team0Hex = "FFFFFF"
            XCTAssertEqual(profile.resolvedTextHex(for: .team0), "111111", id)
        }
    }

    func testBrbWrbDefaultsUseFixedManualTextColors() {
        let brb = ScoreboardStyleProfileV2.default(for: ScoreboardStyleID(rawValue: "pingpong"), theme: .brb)
        XCTAssertEqual(brb.panels?.first(where: { $0.slotKey == .sideLeft })?.backgroundColorHex, "000000")
        XCTAssertEqual(brb.panels?.first(where: { $0.slotKey == .sideRight })?.backgroundColorHex, "000000")
        XCTAssertEqual(brb.resolvedElementTextHex(.mainScore, slotKey: .sideLeft), "FF0000")
        XCTAssertEqual(brb.resolvedElementTextHex(.mainScore, slotKey: .sideRight), "1E5BFF")
        // 渲染键并集：TEAM_NAME/SET_SCORE 等不在能力键内也必须有红/蓝（白底白字防护）。
        XCTAssertNotNil(brb.elements?.first(where: { $0.elementKey == .teamName }))
        XCTAssertNotNil(brb.elements?.first(where: { $0.elementKey == .setScore }))

        let wrb = ScoreboardStyleProfileV2.default(for: ScoreboardStyleID(rawValue: "pingpong"), theme: .wrb)
        XCTAssertEqual(wrb.panels?.first(where: { $0.slotKey == .sideLeft })?.backgroundColorHex, "FFFFFF")
        XCTAssertEqual(wrb.resolvedElementTextHex(.mainScore, slotKey: .sideLeft), "FF0000")
    }

    func testProDarkDefaultForcesWhiteText() {
        let profile = ScoreboardStyleProfileV2.default(for: ScoreboardStyleID(rawValue: "pingpong"), theme: .proDark)
        XCTAssertEqual(profile.themeCode, "pro_dark")
        XCTAssertEqual(profile.resolvedElementTextHex(.mainScore, slotKey: .sideLeft), "FFFFFF")
        XCTAssertEqual(profile.resolvedElementTextHex(.mainScore, slotKey: .sideRight), "FFFFFF")
        XCTAssertEqual(
            profile.resolvedElementTextHex(.mainScore, slotKey: .sideLeft),
            "FFFFFF"
        )
        // pro_dark 特例：任意自定义背景仍固定白字（对齐安卓 resolvedAutoTextColor）。
        let custom = profile.withPanelBackground("FFFFFF", for: .sideLeft)
        XCTAssertEqual(custom.resolvedElementTextHex(.mainScore, slotKey: .sideLeft), "FFFFFF")
    }

    func testDoudizhuDefaultProfileReplicatesAndroidThreePanels() {
        let classic = ScoreboardStyleProfileV2.default(for: ScoreboardStyleID(gameType: .doudizhu))
        XCTAssertEqual(classic.themeCode, "ddz_classic")
        XCTAssertEqual(classic.panels?.first(where: { $0.slotKey == .sideLeft })?.backgroundColorHex, "C62828")
        XCTAssertEqual(classic.panels?.first(where: { $0.slotKey == .sideCenter })?.backgroundColorHex, "34C759")
        XCTAssertEqual(classic.panels?.first(where: { $0.slotKey == .sideRight })?.backgroundColorHex, "1565C0")
        // 经典：中间面板队名/大分固定白字，左右走 AUTO。
        XCTAssertEqual(classic.resolvedElementTextHex(.mainScore, slotKey: .sideCenter), "FFFFFF")
        XCTAssertEqual(classic.resolvedElementTextHex(.mainScore, slotKey: .sideLeft), "FFFFFF")

        let brb = ScoreboardStyleProfileV2.default(for: ScoreboardStyleID(gameType: .doudizhu), theme: .ddzBrb)
        XCTAssertEqual(brb.themeCode, "ddz_brb")
        XCTAssertEqual(brb.resolvedElementTextHex(.mainScore, slotKey: .sideLeft), "FF0000")
        XCTAssertEqual(brb.resolvedElementTextHex(.mainScore, slotKey: .sideCenter), "34C759")
        XCTAssertEqual(brb.resolvedElementTextHex(.mainScore, slotKey: .sideRight), "1E5BFF")

        let wrb = ScoreboardStyleProfileV2.default(for: ScoreboardStyleID(gameType: .doudizhu), theme: .ddzWrb)
        XCTAssertEqual(wrb.resolvedElementTextHex(.mainScore, slotKey: .sideCenter), "1B5E20")

        let retro = ScoreboardStyleProfileV2.default(for: ScoreboardStyleID(gameType: .doudizhu), theme: .ddzRetro)
        XCTAssertEqual(retro.resolvedElementTextHex(.mainScore, slotKey: .sideLeft), "4CAF50")
        XCTAssertEqual(retro.resolvedElementTextHex(.mainScore, slotKey: .sideCenter), "4CAF50")
        // 复古仅主分绿色；队名走 AUTO（黑底 → 白）。
        XCTAssertEqual(retro.resolvedElementTextHex(.teamName, slotKey: .sideLeft), "FFFFFF")

        // 旧通用主题码迁移到 ddz_*（对齐安卓 doudizhuThemeOrDefault）。
        let migrated = ScoreboardStyleProfileV2.default(for: ScoreboardStyleID(gameType: .doudizhu), theme: .defaultTheme)
        XCTAssertEqual(migrated.themeCode, "ddz_classic")
    }

    func testThemePreviewDescriptorMatchesAndroidThemeIcons() {
        // 经典：红/蓝半区铺满 + 白色数字。
        let classic = ScoreboardTheme.defaultTheme.previewDescriptor
        XCTAssertEqual(classic.backgroundHex, "C62828")
        XCTAssertEqual(classic.leftHex, "C62828")
        XCTAssertEqual(classic.rightHex, "007AFF")
        XCTAssertEqual(classic.leftDigitHex, "FFFFFF")
        XCTAssertNil(classic.centerDigitHex)

        // 黑红蓝：纯黑底 + 细缝 + 红/蓝数字。
        let brb = ScoreboardTheme.brb.previewDescriptor
        XCTAssertEqual(brb.backgroundHex, "000000")
        XCTAssertNil(brb.leftHex)
        XCTAssertEqual(brb.seamHex, "1A1A1A")
        XCTAssertEqual(brb.leftDigitHex, "FF0000")
        XCTAssertEqual(brb.rightDigitHex, "1E5BFF")

        // 斗地主经典：三栏 + 白色数字。
        let ddz = ScoreboardTheme.ddzClassic.previewDescriptor
        XCTAssertEqual(ddz.leftHex, "C62828")
        XCTAssertEqual(ddz.centerHex, "34C759")
        XCTAssertEqual(ddz.rightHex, "1565C0")
        XCTAssertNotNil(ddz.centerDigitHex)

        // 白红蓝：纯白底 + 红/绿/蓝数字。
        let ddzWrb = ScoreboardTheme.ddzWrb.previewDescriptor
        XCTAssertEqual(ddzWrb.backgroundHex, "FFFFFF")
        XCTAssertEqual(ddzWrb.centerDigitHex, "1B5E20")
    }

    // MARK: - 能力注册表

    func testRegistryMatchesAndroidWhitelist() {
        let enabled = ScoreboardStyleV2Registry.enabledStyleIDs.map(\.rawValue)
        XCTAssertEqual(Set(enabled).count, 28)
        XCTAssertTrue(ScoreboardStyleV2Registry.isEnabled(ScoreboardStyleID(rawValue: "pingpong")))
        XCTAssertTrue(ScoreboardStyleV2Registry.isEnabled(ScoreboardStyleID(rawValue: "pingpong_doubles")))
        XCTAssertTrue(ScoreboardStyleV2Registry.isEnabled(ScoreboardStyleID(rawValue: "snooker")))
        XCTAssertTrue(ScoreboardStyleV2Registry.isEnabled(ScoreboardStyleID(rawValue: "doudizhu")))
        // 排除项（对齐安卓）
        XCTAssertFalse(ScoreboardStyleV2Registry.isEnabled(ScoreboardStyleID(rawValue: "basketball")))
        XCTAssertFalse(ScoreboardStyleV2Registry.isEnabled(ScoreboardStyleID(rawValue: "three_basketball")))
        XCTAssertFalse(ScoreboardStyleV2Registry.isEnabled(ScoreboardStyleID(rawValue: "nine_ball")))
        XCTAssertFalse(ScoreboardStyleV2Registry.isEnabled(ScoreboardStyleID(rawValue: "uno")))
        XCTAssertFalse(ScoreboardStyleV2Registry.isEnabled(ScoreboardStyleID(rawValue: "multi_scoreboard")))
        XCTAssertFalse(ScoreboardStyleV2Registry.isEnabled(ScoreboardStyleID(rawValue: "go")))
    }

    func testSnookerCapabilitiesIncludeGlobalMatchTitle() throws {
        let capabilities = try XCTUnwrap(ScoreboardStyleV2Registry.capabilities(for: ScoreboardStyleID(rawValue: "snooker")))
        XCTAssertEqual(capabilities.elementKeys.first, .matchTitle)
        XCTAssertEqual(capabilities.globalElementKeys, [.matchTitle])
        XCTAssertEqual(capabilities.sideElementKeys, [.teamName, .mainScore, .setScore])
    }

    func testDoudizhuHasThreeSlots() throws {
        let capabilities = try XCTUnwrap(ScoreboardStyleV2Registry.capabilities(for: ScoreboardStyleID(rawValue: "doudizhu")))
        XCTAssertEqual(capabilities.slotKeys, [.sideLeft, .sideCenter, .sideRight])
        XCTAssertFalse(capabilities.supportsServerIndicator)
    }

    // MARK: - 颜色数学

    func testContrastRatioBoundaries() {
        XCTAssertEqual(ScoreboardStyleColorMath.contrastRatio("000000", "FFFFFF"), 21, accuracy: 0.01)
        XCTAssertEqual(ScoreboardStyleColorMath.contrastRatio("000000", "000000"), 1, accuracy: 0.001)
        XCTAssertTrue(ScoreboardStyleColorMath.isReadableTextColor("FFFFFF", on: "000000"))
        XCTAssertFalse(ScoreboardStyleColorMath.isReadableTextColor("111111", on: "000000"))
    }

    func testHSVRoundTrip() {
        let hex = ScoreboardStyleColorMath.hsvToHex(.init(hue: 120, saturation: 1, value: 1))
        XCTAssertEqual(hex, "00FF00")
        let hsv = ScoreboardStyleColorMath.colorToHsv("00FF00")
        XCTAssertEqual(hsv?.hue ?? -1, 120, accuracy: 0.5)
        XCTAssertEqual(hsv?.saturation ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(hsv?.value ?? -1, 1, accuracy: 0.001)
    }

    func testColorWheelCenterIsWhiteEdgeIsSaturated() {
        XCTAssertEqual(ScoreboardStyleColorMath.colorWheelPointToHex(pointX: 0, pointY: 0), "FFFFFF")
        let right = ScoreboardStyleColorMath.colorWheelPointToHex(pointX: 1, pointY: 0)
        XCTAssertEqual(right, "FF0000") // 0° = 红
        let up = ScoreboardStyleColorMath.colorWheelPointToHex(pointX: 0, pointY: -1)
        XCTAssertEqual(up, "8000FF") // -90° ≈ 270° = 紫
    }

    func testMixHexInterpolates() {
        XCTAssertEqual(ScoreboardStyleColorMath.mixHex("000000", "FFFFFF", t: 0), "000000")
        XCTAssertEqual(ScoreboardStyleColorMath.mixHex("000000", "FFFFFF", t: 1), "FFFFFF")
        XCTAssertEqual(ScoreboardStyleColorMath.mixHex("000000", "FFFFFF", t: 0.5), "808080")
        XCTAssertNil(ScoreboardStyleColorMath.mixHex("zz", "FFFFFF", t: 0.5))
    }
}

private extension ScoreboardStyleProfileV2 {
    func withServerIndicatorColor(_ hex: String) -> Self {
        var copy = self
        copy.serverIndicatorColorHex = ScoreboardStyleProfileV2.normalizedHex(hex)
        return copy
    }
}
