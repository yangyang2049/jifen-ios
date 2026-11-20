//
//  ThemeFreeBadge.swift
//  jifen
//
//  主题入口右上角「限免」斜切角标：与 Android ThemePromoBadge / 鸿蒙 ThemeFreeBadge 同形同径。
//

import SwiftUI

/// 右上角直角三角：两条直角边贴上/右边缘，斜边朝卡片中心。
struct ThemeFreeBadgeTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 主题卡右上角的限免角标。
///
/// 主题卡只有约 1/3 面板宽、68pt 高，横向标签放不下，所以做成右上角的斜切三角：
/// 文字沿 45° 斜边排布，字号按文案实际宽高换算出的半对角线收进三角内切圆，
/// 保证「限免」「Free」「限時免費」这类长短不一的文案都不会被斜边裁切。
struct ThemeFreeBadge: View {
    var badgeSize: CGFloat = 36

    /// 角标直角边长。
    private static let designSize: CGFloat = 36
    /// 等腰直角三角形内切圆半径：r = a(2-√2)/2。
    private static let inscribedRadius: CGFloat = 36 * (2 - CGFloat(2).squareRoot()) / 2
    private static let accent = Color(hex: "FF6B35")
    private static let baseFontSize: CGFloat = 9
    private static let textShift: CGFloat = 7.5

    private var label: String { String(localized: "scoreboard_theme_free_badge") }
    private var description: String { String(localized: "scoreboard_theme_free_badge_desc") }

    /// 旋转 45° 后的文字包围盒半对角线必须落进内切圆，否则按比例缩字号。
    private var fontSize: CGFloat {
        let font = UIFont.systemFont(ofSize: Self.baseFontSize, weight: .bold)
        let measured = (label as NSString).size(withAttributes: [.font: font])
        let halfDiagonal = (measured.width + measured.height) / 2 / CGFloat(2).squareRoot()
        let scale = halfDiagonal > Self.inscribedRadius ? Self.inscribedRadius / halfDiagonal : 1
        return Self.baseFontSize * scale * badgeSize / Self.designSize
    }

    var body: some View {
        ZStack {
            ThemeFreeBadgeTriangle().fill(Self.accent)
            Text(label)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .rotationEffect(.degrees(45))
                .offset(x: badgeSize * Self.textShift / Self.designSize,
                        y: -badgeSize * Self.textShift / Self.designSize)
        }
        .frame(width: badgeSize, height: badgeSize)
        .accessibilityElement()
        .accessibilityLabel(Text(description))
        .accessibilityIdentifier("scoreboard_style_theme_free_badge")
        .allowsHitTesting(false)
    }
}
