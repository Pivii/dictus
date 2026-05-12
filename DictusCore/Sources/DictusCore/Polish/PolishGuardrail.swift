// DictusCore/Sources/DictusCore/Polish/PolishGuardrail.swift
import Foundation

/// Runtime sanity check on every polish output.
///
/// Rejects catastrophic over- or under-generation (empty output, runaway
/// generation) via a character-length ratio. Subtle word substitution is not
/// caught here — round 1 measures whether that is a real failure mode in
/// production logs before hardening (ADR 0002 §"length-ratio guardrail").
public enum PolishGuardrail {
    /// Returns `true` when `polished` is within the allowed ratio band for `mode`.
    /// Light: `[0.5, 2.0]`. Repair: `[0.3, 3.0]`. Empty raw → only empty polished accepted.
    public static func accepts(raw: String, polished: String, mode: PolishMode) -> Bool {
        guard !raw.isEmpty else { return polished.isEmpty }
        let ratio = Double(polished.count) / Double(raw.count)
        switch mode {
        case .light:  return (0.5...2.0).contains(ratio)
        case .repair: return (0.3...3.0).contains(ratio)
        }
    }
}
