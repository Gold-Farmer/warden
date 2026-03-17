// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Warden",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    dependencies: [
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
    ],
    targets: [
        .executableTarget(
            name: "Warden",
            dependencies: ["KeychainAccess"],
            path: "Warden"
        ),
        .testTarget(
            name: "WardenTests",
            dependencies: ["Warden"],
            path: "Tests"
        ),
    ]
)
