// DictusCore/Sources/polish-harness/VocabularyCorpus.swift
// Replaying the committed custom-vocabulary corpus (#80 decision 12).
import Foundation
import DictusCore

/// One replayable case: a vocabulary, a transcript, and the text the pass must
/// produce from it.
///
/// WHY the expectation is in the file and not in this code: it is a judgement about
/// what the feature should do to a sentence, and a judgement that decides behaviour
/// has to be disagreeable with in the open. The corpus is committed under
/// `docs/research/80-vocabulary/`.
struct VocabularyCase: Codable {
    let source: String
    let fixture: String
    /// `constructed` or `captured`. **Every case committed on 2026-09-07 is
    /// `constructed`** — see the corpus README: the available polish exports hold
    /// 182 raw/polished pairs and a scan showed them to be polish rewrites, not
    /// engine manglings of technical terms, so nothing here was harvested. A case
    /// that says `captured` came off a device.
    let origin: String
    /// What the case is for, in one sentence.
    let note: String
    /// The matching rules this case exercises, so a reader can see the corpus covers
    /// what the issue asked it to cover without reading every record.
    let covers: [String]
    let entries: [VocabularyCaseEntry]
    let raw: String
    let expected: String
}

/// A vocabulary entry as the corpus spells it. Deliberately not `VocabularyEntry`
/// itself: the corpus should not have to carry a UUID and a date to say
/// "Kubernetes, written cubernetes".
struct VocabularyCaseEntry: Codable {
    let term: String
    let variants: [String]
    /// Absent means enabled, which is what the add sheet produces.
    let isEnabled: Bool?
}

enum VocabularyCorpus {

    static func load(_ paths: [String]) -> [VocabularyCase] {
        paths.flatMap { path -> [VocabularyCase] in
            guard let data = FileManager.default.contents(atPath: path) else {
                print("error: cannot read corpus at \(path)")
                exit(1)
            }
            do {
                return try JSONDecoder().decode([VocabularyCase].self, from: data)
            } catch {
                print("error: cannot decode corpus at \(path): \(error)")
                exit(1)
            }
        }
    }

    /// The entries as `VocabularyReplacer` receives them in production.
    ///
    /// An entry the model refuses to build — an over-long term, say — is reported
    /// rather than silently skipped: a corpus case that quietly exercises fewer
    /// rules than it declares would score green for the wrong reason.
    static func entries(for item: VocabularyCase) -> [VocabularyEntry] {
        item.entries.compactMap { entry in
            guard let built = VocabularyEntry(
                term: entry.term, variants: entry.variants, isEnabled: entry.isEnabled ?? true
            ) else {
                print("error: \(item.fixture) declares an entry the model refuses: \(entry.term)")
                exit(1)
            }
            return built
        }
    }
}

/// Replay every case, and report what moved.
///
/// Deterministic and model-free, like `guardrail` and `target`: the numbers behind a
/// shipped behaviour have to be re-runnable by anyone, on any Mac, without Apple
/// Intelligence.
func runVocabulary() {
    let paths = CommandLine.arguments.dropFirst(2).filter { !$0.hasPrefix("--") }
    guard !paths.isEmpty else {
        print("usage: swift run polish-harness vocabulary <corpus.json> [more.json ...]")
        exit(1)
    }
    let cases = VocabularyCorpus.load(Array(paths))
    let constructed = cases.filter { $0.origin == "constructed" }.count

    print("corpus: \(cases.count) cases, \(constructed) constructed, "
          + "\(cases.count - constructed) captured on a device")
    print("")

    var failures: [String] = []
    var notIdempotent: [String] = []

    for item in cases {
        let entries = VocabularyCorpus.entries(for: item)
        let once = VocabularyReplacer.apply(item.raw, entries: entries)
        let twice = VocabularyReplacer.apply(once, entries: entries)
        let label = "\(item.source):\(item.fixture)"

        if once != item.expected {
            failures.append(label)
            print("✗ \(label)")
            print("   covers:   \(item.covers.joined(separator: ", "))")
            print("   raw:      \(item.raw)")
            print("   expected: \(item.expected)")
            print("   got:      \(once)")
        } else {
            print("✓ \(label)   [\(item.covers.joined(separator: ", "))]")
        }

        if twice != once {
            notIdempotent.append(label)
            print("   ! not idempotent: a second pass produced \(twice)")
        }
    }

    print("")
    print("── #80 replacement pass")
    print(String(format: "   correct %d/%d   idempotent %d/%d",
                 cases.count - failures.count, cases.count,
                 cases.count - notIdempotent.count, cases.count))
    for failure in failures { print("   failed:        \(failure)") }
    for item in notIdempotent { print("   not idempotent: \(item)") }

    // The coverage the issue asked the corpus to carry, listed rather than counted:
    // a reader checking the acceptance criteria should not have to open the file.
    let covered = Set(cases.flatMap(\.covers)).sorted()
    print("   covers: \(covered.joined(separator: ", "))")

    if !failures.isEmpty || !notIdempotent.isEmpty { exit(1) }
}
