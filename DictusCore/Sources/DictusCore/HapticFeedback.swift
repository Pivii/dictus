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
/// WHY three distinct patterns:
/// - recordingStarted: medium impact — user needs to feel that recording is actively happening
/// - recordingStopped: light impact — subtle confirmation that recording stopped
/// - textInserted: success notification — distinct "done" feel when transcribed text appears
/// - keyTapped: light impact — matches native iOS keyboard tactile feel
public enum HapticFeedback {

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

    /// Medium impact feedback when recording begins.
    public static func recordingStarted() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    /// Light impact feedback when recording stops.
    public static func recordingStopped() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    /// Success notification feedback when transcribed text is inserted into the text field.
    public static func textInserted() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        #endif
    }

    /// Light impact feedback for keyboard key taps.
    ///
    /// WHY .light style: Matches the native iOS keyboard tactile feel.
    /// Users expect key taps to be subtle — heavier feedback would feel wrong
    /// compared to the system keyboard they're used to.
    public static func keyTapped() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
}
