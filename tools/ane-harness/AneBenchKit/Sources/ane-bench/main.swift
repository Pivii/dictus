// tools/ane-harness/Sources/ane-bench/main.swift
//
// THROWAWAY — #268 D2, Mac side. The gate #268's work-split puts before the
// phone: does the converted model load, does Core ML actually place it on the
// Neural Engine, and does it produce sane French on the shipping prompt.
//
// It cannot answer the issue's question. There is no jetsam on a Mac and no
// application lifecycle to be in the background of, so what it produces is a
// floor and a sanity check, exactly as the predecessor spike's Mac figures were.
import Foundation
import CoreML
import AneBenchKit

func option(_ name: String) -> String? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

let defaultModel = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // ane-bench
    .deletingLastPathComponent()   // Sources
    .deletingLastPathComponent()   // AneBenchKit
    .deletingLastPathComponent()   // ane-harness
    .appendingPathComponent(".deps/model")

let modelDirectory = option("--model").map { URL(fileURLWithPath: $0) } ?? defaultModel
let iterations = Int(option("--iterations") ?? "2") ?? 2
let maxNewTokens = Int(option("--max-tokens") ?? "280") ?? 280
let fixtureID = option("--fixture") ?? "3-long"
// `--compute-units cpu` is the control: same model, same prompt, same process,
// Core ML told not to use the Neural Engine. The gap between the two runs is
// what makes "it ran on the ANE" a measurement rather than an assumption.
//
// Unknown values are rejected rather than defaulted. A typo silently producing an
// ANE run labelled `computeUnits=cpuAndNeuralEngine` would look exactly like the
// control it was meant to be, and the whole ANE claim rests on that pair differing.
let computeUnits: MLComputeUnits
switch option("--compute-units") {
case nil, "ane": computeUnits = .cpuAndNeuralEngine
case "cpu":      computeUnits = .cpuOnly
case let other:
    FileHandle.standardError.write(Data("error: --compute-units expects 'ane' or 'cpu', got '\(other ?? "")'\n".utf8))
    exit(2)
}

let runner = AneBenchRunner(configuration: AneBenchRunner.Configuration(
    modelDirectory: modelDirectory,
    maxNewTokens: maxNewTokens,
    iterations: iterations,
    fixtureID: fixtureID,
    computeUnits: computeUnits,
    allowThinking: CommandLine.arguments.contains("--thinking")
))

do {
    try await runner.prepare { message in FileHandle.standardError.write(Data("… \(message)\n".utf8)) }
    let report = try await runner.run { message in FileHandle.standardError.write(Data("… \(message)\n".utf8)) }
    print(report.rendered())
    // `try`, not `try?`: a caller who passed --json and got exit 0 would believe the
    // file is there. And the encode only runs when a path was actually asked for.
    if let path = option("--json") {
        try JSONEncoder().encode(report).write(to: URL(fileURLWithPath: path))
        FileHandle.standardError.write(Data("wrote \(path)\n".utf8))
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
