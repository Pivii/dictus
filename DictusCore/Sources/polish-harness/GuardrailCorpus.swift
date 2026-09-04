// DictusCore/Sources/polish-harness/GuardrailCorpus.swift
// Scoring the two new guardrail checks against committed, hand-labelled outputs
// (#413, #414).
import Foundation
import NaturalLanguage
import DictusCore

/// One output the #393 campaign produced, or one written by hand for a case the
/// campaign does not contain, with the label a human gave it.
///
/// WHY the labels are in the file and not in this code: they are judgements, and a
/// judgement that decides a threshold has to be disagreeable with in the open. The
/// corpus is committed under `docs/research/413-414-guardrail/`.
struct GuardrailCase: Codable {
    let source: String
    let fixture: String
    let run: Int
    /// `polished` (the engine output was accepted) or `engineOut` (it was rejected).
    let kind: String
    /// `polish`, `smart.notes`, `smart.notes.v2`, `smart.translate.en`.
    let task: String
    /// The fixture's declared language, i.e. the route the pipeline took.
    let inputLang: String
    /// The `NLLanguage` code the output is required to read as: the input's own for
    /// every mode that keeps the speaker's language, the target for a translation.
    let expectedLang: String
    /// `sameLanguage` | `bilingual` | `wrongLanguage`, by reading.
    let language: String
    /// `grounded` | `fabricated`, by reading.
    let grounding: String
    /// `aligned` | `displaced` | `unrelated`, by reading (#466): does the output
    /// open where the input opens, does the input's opening reappear late, or does
    /// it not reappear at all.
    ///
    /// Optional because the 128 outputs committed for #413/#414 carry no such label
    /// — they predate the question. Absent reads as `aligned`, which is what every
    /// one of them is by construction: they are campaign outputs of ordinary shape,
    /// and any of them the check refuses is a false rejection worth seeing.
    let prefix: String?
    let wasAccepted: Bool
    let raw: String
    let output: String
    /// Present on the hand-written cases; says what the case is for.
    let note: String?

    /// The text the guardrail actually judges. The pipeline runs the
    /// verbal-punctuation pre-pass first, so the comparison baseline is the pre-pass
    /// output, not the fixture's `raw` — it matters on the one fixture that dictates
    /// punctuation out loud.
    var preprocessed: String {
        guard let language = SupportedLanguage(rawValue: inputLang) else { return raw }
        return VerbalPunctuationPrepass.apply(raw, language: language)
    }

    /// Whether the grounding check is sound for this case's task. It is not for a
    /// translation, which localises names by design, nor for repair, which
    /// reconstructs words by design — see `PolishGrounding` and
    /// `PolishAcceptanceContract.repair`.
    ///
    /// The repair exclusion only reaches cases that say which free-polish variant
    /// they are. The 128 outputs committed for #413/#414 all say `polish`, so they
    /// score exactly as they did.
    var groundingApplies: Bool {
        !task.hasPrefix("smart.translate.") && task != "polish.repair"
    }

    /// Whether the prefix-alignment check runs on this case's task in production —
    /// the free polish only, per `PolishAcceptanceContract.requiresAlignedPrefix` (#466).
    var prefixApplies: Bool { task == "polish" || task.hasPrefix("polish.") }

    /// The free-polish variant, when the case names one: `natural`, `auto`,
    /// `repair`. Nil on the cases committed before #466, which say only `polish`,
    /// and on every Smart Mode.
    var polishMode: String? {
        guard task.hasPrefix("polish.") else { return nil }
        return String(task.dropFirst("polish.".count))
    }

    var mustBeRejectedForLanguage: Bool { language != "sameLanguage" }
    var mustBeRejectedForGrounding: Bool { grounding == "fabricated" }
    var mustBeRejectedForPrefix: Bool { (prefix ?? "aligned") != "aligned" }
}

enum GuardrailCorpus {

    static func load(_ paths: [String]) -> [GuardrailCase] {
        paths.flatMap { path -> [GuardrailCase] in
            guard let data = FileManager.default.contents(atPath: path) else {
                print("error: cannot read corpus at \(path)")
                exit(1)
            }
            do {
                return try JSONDecoder().decode([GuardrailCase].self, from: data)
            } catch {
                print("error: cannot decode corpus at \(path): \(error)")
                exit(1)
            }
        }
    }

    // MARK: - Scoring

    struct Score {
        var caught = 0, missed = 0, correctlyAccepted = 0, falselyRejected = 0
        var falseRejections: [String] = []
        var misses: [String] = []

        var line: String {
            String(format: "caught %d/%d   false rejections %d/%d",
                   caught, caught + missed, falselyRejected, falselyRejected + correctlyAccepted)
        }
    }

