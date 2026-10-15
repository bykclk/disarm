// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DisarmCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DisarmCore", targets: ["DisarmCore"]),
    ],
    targets: [
        .target(name: "DisarmCore"),
        .testTarget(name: "DisarmCoreTests", dependencies: ["DisarmCore"]),
    ]
)
