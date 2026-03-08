// DictusKeyboard/Views/SpecialKeyButton.swift
import SwiftUI
import DictusCore

/// Shift key with three states: off, shift (single character), caps lock.
/// Double-tap detected via timestamp: if second tap arrives within 400ms, activate caps lock.
struct ShiftKey: View {
    @Binding var shiftState: ShiftState
    let width: CGFloat

    @State private var lastTapTime: Date = .distantPast

    var body: some View {
        Button {
            HapticFeedback.keyTapped()
            let now = Date()
            let interval = now.timeIntervalSince(lastTapTime)
            lastTapTime = now

            if interval < 0.4 && shiftState == .shifted {
                // Double-tap: activate caps lock
                shiftState = .capsLocked
            } else {
                switch shiftState {
                case .off:
                    shiftState = .shifted
                case .shifted:
                    shiftState = .off
                case .capsLocked:
                    shiftState = .off
                }
            }
        } label: {
            Image(systemName: shiftIconName)
                .font(.system(size: 16, weight: .medium))
                .frame(width: width)
                .frame(height: KeyMetrics.keyHeight)
                .background(
                    RoundedRectangle(cornerRadius: KeyMetrics.keyCornerRadius)
                        .fill(shiftState != .off
                              ? Color(.label)
                              : Color(.systemGray3))
                )
                .foregroundColor(shiftState != .off
                                 ? Color(.systemBackground)
                                 : Color(.label))
        }
    }

    private var shiftIconName: String {
        switch shiftState {
        case .off: return "shift"
        case .shifted: return "shift.fill"
        case .capsLocked: return "capslock.fill"
        }
    }
}

enum ShiftState {
    case off
    case shifted
    case capsLocked
}

/// Delete key with repeat-on-hold behavior.
/// Uses Task + Task.sleep instead of Timer.scheduledTimer, which is
/// unreliable in keyboard extensions (RunLoop may not be active).
/// Includes ~400ms initial delay before repeat begins (native iOS feel).
struct DeleteKey: View {
    let width: CGFloat
    let onDelete: () -> Void

    @State private var isHolding = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: "delete.left.fill")
            .font(.system(size: 16, weight: .medium))
            .frame(width: width)
            .frame(height: KeyMetrics.keyHeight)
            .background(
                RoundedRectangle(cornerRadius: KeyMetrics.keyCornerRadius)
                    .fill(Color(.systemGray3))
            )
            .foregroundColor(Color(.label))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isHolding {
                            isHolding = true
                            onDelete() // Immediate first delete
                            repeatTask = Task { @MainActor in
                                // Initial delay before repeat begins (~400ms,
                                // matching native iOS delete key behavior)
                                try? await Task.sleep(nanoseconds: 400_000_000)
                                // Repeat at ~100ms intervals while held
                                while !Task.isCancelled {
                                    onDelete()
                                    try? await Task.sleep(nanoseconds: 100_000_000)
                                }
                            }
                        }
                    }
                    .onEnded { _ in
                        isHolding = false
                        repeatTask?.cancel()
                        repeatTask = nil
                    }
            )
    }
}

/// Space bar key.
struct SpaceKey: View {
    let width: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text("espace")
                .font(.system(size: 15))
                .frame(width: width)
                .frame(height: KeyMetrics.keyHeight)
                .background(
                    RoundedRectangle(cornerRadius: KeyMetrics.keyCornerRadius)
                        .fill(KeyMetrics.letterKeyColor)
                        .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 1)
                )
        }
        .foregroundColor(Color(.label))
    }
}

/// Return key.
struct ReturnKey: View {
    let width: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text("retour")
                .font(.system(size: 15, weight: .medium))
                .frame(width: width)
                .frame(height: KeyMetrics.keyHeight)
                .background(
                    RoundedRectangle(cornerRadius: KeyMetrics.keyCornerRadius)
                        .fill(Color(.systemGray3))
                )
        }
        .foregroundColor(Color(.label))
    }
}

/// Globe key (switch keyboards).
struct GlobeKey: View {
    let width: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "globe")
                .font(.system(size: 16, weight: .medium))
                .frame(width: width)
                .frame(height: KeyMetrics.keyHeight)
                .background(
                    RoundedRectangle(cornerRadius: KeyMetrics.keyCornerRadius)
                        .fill(Color(.systemGray3))
                )
        }
        .foregroundColor(Color(.label))
    }
}