    /// Score the per-segment language check at one threshold pair (#413).
    static func scoreLanguage(_ cases: [GuardrailCase],
                              thresholds: PolishLanguageSegmentThresholds) -> Score {
        var score = Score()
        for item in cases {
            let passes = PolishGuardrail.detectedLanguageMatches(
                polished: item.output, inputLanguageCode: item.expectedLang, thresholds: thresholds
            )
            let label = "\(item.source):\(item.fixture)#\(item.run)"
            switch (item.mustBeRejectedForLanguage, passes) {
            case (true, false): score.caught += 1
            case (true, true): score.missed += 1; score.misses.append(label)
            case (false, false): score.falselyRejected += 1; score.falseRejections.append(label)
            case (false, true): score.correctlyAccepted += 1
            }
        }
        return score
    }

    /// Score the grounding check (#414). Cases whose task the check is unsound for
    /// are skipped, which is what the pipeline does with them.
    static func scoreGrounding(_ cases: [GuardrailCase]) -> Score {
        var score = Score()
        for item in cases where item.groundingApplies {
            let ungrounded = PolishGrounding.ungroundedAnchors(
                in: item.output, input: item.preprocessed, languageCode: item.expectedLang
            )
            let label = "\(item.source):\(item.fixture)#\(item.run)"
            switch (item.mustBeRejectedForGrounding, ungrounded.isEmpty) {
            case (true, false): score.caught += 1
            case (true, true): score.missed += 1; score.misses.append(label)
            case (false, false):
                score.falselyRejected += 1
                score.falseRejections.append("\(label) — \(ungrounded.map(\.text).joined(separator: ", "))")
            case (false, true): score.correctlyAccepted += 1
            }
        }
        return score
    }

    /// Score the prefix-alignment check at one threshold set (#466).
    ///
    /// `include` is what makes the repair split visible rather than folded in: the
    /// mode is measured on its own because its output legitimately shares no
    /// vocabulary with its input, which is the one shape this check cannot read.
    static func scorePrefix(_ cases: [GuardrailCase],
                            thresholds: PolishPrefixAlignmentThresholds,
                            include: (GuardrailCase) -> Bool = { _ in true }) -> Score {
        var score = Score()
        for item in cases where item.prefixApplies && include(item) {
            let passes = PolishPrefixAlignment.accepts(
                polished: item.output, raw: item.preprocessed, thresholds: thresholds
            )
            let label = "\(item.source):\(item.fixture)#\(item.run)"
            switch (item.mustBeRejectedForPrefix, passes) {
            case (true, false): score.caught += 1
            case (true, true): score.missed += 1; score.misses.append(label)
            case (false, false):
                score.falselyRejected += 1
                score.falseRejections.append("\(label) — \(offsetDescription(item, thresholds))")
            case (false, true): score.correctlyAccepted += 1
            }
        }
        return score
    }

    /// Where the input's opening reappeared in the output, in words, for a reader
    /// checking a rejection rather than taking it on trust.
    private static func offsetDescription(_ item: GuardrailCase,
                                          _ thresholds: PolishPrefixAlignmentThresholds) -> String {
        switch PolishPrefixAlignment.alignment(
            ofOutput: item.output, against: item.preprocessed, thresholds: thresholds
        ) {
        case .notApplicable: return "not applicable"
        case .aligned: return "the speaker's, from its first line"
        case .openingLineNotTheSpeakers(let share):
            return String(format: "opening line is %.0f%% the speaker's", share * 100)
        case .neverSupported: return "no stretch is the speaker's"
        }
    }

    // MARK: - Reports

    /// One score, and every case behind it that a reader has to be able to check.
    static func report(_ score: Score) {
        print("   \(score.line)")
        for miss in score.misses { print("   missed:   \(miss)") }
        for bad in score.falseRejections { print("   FALSE REJECTION: \(bad)") }
    }

    /// Every segment of every case, with what the recogniser makes of it. This is
    /// the table the thresholds are read off, and it drives no model — so it is
    /// re-runnable by anyone, with or without Apple Intelligence.
    static func segmentTable(_ cases: [GuardrailCase]) {
        print("── per-segment language readings (chars, reading, confidence)")
        for item in cases {
            let segments = PolishSegmentation.segments(of: item.output)
            guard segments.count > 1 else { continue }
            print("\n[\(item.source):\(item.fixture)#\(item.run)] expected=\(item.expectedLang) "
                  + "label=\(item.language) accepted=\(item.wasAccepted)")
            for segment in segments {
                let reading = PolishPipeline.detectLanguageCode(in: segment, confidenceThreshold: 0)
                let confidence = confidenceOfTopHypothesis(segment)
                let agrees = reading == item.expectedLang ? " " : "!"
                print(String(format: "  %@ %3d  %-7@ %.3f  %@",
                             agrees, segment.count, (reading ?? "-") as NSString, confidence, segment))
            }
        }
    }

