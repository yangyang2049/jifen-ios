import SwiftUI

enum ServeTriangleDirection {
    case top
    case bottom
    case left
    case right
}

struct ServeTriangleIndicator: View {
    let direction: ServeTriangleDirection
    var triangleSize: CGFloat = 36
    var color: Color = Color(hex: "30D158")

    var body: some View {
        ServeTriangleShape(direction: direction)
            .fill(color)
            .frame(width: triangleSize, height: triangleSize)
    }
}

/// Draws a single serve indicator whose arrow tip sits exactly on the center line.
struct CenterLineServeIndicator: View {
    let isLeftServing: Bool
    var triangleSize: CGFloat = 36
    var color: Color = Color(hex: "30D158")

    var body: some View {
        ServeTriangleIndicator(
            direction: isLeftServing ? .left : .right,
            triangleSize: triangleSize,
            color: color
        )
        // Keep arrow tip exactly on center line:
        // left tip at frame minX, right tip at frame maxX.
        .offset(x: isLeftServing ? triangleSize / 2 : -triangleSize / 2)
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
