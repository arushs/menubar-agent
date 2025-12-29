// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AiMeter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "aimeter", targets: ["AiMeter"])
    ],
    targets: [
        .executableTarget(
            name: "AiMeter",
            path: "Sources/AiMeter"
        )
    ]
)