// DictusCore/Sources/DictusCore/Polish/SmartModeAvailability.swift
// Whether a Smart Mode may be armed at all, and if not, why (issue #79).
import Foundation

/// Why no Smart Mode may be armed right now.
///
/// Smart Modes run on Apple Foundation Models or they do not run. #268 measured the
/// alternative in two rounds and closed it `wontfix` on 2026-08-22: no model that
/// fits the 4/6 GB tier polishes better than doing nothing, and the best surviving
/// candidate takes 13.8 s backgrounded against Apple FM's field p50 of 1,654 ms. So
/// this enum is not a list of degraded states to fall back through — it is the list
/// of sentences the user is owed instead of a feature.
public enum SmartModeUnavailableReason: Equatable, Sendable {

    /// Apple Intelligence is off, or refuses to enable. Recoverable by the user; the
    /// most common cause is the Siri-vs-iPhone language mismatch.
    case appleIntelligenceNotEnabled

    /// The model is still downloading. Recoverable by waiting.
    case modelNotReady

    /// The hardware cannot run Apple Foundation Models. Definitive.
    case deviceNotEligible

    /// The OS predates Apple Foundation Models. Definitive until the user updates.
    case osTooOld

    /// This build was compiled without the FoundationModels SDK. Definitive, and a
    /// build-configuration problem rather than a user-facing one.
    case sdkMissing

    /// The engine is available but this process has stopped calling it (#315): two
    /// consecutive `rateLimited` refusals. Recoverable, and only by a fresh process
    /// — Apple's background rate limit is not refunded by waiting or by a foreground
    /// visit, which every capture on that issue showed.
    case engineRefusing

    /// Apple reported an unavailability reason this build has never heard of.
    case other(String)

    /// The device can run Smart Modes; the user is not paying for them (#392).
    ///
    /// A different state from every other case here, and it has to read as one:
    /// #79 sells Pro on devices that cannot run Smart Modes at all, so "not
    /// entitled" and "not capable" describe two different people and must never
    /// share a sentence. This one has a remedy the user can act on today.
    case notSubscribed

    /// Stable name for logs and for a UI that wants to key off the reason without
    /// switching over the enum.
    public var slug: String {
        switch self {
        case .appleIntelligenceNotEnabled: return "appleIntelligenceNotEnabled"
        case .modelNotReady: return "modelNotReady"
        case .deviceNotEligible: return "deviceNotEligible"
        case .osTooOld: return "osTooOld"
        case .sdkMissing: return "sdkMissing"
        case .engineRefusing: return "engineRefusing"
        case .other(let detail): return "other:\(detail)"
        case .notSubscribed: return "notSubscribed"
        }
    }

    /// One readable English sentence.
    ///
    /// English and not localised because DictusCore ships no string catalog — the
    /// same reason `ProFeature.displayName` is English here while the app localises
    /// its own copy. The surface that shows this owns its translation, keyed on the
    /// case; this is the fallback and the log form.
    public var englishDescription: String {
        switch self {
        case .appleIntelligenceNotEnabled:
            return "Smart Modes need Apple Intelligence. Turn it on in Settings."
        case .modelNotReady:
            return "Apple Intelligence is still downloading its model. Smart Modes will work once it finishes."
        case .deviceNotEligible:
            return "Smart Modes need Apple Intelligence, which this iPhone does not support."
        case .osTooOld:
            return "Smart Modes need iOS 26 or later."
        case .sdkMissing:
            return "Smart Modes are not available in this build."
        case .engineRefusing:
            return "Apple Intelligence is refusing requests right now. Smart Modes will come back shortly."
        case .other(let detail):
            return "Smart Modes are unavailable (\(detail))."
        case .notSubscribed:
            return "Smart Modes are part of Dictus Pro."
        }
    }

    /// Whether the user can expect this to clear on its own or by an action of
    /// theirs. Definitive reasons are the ones a paywall has to describe honestly
    /// rather than promise around.
    public var isRecoverable: Bool {
        switch self {
        // `.other` carries every reason this build does not recognise, including
        // `@unknown default` — a state Apple adds after we ship. Treating an
        // unrecognised reason as definitive would let a future transient state (a
        // model re-download, a new "busy") clear the user's armed mode for good on
        // the first dictation, with nothing to restore it when the condition lifts.
        // The unknown case is precisely the one where permanence cannot be known,
        // so it is recoverable: log it, run Normal, keep the setting.
        // `.notSubscribed` is recoverable, and that is load-bearing rather than
        // charitable: `SmartModeStore.resolveArmedMode()` clears the stored setting
        // for definitive reasons only, and a lapsed subscription must not silently
        // erase which mode the user had armed. They resubscribe and it is still
        // there.
        case .appleIntelligenceNotEnabled, .modelNotReady, .engineRefusing, .other,
             .notSubscribed:
            return true
        case .deviceNotEligible, .osTooOld, .sdkMissing: return false
        }
    }
}

/// Whether a Smart Mode may be armed.
public enum SmartModeArmability: Equatable, Sendable {
    case armable
    case unavailable(SmartModeUnavailableReason)

    public var isArmable: Bool { self == .armable }

