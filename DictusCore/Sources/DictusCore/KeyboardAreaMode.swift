// DictusCore/Sources/DictusCore/KeyboardAreaMode.swift
// Single value describing what the keyboard extension's keyboard area presents.
import Foundation

/// What the keyboard area — the region below the 52 pt toolbar — is presenting.
///
/// Before #271 this was three independent flags spread over two layers: a SwiftUI
/// `@State` for the emoji picker in `KeyboardRootView`, a separate `Bool` for the
/// same picker in `KeyboardViewController` (kept in step through
/// `NotificationCenter`), and the recording overlay derived from `DictationStatus`.
/// Nothing in the type system stopped two of them being true at once, and the
/// layout code that reacted to them was a chain of negated guards that any new
/// full-area state had to be added to by hand — a state that was forgotten
/// collapsed to toolbar height while still being rendered.
///
/// With one value, mutual exclusion is a consequence of the type. Both layers
/// switch on it: SwiftUI to pick the branch it renders, the view controller to set
/// the hosting height, the hosting bottom anchor and the key grid's visibility.
///
/// Lives in DictusCore rather than DictusKeyboard so the transition rule below is
/// unit-testable — the keyboard extension target has no test bundle. Same
/// reasoning as `DefaultKeyboardLayer` and `LayoutType`.
public enum KeyboardAreaMode: String, Equatable, CaseIterable, Sendable {
    /// The UIKit key grid. Toolbar sits above it at 52 pt.
    case keys
    /// The emoji picker fills the area; the toolbar stays visible above it.
    case emoji
    /// Reserved for the hamburger panel (#241). No view is attached yet — the
    /// layout contract exists so #241 adds a view rather than reopening #271.
    case panel
    /// The recording overlay fills the whole area, toolbar included.
    case recording

    /// The mode after a dictation status change.
    ///
    /// A dictation owns the entire keyboard area while it is in flight, so
    /// entering an owning status is the explicit transition that dismisses the
    /// emoji picker (or, later, the #241 panel). Leaving it returns to the key
    /// grid: a picker the user had open before dictating is not restored, which
    /// is what the pre-#271 code did by clearing its emoji flag on overlay show.
    public static func resolving(
        status: DictationStatus,
        current: KeyboardAreaMode
    ) -> KeyboardAreaMode {
        if status.ownsKeyboardArea {
            return .recording
        }
        return current == .recording ? .keys : current
    }
}

public extension DictationStatus {
    /// Whether a dictation round-trip currently owns the keyboard area, i.e.
    /// whether the recording overlay should be filling it.
    ///
    /// WHY an exhaustive switch and not a `Set` membership test: adding a case to
    /// `DictationStatus` must not silently fall through to "does not own the area".
    /// The compiler stops on this function instead, which is how `processing`
    /// (#267) got here.
    ///
    /// `processing` owning the area is what keeps the overlay on screen through the
    /// LLM stage: it resolves to the same `.recording` mode every other in-flight
    /// status does, so the view controller sees no new mode and no new height.
    var ownsKeyboardArea: Bool {
        switch self {
        case .requested, .recording, .transcribing, .processing:
            return true
        case .idle, .ready, .failed:
            return false
        }
    }
}
