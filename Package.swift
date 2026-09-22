// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "DemoRecorder", platforms: [.macOS(.v15)],
    products: [.executable(name: "DemoRecorder", targets: ["RecorderApp"])],
    targets: [
        .target(name: "RecorderCore"),
        .target(name: "RecorderMedia", dependencies: ["RecorderCore"]),
        .executableTarget(name: "RecorderApp", dependencies: ["RecorderCore", "RecorderMedia"]),
        .testTarget(name: "RecorderCoreTests", dependencies: ["RecorderCore"]),
        .testTarget(name: "RecorderMediaTests", dependencies: ["RecorderMedia", "RecorderCore"])
    ], swiftLanguageModes: [.v5])