/// Emoji key — replaces the globe key visually with a smiling face emoji icon.
/// Functionally identical to globe: tapping cycles to the next input mode.
///
/// WHY emoji icon instead of globe:
/// Apple's native AZERTY keyboard shows an emoji face icon in the bottom-left,
/// not a globe. The globe icon appears only when multiple keyboards are installed
/// AND the user hasn't set a default. Our keyboard always shows emoji to match
/// the most common native experience.
struct EmojiKey: View {
    let width: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text("\u{1F60A}")  // smiling face emoji
                .font(.system(size: 18))
                .frame(width: width)
                .frame(height: KeyMetrics.keyHeight)
                .background(
                    RoundedRectangle(cornerRadius: KeyMetrics.keyCornerRadius)
                        .fill(Color(.systemGray3))
                )
        }
    }
}

/// Adaptive accent key — sits between N and delete on AZERTY row 3.
/// Shows apostrophe by default; after typing a vowel, shows the most common accent
/// for that vowel. Long-press on an accent shows all variants via AccentPopup.
///
/// WHY this key exists:
/// On the native French AZERTY keyboard, there's no dedicated accent key — users
/// access accents via long-press on vowel keys. But the apostrophe is the most
/// common non-letter character in French (l', d', n', j', c', s'...). Having it
/// one tap away on the letters layer eliminates a 3-tap layer switch. The adaptive
/// behavior adds contextual accent insertion without losing the apostrophe default.
///
/// GESTURE PATTERN: Same DragGesture + 400ms Task.sleep as KeyButton.
/// See KeyButton.swift for detailed rationale on why DragGesture handles both tap
/// and long-press instead of using LongPressGesture.
struct AdaptiveAccentKey: View {
    let width: CGFloat
    let isShifted: Bool
    let lastTypedChar: String?
    let onTap: (String) -> Void

    // MARK: - Long-press state (same pattern as KeyButton)

    @State private var isPressed = false
    @State private var showingAccents = false
    @State private var accentOptions: [String] = []
    @State private var selectedAccentIndex: Int? = nil
    @State private var longPressTimer: Task<Void, Never>? = nil
    @State private var dragStartX: CGFloat? = nil

    private let accentCellWidth: CGFloat = 36
    private let keyFontSize: CGFloat = 22

    /// The character the key should display right now.
    private var displayChar: String {
        let base = AccentedCharacters.adaptiveKeyLabel(afterTyping: lastTypedChar)
        return isShifted ? base.uppercased() : base
    }

    var body: some View {
        Text(displayChar)
            .font(.system(size: keyFontSize, weight: .regular))
            .foregroundStyle(.primary)
            .frame(width: width)
            .frame(height: KeyMetrics.keyHeight)
            .background(
                RoundedRectangle(cornerRadius: KeyMetrics.keyCornerRadius)
                    .fill(KeyMetrics.letterKeyColor)
                    .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 1)
            )
            .overlay(
                // Accent popup on long-press (only when showing an accent, not apostrophe)
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
                            isPressed = true
                            dragStartX = value.location.x
                            startLongPressTimer()
                        }
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
                                HapticFeedback.keyTapped()
                            }
                            showingAccents = false
                            accentOptions = []
                            selectedAccentIndex = nil
                        } else {
                            // Normal tap: insert the displayed character
                            onTap(displayChar)
                            HapticFeedback.keyTapped()
                        }
                        dragStartX = nil
                    }
            )
    }

    // MARK: - Long-press helpers

    private func startLongPressTimer() {
        longPressTimer?.cancel()
        longPressTimer = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }

            // Only show accent popup if the adaptive key is showing an accent (not apostrophe).
            // Look up the vowel that triggered the current accent display.
            if let vowel = AccentedCharacters.adaptiveKeyVowel(afterTyping: lastTypedChar),
               let accents = AccentedCharacters.accents(for: vowel), !accents.isEmpty {
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

    private func updateSelectedAccent(dragLocation: CGPoint) {
        guard !accentOptions.isEmpty else { return }
        let totalPopupWidth = CGFloat(accentOptions.count) * accentCellWidth
        let popupStartX = (dragStartX ?? 0) - totalPopupWidth / 2
        let relativeX = dragLocation.x - popupStartX
        let index = Int(relativeX / accentCellWidth)
        if index >= 0 && index < accentOptions.count {
            selectedAccentIndex = index
        } else {
            selectedAccentIndex = nil
        }
    }
}

/// Layer switch key (123 / ABC).
struct LayerSwitchKey: View {
    let label: String
    let width: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .frame(width: width)
                .frame(height: KeyMetrics.keyHeight)
                .background(
                    RoundedRectangle(cornerRadius: KeyMetrics.keyCornerRadius)
                        .fill(Color(.systemGray3))
                )
        }
        .foregroundColor(Color(.label))
    }
}
