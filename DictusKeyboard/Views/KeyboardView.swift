// DictusKeyboard/Views/KeyboardView.swift
import SwiftUI
import UIKit
import Combine
import AudioToolbox
import DictusCore

/// System sound IDs matching Apple's 3-category keyboard click sounds.
/// These are the standard iOS keyboard sounds that differentiate letter keys,
/// delete, and modifier keys (space, return, shift, globe, layer switch).
///
/// WHY AudioServicesPlaySystemSound instead of UIDevice.playInputClick():
/// playInputClick() produces a single identical click for all keys. Apple's
/// native keyboard uses 3 distinct sounds. AudioServicesPlaySystemSound()
/// respects the ringer/silent switch, so it behaves correctly on mute.
enum KeySound {
    static let letter: SystemSoundID = 1104
    static let delete: SystemSoundID = 1155
    static let modifier: SystemSoundID = 1156
}

/// The main keyboard view composing all rows and managing layer/shift state.
struct KeyboardView: View {
    let controller: UIInputViewController
    let hasFullAccess: Bool
    @Binding var isEmojiMode: Bool

    @State private var currentLayer: KeyboardLayerType = .letters
    @State private var shiftState: ShiftState = .off
    /// Tracks the last typed character for the adaptive accent key.
    /// After typing a vowel (e, a, u, i, o), the adaptive key shows the most
    /// common accent for that vowel. Reset on space, delete, return, or layer switch.
    @State private var lastTypedChar: String? = nil
    @State private var isTrackpadActive = false
    /// Remembers which layer to return to when dismissing the emoji picker.
    @State private var previousLayer: KeyboardLayerType? = nil

    private var isShifted: Bool {
        shiftState == .shifted || shiftState == .capsLocked
    }

