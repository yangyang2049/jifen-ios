//
//  ScoreboardStyleEditorControllerTests.swift
//  jifen
//
//  阶段 2 编辑会话 Controller 测试：draft/active/revision、编辑中防覆盖、
//  取消恢复、保存落盘 + revision 自增、字号会话联动。
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
        controller.updateFromPreferences(preferences)
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
        controller.updateFromPreferences(preferences)
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

    func testSavePersistsProfileAndBumpsRevision() {
        let controller = makeController()
        let revisionBefore = preferences.scoreboardRevision
        controller.open(typographySession: nil)
        controller.updateDraft(controller.active
            .withPanelBackground("112233", for: .sideLeft)
            .withElementTextColor(.mainScore, slotKey: .sideRight, mode: .manual, colorHex: "#00ff88"))

        let result = controller.save(preferences: preferences)
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

        _ = controller.save(preferences: preferences)
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
        _ = controller.save(preferences: preferences)
        let snapshot = ScoreboardAppearanceSnapshot.current(styleID: controller.styleID, preferences)
        print("SNAPSHOT theme=\(snapshot.theme.rawValue) palette.bg-l-r=\(snapshot.palette.left) fg=\(snapshot.palette.foreground)")
    }

    func testResetDraftRestoresDefaultStyle() {
        let controller = makeController()
        controller.open(typographySession: nil)
        controller.updateDraft(controller.active.withPanelBackground("112233", for: .sideLeft))
        XCTAssertTrue(controller.canResetDraft)

        controller.resetDraft(preferences: preferences)
        XCTAssertFalse(controller.canResetDraft)
        XCTAssertEqual(controller.draft, ScoreboardStyleProfileV2.default(for: controller.styleID))
    }

    /// 回归：非默认主题下，重置应回到「当前主题下」的默认样式，且不能把主题刷回 default。
    /// 修复前比较基准误用 defaultTheme，会导致未改样式时重置按钮误亮、且重置后主题丢失。
    func testResetPreservesNonDefaultTheme() {
        preferences.scoreboardTheme = ScoreboardTheme.brb.rawValue
        let controller = makeController()

        // 未改样式时重置按钮应置灰（修复前比较基准误用 defaultTheme 会恒亮）。
        XCTAssertFalse(controller.canResetDraft)
        controller.open(typographySession: nil)
        controller.updateDraft(controller.active.withPanelBackground("112233", for: .sideLeft))
        XCTAssertTrue(controller.canResetDraft)

        controller.resetDraft(preferences: preferences)
        // 主题不得丢失
        XCTAssertEqual(controller.draft.themeCode, ScoreboardTheme.brb.rawValue)
        XCTAssertEqual(controller.draft, ScoreboardStyleProfileV2.default(for: controller.styleID, theme: .brb))
        XCTAssertFalse(controller.canResetDraft)
    }
}
