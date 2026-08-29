// DictusApp/SmartModeDisplayName.swift
// The app's own name for a Smart Mode (issue #79, rename 2026-08-27).
import Foundation
import DictusCore

extension SmartMode {

    /// The mode's name as the app shows it.
    ///
    /// ### Why the catalogue's `displayName` is not simply used
    ///
    /// DictusCore ships no string catalog. That is why every user-facing sentence it
    /// owns — `SmartModeUnavailableReason.englishDescription`, `ProFeature.displayName`
    /// — is English and documented as the log form and the fallback, with the surface
    /// owning the translation keyed on the case. The keyboard's `localizedReason` is
    /// that pattern; this is the same pattern for the one mode whose name is a word
    /// rather than a symbol.
    ///
    /// Most modes need nothing here. `"\u{2192} EN"` is deliberately language-neutral
    /// so one string fits a 46 pt fan row in every UI locale, and it falls straight
    /// through — `SmartModeListView.listName` is where the app dresses it up. Only the bullet mode, renamed from `Notes` to `List` / `Liste` on
    /// 2026-08-27, has a name that has to be said in the user's language.
    ///
    /// Keyed on the **identifier**, which the rename deliberately did not touch: no
    /// persisted armed mode is invalidated and no pinned order is lost. A record that
    /// crossed the App Group from an older build carries the old `displayName` and
    /// still lands on the right string here, because the identifier is what is
    /// matched.
    ///
    /// This file has a twin in DictusKeyboard, and it has to: the two targets have
    /// separate string catalogs, and a shared one would mean a catalog in DictusCore.
    var localizedDisplayName: String {
        SmartMode.localizedDisplayName(identifier: id, fallback: displayName)
    }

    /// The same lookup for a caller that has an identifier and a name but no record.
    ///
    /// `SmartModeFailure` and `SmartModeSkipNotice` both travel across the App Group
    /// carrying exactly that pair, and both name a mode in a sentence. `fallback` is
    /// the name the *writing* build used, which is what an unrecognised identifier
    /// should still produce.
    static func localizedDisplayName(identifier: String, fallback: String) -> String {
        switch identifier {
        case SmartModeCatalogue.notesIdentifier:
            return String(
                localized: "List",
                comment: "Name of the Smart Mode that turns spoken ideas into concise bullet points. Renamed from Notes on 2026-08-27."
            )
        default:
            return fallback
        }
    }
}
