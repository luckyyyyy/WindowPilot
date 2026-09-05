// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WindowPilot",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "WindowPilot", targets: ["WindowPilot"])],
    targets: [
        .executableTarget(name: "WindowPilot"),
        .testTarget(name: "WindowPilotTests", dependencies: ["WindowPilot"])
    ],
    swiftLanguageModes: [.v6]
)
