// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PerformanceMonitor",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "PerformanceMonitor",
            targets: ["PerformanceMonitor"]
        )
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            pkgConfig: "sqlite3"
        ),
        .executableTarget(
            name: "PerformanceMonitor",
            dependencies: ["CSQLite"],
            path: "Sources/PerformanceMonitor"
        ),
        .testTarget(
            name: "PerformanceMonitorTests",
            dependencies: ["PerformanceMonitor"],
            path: "Tests/PerformanceMonitorTests"
        )
    ]
)
