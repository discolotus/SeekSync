// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "SeekSyncPrototype",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SeekSyncPrototype", targets: ["SeekSyncPrototype"])
    ],
    targets: [
        .executableTarget(
            name: "SeekSyncPrototype",
            path: "Sources/SeekSyncPrototype"
        ),
        .testTarget(
            name: "SeekSyncPrototypeTests",
            dependencies: ["SeekSyncPrototype"],
            path: "Tests/SeekSyncPrototypeTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
