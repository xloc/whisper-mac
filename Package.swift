// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "whisper-ptt",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "whisper-ptt", targets: ["WhisperPTT"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.0.0")
    ],
    targets: [
        .target(
            name: "WhisperPTTCore",
            dependencies: [.product(name: "WhisperKit", package: "argmax-oss-swift")],
            path: "Sources/WhisperPTTCore",
            resources: [.copy("ModelInfo")]
        ),
        .executableTarget(
            name: "WhisperPTT",
            dependencies: [
                "WhisperPTTCore",
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ],
            path: "Sources/WhisperPTT"
        ),
        .testTarget(
            name: "WhisperPTTCoreTests",
            dependencies: ["WhisperPTTCore"],
            path: "Tests/WhisperPTTCoreTests"
        ),
        .testTarget(
            name: "WhisperPTTIntegrationTests",
            dependencies: [
                "WhisperPTTCore",
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ],
            path: "Tests/WhisperPTTIntegrationTests",
            resources: [.copy("Fixtures")]
        )
    ],
    swiftLanguageModes: [.v5]
)
