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
public enum HapticFeedback {

    /// Medium impact feedback when recording begins.
    public static func recordingStarted() {
        #if canImport(UIKit) && !os(macOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    /// Light impact feedback when recording stops.
    public static func recordingStopped() {
        #if canImport(UIKit) && !os(macOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    /// Success notification feedback when transcribed text is inserted into the text field.
    public static func textInserted() {
        #if canImport(UIKit) && !os(macOS)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        #endif
    }
}
