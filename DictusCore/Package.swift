// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DictusCore",
    platforms: [.iOS(.v17), .macOS("26.0")],
    products: [
        .library(name: "DictusCore", targets: ["DictusCore"]),
        .executable(name: "polish-harness", targets: ["polish-harness"])
    ],
    targets: [
        .target(name: "DictusCore", path: "Sources/DictusCore"),
        // Off-device polish eval harness (macOS only — needs Apple Intelligence).
        // Runs the REAL pipeline (PolishPipeline + AppleFoundationModelsPolishEngine)
        // on text fixtures, sharing one source of truth with the app. Not built by
        // the iOS app or CI; run locally on a Mac with Apple Intelligence enabled.
        .executableTarget(
            name: "polish-harness",
            dependencies: ["DictusCore"],
            path: "Sources/polish-harness",
            resources: [.copy("fixtures")]
        ),
        .testTarget(
            name: "DictusCoreTests",
            dependencies: ["DictusCore"],
            path: "Tests/DictusCoreTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
