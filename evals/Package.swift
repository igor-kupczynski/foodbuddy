// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FoodBuddyAIEvals",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../Packages/FoodBuddyAIShared")
    ],
    targets: [
        .executableTarget(
            name: "FoodBuddyAIEvals",
            dependencies: [
                .product(name: "FoodBuddyAIShared", package: "FoodBuddyAIShared")
            ]
        )
    ]
)
