// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "PixelTrace",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [ .library(name: "PixelTraceCore", targets: ["PixelTraceCore"]) ],
    targets: [
        .target(name: "PixelTraceCore"),
        .testTarget(name: "PixelTraceCoreTests", dependencies: ["PixelTraceCore"]),
    ]
)
