// DictusKeyboard/AppleFMExtensionProbe.swift
import Foundation
import os
import DictusCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// THROWAWAY DIAGNOSTIC CODE for the #357 spike. Delete with the spike.
///
/// #357 asks whether the keyboard extension can call Apple Foundation Models,
/// and specifically whether **the extension's process counts as foreground** for
/// the rate limiter #315 identified. Apple documents `rateLimited` as happening
/// only to an app "running in the background", and a controlled device test on
/// 2026-08-13 showed the rule is applied per call: the same process, seconds
/// apart, is refused backgrounded and served in ~800 ms when active. DictusApp
/// is backgrounded for every polish call by design, so polish runs in the one
/// state Apple deprioritises. The keyboard is in the foreground at exactly the
/// moment polish would run — nobody has checked whether that is a way out.
///
/// WHY this cannot be a test or a simulator run: `docs/agents/simulator.md` §7
/// establishes by experiment that the Dictus keyboard cannot be enabled in any
/// simulator, and the entire question is whether the *extension's* process is
/// treated differently from the app's — so an app-target measurement answers
/// nothing. The answer has to come off the maintainer's device, which is why
/// this is a probe that writes to the persistent log he already exports rather
/// than an assertion.
///
/// **Nothing here runs unless it is deliberately armed.** Disarmed — which is
/// the default and the state this branch sits in — the entire cost is the one
/// `Bool` read in `runIfArmed()`. Nothing is allocated, no session is built and
/// no behaviour changes, which matters because the keyboard runs under a hard
/// memory ceiling and a `didReceiveMemoryWarning` storm is a known hazard here.
enum AppleFMExtensionProbe {

    /// The component name every line of this probe carries, so one `grep` over
    /// an exported log pulls the whole run out.
    private static let component = "AppleFMExtensionProbe"

    /// Fixed synthetic input, never the user's text.
    ///
    /// WHY fixed and synthetic: these lines land in a log that gets exported and
    /// mailed. The rest of the logging in this project is privacy-safe by
    /// construction (`LogEvent` has no free-text content parameter), and a probe
    /// is not a reason to break that.
    ///
    /// WHY this long: it has to serve two questions at once. Q2 wants an
    /// ordinary polish-shaped call, and Q4 wants a generation still in flight
    /// long enough for a human to switch apps and tear the extension down. The
    /// #315 captures put an 824-character input at roughly 5 s of generation, so
    /// a few hundred characters buys the seconds Q4 needs while staying a
    /// realistic dictation. It is unpunctuated spoken French because that is
    /// what the natural-mode prompt is written against.
    private static let fixture = """
    alors ce que je voulais dire c'est que le texte arrive brut sans ponctuation \
    et il faut le remettre en forme pour qu'il soit lisible donc on garde le sens \
    et le registre de la personne mais on ajoute la ponctuation les majuscules et \
    on répare les hésitations parce que sinon le message est difficile à lire quand \
    on le reçoit et c'est exactement ce que la couche de polissage est censée faire \
    sur chaque dictée sans jamais inventer de contenu qui n'a pas été dit
    """

    /// Fire one probe run if, and only if, the App Group flag is set.
    ///
    /// Called from exactly one place, `KeyboardRootView.onAppear`, so the run
    /// happens while the keyboard is on screen — which is the foreground moment
    /// the whole question is about. Everything below the `guard` is unreachable
    /// on a normal dictation: disarmed, this function is one `Bool` read.
    ///
    /// WHY an App Group flag rather than a gesture or a build flag: the probe
    /// has to fire on a build the maintainer can install and use normally for
    /// twenty-five minutes first (driving the app into the refusing state is
    /// the whole setup for Q2), and it has to be armable *after* that state is
    /// reached, without rebuilding and without force-quitting anything — a
    /// relaunch would reset the very state being measured.
    static func runIfArmed() {
        guard AppGroup.defaults.bool(forKey: SharedKeys.appleFMExtensionProbeArmed) else { return }
        // Disarm before running, not after. A probe that was killed
        // mid-generation — which is Q4's whole scenario — must not re-fire on
        // the next keyboard appearance and turn a one-shot measurement into a
        // loop the maintainer cannot switch off from inside the keyboard.
        AppGroup.defaults.set(false, forKey: SharedKeys.appleFMExtensionProbeArmed)
        Task { await run() }
    }

