//
//  FlipCoinTypes.swift
//  jifen
//

import Foundation
import ScoreCore

typealias AppFlipCoinSide = FlipCoinSide

struct FlipCoinResult: Identifiable {
    let id = UUID()
    let side: FlipCoinSide
    let timestamp: Date
}
