// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentMenuBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AgentMenuBar", targets: ["AgentMenuBar"])
    ],
    targets: [
        .executableTarget(
            name: "AgentMenuBar",
            path: "Sources",
            exclude: ["Info.plist"],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
