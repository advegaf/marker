// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MarkerKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "MarkerCore", targets: ["MarkerCore"]),
        .library(name: "MarkerRender", targets: ["MarkerRender"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", branch: "main"),
        .package(url: "https://github.com/mgriebling/SwiftMath.git", from: "1.7.0"),
    ],
    targets: [
        // Pure computation. No AppKit, so `swift test` runs it with no app host.
        .target(
            name: "MarkerCore",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "MarkerRender",
            dependencies: ["MarkerCore", "SwiftMath"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
            ]
        ),
        .testTarget(
            name: "MarkerCoreTests",
            dependencies: ["MarkerCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MarkerRenderTests",
            dependencies: ["MarkerRender"],
            swiftSettings: [.swiftLanguageMode(.v6), .defaultIsolation(MainActor.self)]
        ),
    ]
)
