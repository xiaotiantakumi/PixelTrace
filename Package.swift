// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PixelTrace",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "PixelTraceCore", targets: ["PixelTraceCore"]),
        .library(name: "PixelTrace", targets: ["PixelTrace"]),
        .library(name: "PixelTraceUI", targets: ["PixelTraceUI"]),
    ],
    targets: [
        .target(name: "PixelTraceCore"),
        .target(name: "PixelTrace", dependencies: ["PixelTraceCore"]),
        .target(name: "PixelTraceUI", dependencies: ["PixelTrace", "PixelTraceCore"]),
        .testTarget(name: "PixelTraceCoreTests", dependencies: ["PixelTraceCore"]),
        .testTarget(name: "PixelTraceTests", dependencies: ["PixelTrace"]),
        .testTarget(name: "PixelTraceUITests", dependencies: ["PixelTraceUI"]),
    ]
)
