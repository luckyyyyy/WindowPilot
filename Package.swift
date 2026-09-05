// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WindowPilot",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "WindowPilot", targets: ["WindowPilot"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")],
    targets: [
        .executableTarget(name: "WindowPilot",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]) ]),
        .testTarget(name: "WindowPilotTests", dependencies: ["WindowPilot"])
    ],
    swiftLanguageModes: [.v6]
)
