import ScoreCore

/// M2 已将投篮训练模型下沉至 ScoreCore（ScoreCore/s2/ShotTraining.swift）。
/// 这里保留兼容 typealias：LinkCore 与双端既有调用点无需改动。
public typealias LinkedShotTrainingMode = ScoreCore.ShotTrainingMode
public typealias LinkedShotTrainingShot = ScoreCore.ShotTrainingShot
public typealias ShotTrainingCounts = ScoreCore.ShotTrainingCounts
public typealias LinkedShotTrainingState = ScoreCore.ShotTrainingState
