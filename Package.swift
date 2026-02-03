// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "osaurus-images",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "osaurus-images", type: .dynamic, targets: ["osaurus_images"])
    ],
    targets: [
        .target(
            name: "osaurus_images",
            path: "Sources/osaurus_images"
        )
    ]
)