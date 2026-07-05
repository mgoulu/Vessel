// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Vessel",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Vessel", targets: ["Vessel"])
    ],
    targets: [
        .executableTarget(name: "Vessel")
    ]
)
