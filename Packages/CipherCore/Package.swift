// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CipherCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "CipherCore", targets: ["CipherCore"]),
        // Создание личности — только для приложения. Клавиатура этот продукт не линкует.
        .library(name: "CipherCoreIdentityStore", targets: ["CipherCoreIdentityStore"]),
    ],
    targets: [
        .target(name: "CipherCore"),
        .target(name: "CipherCoreIdentityStore", dependencies: ["CipherCore"]),
        .testTarget(name: "CipherCoreTests", dependencies: ["CipherCore", "CipherCoreIdentityStore"]),
    ]
)
