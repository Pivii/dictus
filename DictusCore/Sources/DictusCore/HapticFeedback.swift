// DictusCore/Sources/DictusCore/HapticFeedback.swift
// Haptic feedback helpers for dictation recording lifecycle events.
#if canImport(UIKit)
import UIKit
#endif

/// Provides distinct haptic feedback for key dictation events.
///
/// WHY this lives in DictusCore:
/// Both DictusApp (RecordingView) and DictusKeyboard (mic button, transcription insert)
/// use the same haptic patterns. Centralizing them ensures consistent tactile feedback
/// across both targets.
///
/// WHY #if canImport(UIKit):
/// DictusCore is a Swift package that compiles on macOS for testing (swift test).
/// UIKit is only available on iOS. The #if guard prevents build failures during
/// macOS-based SPM test runs while keeping the code available on iOS targets.
///
/// WHY pre-allocated static generators:
/// Creating a new UIImpactFeedbackGenerator per call adds 2-5ms latency because the
/// Taptic Engine needs to spin up. Static instances stay warm, and calling .prepare()
/// after each use re-primes the hardware for the next tap with zero perceptible delay.
///
/// WHY three distinct patterns:
/// - recordingStarted: medium impact -- user needs to feel that recording is actively happening
/// - recordingStopped: light impact -- subtle confirmation that recording stopped
/// - textInserted: success notification -- distinct "done" feel when transcribed text appears
/// - keyTapped: light impact -- matches native iOS keyboard tactile feel
/// - trackpadActivated: medium impact -- confirms spacebar trackpad mode activation
public enum HapticFeedback {

    // MARK: - Pre-allocated generators

    #if canImport(UIKit) && !os(macOS)
    /// Light impact generator for key taps and subtle feedback.
    /// Static allocation avoids 2-5ms per-call overhead from creating new generators.
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)

    /// Medium impact generator for recording events and trackpad activation.
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)

    /// Notification generator for success/error feedback (e.g., text inserted).
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    /// Selection feedback generator for cursor movement during trackpad drag.
    /// UISelectionFeedbackGenerator produces the same subtle "tick" Apple uses
    /// for pickers and the native cursor — distinct from impact feedback,
    /// specifically designed for discrete selection changes.
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    #endif

    /// WHY isEnabled() reads from App Group at point of use (not cached):
    /// When the user toggles haptics in Settings, the change writes to App Group
    /// UserDefaults immediately. Reading at point of use means the next haptic
    /// event respects the new setting without requiring app restart or notification.
    ///
    /// WHY `object(forKey:) as? Bool ?? true` instead of `bool(forKey:)`:
    /// `bool(forKey:)` returns false when the key has never been set.
    /// The correct default is true (haptics enabled out of the box).
    /// `object(forKey:)` returns nil for missing keys, letting us provide the right default.
    #if canImport(UIKit) && !os(macOS)
    private static func isEnabled() -> Bool {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        return defaults?.object(forKey: SharedKeys.hapticsEnabled) as? Bool ?? true
    }
    #endif

    /// Prepare all generators for immediate use.
    /// Call this once at keyboard load (e.g., in KeyboardRootView.onAppear) so the
    /// first key tap has zero latency. Each generator's .prepare() tells the Taptic
    /// Engine to spin up in advance.
    public static func warmUp() {
        #if canImport(UIKit) && !os(macOS)
        lightGenerator.prepare()
        mediumGenerator.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
        #endif
    }

    /// Medium impact feedback when recording begins.
    public static func recordingStarted() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        mediumGenerator.impactOccurred()
        mediumGenerator.prepare()
        #endif
    }

    /// Light impact feedback when recording stops.
    public static func recordingStopped() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        lightGenerator.impactOccurred()
        lightGenerator.prepare()
        #endif
    }

    /// Success notification feedback when transcribed text is inserted into the text field.
    public static func textInserted() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
        #endif
    }

    /// Light impact feedback for keyboard key taps.
    ///
    /// WHY .light style: Matches the native iOS keyboard tactile feel.
    /// Users expect key taps to be subtle -- heavier feedback would feel wrong
    /// compared to the system keyboard they're used to.
    ///
    /// WHY .prepare() after impactOccurred():
    /// Calling prepare() immediately after firing re-primes the Taptic Engine
    /// for the next tap. This keeps latency at ~0ms for rapid typing.
    public static func keyTapped() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        lightGenerator.impactOccurred()
        lightGenerator.prepare()
        #endif
    }

    /// Medium impact feedback for spacebar trackpad mode activation.
    /// Provides a stronger haptic cue when the user activates cursor movement
    /// mode by long-pressing the spacebar (Plan 04 feature).
    public static func trackpadActivated() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        mediumGenerator.impactOccurred()
        mediumGenerator.prepare()
        #endif
    }

    /// Selection tick feedback for each character of cursor movement during trackpad drag.
    /// Uses UISelectionFeedbackGenerator — the same subtle "tick" Apple uses for pickers
    /// and the native cursor. This is the #1 factor for perceived trackpad fluidity.
    /// Pre-arms the generator immediately after firing for zero-latency on the next tick.
    public static func cursorMoved() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
        #endif
    }
}
