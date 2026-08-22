// swift-tools-version: 6.0
//
// THROWAWAY — #268 D2. Not part of the app: nothing in Dictus.xcodeproj, in
// DictusCore's package, or in CI references this. It exists to answer one
// question — can a backgrounded DictusApp reach the Neural Engine to run an
// LLM — and it is meant to be deleted with the branch that carries it.
//
// `../.deps/Anemll` does not exist in a fresh checkout: run ../setup.sh first,
// or this manifest fails to load.
import PackageDescription

let package = Package(
    name: "ane-harness",
    // macOS 26 comes from DictusCore, which the polish prompts live in;
    // iOS 18 is AnemllCore's floor. The harness itself needs neither.
    platforms: [.iOS(.v18), .macOS("26.0")],
    products: [
        .library(name: "AneBenchKit", targets: ["AneBenchKit"]),
        .executable(name: "ane-bench", targets: ["ane-bench"])
    ],
    dependencies: [
        .package(path: "../../../DictusCore"),
        .package(path: "../.deps/Anemll/anemll-swift-cli")
    ],
    targets: [
        .target(
            name: "AneBenchKit",
            dependencies: [
                .product(name: "DictusCore", package: "DictusCore"),
                .product(name: "AnemllCore", package: "anemll-swift-cli")
            ],
            resources: [.copy("Resources/seed.json")]
        ),
        .executableTarget(name: "ane-bench", dependencies: ["AneBenchKit"])
    ]
)
