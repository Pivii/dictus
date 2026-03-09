// DictusKeyboard/Views/SpecialKeyButton.swift
import SwiftUI
import AudioToolbox
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
            AudioServicesPlaySystemSound(KeySound.modifier)
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
                        .fill(KeyMetrics.letterKeyColor)
                        .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 1)
                )
                .foregroundColor(shiftState != .off ? .white : Color(.label))
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

/// Delete key with repeat-on-hold behavior and word-level acceleration.
/// Uses Task + Task.sleep instead of Timer.scheduledTimer, which is
/// unreliable in keyboard extensions (RunLoop may not be active).
/// Includes ~400ms initial delay before repeat begins (native iOS feel).
///
/// ACCELERATION PATTERN (matches Apple):
/// - First 10 deletions: character-by-character at 100ms intervals
/// - After 10 deletions: word-by-word at 120ms intervals (slightly slower
///   to give visual feedback of larger jumps)
/// - Counter resets on finger lift
struct DeleteKey: View {
    let width: CGFloat
    let onDelete: () -> Void
    let onWordDelete: () -> Void

    @State private var isHolding = false
    @State private var repeatTask: Task<Void, Never>?
    @State private var deleteCount: Int = 0

    /// Number of character deletions before switching to word-level mode
    private let wordModeThreshold = 10

    var body: some View {
        Image(systemName: "delete.backward")
            .font(.system(size: 16, weight: .medium))
            .frame(width: width)
            .frame(height: KeyMetrics.keyHeight)
            .background(
                RoundedRectangle(cornerRadius: KeyMetrics.keyCornerRadius)
                    .fill(KeyMetrics.letterKeyColor)
                    .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 1)
            )
            .foregroundColor(Color(.label))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isHolding {
                            isHolding = true
                            onDelete() // Immediate first delete
                            HapticFeedback.keyTapped()
                            AudioServicesPlaySystemSound(KeySound.delete)
                            deleteCount = 1
                            repeatTask = Task { @MainActor in
                                // Initial delay before repeat begins (~400ms,
                                // matching native iOS delete key behavior)
                                try? await Task.sleep(nanoseconds: 400_000_000)
                                // Repeat while held, accelerating after threshold
                                while !Task.isCancelled {
                                    if deleteCount >= wordModeThreshold {
                                        // Word-level deletion: delete back to previous word boundary
                                        onWordDelete()
                                        HapticFeedback.keyTapped()
                                        AudioServicesPlaySystemSound(KeySound.delete)
                                        try? await Task.sleep(nanoseconds: 120_000_000)
                                    } else {
                                        onDelete()
                                        HapticFeedback.keyTapped()
                                        AudioServicesPlaySystemSound(KeySound.delete)
                                        try? await Task.sleep(nanoseconds: 100_000_000)
                                    }
                                    deleteCount += 1
                                }
                            }
                        }
                    }
                    .onEnded { _ in
                        isHolding = false
                        repeatTask?.cancel()
                        repeatTask = nil
                        deleteCount = 0
                    }
            )
    }
}

/// Space bar key with trackpad mode.
///
/// Short tap inserts a space. Long-pressing for 400ms activates trackpad mode:
/// dragging moves the cursor through text via `onCursorMove`. A greyed-out overlay
/// is managed by the parent through `onTrackpadStateChange`.
///
/// WHY DragGesture instead of LongPressGesture + DragGesture combo:
/// Same reason as DeleteKey — LongPressGesture is unreliable in keyboard extensions.
/// DragGesture(minimumDistance: 0) fires immediately on touch, then a Task.sleep
/// handles the 400ms threshold for trackpad activation.
///
/// HAPTIC PATTERN:
/// - Initial touch: light impact (keyTapped)
/// - Mode activation at 400ms: medium impact (trackpadActivated)
/// - During drag: selection tick per character moved (cursorMoved) — #1 fluidity factor
///
/// TRACKPAD TUNING (see Issue #5):
/// - Dead zone: 8pt radius after activation to absorb jitter
/// - Sensitivity: 12 pt/char base (Apple uses ~12-15pt)
/// - Acceleration: cosine interpolation from 1.0x (slow) to 2.5x (fast) — no abrupt steps
/// - Vertical drag: mapped to character offsets (crosses line boundaries → moves up/down)
/// - Rate limit: 16ms (60fps cap) to avoid overloading the text API
struct SpaceKey: View {
    let width: CGFloat
    let onTap: () -> Void
    let onCursorMove: (Int) -> Void              // character offset for cursor movement
    let onTrackpadStateChange: (Bool) -> Void     // notify parent of trackpad mode for overlay

