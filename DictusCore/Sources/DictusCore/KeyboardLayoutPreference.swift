// DictusCore/Sources/DictusCore/KeyboardLayoutPreference.swift
// Per-language keyboard layout storage: which layout each dictionary language uses,
// and whether that value is the language's default or a choice the user made (#272).
import Foundation

/// Where the keyboard layout of each `SupportedLanguage` is stored and resolved.
///
/// WHY per language and not one global value (#272):
/// picking a language used to write that language's `defaultLayout` on top of whatever
/// the user had chosen, so "English autocorrect on the AZERTY my fingers know" was
/// unreachable. A French/English bilingual needs French→AZERTY *and* English→QWERTY
/// remembered independently, which one shared override cannot express.
///
/// WHY absence means inherited:
/// a language with no stored entry resolves to `defaultLayout` and keeps tracking it —
/// so shipping a new default (QWERTZ for German in #151) still reaches the users who
/// never expressed a preference. Storing an entry stops that tracking for that language
/// only. The distinction is the presence of the key, not a second flag that could drift
/// out of step with the value.
public enum KeyboardLayoutPreference {

    // MARK: - Reading

    /// The layout `language` types on: its explicit choice, or its default when it has none.
    ///
    /// This is the only resolution rule in the codebase — `LayoutType.active` is this
    /// function applied to the active language.
    public static func layout(for language: SupportedLanguage) -> LayoutType {
        migrateToPerLanguageLayoutsIfNeeded()
        return storedLayout(for: language) ?? language.defaultLayout
    }

    /// The layout the user explicitly chose for `language`, or nil when it still inherits
    /// `defaultLayout`. UI that wants to distinguish the two reads this; UI that only
    /// needs to know what the keys look like reads `layout(for:)`.
    public static func explicitLayout(for language: SupportedLanguage) -> LayoutType? {
        migrateToPerLanguageLayoutsIfNeeded()
        return storedLayout(for: language)
    }

    /// True while `language` still follows `defaultLayout`.
    public static func isInherited(for language: SupportedLanguage) -> Bool {
        explicitLayout(for: language) == nil
    }

    // MARK: - Writing

    /// Records `layout` as `language`'s explicit choice.
    ///
    /// WHY a pick equal to `defaultLayout` is still stored as explicit:
    /// a German user who tries QWERTY and then taps QWERTZ back has chosen QWERTZ. If a
    /// later release changed German's default, reshaping their keyboard under them would
    /// break the same promise this issue exists to keep.
    public static func setLayout(_ layout: LayoutType, for language: SupportedLanguage) {
        migrateToPerLanguageLayoutsIfNeeded()

        var layouts = storedLayouts()
        layouts[language.rawValue] = layout.rawValue
        AppGroup.defaults.set(layouts, forKey: SharedKeys.keyboardLayoutsByLanguage)

        if language == .active {
            mirrorToLegacyKey(layout)
        }
    }

    // MARK: - Migration (#272)

    /// Freezes the layout an existing install is already typing on, once, before the
    /// per-language store is used for anything.
    ///
    /// The rule (spec §6): the **currently active language** keeps whatever layout value is
    /// actually stored today, frozen as explicit — not recomputed from `defaultLayout`. The
    /// pre-#272 Settings picker let a layout diverge from the active language's default until
    /// the next language change, so a divergent pair may already sit in storage; recomputing
    /// would silently reshape those keyboards. The other languages, never having had a visible
    /// value, stay absent and therefore seed at their true `defaultLayout`.
    ///
    /// WHY the dictionary is written even when it stays empty:
    /// its presence is the "already migrated" stamp. Without it, a fresh install that picks
    /// German *after* updating would look, at the next read, exactly like an upgrade sitting
    /// on German with no stored layout — and would be frozen to AZERTY.
    ///
    /// WHY it is lazy instead of a launch hook: both processes read layouts, and the keyboard
    /// extension can run before DictusApp ever launches again. Every entry point calls this
    /// first, so no write can precede the freeze.
    public static func migrateToPerLanguageLayoutsIfNeeded() {
        let defaults = AppGroup.defaults
        guard defaults.dictionary(forKey: SharedKeys.keyboardLayoutsByLanguage) == nil else { return }

        var frozen: [String: String] = [:]
        let legacyRaw = defaults.string(forKey: SharedKeys.keyboardLayout)
        // An install with something to preserve: it either stored a layout, or it has been
        // through onboarding and so has been typing on the AZERTY fallback all along.
        // A fresh install matches neither and stays fully inherited.
        let hasShapeToPreserve = legacyRaw != nil || defaults.bool(forKey: SharedKeys.hasCompletedOnboarding)
        if hasShapeToPreserve {
            // The pre-#272 semantics of `LayoutType.active`, reproduced exactly: the stored
            // raw value, AZERTY when it is missing or unreadable.
            let effective = legacyRaw.flatMap(LayoutType.init(rawValue:)) ?? .azerty
            frozen[SupportedLanguage.active.rawValue] = effective.rawValue
        }
        defaults.set(frozen, forKey: SharedKeys.keyboardLayoutsByLanguage)
    }

    // MARK: - Legacy mirror

    /// Keeps `SharedKeys.keyboardLayout` equal to the active language's effective layout.
    ///
    /// Nothing reads that key anymore except migration. It is maintained for one reason:
    /// a build without #272 (a rollback, or an older TestFlight install) reads it as the
    /// single global layout, and must find the shape the user is actually on rather than
    /// whatever they last had before the update.
    static func mirrorToLegacyKey(_ layout: LayoutType) {
        AppGroup.defaults.set(layout.rawValue, forKey: SharedKeys.keyboardLayout)
    }

    // MARK: - Private

    private static func storedLayouts() -> [String: String] {
        AppGroup.defaults.dictionary(forKey: SharedKeys.keyboardLayoutsByLanguage) as? [String: String] ?? [:]
    }

    private static func storedLayout(for language: SupportedLanguage) -> LayoutType? {
        guard let raw = storedLayouts()[language.rawValue] else { return nil }
        // An unreadable entry is treated as no entry: the language falls back to its
        // default instead of to AZERTY, which is what a missing value has always meant.
        return LayoutType(rawValue: raw)
    }
}
