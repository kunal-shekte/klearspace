// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Klearspace",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Klearspace", targets: ["Klearspace"])],
    targets: [
        .target(name: "KlearspaceCore"),
        .executableTarget(name: "Klearspace", dependencies: ["KlearspaceCore"]),
        .testTarget(name: "KlearspaceCoreTests", dependencies: ["KlearspaceCore"])
    ],
    swiftLanguageModes: [.v5]
)