    private var currentRows: [[KeyDefinition]] {
        switch currentLayer {
        case .letters:
            // Use dynamic layout (AZERTY or QWERTY) based on App Group preference.
            // Filter out .mic keys from every row -- the mic button now lives in the
            // toolbar above the keyboard (Plan 03-02). Filtering all rows (not just row 4)
            // is a safety measure in case layouts are restructured in the future.
            return KeyboardLayout.currentLettersRows().map { row in
                row.filter { $0.type != .mic }
            }
        case .numbers: return KeyboardLayout.numbersRows
        case .symbols: return KeyboardLayout.symbolsRows
        case .emoji: return [] // Not used — emoji picker replaces the keyboard rows
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if currentLayer == .emoji {
                    // Emoji picker replaces the keyboard rows entirely
                    EmojiPickerView(
                        onEmojiInsert: { emoji in
                            controller.textDocumentProxy.insertText(emoji)
                        },
                        onDelete: {
                            controller.textDocumentProxy.deleteBackward()
                        },
                        onDismiss: {
                            HapticFeedback.keyTapped()
                            AudioServicesPlaySystemSound(KeySound.modifier)
                            currentLayer = previousLayer ?? .letters
                            previousLayer = nil
                            isEmojiMode = false
                        }
                    )
                } else {
                    VStack(spacing: KeyMetrics.rowSpacing) {
                        ForEach(Array(currentRows.enumerated()), id: \.offset) { _, row in
                            KeyRow(
                                keys: row,
                                rowWidth: geometry.size.width,
                                isShifted: isShifted,
                                shiftState: $shiftState,
                                onCharacter: { char in
                                    insertCharacter(char)
                                },
                                onDelete: {
                                    // Sound is played by DeleteKey directly (alongside haptic)
                                    controller.textDocumentProxy.deleteBackward()
                                    lastTypedChar = nil
                                    checkAutocapitalize()
                                },
                                onWordDelete: {
                                    // Delete backward to the previous word boundary.
                                    // textDocumentProxy has no deleteWordBackward(), so we
                                    // read the text before the cursor and find the last word boundary.
                                    // Sound is played by DeleteKey directly (alongside haptic)
                                    deleteWordBackward()
                                    lastTypedChar = nil
                                    checkAutocapitalize()
                                },
                                onGlobe: {
                                    HapticFeedback.keyTapped()
                                    AudioServicesPlaySystemSound(KeySound.modifier)
                                    controller.advanceToNextInputMode()
                                },
                                onEmoji: {
                                    HapticFeedback.keyTapped()
                                    AudioServicesPlaySystemSound(KeySound.modifier)
                                    previousLayer = currentLayer
                                    currentLayer = .emoji
                                    isEmojiMode = true
                                },
                                onLayerSwitch: {
                                    HapticFeedback.keyTapped()
                                    AudioServicesPlaySystemSound(KeySound.modifier)
                                    toggleLettersNumbers()
                                },
                                onSymbolToggle: {
                                    HapticFeedback.keyTapped()
                                    AudioServicesPlaySystemSound(KeySound.modifier)
                                    toggleNumbersSymbols()
                                },
                                onSpace: {
                                    AudioServicesPlaySystemSound(KeySound.modifier)
                                    controller.textDocumentProxy.insertText(" ")
                                    lastTypedChar = nil
                                    checkAutocapitalize()
                                },
                                onReturn: {
                                    HapticFeedback.keyTapped()
                                    AudioServicesPlaySystemSound(KeySound.modifier)
                                    controller.textDocumentProxy.insertText("\n")
                                    lastTypedChar = nil
                                    checkAutocapitalize()
                                },
                                onAccentAdaptive: { char in
                                    HapticFeedback.keyTapped()
                                    AudioServicesPlaySystemSound(KeySound.letter)
                                    // If the accent key is replacing a vowel (not inserting apostrophe),
                                    // delete the previous vowel first, then insert the accented version.
                                    if AccentedCharacters.shouldReplace(afterTyping: lastTypedChar) {
                                        controller.textDocumentProxy.deleteBackward()
                                    }
                                    insertCharacter(char)
                                },
                                onCursorMove: { offset in
                                    controller.textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
                                },
                                onTrackpadStateChange: { active in
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        isTrackpadActive = active
                                    }
                                },
                                lastTypedChar: lastTypedChar,
                                hasFullAccess: hasFullAccess
                            )
                        }
                    }
                    .padding(.vertical, 4)

                    // Greyed-out overlay during trackpad mode (Apple behavior).
                    // allowsHitTesting(false) ensures the spacebar's DragGesture
                    // continues receiving touch events while the overlay is visible.
                    if isTrackpadActive {
                        Color(.systemBackground).opacity(0.6)
                            .cornerRadius(8)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
            }
        }
        .frame(height: keyboardHeight)
        .onAppear {
            // Set initial shift state based on text field content.
            // Empty field = capitalize first letter (standard iOS behavior).
            checkAutocapitalize()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dictusTextDidChange)) { _ in
            // External text changes (paste, cursor move) may expose a sentence ending.
            checkAutocapitalize()
        }
    }

    private var keyboardHeight: CGFloat {
        let rows: CGFloat = 4
        let standardHeight = (rows * KeyMetrics.keyHeight)
            + ((rows - 1) * KeyMetrics.rowSpacing)
            + 8

        if currentLayer == .emoji {
            // Emoji picker takes full height: toolbar (48pt) + keyboard + bottom spacer (8pt)
            // are hidden by the parent, so we expand to fill that space.
            return standardHeight + 48 + 8
        }
        return standardHeight
    }

    private func insertCharacter(_ char: String) {
        // Play letter-category keyboard click sound.
        // AudioServicesPlaySystemSound respects the ringer/silent switch automatically.
        AudioServicesPlaySystemSound(KeySound.letter)

        // Track last typed character for the adaptive accent key.
        // The accent key uses this to decide whether to show apostrophe or an accent.
        lastTypedChar = char

        controller.textDocumentProxy.insertText(char)

        // Auto-unshift after one character (unless caps locked)
        if shiftState == .shifted {
            shiftState = .off
        }
    }

    /// Check whether autocapitalisation should activate shift.
    /// Respects the host app's autocapitalizationType: .none disables autocap entirely,
    /// .sentences (default) capitalizes after ". ", "! ", "? ", newline, or empty field.
    ///
    /// WHY only auto-SHIFT, never auto-unshift:
    /// Auto-unshift is already handled by insertCharacter() (shifts off after one char).
    /// If we auto-unshifted here, it would fight with manual shift taps.
    /// Caps lock is never touched by autocap — it's always a deliberate user action.
    private func checkAutocapitalize() {
        let proxy = controller.textDocumentProxy

        // Respect autocapitalizationType from the host text field.
        // .none = never autocap (e.g., email, password fields).
        // .sentences = capitalize after sentence-ending punctuation (default).
        // .words and .allCharacters are less common; we handle .sentences and .none.
        if let autocapType = proxy.autocapitalizationType,
           autocapType == .none {
            return
        }

        let before = proxy.documentContextBeforeInput ?? ""

        let shouldCap: Bool
        if before.isEmpty {
            // Empty field = capitalize first letter
            shouldCap = true
        } else if before.hasSuffix(". ") || before.hasSuffix("! ") || before.hasSuffix("? ") {
            // After sentence-ending punctuation followed by space
            shouldCap = true
        } else if before.hasSuffix("\n") {
            // After newline
            shouldCap = true
        } else {
            shouldCap = false
        }

        // Only auto-activate shift; don't interfere with caps lock or manual shift
        if shouldCap && shiftState == .off {
            shiftState = .shifted
        }
    }

    /// Delete backward to the previous word boundary.
    /// Since UITextDocumentProxy doesn't provide deleteWordBackward(),
    /// we read the text before the cursor, find the last word boundary
    /// (space or start of string), and delete that many characters.
    private func deleteWordBackward() {
        let proxy = controller.textDocumentProxy
        guard let before = proxy.documentContextBeforeInput, !before.isEmpty else {
            // Nothing to delete — fall back to single char delete
            proxy.deleteBackward()
            return
        }

        // Trim trailing spaces first (delete spaces before the word)
        var trimmed = before
        var trailingSpaces = 0
        while trimmed.hasSuffix(" ") {
            trimmed = String(trimmed.dropLast())
            trailingSpaces += 1
        }

        // Find the last word boundary (space) in the remaining text
        let charsInWord: Int
        if let lastSpace = trimmed.lastIndex(of: " ") {
            charsInWord = trimmed.distance(from: trimmed.index(after: lastSpace), to: trimmed.endIndex)
        } else {
            // No space found — delete everything remaining
            charsInWord = trimmed.count
        }

        let totalToDelete = trailingSpaces + charsInWord
        for _ in 0..<totalToDelete {
            proxy.deleteBackward()
        }
    }

    private func toggleLettersNumbers() {
        if currentLayer == .letters {
            currentLayer = .numbers
        } else {
            currentLayer = .letters
            shiftState = .off
        }
    }

    private func toggleNumbersSymbols() {
        if currentLayer == .numbers {
            currentLayer = .symbols
        } else {
            currentLayer = .numbers
        }
    }
}
