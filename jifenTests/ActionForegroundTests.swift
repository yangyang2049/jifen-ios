import XCTest
@testable import jifen

/// 实心操作按钮前景色：红底白字、绿底白字、其余走对比度。
/// 对齐安卓 `actionForeground` + `AppActionColors`、鸿蒙 `actionTextColor` 的口径。
final class ActionForegroundTests: XCTestCase {

    private func rgb(_ hex: String) -> (CGFloat, CGFloat, CGFloat) {
        let value = Int(hex, radix: 16)!
        return (
            CGFloat((value >> 16) & 0xFF) / 255,
            CGFloat((value >> 8) & 0xFF) / 255,
            CGFloat(value & 0xFF) / 255
        )
    }

    private func foreground(_ hex: String, appearance: UIUserInterfaceStyle) -> UIColor {
        let (r, g, b) = rgb(hex)
        return Theme.actionForeground(on: UIColor(red: r, green: g, blue: b, alpha: 1), appearance: appearance)
    }

    /// 实心红底在深浅模式都用白字，即使黑字对比度更高。
    func testSolidRedActionsUseWhiteInBothAppearances() {
        for hex in ["FF3B30", "EF4444", "FF6B6B", "E5484D", "FF5252", "D32F2F", "B42318"] {
            XCTAssertEqual(foreground(hex, appearance: .light), .white, "light \(hex)")
            XCTAssertEqual(foreground(hex, appearance: .dark), .white, "dark \(hex)")
        }
    }

    /// 橙黄警告与浅红提示底不能被误判成红，仍按对比度选黑字。
    func testOrangeYellowAndPaleSurfacesKeepContrastPolicy() {
        for hex in ["FF9800", "F59E0B", "FFD600", "FFC107", "F97316", "FFE0E0"] {
            XCTAssertEqual(foreground(hex, appearance: .light), .black, "light \(hex)")
            XCTAssertEqual(foreground(hex, appearance: .dark), .black, "dark \(hex)")
        }
    }

    /// 浅色模式主题绿继续白字；深色模式沿用既有规则。
    func testLightThemeGreenKeepsWhiteLabel() {
        XCTAssertEqual(foreground("4CAF50", appearance: .light), .white)
        XCTAssertEqual(foreground("248A3D", appearance: .light), .white)
    }

    /// 中性色与蓝色仍按对比度计算。
    /// 注意 `007AFF` 的黑字对比 5.23 > 白字 4.02，所以这里**本来就该是黑字**——
    /// 蓝色不在本次红底规则范围内，保持既有行为。
    func testNeutralAndBlueRetainContrast() {
        XCTAssertEqual(foreground("000000", appearance: .light), .white)
        XCTAssertEqual(foreground("FFFFFF", appearance: .light), .black)
        XCTAssertEqual(foreground("007AFF", appearance: .light), .black)
    }

    /// 判定函数本身：高饱和 + 红区色相。
    func testSolidRedPredicate() {
        let (r1, g1, b1) = rgb("FF3B30")
        XCTAssertTrue(Theme.isSolidRedAction(red: r1, green: g1, blue: b1))
        let (r2, g2, b2) = rgb("FF9800")
        XCTAssertFalse(Theme.isSolidRedAction(red: r2, green: g2, blue: b2))
        let (r3, g3, b3) = rgb("4CAF50")
        XCTAssertFalse(Theme.isSolidRedAction(red: r3, green: g3, blue: b3))
    }

    /// 多行说明文案行高：换算后必须非负，且 caption/body 都落在可读范围。
    func testGroupLineHeightSpacingIsNonNegative() {
        XCTAssertGreaterThan(GroupTypography.LineHeight.captionSpacing, 0)
        XCTAssertGreaterThan(GroupTypography.LineHeight.bodySpacing, 0)
        XCTAssertLessThan(GroupTypography.LineHeight.captionSpacing, GroupTypography.LineHeight.caption)
        XCTAssertLessThan(GroupTypography.LineHeight.bodySpacing, GroupTypography.LineHeight.body)
    }
}