    @State private var isPressed = false
    @State private var isTrackpadMode = false
    @State private var longPressTask: Task<Void, Never>?
    @State private var lastDragLocation: CGPoint = .zero
    @State private var accumulatedOffsetX: CGFloat = 0
    @State private var accumulatedOffsetY: CGFloat = 0

    // Dead zone: activation point and whether the finger has left the dead zone
    @State private var activationLocation: CGPoint = .zero
    @State private var hasExitedDeadZone = false

    // Rate limiting: timestamp of the last cursor move
    @State private var lastMoveTime: CFTimeInterval = 0

    // --- Tuning constants ---

    /// Base sensitivity: points of drag per character at slow speed.
    /// Apple's native trackpad uses ~12-15pt. 12pt feels precise without being twitchy.
    private let basePtsPerChar: CGFloat = 12.0

    /// Dead zone radius in points (~1mm on retina). Absorbs micro-jitter right after
    /// long-press activation so the cursor doesn't jump on release of the press.
    private let deadZoneRadius: CGFloat = 8.0

    /// Minimum interval between cursor moves (seconds). 1/60s = 60fps cap.
    /// Prevents overloading adjustTextPosition which can stutter at very high call rates.
    private let minMoveInterval: CFTimeInterval = 0.016

    // Acceleration curve boundaries (in points/second)
    private let slowVelocity: CGFloat = 100    // below this → base sensitivity (precise)
    private let fastVelocity: CGFloat = 400    // above this → max acceleration (fast)
    private let maxAccelMultiplier: CGFloat = 2.5

