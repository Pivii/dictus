// DictusKeyboard/Views/UIKit/KeyboardTouchState.swift
// ObservableObject bridge from UIKit touch events to SwiftUI popup/accent/trackpad state.
import Foundation
import Combine

/// Bridges UIKit touch state to SwiftUI for popup preview, accent strip, and trackpad overlay.
///
/// WHY an ObservableObject bridge:
/// UIButton subclasses handle touches in UIKit (touchesBegan/Ended), but the popup preview
/// and accent strip are rendered in SwiftUI. This class publishes touch state changes so
/// SwiftUI views can observe and render popups at the correct position.
///
/// WHY @Published (not manual objectWillChange):
/// @Published auto-triggers SwiftUI updates on every property change. For keyboard popups,
/// the update frequency is low (one press at a time), so the overhead is negligible.
class KeyboardTouchState: ObservableObject {

    // MARK: - Key press popup state

    /// Label of the currently pressed key (nil when no key is pressed).
    /// Used by SwiftUI to show the popup preview bubble above the pressed key.
    @Published var pressedKeyLabel: String?

    /// Frame of the pressed key in keyboard coordinate space.
    /// Used by SwiftUI to position the popup preview above the correct key.
    @Published var pressedKeyFrame: CGRect = .zero

    // MARK: - Accent popup state

    /// Whether the accent popup strip is currently visible.
    @Published var showingAccents: Bool = false

    /// Accented character options to display in the popup strip.
    @Published var accentOptions: [String] = []

    /// Index of the accent the user's finger is hovering over (nil = none selected).
    @Published var selectedAccentIndex: Int?

    /// Frame of the key showing accents, for popup positioning.
    @Published var accentKeyFrame: CGRect = .zero

    // MARK: - Trackpad state

    /// Whether the space bar trackpad cursor mode is active.
    /// Used by SwiftUI to show/hide the greyed-out trackpad overlay.
    @Published var isTrackpadActive: Bool = false

    // MARK: - Methods

    /// Publish that a key is being pressed. Called from touchesBegan.
    func showPress(label: String, frame: CGRect) {
        pressedKeyLabel = label
        pressedKeyFrame = frame
    }

    /// Clear press state. Called from touchesEnded/Cancelled.
    func hidePress() {
        pressedKeyLabel = nil
    }

    /// Show accent popup with the given options. Called after 400ms long-press.
    func showAccents(_ accents: [String], keyFrame: CGRect) {
        accentOptions = accents
        accentKeyFrame = keyFrame
        showingAccents = true
        selectedAccentIndex = nil
    }

    /// Update which accent the finger is hovering over during drag.
    func updateAccentSelection(at index: Int?) {
        selectedAccentIndex = index
    }

    /// Hide accent popup and reset all accent state.
    func hideAccents() {
        showingAccents = false
        accentOptions = []
        selectedAccentIndex = nil
        accentKeyFrame = .zero
    }

    /// Set trackpad mode active/inactive. Called by SpaceKeyButton.
    func setTrackpad(_ active: Bool) {
        isTrackpadActive = active
    }
}
