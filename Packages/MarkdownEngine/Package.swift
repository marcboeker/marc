// swift-tools-version: 5.9
import PackageDescription

// Marc: vendored fork of nodes-app/swift-markdown-engine. Only the core
// `MarkdownEngine` target is kept; the optional CodeBlocks/Latex bridges and
// their remote dependencies were dropped. See NOTICE.
let package = Package(
    name: "MarkdownEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MarkdownEngine", targets: ["MarkdownEngine"]),
    ],
    targets: [
        .target(name: "MarkdownEngine"),
    ]
)
