// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JifenCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "ScoreCore", targets: ["ScoreCore"]),
        .library(name: "SessionCore", targets: ["SessionCore"]),
        .library(name: "RecordCore", targets: ["RecordCore"]),
        .library(name: "PersistenceCore", targets: ["PersistenceCore"]),
        .library(name: "LinkCore", targets: ["LinkCore"]),
        .library(name: "TimerCore", targets: ["TimerCore"])
    ],
    targets: [
        .target(name: "ScoreCore"),
        .target(name: "SessionCore", dependencies: ["ScoreCore"]),
        .target(name: "RecordCore", dependencies: ["ScoreCore", "SessionCore"]),
        .target(name: "PersistenceCore", dependencies: ["ScoreCore", "SessionCore", "RecordCore"]),
        .target(name: "LinkCore", dependencies: ["ScoreCore", "SessionCore", "RecordCore"]),
        .target(name: "TimerCore", dependencies: ["ScoreCore"]),
        .testTarget(name: "JifenCoreTests", dependencies: ["ScoreCore", "SessionCore", "RecordCore", "PersistenceCore", "LinkCore", "TimerCore"])
    ]
)