    /// Sweep the two thresholds and print the confusion matrix at each pair.
    static func sweep(_ cases: [GuardrailCase]) {
        print("\n── #413 threshold sweep (rows: minimum segment characters, columns: confidence floor)")
        let lengths = [12, 15, 20, 25, 30, 35, 40]
        let floors = [0.50, 0.60, 0.70, 0.80, 0.85, 0.90, 0.95]
        print("       " + floors.map { String(format: "%12.2f", $0) }.joined())
        for length in lengths {
            var row = String(format: "  %3d  ", length)
            for floor in floors {
                let score = scoreLanguage(cases, thresholds: PolishLanguageSegmentThresholds(
                    minimumSegmentCharacters: length, confidenceFloor: floor
                ))
                row += cell("\(score.caught)c/\(score.falselyRejected)fr")
            }
            print(row)
        }
        print("  (c = drifted outputs caught out of \(cases.filter(\.mustBeRejectedForLanguage).count);"
              + " fr = legitimate outputs falsely rejected out of \(cases.filter { !$0.mustBeRejectedForLanguage }.count))")
    }

    /// Sweep the two prefix thresholds and print the confusion matrix at each pair,
    /// for the modes the check ships on and for repair separately (#466).
    ///
    /// The offset axis of the earlier sweeps is gone with the threshold it swept —
    /// §8 of the research note measured that no value of it separates a preamble
    /// from a legitimately translated opening.
    static func sweepPrefix(_ cases: [GuardrailCase]) {
        let defaults = PolishPrefixAlignmentThresholds.default
        let windows = [4, 6, 8, 10, 12, 16]
        let floors = [0.50, 0.60, 0.70, 0.75, 0.80, 0.90]
        for (title, include) in [
            ("natural + auto — the modes the check ships on",
             { (item: GuardrailCase) in item.polishMode != "repair" }),
            ("repair — measured separately, see docs/research/466-preamble-guardrail.md §6.3",
             { (item: GuardrailCase) in item.polishMode == "repair" })
        ] {
            let scoped = cases.filter { $0.prefixApplies && include($0) }
            print("\n── #466 prefix sweep, \(title)")
            print("   minimum=\(defaults.minimumWords) words")
            print("        " + floors.map { String(format: "%12.2f", $0) }.joined())
            for window in windows {
                var row = String(format: "  %3d   ", window)
                for floor in floors {
                    let score = scorePrefix(cases, thresholds: PolishPrefixAlignmentThresholds(
                        windowWords: window, supportFloor: floor, minimumWords: defaults.minimumWords
                    ), include: include)
                    row += cell("\(score.caught)c/\(score.falselyRejected)fr")
                }
                print(row)
            }
            print("  (rows: window judged at once, in words; columns: share of a stretch"
                  + " that must be the speaker's own words — one floor serves both tests)")
            print("  (c = caught out of \(scoped.filter(\.mustBeRejectedForPrefix).count);"
                  + " fr = falsely rejected out of \(scoped.filter { !$0.mustBeRejectedForPrefix }.count))")
        }
        openingLineTable(cases)
    }

    /// The opening-line support share of every multi-line output, which is the table
    /// the floor is read off. A reader can see the band it sits in rather than take
    /// it on trust.
    private static func openingLineTable(_ cases: [GuardrailCase]) {
        var legitimate: [Double] = []
        var refused: [Double] = []
        for item in cases where item.prefixApplies && item.polishMode != "repair" {
            guard let share = PolishPrefixAlignment.openingLineSupport(
                ofOutput: item.output, against: item.preprocessed
            ) else { continue }
            if item.mustBeRejectedForPrefix { refused.append(share) } else { legitimate.append(share) }
        }
        print("\n── #466 opening-line support share, multi-line outputs only")
        print(String(format: "   legitimate           n=%3d   worst (lowest)  %.2f",
                     legitimate.count, legitimate.min() ?? .nan))
        print(String(format: "   preamble/fabricated  n=%3d   worst (highest) %.2f",
                     refused.count, refused.max() ?? .nan))
        print("   (the floor sits between those two numbers; a single-line output is not judged here)")
    }

    /// The anchors every case carries, grounded or not. What #414's precision rests
    /// on is visible here rather than asserted.
    static func anchorTable(_ cases: [GuardrailCase]) {
        print("\n── #414 anchors found per output")
        for item in cases where item.groundingApplies {
            let all = PolishGrounding.anchors(in: item.output, languageCode: item.expectedLang)
            guard !all.isEmpty else { continue }
            let ungrounded = Set(PolishGrounding.ungroundedAnchors(
                in: item.output, input: item.preprocessed, languageCode: item.expectedLang
            ).map(\.text))
            let rendered = all.map { ungrounded.contains($0.text) ? "\($0.text)⚑" : $0.text }
            print("  [\(item.source):\(item.fixture)#\(item.run)] \(item.grounding): \(rendered.joined(separator: ", "))")
        }
        print("  (⚑ = present in the output, absent from the input)")
    }

    /// Right-align a cell in a fixed-width column.
    ///
    /// `String(format: "%12@", … as NSString)` does not pad on this platform — it
    /// prints the string and ignores the width — so every sweep table this file has
    /// ever printed came out as one run-on line. Found while adding the #466 sweep;
    /// fixed for both.
    private static func cell(_ text: String, width: Int = 12) -> String {
        String(repeating: " ", count: max(0, width - text.count)) + text
    }

    private static func confidenceOfTopHypothesis(_ text: String) -> Double {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.languageHypotheses(withMaximum: 1).values.max() ?? 0
    }
}
