// swift-tools-version: 6.0
import PackageDescription

/// The quick-start sample is its own package so it depends on Laravel Mobile Kit
/// exactly as an application would, and so `swift build` proves the documented
/// integration still compiles.
let package = Package(
    name: "QuickStart",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    dependencies: [
        .package(name: "LaravelMobileKit", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "QuickStart",
            dependencies: [
                .product(name: "LaravelMobileKit", package: "LaravelMobileKit")
            ],
            path: "Sources/QuickStart"
        )
    ],
    swiftLanguageModes: [.v6]
)
