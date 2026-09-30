// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TamilCore",
    // iOS 17 matches ios/project.yml's deploymentTarget.iOS exactly (must
    // never exceed it, or the app would fail to build/run below that
    // version). macOS 14 is needed only because `swift test` runs this
    // package on the Mac itself, and URLSession's async data(for:) requires
    // macOS 12+; iOS apps never run the macOS platform slice.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TamilCore", targets: ["TamilCore"])
    ],
    targets: [
        .target(name: "TamilCore"),
        .testTarget(name: "TamilCoreTests", dependencies: ["TamilCore"]),
    ]
)
