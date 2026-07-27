// DictusApp/Onboarding/PolishTogglePage.swift
// Onboarding step: opt-in toggle for the local transcription polish layer.
import SwiftUI
import DictusCore

/// Onboarding page introducing the local transcription polish capability (#141)
/// and letting the user opt in before their first dictation.
///
/// WHY this replaces the old layer-choice step (ModeSelectionPage, issue #213):
/// Product focus is keyboard-only dictation for now. Asking new users to pick a
/// default keyboard layer (ABC / 123) exposed internal complexity they didn't
/// need yet — the layer picker stays available in Settings with its default
/// value. Introducing the polish opt-in here instead surfaces a real quality
/// choice early, with a clear quality/latency tradeoff.
///
/// WHY @AppStorage on the App Group suite:
/// SharedKeys.polishEnabled is the single source of truth read by the polish
/// pipeline and by the Settings toggle. Writing the same key here means the
/// choice made during onboarding is immediately reflected in Settings, and
/// remains editable there afterwards.
///
/// AVAILABILITY: OnboardingView only shows this page when
/// PolishAvailability.isToggleVisible is true, i.e. on devices where Apple
/// Foundation Models either works or can be fixed by the user (enable Apple
/// Intelligence, wait for the model download). For those fixable states a short
/// caption explains the situation under the toggle — never a dead toggle.
struct PolishTogglePage: View {
    let onNext: () -> Void

    /// Same preference as the Settings polish toggle — off by default (opt-in).
    @AppStorage(SharedKeys.polishEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
    private var polishEnabled = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            Image(systemName: "wand.and.stars")
                .font(.system(size: 72))
                .foregroundColor(.dictusAccent)
                .padding(.bottom, 24)

            // Title
            Text("Polish transcription with a local model")
                .font(.dictusHeading)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)

            // Explanation — what polish does, faithful to the issue copy:
            // local model, light corrections, possible added processing time.
            Text("Dictus can use Apple's local Foundation Model to lightly polish your transcription after speech recognition: punctuation, casing, accents and small corrections.")
                .font(.dictusBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)

            Text("This can improve transcription quality, but may add a little processing time.")
                .font(.dictusBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            // Opt-in toggle card
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enable transcription polish", isOn: $polishEnabled)
                    .font(.dictusBody)
                    .tint(.dictusAccent)

                if let note = availabilityNote {
                    Text(note)
                        .font(.dictusCaption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .dictusGlass(in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 32)
            .padding(.bottom, 12)

            // Reassurance: optional, on-device, editable later.
            Text("Optional, runs fully on your device. You can change this anytime in Settings.")
                .font(.dictusCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)

            // Continue button — matches the style used by other onboarding pages
            // (custom RoundedRectangle instead of .borderedProminent which renders
            // as a capsule pill on iOS 26 Liquid Glass).
            Button(action: onNext) {
                Text("Continue")
                    .font(.dictusSubheading)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.dictusAccent)
                    )
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Availability

    /// Short explanation when Apple Foundation Models needs a user-side fix.
    ///
    /// Mirrors the Settings availability footer with onboarding-length copy.
    /// This page is only shown when PolishAvailability.isToggleVisible is true,
    /// so the non-available states reachable here are the fixable ones (Apple
    /// Intelligence off, model still downloading). The last case only exists for
    /// exhaustiveness and DEBUG builds forcing the toggle visible.
    private var availabilityNote: LocalizedStringKey? {
        switch PolishAvailability.state {
        case .available:
            return nil
        case .appleIntelligenceNotEnabled:
            return "Requires Apple Intelligence. You can turn it on later in iPhone Settings."
        case .modelNotReady:
            return "The Apple Intelligence model is still downloading on your device. Polish will start working once it's ready."
        case .deviceNotEligible, .osTooOld, .sdkMissing, .other:
            return "Polish isn't available on this device."
        }
    }
}
