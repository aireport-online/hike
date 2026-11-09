// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HikeCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "HikeCore", targets: ["HikeCore"])
    ],
    targets: [
        .target(name: "HikeCore"),
        .testTarget(name: "HikeCoreTests", dependencies: ["HikeCore"])
    ]
)
