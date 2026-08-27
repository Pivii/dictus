// tools/ane-harness/Sources/AneBenchKit/ComputePlanProbe.swift
//
// THROWAWAY — #268 D2.
//
// A latency figure does not say which processor produced it. `MLComputeUnits`
// is documented as "allow", not "require" — the report this spike extends says
// so explicitly and records that the mechanism was never investigated. So the
// claim "this ran on the Neural Engine" is taken from Core ML's own compute
// plan, which names the anticipated device per operation, rather than inferred
// from a number being fast.
import Foundation
import CoreML

public enum ComputePlanProbe {

    /// Count anticipated compute devices over one compiled model.
    ///
    /// Returns nil when the plan cannot be built (an older OS, or a model
    /// Core ML declines to plan) — an absent count is reported as absent, never
    /// as zero ANE operations.
    @available(iOS 17.4, macOS 14.4, *)
    public static func summarize(modelAt url: URL,
                                 computeUnits: MLComputeUnits = .cpuAndNeuralEngine) async -> ComputePlanSummary? {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        guard let plan = try? await MLComputePlan.load(contentsOf: url, configuration: configuration) else {
            return nil
        }
        guard case let .program(program) = plan.modelStructure else { return nil }

        var ane = 0, cpu = 0, gpu = 0, unknown = 0
        for (_, function) in program.functions {
            walk(function.block, plan: plan, ane: &ane, cpu: &cpu, gpu: &gpu, unknown: &unknown)
        }
        return ComputePlanSummary(
            modelName: url.lastPathComponent,
            neuralEngineOps: ane,
            cpuOps: cpu,
            gpuOps: gpu,
            unknownOps: unknown
        )
    }

    @available(iOS 17.4, macOS 14.4, *)
    private static func walk(_ block: MLModelStructure.Program.Block,
                             plan: MLComputePlan,
                             ane: inout Int, cpu: inout Int, gpu: inout Int, unknown: inout Int) {
        for operation in block.operations {
            // `const` is a weight, not work. Counting them would drown the ratio
            // in operations no processor ever executes.
            if operation.operatorName != "const" {
                switch plan.deviceUsage(for: operation)?.preferred {
                case .some(.neuralEngine): ane += 1
                case .some(.cpu): cpu += 1
                case .some(.gpu): gpu += 1
                default: unknown += 1
                }
            }
            for nested in operation.blocks {
                walk(nested, plan: plan, ane: &ane, cpu: &cpu, gpu: &gpu, unknown: &unknown)
            }
        }
    }
}