    public var reason: SmartModeUnavailableReason? {
        guard case .unavailable(let reason) = self else { return nil }
        return reason
    }
}

/// The arming policy: fail early, before the user speaks.
///
/// **Smart Mode must never silently insert untransformed text**, and the honest way
/// to hold that is to refuse the arming rather than the dictation. Apple Foundation
/// Models availability is knowable before a word is said, so the fan opens with modes
/// disabled and a readable reason and the user never discovers the problem after
/// speaking (#79).
///
/// This is the *policy*. The surfaces that show it — the fan in the keyboard, the
/// mode list and the paywall in the app — are separate work.
public enum SmartModeAvailability {

    /// Resolve armability from the three facts that decide it.
    ///
    /// - Parameter engineState: what the device and the Apple Intelligence
    ///   configuration say, from `PolishAvailability.state`.
    /// - Parameter engineIsRefusing: whether the process that will run the
    ///   generation has given up on the engine for its lifetime (#315).
    /// - Parameter isEntitled: whether the user is paying for Smart Modes (#392).
    ///
    /// **The order is the message.** A device that cannot run the engine is told
    /// that, not sold a subscription it could never use — #79 sells Pro on such
    /// devices precisely because the feature list is honest about them, and a
    /// paywall reached from "buy Pro to unlock this" on an iPhone 13 is the
    /// misleading-metadata rejection that issue names. Capability first,
    /// entitlement second, transient refusal last.
    ///
    /// `isEntitled` has no default on purpose. #392 exists because this property is
    /// named "the arming policy" and answered on Apple Intelligence alone, which is
    /// exactly what someone building a paid surface on top of it would trust. A
    /// default would put that trap back.
    public static func armability(engineState: PolishAvailabilityState,
                                  engineIsRefusing: Bool,
                                  isEntitled: Bool) -> SmartModeArmability {
        switch engineState {
        case .appleIntelligenceNotEnabled: return .unavailable(.appleIntelligenceNotEnabled)
        case .modelNotReady: return .unavailable(.modelNotReady)
        case .deviceNotEligible: return .unavailable(.deviceNotEligible)
        case .osTooOld: return .unavailable(.osTooOld)
        case .sdkMissing: return .unavailable(.sdkMissing)
        case .other(let detail): return .unavailable(.other(detail))
        case .available:
            guard isEntitled else { return .unavailable(.notSubscribed) }
            return engineIsRefusing ? .unavailable(.engineRefusing) : .armable
        }
    }

    /// Armability as it stands in *this* process.
    ///
    /// The #315 half is per-process by nature: the flag is written and cleared by
    /// the keyboard extension, which is the process that runs the generation for a
    /// keyboard dictation. Read from the app it describes the keyboard's last known
    /// state, which is the right thing for a mode list to say and the wrong thing to
    /// disarm on — see `SmartModeStore.resolveArmedMode()`.
    ///
    /// The entitlement is read here rather than passed in, because both processes
    /// read it the same way: `FeatureGate` goes to the App Group, which the keyboard
    /// and the app share.
    public static var current: SmartModeArmability {
        armability(
            engineState: PolishAvailability.state,
            engineIsRefusing: PolishAvailabilityChannel.isUnavailable,
            isEntitled: isEntitled
        )
    }

    /// Whether the user is paying for Smart Modes.
    ///
    /// `FeatureGate.isAvailable` and not `isProActive`: the per-feature toggle is
    /// part of the entitlement, and a subscriber who switched Smart Mode off in
    /// Settings has said what they want.
    public static var isEntitled: Bool {
        FeatureGate.isAvailable(.smartMode)
    }

    /// Whether the device could ever run a Smart Mode, ignoring transient refusals
    /// and ignoring what the user pays.
    ///
    /// This is the half that decides whether an armed mode *survives*: a device that
    /// has lost Apple Intelligence cannot honour the mode at all, while a process on
    /// the wrong side of a rate limit — or a lapsed subscription — will be fine
    /// again later. Entitlement is deliberately `true` here for that reason: a
    /// cancelled subscription must stop the mode applying without erasing which mode
    /// the user had armed.
    public static var deviceCanRunModes: Bool {
        armability(
            engineState: PolishAvailability.state, engineIsRefusing: false, isEntitled: true
        ).isArmable
    }

    /// Whether this iPhone could run Smart Modes if it were configured for them.
    ///
    /// The distinction the paywall needs, and the one `deviceCanRunModes` does not
    /// make: an iPhone 15 Pro with Apple Intelligence switched off is **capable**,
    /// an iPhone 13 is not. Selling Pro to the first is honest and selling it to the
    /// second on a Smart Mode card is the rejection risk #79 names.
    ///
    /// Hardware, OS and SDK are exactly the definitive reasons, so this is
    /// `isRecoverable` read as a capability question rather than a second table that
    /// could drift from the first.
    public static var deviceIsCapable: Bool {
        switch armability(
            engineState: PolishAvailability.state, engineIsRefusing: false, isEntitled: true
        ) {
        case .armable: return true
        case .unavailable(let reason): return reason.isRecoverable
        }
    }
}
