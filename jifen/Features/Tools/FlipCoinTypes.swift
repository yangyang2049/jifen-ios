//
//  FlipCoinTypes.swift
//  jifen
//
//  Shared types for flip coin - in separate file to avoid main-actor isolation (Swift 6).
//

import Foundation

enum FlipCoinSide {
    case heads, tails
}

struct FlipCoinResult: Identifiable {
    let id = UUID()
    let side: FlipCoinSide
    let timestamp: Date
}
