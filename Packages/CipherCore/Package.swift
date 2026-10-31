// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CipherCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "CipherCore", targets: ["CipherCore"])
    ],
    targets: [
        .target(name: "CipherCore"),
        .testTarget(name: "CipherCoreTests", dependencies: ["CipherCore"]),
    ]
)
