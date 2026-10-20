// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EasyShoot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "EasyShoot",
            path: "Sources/EasyShoot"
        ),
        .testTarget(
            name: "EasyShootTests",
            dependencies: ["EasyShoot"],
            path: "Tests/EasyShootTests"
        ),
    ]
)
