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
        for id in ["nine_ball", "multi_scoreboard", "uno"] {
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
        XCTAssertEqual(Set(enabled).count, 30)
        XCTAssertTrue(ScoreboardStyleV2Registry.isEnabled(ScoreboardStyleID(rawValue: "pingpong")))
        XCTAssertTrue(ScoreboardStyleV2Registry.isEnabled(ScoreboardStyleID(rawValue: "pingpong_doubles")))
        XCTAssertTrue(ScoreboardStyleV2Registry.isEnabled(ScoreboardStyleID(rawValue: "snooker")))
        XCTAssertTrue(ScoreboardStyleV2Registry.isEnabled(ScoreboardStyleID(rawValue: "doudizhu")))
        // 排除项（对齐安卓）
        XCTAssertTrue(ScoreboardStyleV2Registry.isEnabled(ScoreboardStyleID(rawValue: "basketball")))
        XCTAssertTrue(ScoreboardStyleV2Registry.isEnabled(ScoreboardStyleID(rawValue: "three_basketball")))
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

    func testBasketballModesSupportIndependentPanelsAndTextWithoutServeControls() throws {
        for id in ["basketball", "three_basketball"] {
            let styleID = ScoreboardStyleID(rawValue: id)
            let capabilities = try XCTUnwrap(ScoreboardStyleV2Registry.capabilities(for: styleID))
            XCTAssertEqual(capabilities.elementKeys, [.teamName, .mainScore])
            XCTAssertFalse(capabilities.supportsServerIndicator)
            let profile = ScoreboardStyleProfileV2.default(for: styleID)
                .withPanelBackground("FFFFFF", for: .sideLeft)
                .withElementTextColor(.mainScore, slotKey: .sideRight, mode: .manual, colorHex: "FDD835")
            XCTAssertEqual(profile.resolvedElementTextHex(.mainScore, slotKey: .sideLeft), "111111")
            XCTAssertEqual(profile.resolvedElementTextHex(.mainScore, slotKey: .sideRight), "FDD835")
            let restored = try JSONDecoder().decode(ScoreboardStyleProfileV2.self, from: JSONEncoder().encode(profile))
            XCTAssertEqual(profile, restored)
            let wire = ScoreboardDisplayStyle(profile: restored, fontCode: "digital").projected(team0OnRight: true)
            XCTAssertEqual(wire.color("mainScore", slot: "side_left"), "#FDD835")
            XCTAssertEqual(wire.panelColor(slot: "side_right"), "#FFFFFF")
        }
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

@MainActor
extension ScoreboardStyleV2ModelTests {
    private func photoState(swapped: Bool = true, doubles: Bool = false) -> ScoreboardDisplayState {
        var profile = ScoreboardStyleProfileV2.photoTheme(for: .init(rawValue: doubles ? "pingpong_doubles" : "pingpong"))
        profile.nameFontCode = "serif"
        profile.backdrop = .init(imageData: "data:image/jpeg;base64,/9j/2Q==", dim: 0.45, panelOpacity: 0.67)
        let snapshot = ScoreboardAppearanceSnapshot(theme: .defaultTheme, styleProfileV2: profile, font: .sevenSegment,
            keepScreenOn: false, immersiveMode: false, touchGuard: false, doubleTapSubtract: false)
        var appearance = ScoreboardDisplayAppearance(snapshot: snapshot)
        appearance.style = appearance.style?.projected(team0OnRight: swapped)
        appearance.style?.fontSizeMultipliers = ["mainScore": 1.2, "teamName": 0.9, "gameScore": 1.4, "setScore": 0.8]
        return .init(gameType: doubles ? "pingpong_doubles" : "pingpong", orientation: .landscape,
            layoutKind: doubles ? .doublesCourt : .twoSide,
            teams: [.init(id: "team_0", name: "Team A", score: 11, sets: 2, order: 0),
                    .init(id: "team_1", name: "Team B", score: 8, sets: 1, order: 1)],
            matchTitle: "Community Cup", players: doubles ? [
                .init(id: "p0", name: "A1", teamID: "team_0", order: 0),
                .init(id: "p1", name: "A2", teamID: "team_0", order: 1),
                .init(id: "p2", name: "B1", teamID: "team_1", order: 2),
                .init(id: "p3", name: "B2", teamID: "team_1", order: 3)] : nil,
            sportState: ["team0ScreenSide": .string(swapped ? "right" : "left"), "servingTeam": .integer(0),
                "tableTennisTeam0Yellow": .boolean(true), "tableTennisTeam0RedCount": .integer(2)],
            appearance: appearance, updatedAt: 13, keyPoint: .init(kind: "match", side: swapped ? "right" : "left"),
            clock: .init(elapsedMilliseconds: 61_000, isRunning: false, anchorWallClockMilliseconds: 0))
    }

    func testPhotoFieldsRoundtripThroughWireForSinglesAndDoubles() throws {
        for game in ScoreboardPhotoProjects.supported.sorted() {
            let doubles = ScoreboardPhotoProjects.isDoubles(game)
            var source = photoState(doubles: doubles)
            source.gameType = game
            source.appearance.style?.serverIndicatorHidden = true
            source.appearance.style?.serverIndicatorStyle = "sport"
            let encoded = try XCTUnwrap(DisplayStateWireCodec.encode(source))
            let transport = try JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: encoded)) as! [String: Any]
            let decoded = try XCTUnwrap(DisplayStateWireCodec.decode(transport))
            XCTAssertEqual(decoded.gameType, game)
            XCTAssertEqual(decoded.appearance.style?.backdrop, source.appearance.style?.backdrop)
            XCTAssertEqual(decoded.appearance.style?.nameFontCode, "serif")
            XCTAssertEqual(decoded.appearance.style?.serverIndicatorHidden, true)
            XCTAssertEqual(decoded.appearance.style?.serverIndicatorStyle, "sport")
            XCTAssertEqual(decoded.appearance.style?.fontCode, "seven_segment")
            XCTAssertEqual(decoded.appearance.style?.fontSizeMultipliers["gameScore"], 1.4)
            XCTAssertEqual(decoded.appearance.style?.fontSizeMultipliers["setScore"], 0.8)
            XCTAssertEqual(decoded.matchTitle, source.matchTitle)
            XCTAssertEqual(decoded.keyPoint, source.keyPoint)
            XCTAssertEqual(decoded.players?.count ?? 0, doubles ? 4 : 0)
        }
    }

    /// 投屏帧只带 1 份 displayState：四端显示端都是「扫描所有参与者、取最新的那份」，
    /// 历史上为规避 PARTICIPANT_SYNC 首条旧态才给每个参与者各塞一份（双打 = 4 份纯冗余）。
    /// 这里用真实映射钉死「只有第一个参与者带 displayState，其余显式清空」。
    func testOnlyFirstParticipantCarriesDisplayState() throws {
        for doubles in [false, true] {
            let state = photoState(doubles: doubles)
            let wire = try XCTUnwrap(DisplayStateWireCodec.encode(state))
            let participants = RemoteSyncController.mapDisplayStateToParticipants(state, wire: wire)
            XCTAssertGreaterThanOrEqual(participants.count, 2)

            let firstMetadata = try XCTUnwrap(participants[0]["metadata"] as? [String: Any])
            XCTAssertNotNil(firstMetadata["displayState"], "首个参与者必须携带 displayState")
            for participant in participants.dropFirst() {
                let metadata = participant["metadata"] as? [String: Any]
                XCTAssertNil(metadata?["displayState"], "非首个参与者不得重复携带 displayState")
            }
        }
    }

    /// 整帧预算：后端实时消息硬上限 512KB（`REALTIME_MAX_PAYLOAD_BYTES`）。
    /// 单副本后最大图片（90,000 字符）× 1 份仍应远低于上限，给其它字段留足余量。
    func testLargestPhotoImageKeepsDoublesFrameWithinBackendPayloadBudget() throws {
        let prefix = "data:image/jpeg;base64,"
        let bodyLength = (ScoreboardBackdrop.imageDataCharacterLimit - prefix.count) / 4 * 4
        let image = prefix + String(repeating: "A", count: bodyLength)
        XCTAssertLessThanOrEqual(image.count, ScoreboardBackdrop.imageDataCharacterLimit)

        var state = photoState(doubles: true)
        state.appearance.style?.backdrop = .init(imageData: image, dim: 0.45, panelOpacity: 0.67)
        let wire = try XCTUnwrap(DisplayStateWireCodec.encode(state))
        let participants = RemoteSyncController.mapDisplayStateToParticipants(state, wire: wire)

        let envelope: [String: Any] = [
            "type": "participant_update",
            "payload": ["matchId": "match", "sessionPhase": "active", "replace": false, "participants": participants]
        ]
        let bytes = try JSONSerialization.data(withJSONObject: envelope).count
        XCTAssertLessThan(bytes, 512 * 1024, "整帧 \(bytes) 字节超出后端 512KB 上限")

        let metadata = try XCTUnwrap(participants[0]["metadata"] as? [String: Any])
        let displayState = try XCTUnwrap(metadata["displayState"] as? [String: Any])
        let style = try XCTUnwrap((displayState["appearance"] as? [String: Any])?["style"] as? [String: Any])
        XCTAssertEqual((style["backdrop"] as? [String: Any])?["imageData"] as? String, image)
    }

    /// 图片只在「变更的那一次」随帧下发：其余帧只带 digest，接收端按 digest 命中缓存。
    func testBackdropImageIsOnlySentWhenItChanges() throws {
        let imageData = "data:image/jpeg;base64," + Data(repeating: 0x5A, count: 240).base64EncodedString()
        var state = photoState(doubles: true)
        state.appearance.style?.backdrop = .init(imageData: imageData, dim: 0.45, panelOpacity: 0.67)
        let digest = try XCTUnwrap(state.appearance.style?.backdrop?.contentDigest)
        XCTAssertFalse(digest.isEmpty)

        // 首帧（新显示端加入）必须带图。
        let first = try XCTUnwrap(DisplayStateWireCodec.encode(state, includeBackdropImage: true))
        XCTAssertEqual(Self.backdropImageData(first), imageData)
        XCTAssertEqual(Self.backdropDigest(first), digest)

        // 图片未变：只带 digest，图片字段消失。
        ScoreboardBackdropImageCache.shared.removeAll()
        let digestOnly = try XCTUnwrap(DisplayStateWireCodec.encode(state, includeBackdropImage: false))
        XCTAssertNil(Self.backdropImageData(digestOnly))
        XCTAssertEqual(Self.backdropDigest(digestOnly), digest)

        // 接收端仅靠 digest 无法还原像素（缓存尚未写入）。
        let cold = try XCTUnwrap(DisplayStateWireCodec.decode(digestOnly))
        XCTAssertNil(cold.appearance.style?.backdrop?.imageData)

        // 先收一次带图的帧把缓存填上，再收只带 digest 的帧，图片必须还原。
        _ = try XCTUnwrap(DisplayStateWireCodec.decode(first))
        let warm = try XCTUnwrap(DisplayStateWireCodec.decode(digestOnly))
        XCTAssertEqual(warm.appearance.style?.backdrop?.imageData, imageData, "同 digest 必须命中缓存")
    }

    /// 发送策略：图片变了才带；新显示端加入必须补齐；图片被移除时不再带。
    func testBackdropImageSendPolicy() {
        XCTAssertTrue(RemoteSyncController.shouldIncludeBackdropImage(
            digest: "a", hasImage: true, lastSentDigest: "a", mustSend: true), "新显示端加入必须补图")
        XCTAssertFalse(RemoteSyncController.shouldIncludeBackdropImage(
            digest: "a", hasImage: true, lastSentDigest: "a", mustSend: false), "图片未变不得重传")
        XCTAssertTrue(RemoteSyncController.shouldIncludeBackdropImage(
            digest: "b", hasImage: true, lastSentDigest: "a", mustSend: false), "图片变更必须重传")
        XCTAssertFalse(RemoteSyncController.shouldIncludeBackdropImage(
            digest: nil, hasImage: false, lastSentDigest: "a", mustSend: false), "无图时不得带 imageData")
        XCTAssertTrue(RemoteSyncController.shouldIncludeBackdropImage(
            digest: nil, hasImage: true, lastSentDigest: nil, mustSend: false), "缺摘要时必须照常带图")
    }

    private static func backdropImageData(_ wire: [String: Any]?) -> String? {
        ((wire?["appearance"] as? [String: Any])?["style"] as? [String: Any])
            .flatMap { ($0["backdrop"] as? [String: Any])?["imageData"] as? String }
    }

    private static func backdropDigest(_ wire: [String: Any]?) -> String? {
        ((wire?["appearance"] as? [String: Any])?["style"] as? [String: Any])
            .flatMap { ($0["backdrop"] as? [String: Any])?["digest"] as? String }
    }

    /// 生产链路（LocalScoreboardSyncCoordinator → `ScoreboardDisplayState(compactState:)`）的
    /// 照片主题往返：compact 快照里的扁平 themeID 只是全局主题，V2 themeCode 与背景图必须
    /// 原样跨端，既不能被扁平 theme 覆盖，也不能因扁平 theme 不是照片主题而被清空。
    func testPhotoThemeSurvivesWireRoundTripThroughProductionCompactState() throws {
        let styleID = ScoreboardStyleID(rawValue: "pingpong")
        let imageData = "data:image/jpeg;base64," + Data(repeating: 0x7A, count: 96).base64EncodedString()
        var profile = ScoreboardStyleProfileV2.photoTheme(for: styleID)
        profile.backdrop = .init(imageData: imageData, dim: 0.45, panelOpacity: 0.67)
        let preferences = PreferencesManager.shared
        preferences.setScoreboardStyleProfilePreview(profile, for: styleID)
        defer { preferences.setScoreboardStyleProfilePreview(nil, for: styleID) }

        let compact = LocalScoreboardDisplayState(
            gameID: "pingpong",
            title: "Photo Cup",
            leftName: "A",
            rightName: "B",
            leftScore: "11",
            rightScore: "8",
            themeID: "default",
            fontID: "default",
            finished: false,
            revision: 7
        )
        let state = ScoreboardDisplayState(compactState: compact)
        XCTAssertEqual(state.appearance.theme, "default")
        XCTAssertEqual(state.appearance.style?.themeCode, "event_background")
        XCTAssertEqual(state.appearance.style?.backdrop?.imageData, imageData)

        let wire = try XCTUnwrap(DisplayStateWireCodec.encode(state))
        let appearance = try XCTUnwrap(wire["appearance"] as? [String: Any])
        // 扁平兼容字段跟随 V2 主题，样式自身的 themeCode 不被反向覆盖。
        XCTAssertEqual(appearance["theme"] as? String, "event_background")
        XCTAssertEqual((appearance["style"] as? [String: Any])?["themeCode"] as? String, "event_background")

        let transport = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONSerialization.data(withJSONObject: wire)) as? [String: Any])
        let decoded = try XCTUnwrap(DisplayStateWireCodec.decode(transport))
        XCTAssertEqual(decoded.appearance.style?.themeCode, "event_background", "照片主题的 themeCode 丢失")
        XCTAssertEqual(decoded.appearance.theme, "event_background")
        XCTAssertEqual(decoded.appearance.style?.backdrop?.imageData, imageData, "照片背景图丢失")
        XCTAssertEqual(decoded.appearance.style?.backdrop?.dim, 0.45)
        XCTAssertEqual(decoded.appearance.style?.backdrop?.panelOpacity, 0.67)
    }

    /// 解码侧不得凭空补值：编码省略的可选字段（发球指示器隐藏/样式）必须保持缺失，
    /// 否则往返结果不再 Equatable 相等、可能触发无谓刷新。
    func testAbsentServerIndicatorFieldsStayAbsentThroughWireRoundTrip() throws {
        var state = ScoreboardDisplayState(compactState: LocalScoreboardDisplayState(
            gameID: "pingpong",
            title: "",
            leftName: "A",
            rightName: "B",
            leftScore: "3",
            rightScore: "1",
            themeID: "default",
            fontID: "default",
            finished: false,
            revision: 1
        ))
        state.appearance.style?.serverIndicatorHidden = nil
        state.appearance.style?.serverIndicatorStyle = nil

        let wire = try XCTUnwrap(DisplayStateWireCodec.encode(state))
        let style = try XCTUnwrap((wire["appearance"] as? [String: Any])?["style"] as? [String: Any])
        XCTAssertNil(style["serverIndicatorHidden"], "nil 不应写出该 key")
        XCTAssertNil(style["serverIndicatorStyle"], "nil 不应写出该 key")

        let transport = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONSerialization.data(withJSONObject: wire)) as? [String: Any])
        let decoded = try XCTUnwrap(DisplayStateWireCodec.decode(transport))
        XCTAssertNil(decoded.appearance.style?.serverIndicatorHidden, "缺失字段不应被补成 false")
        XCTAssertNil(decoded.appearance.style?.serverIndicatorStyle, "缺失字段不应被补成 arrow")

        let reencoded = try XCTUnwrap(DisplayStateWireCodec.encode(decoded))
        let reStyle = try XCTUnwrap((reencoded["appearance"] as? [String: Any])?["style"] as? [String: Any])
        XCTAssertNil(reStyle["serverIndicatorHidden"])
        XCTAssertNil(reStyle["serverIndicatorStyle"])

        // 已存在的值保持原义：sport 仍是 sport，其余仍是 arrow。
        state.appearance.style?.serverIndicatorHidden = false
        state.appearance.style?.serverIndicatorStyle = "sport"
        let presentWire = try XCTUnwrap(DisplayStateWireCodec.encode(state))
        let presentStyle = try XCTUnwrap((presentWire["appearance"] as? [String: Any])?["style"] as? [String: Any])
        XCTAssertEqual(presentStyle["serverIndicatorHidden"] as? Bool, false)
        XCTAssertEqual(presentStyle["serverIndicatorStyle"] as? String, "sport")
        let presentTransport = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONSerialization.data(withJSONObject: presentWire)) as? [String: Any])
        let presentDecoded = try XCTUnwrap(DisplayStateWireCodec.decode(presentTransport))
        XCTAssertEqual(presentDecoded.appearance.style?.serverIndicatorHidden, false)
        XCTAssertEqual(presentDecoded.appearance.style?.serverIndicatorStyle, "sport")
    }

    func testPhotoProjectionMapsSwappedLogicalTeamsPlayersCardsAndServe() {
        for doubles in [false, true] {
            let state = photoState(doubles: doubles)
            let left = ScoreboardPhotoProjection.team(state, visualIndex: 0)
            let right = ScoreboardPhotoProjection.team(state, visualIndex: 1)
            XCTAssertEqual(left.name, doubles ? "B1 / B2" : "Team B")
            XCTAssertEqual(right.name, doubles ? "A1 / A2" : "Team A")
            XCTAssertEqual(left.score, "8"); XCTAssertEqual(right.score, "11")
            XCTAssertEqual(left.sets, "1"); XCTAssertEqual(right.sets, "2")
            XCTAssertEqual(right.badgeKind, "match")
            XCTAssertTrue(right.markers.hasYellowCard); XCTAssertEqual(right.markers.redCardCount, 2)
            XCTAssertEqual(ScoreboardPhotoProjection.servingLeft(state), false)
        }
    }

    func testPhotoNormalizationAndLegacyFontCompatibility() throws {
        let invalid = ScoreboardBackdrop(imageData: "file:///private.jpg", dim: .nan, panelOpacity: -.infinity).normalized()
        XCTAssertNil(invalid.imageData); XCTAssertEqual(invalid.dim, 0.30); XCTAssertEqual(invalid.panelOpacity, 0.84)
        let profile = ScoreboardStyleProfileV2.default(for: .init(rawValue: "pingpong"))
        // 新建 profile 不写死队名字体：nil 表示跟随全局计分字体（写死 "default" 会把队名钉死在系统字体）。
        XCTAssertNil(profile.nameFontCode, "新建样式默认跟随全局计分字体")
        var custom = profile; custom.nameFontCode = "rounded"; custom.serverIndicatorHidden = true; custom.serverIndicatorStyle = "sport"
        custom.backdrop = .init(imageData: "data:image/jpeg;base64,/9j/2Q==")
        XCTAssertEqual(try JSONDecoder().decode(ScoreboardStyleProfileV2.self, from: JSONEncoder().encode(custom)), custom)
        XCTAssertNil(ScoreboardDisplayStyle(profile: custom, fontCode: "digital").backdrop)
        custom.themeCode = "event_background"
        XCTAssertNotNil(ScoreboardDisplayStyle(profile: custom, fontCode: "digital").backdrop)
    }

    func testPhotoNativeVisualScoreOverridesKeepLogicalNamesAndRosters() {
        for doubles in [false, true] {
            var state = photoState(doubles: doubles)
            state.sportState?["leftDisplayScore"] = .string("8")
            state.sportState?["rightDisplayScore"] = .string("11")
            XCTAssertEqual(ScoreboardPhotoProjection.team(state, visualIndex: 0).name, doubles ? "B1 / B2" : "Team B")
            XCTAssertEqual(ScoreboardPhotoProjection.team(state, visualIndex: 1).name, doubles ? "A1 / A2" : "Team A")
        }
    }

    /// 发球指示器样式必须能在草稿里往返保存（编辑面板点击后依赖这个字段）。
    func testServerIndicatorStyleSurvivesNormalizeAndWire() throws {
        for styleID in ["pingpong", "badminton"] {
            let base = ScoreboardStyleProfileV2.default(for: .init(rawValue: styleID))
            var edited = base
            edited.serverIndicatorStyle = "sport"
            XCTAssertEqual(edited.normalized().serverIndicatorStyle, "sport")
            let data = try JSONEncoder().encode(edited)
            let decoded = try JSONDecoder().decode(ScoreboardStyleProfileV2.self, from: data)
            XCTAssertEqual(decoded.serverIndicatorStyle, "sport")
            var back = decoded
            back.serverIndicatorStyle = "arrow"
            XCTAssertEqual(back.normalized().serverIndicatorStyle, "arrow")
        }
    }

    func testPresetThemesKeepManualAndAutomaticTextEdits() {
        for theme in [ScoreboardTheme.proDark, .brb, .wrb] {
            let profile = ScoreboardStyleProfileV2.default(for: .init(rawValue: "pingpong"), theme: theme)
            let manual = profile.withElementTextColor(.mainScore, slotKey: .sideLeft, mode: .manual, colorHex: "FDD835").normalized()
            XCTAssertEqual(manual.resolvedElementTextHex(.mainScore, slotKey: .sideLeft), "FDD835")
            let automatic = manual.withElementTextColor(.mainScore, slotKey: .sideLeft, mode: .auto, colorHex: "FDD835").normalized()
            XCTAssertFalse(automatic.elementHasManualColor(.mainScore, slotKey: .sideLeft))
        }
    }

    func testPhotoDefaultTextIsWhiteOnBothPanelsAndKeepsManualOverrides() {
        for id in ["pingpong", "pingpong_doubles"] {
            let profile = ScoreboardStyleProfileV2.photoTheme(for: .init(rawValue: id))
            let keys: [ScoreboardStyleElementKeyV2] = id == "pingpong" ? [.teamName, .mainScore, .setScore] : [.playerName, .mainScore, .setGameScore]
            for slot in [ScoreboardStyleSlotKeyV2.sideLeft, .sideRight] {
                for key in keys { XCTAssertEqual(profile.resolvedElementTextHex(key, slotKey: slot), "FFFFFF") }
            }
            let manual = profile.withElementTextColor(.mainScore, slotKey: .sideRight, mode: .manual, colorHex: "FDD835").normalized()
            XCTAssertEqual(manual.resolvedElementTextHex(.mainScore, slotKey: .sideRight), "FDD835")
        }
    }

    /// 复古主题是黑底绿字：AUTO 自动对比在纯黑底上会选白字，必须显式给手动绿字，
    /// 否则预览与投屏都会丢掉主题色（回归：用户报告“复古预览是黑底白字”）。
    /// 可复算证据：`docs/verification/audit-remediation-2026-10-25/ios-final.log` 中
    /// `THEME[retro] … fg=00FF00` 与紧随其后的 `resolvedText t0=FFFFFF t1=FFFFFF`
    /// 记录了修复前的黑底白字结果。
    func testRetroThemeKeepsGreenTextInsteadOfAutoContrastWhite() throws {
        for styleID in ["basketball", "pingpong", "badminton"] {
            let profile = ScoreboardStyleProfileV2.default(
                for: ScoreboardStyleID(rawValue: styleID),
                theme: .retro
            )
            XCTAssertEqual(profile.themeCode, "retro", "\(styleID) theme code")
            for slot in [ScoreboardStyleSlotKeyV2.sideLeft, .sideRight] {
                XCTAssertEqual(profile.slotBackgroundHex(slot), "000000", "\(styleID) retro panel stays black")
                for key in [ScoreboardStyleElementKeyV2.teamName, .mainScore] {
                    XCTAssertEqual(
                        profile.resolvedElementTextHex(key, slotKey: slot),
                        "00FF00",
                        "\(styleID) retro must render green text on \(slot.rawValue)"
                    )
                }
            }
        }
        // 其它主题保持原有行为：纯黑底的 electronic 仍是白字。
        let electronic = ScoreboardStyleProfileV2.default(
            for: ScoreboardStyleID(rawValue: "basketball"),
            theme: .electronic
        )
        XCTAssertEqual(electronic.resolvedElementTextHex(.mainScore, slotKey: .sideLeft), "FFFFFF")
    }

    func testPhotoUndoKeepsNewOpacityAndDimAndExpires() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let undo = ScoreboardPhotoImageUndo(imageData: "original", now: now)
        let adjusted = ScoreboardBackdrop(imageData: nil, dim: 0.52, panelOpacity: 0.71)
        let restored = try XCTUnwrap(undo.restoring(adjusted, now: now.addingTimeInterval(4)))
        XCTAssertEqual(restored.imageData, "original")
        XCTAssertEqual(restored.dim, 0.52)
        XCTAssertEqual(restored.panelOpacity, 0.71)
        XCTAssertNil(undo.restoring(adjusted, now: now.addingTimeInterval(5)))
    }
}
