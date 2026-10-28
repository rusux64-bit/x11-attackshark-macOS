// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SharkControlProtocol",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SharkControlProtocol", targets: ["SharkControlProtocol"])
    ],
    targets: [
        .target(
            name: "SharkControlProtocol",
            path: "Protocol"
        ),
        .testTarget(
            name: "SharkControlProtocolTests",
            dependencies: ["SharkControlProtocol"]
        )
    ]
)
