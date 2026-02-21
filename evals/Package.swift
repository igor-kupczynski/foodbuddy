// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FoodBuddyAIEvals",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../Packages/FoodBuddyAIShared"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.9.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        .executableTarget(
            name: "FoodBuddyAIEvals",
            dependencies: [
                .product(name: "FoodBuddyAIShared", package: "FoodBuddyAIShared"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
            ]
        )
    ]
)
