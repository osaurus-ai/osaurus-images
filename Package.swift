// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "osaurus-images",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "osaurus-images", type: .dynamic, targets: ["osaurus_images"])
    ],
    dependencies: [
        .package(url: "https://github.com/osaurus-ai/osaurus-plugin-sdk.git", exact: "1.0.0")
    ],
    targets: [
        .target(
            name: "osaurus_images",
            dependencies: [
                .product(name: "OsaurusPluginABI", package: "osaurus-plugin-sdk"),
                .product(name: "OsaurusPluginKit", package: "osaurus-plugin-sdk"),
            ],
            path: "Sources/osaurus_images"
        ),
        .testTarget(
            name: "osaurus_imagesTests",
            dependencies: [
                "osaurus_images",
                .product(name: "OsaurusPluginKit", package: "osaurus-plugin-sdk"),
                .product(name: "OsaurusPluginTestSupport", package: "osaurus-plugin-sdk"),
            ],
            path: "Tests/osaurus_imagesTests"
        )
    ]
)
