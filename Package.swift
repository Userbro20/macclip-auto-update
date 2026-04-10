// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacClipper",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "MacClipper", targets: ["MacClipper"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1")
    ],
    targets: [
        .executableTarget(
            name: "MacClipper",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Speech"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .unsafeFlags([
                    "-Xlinker",
                    "-rpath",
                    "-Xlinker",
                    "@executable_path/../Frameworks"
                ])
            ]
        )
    ]
)
