// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LaravelMobileKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(name: "LaravelMobileKitCore", targets: ["LaravelMobileKitCore"]),
        .library(name: "LaravelMobileKitLaravel", targets: ["LaravelMobileKitLaravel"]),
        .library(name: "LaravelMobileKitAuth", targets: ["LaravelMobileKitAuth"]),
        .library(name: "LaravelMobileKitUploads", targets: ["LaravelMobileKitUploads"]),
        .library(name: "LaravelMobileKit", targets: ["LaravelMobileKit"]),
    ],
    targets: [
        .target(
            name: "LaravelMobileKitCore",
            path: "Sources/Core"
        ),
        .target(
            name: "LaravelMobileKitLaravel",
            dependencies: ["LaravelMobileKitCore"],
            path: "Sources/Laravel"
        ),
        .target(
            name: "LaravelMobileKitAuth",
            dependencies: ["LaravelMobileKitCore"],
            path: "Sources/Auth"
        ),
        .target(
            name: "LaravelMobileKitUploads",
            dependencies: ["LaravelMobileKitCore"],
            path: "Sources/Uploads"
        ),
        .target(
            name: "LaravelMobileKit",
            dependencies: [
                "LaravelMobileKitCore",
                "LaravelMobileKitLaravel",
                "LaravelMobileKitAuth",
                "LaravelMobileKitUploads",
            ],
            path: "Sources/LaravelMobileKit"
        ),
        .testTarget(
            name: "LaravelMobileKitTests",
            dependencies: ["LaravelMobileKit"],
            path: "Tests/LaravelMobileKitTests"
        ),
        // Runs against the Laravel fixture in TestApp/. Every suite is skipped
        // unless LARAVEL_TEST_URL points at a running instance.
        .testTarget(
            name: "LaravelMobileKitIntegrationTests",
            dependencies: ["LaravelMobileKit"],
            path: "Tests/LaravelMobileKitIntegrationTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
