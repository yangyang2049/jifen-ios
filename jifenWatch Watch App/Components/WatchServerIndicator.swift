//
//  WatchServerIndicator.swift
//  jifenWatch Watch App
//
//  Triangle indicator for current server (aligned with Harmony PlayerIndicator).
//

import SwiftUI

enum WatchServerIndicatorDirection {
    case top
    case bottom
    case left
    case right
}

struct WatchServerIndicator: View {
    var direction: WatchServerIndicatorDirection = .left
    var size: CGFloat = 14
    var color: Color = Color.white

    var body: some View {
        TriangleShape(direction: direction)
            .fill(color)
            .frame(width: width, height: height)
    }

    private var width: CGFloat {
        size
    }

    private var height: CGFloat {
        size
    }
}

private struct TriangleShape: Shape {
    var direction: WatchServerIndicatorDirection

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
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
            path.addLine(to: CGPoint(x: 0, y: h))
            path.addLine(to: CGPoint(x: 0, y: 0))
        }
        path.closeSubpath()
        return path
    }
}
