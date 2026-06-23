// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LiquidBar",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "LiquidBar",
            path: "Sources/LiquidBar",
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("IOKit"),
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
