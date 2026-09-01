// DictusCore/Sources/polish-harness/TargetElectionCorpus.swift
// Scoring the polish target election against committed, hand-labelled transcripts
// (#456).
import Foundation
import DictusCore

/// One raw transcript and the target a correct election has to produce for it.
///
/// WHY the labels are in the file and not in this code: they are judgements, and a
/// judgement that decides a threshold has to be disagreeable with in the open. The
/// corpus is committed under `docs/research/456-target-election/`.
struct ElectionCase: Codable {
    let id: String
    /// What the case is for. Every case carries one — the corpus is small enough that
    /// a case with no stated purpose is a case nobody can argue with.
    let note: String
    /// The keyboard language at dictation time, i.e. what the election falls back to.
    let keyboardLanguage: String
    /// The language the polish prompt must be resolved for: a code, or `none` when the
    /// transcript is in a language the per-language prompts do not cover and polish
    /// must be skipped rather than retargeted.
    let expectedTarget: String
    /// Whether the gibberish gate is expected to skip this transcript. True only for
    /// `expectedTarget == "none"`, and stated separately because "no target" and "no
    /// polish" are two facts and the second is what protects the user.
    let expectsGibberishSkip: Bool
    let raw: String
}

enum TargetElectionCorpus {

    static func load(_ paths: [String]) -> [ElectionCase] {
        paths.flatMap { path -> [ElectionCase] in
            guard let data = FileManager.default.contents(atPath: path) else {
                print("error: cannot read corpus at \(path)")
                exit(1)
            }
            do {
                return try JSONDecoder().decode([ElectionCase].self, from: data)
            } catch {
                print("error: cannot decode corpus at \(path): \(error)")
                exit(1)
            }
        }
    }

    // MARK: - Scoring

    struct Score {
        var correct = 0
        var wrong: [String] = []
        /// Decided by the transcript's own proportions.
        var byProportion = 0
        /// Decided by the keyboard language, because nothing led by enough.
        var byKeyboard: [String] = []
        /// No supported language read at all — polish is skipped, no target used.
        var skipped = 0

        var line: String {
            String(format: "correct %2d/%-2d   by proportion %2d   by keyboard %2d   skipped %d",
                   correct, correct + wrong.count, byProportion, byKeyboard.count, skipped)
        }
    }

    /// Run the real election — the same `polishPromptSelection` the pipeline calls, on
    /// the same `PolishLanguageMix.measure` — at one dominance floor.
    ///
    /// A case whose expected target is `none` is scored on the gibberish gate instead:
    /// the election returns the keyboard language there (it has nothing else to
    /// return), and what actually protects the user is that no supported language was
    /// read, so polish is skipped before the target is used.
    static func score(_ cases: [ElectionCase], floor: Double) -> Score {
        var score = Score()
        for item in cases {
            let mix = PolishLanguageMix.measure(item.raw)
            let actual: String
            if mix.dominantSupportedLanguage == nil {
                actual = "none"
                score.skipped += 1
            } else if let elected = mix.electedLanguage(floor: floor) {
                actual = elected.rawValue
                score.byProportion += 1
            } else {
                actual = item.keyboardLanguage
                score.byKeyboard.append(item.id)
            }
            if actual == item.expectedTarget {
                score.correct += 1
            } else {
                score.wrong.append("\(item.id) — expected \(item.expectedTarget), got \(actual)")
            }
        }
        return score
    }

    // MARK: - Reports

    /// The table the floor is read off: what each transcript is made of, what it elects,
    /// and how it was decided. Drives no model, so anyone can re-run it.
    static func table(_ cases: [ElectionCase], floor: Double) {
        print("── per-case measurement (floor \(String(format: "%.2f", floor)))")
        for item in cases {
            let mix = PolishLanguageMix.measure(item.raw)
            let shares = mix.shares.sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }.map { String(format: "%@ %.3f", $0.key, $0.value) }.joined(separator: " / ")
            let whole = PolishPipeline.detectLanguageCode(in: item.raw) ?? "-"
            let elected = mix.electedLanguage(floor: floor)
            let via: String
            if mix.dominantSupportedLanguage == nil {
                via = "skipped (no supported language)"
            } else if let elected {
                via = "proportion → \(elected.rawValue)"
            } else {
                via = "keyboard → \(item.keyboardLanguage)"
            }
            let fallback = mix.countedCharacters == 0 ? "  [whole-string fallback]" : ""
            print("  \(item.id)")
            print("    whole-blob=\(whole)   mix=\(shares.isEmpty ? "-" : shares)"
                  + "   counted=\(mix.countedCharacters)ch\(fallback)")
            print("    expected=\(item.expectedTarget)   \(via)")
        }
    }

    /// Sweep the dominance floor. This is the measurement the 60 % is kept or moved on:
    /// the brief declared it a judgement call and required it to be scored against
    /// fixtures before shipping.
    ///
    /// **Read the `by keyboard` column, not only the `correct` one.** In
    /// `.followKeyboard` the fallback usually lands on the same language the
    /// proportion would have elected, because the user is usually on the keyboard of
    /// the language they are speaking — so a floor far too high still scores perfectly
    /// on a corpus while quietly making the target depend on the keyboard being right.
    /// That dependency is exactly what #332 was about. The floor's upper bound is
    /// therefore the last one at which every monolingual-intent transcript is still
    /// decided by its own content.
    static func sweep(_ cases: [ElectionCase]) {
        print("\n── #456 dominance-floor sweep")
        for floor in stride(from: 0.50, through: 0.95, by: 0.05) {
            let score = score(cases, floor: floor)
            let marker = floor == TranscriptionLanguagePolicy.dominantLanguageShareFloor
                ? "  <-- shipping" : ""
            print(String(format: "  %.2f   %@%@", floor, score.line as NSString, marker as NSString))
            for wrong in score.wrong { print("          WRONG:       \(wrong)") }
            for fallback in score.byKeyboard { print("          via keyboard: \(fallback)") }
        }
    }
}
