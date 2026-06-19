// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LiquidBar",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "LiquidBar",
            path: "Sources/LiquidBar",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
        .testTarget(
            name: "LiquidBarTests",
            dependencies: ["LiquidBar"]
        ),
    ]
)
