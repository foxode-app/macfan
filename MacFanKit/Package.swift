// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacFanKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacFanKit", targets: ["MacFanKit"]),
        .executable(name: "macfan", targets: ["macfan"]),
    ],
    targets: [
        .target(name: "MacFanKit"),
        .executableTarget(name: "macfan", dependencies: ["MacFanKit"]),
        .testTarget(name: "MacFanKitTests", dependencies: ["MacFanKit"]),
    ]
)
