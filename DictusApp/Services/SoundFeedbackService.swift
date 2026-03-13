// DictusApp/Services/SoundFeedbackService.swift
// Plays short WAV sounds at key dictation lifecycle events using AudioToolbox.
import AudioToolbox
import DictusCore

/// Plays audio feedback for dictation recording events (start, stop, cancel).
///
/// WHY AudioServicesPlaySystemSound (not AVAudioPlayer):
/// AudioServicesPlaySystemSound is the only API that respects the physical silent switch
/// on iPhone natively. AVAudioPlayer ignores it unless you manually check the ring/silent
/// switch state (which has no public API). Using AudioToolbox means: sound plays when
/// the phone is not on silent, and stays silent when the user has flipped the switch --
/// exactly the behavior users expect from feedback sounds.
///
/// WHY static cached sounds:
/// AudioServicesCreateSystemSoundID has a ~2-5ms overhead per call (reads file from disk,
/// registers with the system). By caching the SystemSoundID after the first play, subsequent
/// plays are instant. The cache persists for the app's lifetime -- these IDs are cheap
/// (just an integer handle) and there are at most 29 of them.
///
/// WHY enum with static methods (same pattern as HapticFeedback):
/// Consistency with the existing DictusCore HapticFeedback enum. Both are stateless
/// utility types with class-level state (generators for haptics, cached IDs for sounds).
enum SoundFeedbackService {

    // MARK: - Cache

    /// Maps sound file name (without extension) to its registered SystemSoundID.
    private static var cachedSounds: [String: SystemSoundID] = [:]

    // MARK: - Configuration

    /// Check if sound feedback is enabled in user preferences.
    ///
    /// WHY object(forKey:) instead of bool(forKey:):
    /// Same pattern as HapticFeedback.isEnabled() -- bool(forKey:) returns false
    /// when the key has never been set, but we want the default to be true
    /// (sounds enabled out of the box). object(forKey:) returns nil for missing keys.
    private static func isEnabled() -> Bool {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        return defaults?.object(forKey: SharedKeys.soundFeedbackEnabled) as? Bool ?? true
    }

    // MARK: - Playback

    /// Play a sound by file name (without .wav extension).
    ///
    /// Looks up the sound in the cache first. If not cached, finds the WAV file
    /// in the app bundle, registers it with AudioToolbox, caches the ID, then plays.
    /// Silently returns if the file is not found or registration fails.
    ///
    /// - Parameter soundName: File name without extension (e.g., "electronic_01a")
    static func play(_ soundName: String) {
        guard !soundName.isEmpty else { return }

        // Check cache first
        if let cachedID = cachedSounds[soundName] {
            AudioServicesPlaySystemSound(cachedID)
            return
        }

        // Find the WAV file in the app bundle
        guard let url = Bundle.main.url(forResource: soundName, withExtension: "wav") else {
            return
        }

        // Register with AudioToolbox
        var soundID: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        guard status == kAudioServicesNoError else {
            return
        }

        // Cache and play
        cachedSounds[soundName] = soundID
        AudioServicesPlaySystemSound(soundID)
    }

    /// Play the recording-start sound.
    /// Default: "electronic_01a" -- a short, distinct beep that signals "recording has begun".
    static func playRecordStart() {
        guard isEnabled() else { return }
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        let name = defaults?.string(forKey: SharedKeys.recordStartSoundName) ?? "electronic_01a"
        play(name)
    }

    /// Play the recording-stop sound.
    /// Default: "ui_chime_01" -- a softer chime that signals "recording stopped, transcribing".
    static func playRecordStop() {
        guard isEnabled() else { return }
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        let name = defaults?.string(forKey: SharedKeys.recordStopSoundName) ?? "ui_chime_01"
        play(name)
    }

    /// Play the recording-cancel sound.
    /// Default: "electronic_02a" -- a distinct tone that signals "cancelled, no transcription".
    static func playRecordCancel() {
        guard isEnabled() else { return }
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        let name = defaults?.string(forKey: SharedKeys.recordCancelSoundName) ?? "electronic_02a"
        play(name)
    }

    // MARK: - Sound Catalog

    /// All available sound file names (without extension), sorted alphabetically.
    ///
    /// WHY hardcoded instead of Bundle directory enumeration:
    /// Bundle.main.urls(forResourcesWithExtension:) can return nil or be unreliable
    /// depending on how resources are bundled (folder reference vs file reference).
    /// Hardcoding is explicit, testable, and doesn't break if the bundle structure changes.
    static func availableSounds() -> [String] {
        [
            "electronic_01a", "electronic_01b", "electronic_01c",
            "electronic_01d", "electronic_01e", "electronic_01f",
            "electronic_02a", "electronic_02b", "electronic_02c",
            "electronic_02d", "electronic_02e", "electronic_02f",
            "electronic_03a", "electronic_03b", "electronic_03c",
            "electronic_03d", "electronic_03e", "electronic_03f",
            "electronic_03g", "electronic_03h", "electronic_03i",
            "electronic_04a", "electronic_04b", "electronic_04c",
            "electronic_04d", "electronic_04e", "electronic_04f",
            "electronic_04g",
            "ui_chime_01",
        ]
    }

    /// Format a sound file name for display in the UI.
    /// Replaces underscores with spaces and capitalizes the first letter.
    /// Example: "electronic_01a" -> "Electronic 01a"
    static func displayName(for soundName: String) -> String {
        let formatted = soundName.replacingOccurrences(of: "_", with: " ")
        return formatted.prefix(1).uppercased() + formatted.dropFirst()
    }
}