    private static func run() async {
        // Short token shared by every line of one run, so a start with no
        // completion is unambiguous. That pairing IS the Q4 answer: no
        // completion line means the process died with `respond()` in flight.
        let token = String(UUID().uuidString.prefix(8))
        let memBefore = MemoryFootprint.residentMB()

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            report(token: token, action: "skipped", details: "reason=osTooOld")
            return
        }

        // Availability as seen from INSIDE the extension process. This is Q1's
        // runtime half and it is not answerable from the app: the app reporting
        // `.available` says nothing about whether the same system service is
        // reachable across the extension's sandbox boundary.
        let availability = describe(SystemLanguageModel.default.availability)

        report(
            token: token,
            action: "started",
            details: "availability=\(availability) memBeforeMB=\(memBefore) inputChars=\(fixture.count)"
        )
        // Flush before generating, not after. If Q4's teardown kills the process
        // mid-`respond()`, an unflushed start line would be lost too and the run
        // would leave no trace at all — the one outcome that cannot be read.
        PersistentLog.flush()

        // Sample the footprint while the call is in flight. A peak that only
        // exists during generation is exactly the shape Q3 is looking for, and
        // a before/after pair would step straight over it.
        let peak = PeakSampler(initial: memBefore)
        let sampling = Task { await peak.sample() }

        // The REAL shipping engine, real prompts, real session lifecycle. WHY
        // not a hand-rolled `LanguageModelSession`: what Q3 needs priced is what
        // a future implementation would actually pay, and what Q2 needs refused
        // or served is a call Apple sees as identical to the app's. Using the
        // production type also makes the build itself the Q1a evidence — this
        // file puts `AppleFoundationModelsPolishEngine` into a target compiled
        // with `APPLICATION_EXTENSION_API_ONLY = YES`.
        let engine = AppleFoundationModelsPolishEngine()
        let start = DispatchTime.now().uptimeNanoseconds
        var outcome: String
        do {
            let polished = try await engine.polish(raw: fixture, targetLanguage: .french, mode: .natural)
            // Length only. The generated text is not logged, for the same
            // privacy reason the input is a fixture.
            outcome = "success outputChars=\(polished.count)"
        } catch {
            // Reuse the engine's own #315 classification so a refusal here is
            // directly comparable with the app-side `failureReason` slugs in the
            // polish export. `rateLimited` versus anything else IS the Q2 answer.
            outcome = "failed reason=\(engine.failureReason(for: error).slug)"
        }
        let engineMs = Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)

        sampling.cancel()
        let memAfter = MemoryFootprint.residentMB()

        report(
            token: token,
            action: "finished",
            details: "\(outcome) engineMs=\(engineMs) memBeforeMB=\(memBefore)"
                + " memPeakMB=\(peak.value) memAfterMB=\(memAfter)"
        )
        PersistentLog.flush()
        #else
        report(token: token, action: "skipped", details: "reason=sdkMissing memBeforeMB=\(memBefore)")
        #endif
    }

    private static func report(token: String, action: String, details: String) {
        PersistentLog.log(.diagnosticProbe(
            component: component,
            instanceID: token,
            action: action,
            details: details
        ))
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func describe(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available: return "available"
        case .unavailable(let reason): return "unavailable:\(reason)"
        @unknown default: return "unknown"
        }
    }
    #endif
}

/// Polls `phys_footprint` and keeps the maximum seen, for the duration of one
/// probe generation.
///
/// WHY polling rather than a high-water-mark API: there is no public one. iOS
/// exposes the current footprint (`MemoryFootprint.residentMB()`, which is what
/// jetsam scores) and nothing that remembers the peak, so a transient spike
/// during session creation or generation is invisible to a before/after pair.
/// 25 ms is fine-grained against a generation measured in hundreds of
/// milliseconds to seconds, and this task exists only inside an armed run.
private final class PeakSampler: @unchecked Sendable {

    private let peak: OSAllocatedUnfairLock<Int>

    init(initial: Int) {
        peak = OSAllocatedUnfairLock(initialState: initial)
    }

    var value: Int { peak.withLock { $0 } }

    func sample() async {
        while !Task.isCancelled {
            let now = MemoryFootprint.residentMB()
            peak.withLock { $0 = max($0, now) }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }
}
