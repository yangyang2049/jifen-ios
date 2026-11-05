//
//  ScoreboardStyleEditorControllerTests.swift
//  jifen
//
//  阶段 2 编辑会话 Controller 测试：draft/active/revision、编辑中防覆盖、
//  取消恢复、保存落盘 + revision 自增、字号会话联动（含真实 ScoreboardTypographySession
//  下的重置收敛与持久化清理）。
//

import XCTest
@testable import jifen

@MainActor
final class ScoreboardStyleEditorControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var preferences: PreferencesManager!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ScoreboardStyleEditorControllerTests")
        defaults.removePersistentDomain(forName: "ScoreboardStyleEditorControllerTests")
        preferences = PreferencesManager(defaults: defaults)
    }

    override func tearDown() {
        // updateDraft 的实时预览写入共享 PreferencesManager（内存态），测试结束统一清理。
        for styleID in ["pingpong", "doudizhu"] {
            PreferencesManager.shared.setScoreboardStyleProfilePreview(
                nil,
                for: ScoreboardStyleID(rawValue: styleID)
            )
        }
        preferences = nil
        defaults = nil
        super.tearDown()
    }

    private func makeController(styleID: ScoreboardStyleID = ScoreboardStyleID(rawValue: "pingpong")) -> ScoreboardStyleEditorController {
        ScoreboardStyleEditorController(
            styleID: styleID,
            capabilities: ScoreboardStyleV2Registry.capabilities(for: styleID),
            preferences: preferences
        )
    }

    func testInitialStateMirrorsPreferences() {
        let controller = makeController()
        XCTAssertFalse(controller.isEditing)
        XCTAssertFalse(controller.isSaving)
        XCTAssertEqual(controller.effective, controller.active)
        XCTAssertEqual(controller.effective, ScoreboardStyleProfileV2.default(for: ScoreboardStyleID(rawValue: "pingpong"), theme: .defaultTheme))
        XCTAssertFalse(controller.canResetDraft)
    }

    func testOpenAndEditDraftDoNotTouchActive() {
        let controller = makeController()
        controller.open(typographySession: nil)
        XCTAssertTrue(controller.isEditing)

        let edited = controller.active.withPanelBackground("112233", for: .sideLeft)
        controller.updateDraft(edited)
        XCTAssertEqual(controller.effective.slotBackgroundHex(.sideLeft), "112233")
        XCTAssertNotEqual(controller.active, controller.draft)
        XCTAssertTrue(controller.canResetDraft)
    }

    func testUpdateFromPreferencesSkipsWhileEditing() {
        let controller = makeController()
        controller.open(typographySession: nil)
        controller.updateDraft(controller.active.withPanelBackground("112233", for: .sideLeft))

        // 模拟外部配置变化（编辑中必须跳过）
        controller.updateFromPreferences()
        XCTAssertEqual(controller.draft.slotBackgroundHex(.sideLeft), "112233")
    }

    func testUpdateFromPreferencesReloadsAfterEditingEnds() {
        let controller = makeController()
        let original = controller.active
        controller.open(typographySession: nil)
        controller.updateDraft(original.withPanelBackground("112233", for: .sideLeft))
        controller.cancel()

        XCTAssertFalse(controller.isEditing)
        XCTAssertEqual(controller.effective, original)

        // 保存一份新样式后，非编辑态同步生效
        preferences.setScoreboardStyleProfileV2(original.withPanelBackground("445566", for: .sideRight), for: controller.styleID)
        controller.updateFromPreferences()
        XCTAssertEqual(controller.effective.slotBackgroundHex(.sideRight), "445566")
    }

    func testCancelRestoresActiveAndDiscardsDraft() {
        let controller = makeController()
        let active = controller.active
        controller.open(typographySession: nil)
        var draft = controller.active
        draft.serverIndicatorColorHex = "30D158"
        controller.updateDraft(draft)
        controller.cancel()

        XCTAssertFalse(controller.isEditing)
        XCTAssertEqual(controller.effective, active)
        // 默认样式现已 1:1 携带 V2 panels/elements（对齐安卓），取消后 draft 应回到 active
        XCTAssertEqual(controller.draft, active)
    }

    func testBasketballSaveAndCancelKeepModesIndependent() {
        let basketball = makeController(styleID: ScoreboardStyleID(rawValue: "basketball"))
        let three = makeController(styleID: ScoreboardStyleID(rawValue: "three_basketball"))
        let untouched = three.active
        basketball.open(typographySession: nil)
        var custom = basketball.active.withPanelBackground("FFFFFF", for: .sideLeft)
            .withElementTextColor(.mainScore, slotKey: .sideRight, mode: .manual, colorHex: "FDD835")
        custom.nameFontCode = "serif"
        basketball.updateDraft(custom)
        guard case .success = basketball.save() else { return XCTFail("save failed") }
        XCTAssertEqual(preferences.scoreboardStyleProfileV2(for: basketball.styleID), custom.normalized())
        basketball.open(typographySession: nil)
        basketball.updateDraft(custom.withPanelBackground("123456", for: .sideLeft))
        basketball.cancel()
        XCTAssertEqual(basketball.effective, custom.normalized())
        three.updateFromPreferences()
        XCTAssertEqual(three.active, untouched)
        three.open(typographySession: nil)
        three.updateDraft(three.active.withPanelBackground("445566", for: .sideRight))
        guard case .success = three.save() else { return XCTFail("3x3 save failed") }
        basketball.updateFromPreferences()
        XCTAssertEqual(basketball.active, custom.normalized())
    }

    func testSavePersistsProfileAndBumpsRevision() {
        let controller = makeController()
        let revisionBefore = preferences.scoreboardRevision
        controller.open(typographySession: nil)
        controller.updateDraft(controller.active
            .withPanelBackground("112233", for: .sideLeft)
            .withElementTextColor(.mainScore, slotKey: .sideRight, mode: .manual, colorHex: "#00ff88"))

        let result = controller.save()
        guard case .success = result else {
            return XCTFail("save should succeed")
        }
        XCTAssertFalse(controller.isEditing)
        XCTAssertFalse(controller.isSaving)
        XCTAssertEqual(controller.active.slotBackgroundHex(.sideLeft), "112233")
        XCTAssertEqual(controller.active.resolvedElementTextHex(.mainScore, slotKey: .sideRight), "00FF88")
        XCTAssertGreaterThan(preferences.scoreboardRevision, revisionBefore)
        XCTAssertEqual(controller.revision, preferences.scoreboardRevision)

        // 落盘数据可读回
        let persisted = preferences.scoreboardStyleProfileV2(for: controller.styleID)
        XCTAssertEqual(persisted.slotBackgroundHex(.sideLeft), "112233")
    }

    func testSaveNormalizesInvalidColors() {
        let controller = makeController()
        controller.open(typographySession: nil)
        var draft = controller.active
        draft.panels = [ScoreboardStylePanelV2(slotKey: .sideLeft, backgroundColorHex: "ZZZZZZ")]
        controller.updateDraft(draft)

        _ = controller.save()
        XCTAssertNil(controller.active.panels, "非法色值面板应在保存时被清洗")
    }

    func testDiagnosticThemeSelectionPalette() {
        let controller = makeController()
        controller.open(typographySession: nil)
        for theme in ScoreboardTheme.allCases {
            let themed = ScoreboardStyleProfileV2.default(for: controller.styleID, theme: theme)
            print("THEME[\(theme.rawValue)] team0=\(themed.team0Hex) team1=\(themed.team1Hex) bg=\(themed.backgroundHex) fg=\(themed.foregroundHex) auto=\(themed.autoContrast) panels=\(themed.panels.map { $0.map { "\($0.slotKey.rawValue):\($0.backgroundColorHex)" }.joined(separator: ",") } ?? "nil")")
            print("  resolvedText t0=\(themed.resolvedTextHex(for: .team0)) t1=\(themed.resolvedTextHex(for: .team1)) slotL=\(themed.slotBackgroundHex(.sideLeft)) slotR=\(themed.slotBackgroundHex(.sideRight))")
        }
        controller.updateDraft(ScoreboardStyleProfileV2.default(for: controller.styleID, theme: .brb))
        _ = controller.save()
        let snapshot = ScoreboardAppearanceSnapshot.current(styleID: controller.styleID, preferences)
        print("SNAPSHOT theme=\(snapshot.theme.rawValue) palette.bg-l-r=\(snapshot.palette.left) fg=\(snapshot.palette.foreground)")
    }

    func testResetDraftRestoresDefaultStyle() {
        let controller = makeController()
        controller.open(typographySession: nil)
        controller.updateDraft(controller.active.withPanelBackground("112233", for: .sideLeft))
        XCTAssertTrue(controller.canResetDraft)

        controller.resetDraft()
        XCTAssertFalse(controller.canResetDraft)
        XCTAssertEqual(controller.draft, ScoreboardStyleProfileV2.default(for: controller.styleID))
    }

    /// 工作台重置当前项目，取消可恢复原主题，全局主题保持不变。
    func testResetRestoresClassicWithoutChangingGlobalTheme() {
        preferences.scoreboardTheme = ScoreboardTheme.brb.rawValue
        let controller = makeController()

        XCTAssertTrue(controller.canResetDraft)
        controller.open(typographySession: nil)
        controller.updateDraft(controller.active.withPanelBackground("112233", for: .sideLeft))
        XCTAssertTrue(controller.canResetDraft)

        controller.resetDraft()
        XCTAssertEqual(controller.draft.themeCode, ScoreboardTheme.defaultTheme.rawValue)
        XCTAssertEqual(controller.draft, ScoreboardStyleProfileV2.default(for: controller.styleID))
        XCTAssertEqual(preferences.scoreboardTheme, ScoreboardTheme.brb.rawValue)
        controller.cancel()
        XCTAssertEqual(controller.draft.themeCode, ScoreboardTheme.brb.rawValue)
        controller.open(typographySession: nil)
        controller.resetDraft()
        XCTAssertFalse(controller.canResetDraft)
    }

    // MARK: - 字号会话联动（真实 ScoreboardTypographySession）

    /// 重置必须收敛到默认：走 session 时重置后按钮立即置灰，且保存不再把残留倍率写回持久化。
    func testResetDraftWithTypographySessionDisablesResetAndClearsStoredMultipliers() {
        let styleID = ScoreboardStyleID(rawValue: "pingpong")
        var stored = ScoreboardTypographyPreference.default(font: .monospaced)
        stored.elementMultipliers = ["mainScore": 1.45, "teamName": 1.35]
        preferences.setScoreboardTypography(stored, for: styleID)
        XCTAssertNotNil(preferences.scoreboardTypography(for: styleID).elementMultipliers, "前置条件：已持久化元素倍率")

        let session = ScoreboardTypographySession(styleID: styleID, preferences: preferences)
        let controller = makeController(styleID: styleID)
        controller.open(typographySession: session)
        XCTAssertTrue(controller.canResetDraft, "已保存非默认字号时应可重置")

        // 已有预览（模拟用户先拖过字号）也必须被重置覆盖，不能残留。
        session.updateElementMultiplier(1.3, for: .teamName, isLargeScreen: Theme.usesPadLayout)
        XCTAssertTrue(controller.canResetDraft)

        controller.resetDraft()
        XCTAssertFalse(controller.canResetDraft, "重置后草稿与字号都必须等于默认（按钮置灰）")
        XCTAssertEqual(controller.draft, ScoreboardStyleProfileV2.default(for: styleID))

        guard case .success = controller.save() else { return XCTFail("save failed") }
        XCTAssertFalse(preferences.hasScoreboardTypography(for: styleID), "重置保存后应清掉持久化字号键")
        XCTAssertNil(preferences.scoreboardTypography(for: styleID).elementMultipliers, "不应把残留倍率写回")
    }

    /// `updateElementMultiplier` 会把 nil 展开成全量字典；结构差异不代表用户改过字号。
    func testCanResetDraftComparesResolvedMultipliersInsteadOfStructShape() {
        let styleID = ScoreboardStyleID(rawValue: "pingpong")
        let session = ScoreboardTypographySession(styleID: styleID, preferences: preferences)
        let controller = makeController(styleID: styleID)
        controller.open(typographySession: session)

        for key in controller.capabilities.elementKeys {
            session.updateElementMultiplier(1, for: key, isLargeScreen: Theme.usesPadLayout)
        }
        XCTAssertNotNil(session.effectivePreference.elementMultipliers, "前置条件：倍率字典已被展开")
        XCTAssertFalse(controller.canResetDraft, "倍率全为 1 时不应因字典结构差异而保持可重置")
    }

    /// 回归：字号面板写的是 `elementMultipliers`，而渲染读的是
    /// `scoreMultiplier` / `nameMultiplier`。保存时必须把元素倍率解析进这两个
    /// 字段，否则“拖了字号 → 保存 → 不生效”（用户报告的篮球字号问题）。
    func testSavedTypographyAppliesElementMultiplierToRenderFields() {
        let styleID = ScoreboardStyleID(rawValue: "basketball")
        let session = ScoreboardTypographySession(styleID: styleID, preferences: preferences)
        let controller = makeController(styleID: styleID)
        controller.open(typographySession: session)

        // 用户在字号面板拖动“队名”和“主分”。
        session.updateElementMultiplier(1.4, for: .teamName, isLargeScreen: Theme.usesPadLayout)
        session.updateElementMultiplier(1.25, for: .mainScore, isLargeScreen: Theme.usesPadLayout)
        XCTAssertEqual(session.effectivePreference.nameMultiplier, 1.4, accuracy: 0.001, "预览期应即时生效")
        XCTAssertEqual(session.effectivePreference.scoreMultiplier, 1.25, accuracy: 0.001)

        XCTAssertNoThrow(try controller.save().get())

        // 保存后重新读取（模拟重新进入计分板），渲染字段必须是用户拖的值。
        let reloaded = ScoreboardTypographySession(styleID: styleID, preferences: preferences)
        XCTAssertEqual(reloaded.effectivePreference.nameMultiplier, 1.4, accuracy: 0.001,
                       "保存后队名字号必须落到渲染字段 nameMultiplier")
        XCTAssertEqual(reloaded.effectivePreference.scoreMultiplier, 1.25, accuracy: 0.001,
                       "保存后主分字号必须落到渲染字段 scoreMultiplier")
    }

    /// 回归二段：篮球主分字号受“按钮区宽度”硬约束（三位数不得溢出），
    /// 所以在窄面板上放大倍率未必能变大；但**绝不能因为队名被调大而反向变小**。
    /// 直接走篮球面板所用的 `ScoreboardTypographyResolver`（profile: .basketball）。
    func testBasketballScoreDoesNotShrinkWhenNameGrows() {
        let panelSize = CGSize(width: 160, height: 320)
        func resolve(_ preference: ScoreboardTypographyPreference) -> ScoreboardTypographyResult {
            ScoreboardTypographyResolver.resolve(
                ScoreboardTypographyLayoutContext(
                    profile: .basketball,
                    containerSize: panelSize,
                    nameText: "A队",
                    scoreText: "12",
                    secondaryText: "3 2",
                    preference: preference,
                    horizontalPadding: 0,
                    nameAvailableWidth: 140,
                    scoreAvailableWidth: 120,
                    reservedHeight: 76,
                    isLargeScreen: false
                )
            )
        }
        let base = ScoreboardTypographyPreference.default(font: .default)
        var large = base
        large.scoreMultiplier = 1.5
        large.nameMultiplier = 1.5

        let baseResult = resolve(base)
        let largeResult = resolve(large)
        XCTAssertGreaterThan(
            largeResult.nameFontSize, baseResult.nameFontSize,
            "队名字号必须随 nameMultiplier 变大"
        )
        // 关键回归：队名放大后，主分不得缩小（旧实现 82pt → 64pt）。
        XCTAssertGreaterThanOrEqual(
            largeResult.scoreFontSize, baseResult.scoreFontSize,
            "队名调大不应把主分挤小（主分垂直预算不得包含队名行高）"
        )
    }

    /// 饱和倍率：宽度/垂直上限之下，字号超过某个倍率就不再变化。
    /// 字号面板据此封顶并给出“已达本机上限”提示（用户报告的 SE 篮球主分问题）。
    func testFontSizeSaturationDetectsDeadUpperRange() {
        let range = ScoreboardFontSizePolicy.range(isLargeScreen: false) // 0.8 ... 1.5

        // 篮球 SE 侧栏主分：0.8x=118, 1.0x=140，1.0 以上完全饱和。
        let capped: (Double) -> CGFloat = { m in CGFloat(min(144.0 * m, 140.0)) }
        XCTAssertEqual(
            ScoreboardFontSizeSaturation.effectiveUpperBound(range: range, step: 0.05, size: capped),
            1.0, accuracy: 1e-9,
            "顶格的主分应判定为 1.0 封顶"
        )

        // 已是上限且往下调也不变（三位数：0.8x 与 1.0x 都是 93）。
        let flat: (Double) -> CGFloat = { _ in 93 }
        XCTAssertEqual(
            ScoreboardFontSizeSaturation.effectiveUpperBound(range: range, step: 0.05, size: flat),
            range.lowerBound, accuracy: 1e-9,
            "完全不随倍率变化时应判定为下限"
        )

        // 宽面板（iPhone 17 Pro 主分）：1.0x=153, 1.2x=181，之后饱和。
        let wide: (Double) -> CGFloat = { m in CGFloat(min(153.0 * m, 181.0)) }
        XCTAssertEqual(
            ScoreboardFontSizeSaturation.effectiveUpperBound(range: range, step: 0.05, size: wide),
            1.2, accuracy: 0.051,
            "有富余的面板应支持放大到饱和点"
        )

        // 全程可用：应返回区间上限。
        let free: (Double) -> CGFloat = { m in CGFloat(144 * m) }
        XCTAssertEqual(
            ScoreboardFontSizeSaturation.effectiveUpperBound(range: range, step: 0.05, size: free),
            range.upperBound, accuracy: 1e-9
        )
    }

    /// 篮球主分字号在放大倍率时应变大，前提是面板有足够宽度。
    /// 用宽面板验证倍率确实能生效，避免“滑块完全无效”。
    func testBasketballScoreScalesWithMultiplierOnWidePanel() {
        let panelSize = CGSize(width: 420, height: 360)
        func resolve(_ scoreMultiplier: Double) -> CGFloat {
            var preference = ScoreboardTypographyPreference.default(font: .default)
            preference.scoreMultiplier = scoreMultiplier
            return ScoreboardTypographyResolver.resolve(
                ScoreboardTypographyLayoutContext(
                    profile: .basketball,
                    containerSize: panelSize,
                    nameText: "A",
                    scoreText: "1",
                    secondaryText: "",
                    preference: preference,
                    horizontalPadding: 0,
                    nameAvailableWidth: 400,
                    scoreAvailableWidth: 400,
                    reservedHeight: 76,
                    isLargeScreen: false
                )
            ).scoreFontSize
        }
        XCTAssertGreaterThan(
            resolve(1.5), resolve(1.0),
            "宽面板下主分字号必须随倍率变大"
        )
    }

    /// 取消重置：会话预览丢弃，持久化字号保持原样。
    func testCancelAfterResetKeepsStoredTypography() {
        let styleID = ScoreboardStyleID(rawValue: "pingpong")
        var stored = ScoreboardTypographyPreference.default(font: .monospaced)
        stored.elementMultipliers = ["mainScore": 1.45]
        preferences.setScoreboardTypography(stored, for: styleID)

        let session = ScoreboardTypographySession(styleID: styleID, preferences: preferences)
        let controller = makeController(styleID: styleID)
        controller.open(typographySession: session)
        controller.resetDraft()
        XCTAssertFalse(controller.canResetDraft)

        controller.cancel()
        XCTAssertTrue(preferences.hasScoreboardTypography(for: styleID), "取消不应删除持久化字号")
        XCTAssertNotNil(preferences.scoreboardTypography(for: styleID).elementMultipliers)
    }
}
