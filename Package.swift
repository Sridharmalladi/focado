// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Focado",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Focado",
            path: "Sources/AVA",
            swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]
        )
    ],
    swiftLanguageVersions: [.v5]
)
