// swift-tools-version: 6.0
import PackageDescription

/// Compiles the examples printed in `Documentation/`.
///
/// The guides are only useful if their code is real, so every non-trivial
/// snippet has a counterpart here and CI builds this package. When an API
/// changes, this stops compiling before the documentation goes stale.
let package = Package(
    name: "DocumentationSnippets",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    dependencies: [
        .package(name: "LaravelMobileKit", path: "../..")
    ],
    targets: [
        .target(
            name: "DocumentationSnippets",
            dependencies: [
                .product(name: "LaravelMobileKit", package: "LaravelMobileKit")
            ],
            path: "Sources/DocumentationSnippets"
        )
    ],
    swiftLanguageModes: [.v6]
)
