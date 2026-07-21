import SwiftUI

enum ScoreboardServeGeometry {
    static let triangleSize: CGFloat = 36

    static func doublesAnchorY(height: CGFloat, topRow: Bool) -> CGFloat {
        height * (topRow ? 1 / 6 : 5 / 6)
    }

    static func keyPointBadgeCenterY(
        height: CGFloat,
        doublesTopRow: Bool?,
        largeWindow: Bool
    ) -> CGFloat {
        let triangleCenterY = doublesTopRow.map {
            doublesAnchorY(height: height, topRow: $0)
        } ?? (height / 2)
        let gap: CGFloat = largeWindow ? 14 : 10
        let badgeHalfHeight: CGFloat = 14
        return triangleCenterY - triangleSize / 2 - gap - badgeHalfHeight
    }
}

enum ServeTriangleDirection {
    case top
    case bottom
    case left
    case right
}

struct ServeTriangleIndicator: View {
    let direction: ServeTriangleDirection
    var triangleSize: CGFloat = ScoreboardServeGeometry.triangleSize
    var color: Color = Color(hex: "30D158")

    var body: some View {
        ServeTriangleShape(direction: direction)
            .fill(color)
            .frame(width: triangleSize, height: triangleSize)
    }
}

/// 发球指示：箭头整体在发球方一侧，贴中心线。红队发球→箭头在红区右缘贴中线；蓝队发球→箭头在蓝区左缘贴中线。
struct CenterLineServeIndicator: View {
    let isLeftServing: Bool
    var triangleSize: CGFloat = ScoreboardServeGeometry.triangleSize
    var color: Color = Color(hex: "30D158")

    var body: some View {
        ServeTriangleIndicator(
            direction: isLeftServing ? .left : .right,
            triangleSize: triangleSize,
            color: color
        )
        // 红队发球：箭头在左半区，右缘贴中线 → 整体左移 half。蓝队发球：箭头在右半区，左缘贴中线 → 整体右移 half。
        .offset(x: isLeftServing ? -triangleSize / 2 : triangleSize / 2)
        .allowsHitTesting(false)
    }
}

private struct ServeTriangleShape: Shape {
    let direction: ServeTriangleDirection

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        switch direction {
        case .top:
            path.move(to: CGPoint(x: w / 2, y: 0))
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: 0, y: h))
        case .bottom:
            path.move(to: CGPoint(x: w / 2, y: h))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: w, y: 0))
        case .left:
            path.move(to: CGPoint(x: 0, y: h / 2))
            path.addLine(to: CGPoint(x: w, y: 0))
            path.addLine(to: CGPoint(x: w, y: h))
        case .right:
            path.move(to: CGPoint(x: w, y: h / 2))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: h))
        }

        path.closeSubpath()
        return path
    }
}
