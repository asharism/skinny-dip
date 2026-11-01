// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarkdownCore",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "MarkdownCore", targets: ["MarkdownCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "MarkdownCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                "SwiftSoup",
            ]
        ),
        .testTarget(
            name: "MarkdownCoreTests",
            dependencies: ["MarkdownCore"],
            resources: [.copy("Golden")]
        ),
    ]
)