    var body: some View {
        Text("espace")
            .font(.system(size: 15))
            .foregroundColor(Color(.label))
            .frame(width: width)
            .frame(height: KeyMetrics.keyHeight)
            .background(
                RoundedRectangle(cornerRadius: KeyMetrics.keyCornerRadius)
                    .fill(KeyMetrics.letterKeyColor)
                    .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 1)
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isPressed {
                            // First touch
                            isPressed = true
                            lastDragLocation = value.location
                            HapticFeedback.keyTapped()
                            startTrackpadTimer()
                        }
                        if isTrackpadMode {
                            handleTrackpadDrag(currentLocation: value.location)
                        }
                    }
                    .onEnded { _ in
                        if !isTrackpadMode {
                            onTap()  // Normal space insertion
                        }
                        deactivateTrackpad()
                    }
            )
    }

    private func startTrackpadTimer() {
        longPressTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)  // 400ms
            guard !Task.isCancelled else { return }
            isTrackpadMode = true
            activationLocation = lastDragLocation
            hasExitedDeadZone = false
            lastMoveTime = CACurrentMediaTime()
            onTrackpadStateChange(true)
            HapticFeedback.trackpadActivated()
        }
    }

    private func handleTrackpadDrag(currentLocation: CGPoint) {
        // Dead zone: ignore movement until finger exits 8pt radius from activation point.
        // This prevents the cursor from jumping due to micro-jitter during the long-press.
        if !hasExitedDeadZone {
            let dx = currentLocation.x - activationLocation.x
            let dy = currentLocation.y - activationLocation.y
            let distance = sqrt(dx * dx + dy * dy)
            if distance < deadZoneRadius {
                return
            }
            // Exiting dead zone: reset drag origin to current point so the first
            // move doesn't include the dead zone distance as a big jump.
            hasExitedDeadZone = true
            lastDragLocation = currentLocation
            lastMoveTime = CACurrentMediaTime()
            return
        }

        // Rate limiting: skip if less than 16ms since last move (60fps cap)
        let now = CACurrentMediaTime()
        let elapsed = now - lastMoveTime
        let deltaX = currentLocation.x - lastDragLocation.x
        let deltaY = currentLocation.y - lastDragLocation.y

        if elapsed < minMoveInterval {
            accumulatedOffsetX += deltaX
            accumulatedOffsetY += deltaY
            lastDragLocation = currentLocation
            return
        }

        let totalDeltaX = accumulatedOffsetX + deltaX
        let totalDeltaY = accumulatedOffsetY + deltaY
        lastDragLocation = currentLocation

        // Velocity from 2D drag magnitude for acceleration curve
        let dragMagnitude = sqrt(totalDeltaX * totalDeltaX + totalDeltaY * totalDeltaY)
        let velocity = elapsed > 0 ? dragMagnitude / CGFloat(elapsed) : 0

        // Cosine interpolation for smooth acceleration:
        // Slow (<100 pt/s) → 1.0x, Fast (>400 pt/s) → 2.5x, smooth S-curve in between
        let multiplier: CGFloat
        if velocity <= slowVelocity {
            multiplier = 1.0
        } else if velocity >= fastVelocity {
            multiplier = maxAccelMultiplier
        } else {
            let t = (velocity - slowVelocity) / (fastVelocity - slowVelocity)
            let smooth = (1.0 - cos(t * .pi)) / 2.0
            multiplier = 1.0 + (maxAccelMultiplier - 1.0) * smooth
        }

        let effectivePtsPerChar = basePtsPerChar / multiplier

        // Process X and Y independently into character counts, then sum.
        // Both axes use the same sensitivity — adjustTextPosition(byCharacterOffset:)
        // traverses line boundaries, so forward/backward offset from Y drag
        // naturally moves the cursor across lines (down = forward, up = backward).
        let charsFromX = Int(totalDeltaX / effectivePtsPerChar)
        let charsFromY = Int(totalDeltaY / effectivePtsPerChar)
        let totalChars = charsFromX + charsFromY

        if totalChars != 0 {
            onCursorMove(totalChars)
            HapticFeedback.cursorMoved()
            // Keep fractional remainders for each axis independently
            accumulatedOffsetX = totalDeltaX - CGFloat(charsFromX) * effectivePtsPerChar
            accumulatedOffsetY = totalDeltaY - CGFloat(charsFromY) * effectivePtsPerChar
            lastMoveTime = now
        } else {
            accumulatedOffsetX = totalDeltaX
            accumulatedOffsetY = totalDeltaY
        }
    }

    private func deactivateTrackpad() {
        isPressed = false
        if isTrackpadMode {
            isTrackpadMode = false
            onTrackpadStateChange(false)
        }
        longPressTask?.cancel()
        longPressTask = nil
        accumulatedOffsetX = 0
        accumulatedOffsetY = 0
        hasExitedDeadZone = false
        lastMoveTime = 0
    }
}

/// Return key.
struct ReturnKey: View {
    let width: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "return.left")
                .font(.system(size: 16, weight: .medium))
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
                        .fill(KeyMetrics.letterKeyColor)
                        .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 1)
                )
        }
        .foregroundColor(Color(.label))
    }
}

/// Emoji key — shows a face.smiling icon matching Apple's native AZERTY visual style.
/// Tapping opens the built-in emoji picker (EmojiPickerView) within the keyboard extension.
/// The globe key (managed by iOS, separate from this button) handles switching between
/// installed keyboards.
struct EmojiKey: View {
    let width: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "face.smiling")
                .font(.system(size: 18, weight: .medium))
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
    /// The accent already has the correct case from adaptiveKeyLabel (which
    /// preserves the case of lastTypedChar). No need for isShifted re-casing.
    private var displayChar: String {
        AccentedCharacters.adaptiveKeyLabel(afterTyping: lastTypedChar)
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
                // Derive case from lastTypedChar (not isShifted, which auto-unshifts after typing)
                let isUppercase = lastTypedChar?.uppercased() == lastTypedChar && lastTypedChar?.lowercased() != lastTypedChar
                if isUppercase {
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
                        .fill(KeyMetrics.letterKeyColor)
                        .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 1)
                )
        }
        .foregroundColor(Color(.label))
    }
}
