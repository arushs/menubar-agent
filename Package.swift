// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "menubar-agent",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "menubar-agent", targets: ["menubar-agent"])
    ],
    targets: [
        .executableTarget(
            name: "menubar-agent",
            path: "Sources/menubar-agent"
        )
    ]
)