// swift-tools-version:5.9
import PackageDescription

// The engine lives in its own package, deliberately: it has no UI and no I/O,
// so it builds and tests under plain `swift test` with no Xcode project, no
// signing and no simulator. That makes it the part CI can verify on its own.
let package = Package(
    name: "WriterblocksCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WriterblocksCore", targets: ["WriterblocksCore"])
    ],
    targets: [
        .target(
            name: "WriterblocksCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "WriterblocksCoreTests",
            dependencies: ["WriterblocksCore"]
        )
    ]
)
