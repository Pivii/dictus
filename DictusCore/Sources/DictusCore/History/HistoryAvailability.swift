// DictusCore/Sources/DictusCore/History/HistoryAvailability.swift
// Who may keep a transcription history, and what everyone else sees instead.
import Foundation

/// What the home screen offers for the transcription history.
public enum HistoryEntryPoint: Equatable, Sendable {
    /// The hint and the swipe open the history.
    case open
    /// The hint is drawn locked and leads to the paywall. Marked rather than
    /// removed, for the reason #395 marks the paywall's Smart Mode card rather than
    /// dropping it: a surface that silently contains different things for different
    /// people is one nobody can screenshot for review or reason about in a support
    /// thread, and a user who subscribes would otherwise never learn it was there.
    case locked
    /// Nothing at all. No hint, no gesture, no route to the paywall.
    case hidden
}

/// The entitlement policy for the transcription history (#70, corrected 2026-08-28).
///
/// The history is a **Pro feature**. #70's body says otherwise; that sentence
/// predates #54, which puts "Transcription history + search" on the Pro side of the
/// free/Pro split, and predates `ProFeature.history`, which has been in the shipped
/// code with its icon and its paywall descriptions since Pro gating landed.
///
/// ### Why this is a type and not two `if`s at the call sites
///
/// Same reason #392 gave `SmartModeAvailability.armability` an `isEntitled`
/// parameter: an entitlement answered inline, in the view that happens to need it,
/// is an entitlement the next surface will answer differently. The questions are
/// pure functions here, so both directions are testable on a Mac with no App Group,
/// no StoreKit and no subscriber — which matters more than usual for this feature,
/// because nobody can be a subscriber until #215 opens the paywall.
///
/// Neither argument below carries a default, deliberately. #392 exists because a
/// property named "the arming policy" answered on hardware alone, and a default
/// would put that trap straight back. The compiler asks instead.
public enum HistoryAvailability {

    /// Whether the user is paying for the history **and** has it switched on.
    ///
    /// `FeatureGate.isAvailable` and not `isProActive`, matching
    /// `SmartModeAvailability.isEntitled`: the per-feature toggle is part of the
    /// entitlement, and a subscriber who turned History off in Settings has said
    /// what they want. Turning it off stops new dictations being stored; it does not
    /// take away what is already stored — see `clearRowIsVisible`.
    public static var isEntitled: Bool {
        FeatureGate.isAvailable(.history)
    }

    /// What the home screen shows.
    ///
    /// The `.hidden` case is not shyness, it is #236's rule as `SettingsView` and
    /// `ToolbarView` already apply it: while `PremiumFlags.paywallVisible` is false
    /// the app must look like there is no subscription at all — no locked rows, no
    /// PRO pills, no navigation path to `PaywallView`. A lock on the home screen
    /// leading nowhere would be the one place that broke it.
    public static func entryPoint(isEntitled: Bool, paywallVisible: Bool) -> HistoryEntryPoint {
        if isEntitled { return .open }
        return paywallVisible ? .locked : .hidden
    }

    /// The live answer for this process.
    public static var entryPoint: HistoryEntryPoint {
        entryPoint(isEntitled: isEntitled, paywallVisible: PremiumFlags.paywallVisible)
    }

    /// Whether Settings shows the destructive "Clear history" row.
    ///
    /// **This is the rule that a lapsed subscription must not imprison the data**,
    /// and it is one line because it should be impossible to get wrong. An
    /// entitlement that goes away stops the history growing and locks it for
    /// reading; it must never be what stands between the user and deleting a
    /// plaintext record of everything they have ever dictated. So the row survives
    /// the entitlement for exactly as long as there is something to delete.
    ///
    /// It is still hidden for someone who never had the feature and has nothing
    /// stored, because there the row would only advertise a feature #236 says must
    /// not be visible yet.
    public static func clearRowIsVisible(isEntitled: Bool, hasSavedRecords: Bool) -> Bool {
        isEntitled || hasSavedRecords
    }
}
