// DictusKeyboard/Views/KeyButton.swift
import SwiftUI
import DictusCore

/// A standard keyboard key that inserts a character on tap.
/// Shows a popup preview above the key during the press gesture.
/// Long-pressing a key with accented variants (e.g., "e" on AZERTY) shows an AccentPopup
/// where the user can slide their finger to select an accented character.
///
/// WHY DragGesture handles both tap and long-press:
/// SwiftUI's LongPressGesture doesn't provide continuous drag tracking after recognition.
/// By using DragGesture alone with a Task.sleep timer, we get: (1) normal tap when released
/// before 400ms, (2) long-press accent popup when held past 400ms, (3) continuous drag
/// tracking to highlight the accent under the finger. This is how Apple's own keyboard works.
struct KeyButton: View {
    let key: KeyDefinition
    let isShifted: Bool
    let onTap: (String) -> Void

    @State private var isPressed = false

    // MARK: - Accent long-press state

    /// Whether the accent popup is currently visible.
    @State private var showingAccents = false
    /// The accented characters available for the current key.
    @State private var accentOptions: [String] = []
    /// Which accent cell the user's finger is hovering over (nil = none selected).
    @State private var selectedAccentIndex: Int? = nil
    /// The async task that waits 400ms before showing the accent popup.
    /// Stored so it can be cancelled if the user lifts their finger early (normal tap).
    @State private var longPressTimer: Task<Void, Never>? = nil
    /// The initial X position when the drag started, used to calculate which accent
    /// the finger is hovering over relative to the key's center.
    @State private var dragStartX: CGFloat? = nil

    private var displayLabel: String {
        isShifted ? key.label.uppercased() : key.label.lowercased()
    }

    private var outputChar: String {
        guard let output = key.output else { return "" }
        return isShifted ? output.uppercased() : output
    }

    /// Cell width matching AccentPopup's cellWidth for hit-testing calculations.
    private let accentCellWidth: CGFloat = 36

    /// Font size scales with Dynamic Type for key labels.
    @ScaledMetric private var keyFontSize: CGFloat = 22

    var body: some View {
        // Using a plain gesture to get press/release states
        Text(displayLabel)
            .font(.system(size: keyFontSize, weight: .regular))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: KeyMetrics.keyHeight)
            .background(keyBackground)
            .overlay(
                // Popup preview shown above key on press (hidden when accents are showing)
                Group {
                    if isPressed && !showingAccents {
                        KeyPopup(label: displayLabel)
                            .offset(y: -(KeyMetrics.keyHeight + 8))
                    }
                },
                alignment: .top
            )
            .overlay(
                // Accent popup shown on long-press, positioned above the key.
                // Uses .top alignment so offset pushes it above the key.
                Group {
                    if showingAccents {
                        AccentPopup(
                            accents: accentOptions,
                            selectedIndex: selectedAccentIndex
                        )
                        .offset(y: -(KeyMetrics.keyHeight + 12))
                    }
                },
                alignment: .top
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isPressed {
                            // First touch — start the press and the long-press timer
                            isPressed = true
                            dragStartX = value.location.x
                            startLongPressTimer()
                        }

                        // While accents are showing, track finger position to highlight
                        if showingAccents {
                            updateSelectedAccent(dragLocation: value.location)
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        longPressTimer?.cancel()
                        longPressTimer = nil

                        if showingAccents {
                            // Long-press mode: insert selected accent or dismiss
                            if let index = selectedAccentIndex, index >= 0, index < accentOptions.count {
                                onTap(accentOptions[index])
                            }
                            // Reset accent state
                            showingAccents = false
                            accentOptions = []
                            selectedAccentIndex = nil
                        } else {
                            // Normal tap: insert the regular character
                            onTap(outputChar)
                        }
                        dragStartX = nil
                    }
            )
    }

    // MARK: - Key Background

    /// Key background: glass on iOS 26, material fallback on older versions.
    ///
    /// WHY conditional glass:
    /// On iOS 26, the native keyboard container already has a glass-like chrome.
    /// Adding individual glass effects to keys might create glass-on-glass artifacts.
    /// We use dictusGlass which applies .glassEffect on iOS 26 and .regularMaterial
    /// on older iOS. If glass-on-glass looks wrong on iOS 26, this can be adjusted
    /// to only apply the fallback material on older versions.
    @ViewBuilder
    private var keyBackground: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 1)
            .dictusGlass(in: RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Long-press helpers

    /// Starts a 400ms timer. If the timer completes (user hasn't lifted finger),
    /// check if the key has accented variants and show the popup.
    ///
    /// WHY 400ms:
    /// iOS system keyboard uses ~350-500ms for long-press detection. 400ms balances
    /// responsiveness (not too slow) with avoiding false triggers during fast typing.
    private func startLongPressTimer() {
        longPressTimer?.cancel()
        longPressTimer = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms

            // Check cancellation — user may have lifted finger before 400ms
            guard !Task.isCancelled else { return }

            // Look up accented variants for this key
            if let accents = AccentedCharacters.accents(for: key.label.lowercased()), !accents.isEmpty {
                // Apply shift state: uppercase the accented characters when shifted
                if isShifted {
                    accentOptions = accents.map { $0.uppercased() }
                } else {
                    accentOptions = accents
                }
                showingAccents = true
                selectedAccentIndex = nil
            }
        }
    }

    /// Maps the current drag position to a selected accent index.
    ///
    /// WHY horizontal position mapping:
    /// The accent popup is a horizontal row of cells centered above the key.
    /// As the user slides their finger left/right, we calculate which cell
    /// they're over based on the horizontal distance from center.
    private func updateSelectedAccent(dragLocation: CGPoint) {
        guard !accentOptions.isEmpty else { return }

        // The popup is centered above the key. Calculate the offset from
        // the drag start position to determine which cell the finger is over.
        let totalPopupWidth = CGFloat(accentOptions.count) * accentCellWidth
        let popupStartX = (dragStartX ?? 0) - totalPopupWidth / 2

        // Calculate which cell the finger is over
        let relativeX = dragLocation.x - popupStartX
        let index = Int(relativeX / accentCellWidth)

        if index >= 0 && index < accentOptions.count {
            selectedAccentIndex = index
        } else {
            selectedAccentIndex = nil
        }
    }
}

/// The popup preview bubble shown above a pressed key.
struct KeyPopup: View {
    let label: String

    @ScaledMetric private var popupFontSize: CGFloat = 32

    var body: some View {
        Text(label)
            .font(.system(size: popupFontSize, weight: .regular))
            .foregroundStyle(.primary)
            .frame(width: 50, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
            )
    }
}

/// Shared key dimension constants.
enum KeyMetrics {
    static let keyHeight: CGFloat = 42
    static let rowSpacing: CGFloat = 6
    static let keySpacing: CGFloat = 4
    static let rowHorizontalPadding: CGFloat = 3
}
