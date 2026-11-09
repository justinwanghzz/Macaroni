// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UtilityApp",
    platforms: [.macOS(.v14)],
    products: [.library(name: "UtilityCore", targets: ["UtilityCore"]), .executable(name: "UtilityApp", targets: ["UtilityApp"])],
    dependencies: [.package(path: "Vendor/ZIPFoundation")],
    targets: [
        .target(name: "UtilityCore", dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")]),
        .executableTarget(name: "UtilityApp", dependencies: ["UtilityCore"], resources: [.copy("Resources")]),
        .testTarget(name: "UtilityCoreTests", dependencies: ["UtilityCore", .product(name: "ZIPFoundation", package: "ZIPFoundation")])
    ]
)
