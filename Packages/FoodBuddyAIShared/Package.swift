// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FoodBuddyAIShared",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "FoodBuddyAIShared",
            targets: ["FoodBuddyAIShared"]
        )
    ],
    targets: [
        .target(
            name: "FoodBuddyAIShared"
        ),
        .testTarget(
            name: "FoodBuddyAISharedTests",
            dependencies: ["FoodBuddyAIShared"]
        )
    ]
)
