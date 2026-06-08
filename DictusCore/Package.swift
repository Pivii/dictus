// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DictusCore",
    platforms: [.iOS(.v17), .macOS("26.0")],
    products: [
        .library(name: "DictusCore", targets: ["DictusCore"])
    ],
    targets: [
        .target(name: "DictusCore", path: "Sources/DictusCore"),
        .testTarget(
            name: "DictusCoreTests",
            dependencies: ["DictusCore"],
            path: "Tests/DictusCoreTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
