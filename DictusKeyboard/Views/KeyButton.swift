// DictusKeyboard/Views/KeyButton.swift
import SwiftUI
import AudioToolbox
import DictusCore

/// A standard keyboard key that inserts a character on tap.
/// Shows a popup preview above the key during the press gesture.
/// Long-pressing a key with accented variants (e.g., "e" on AZERTY) shows an AccentPopup
/// where the user can slide their finger to select an accented character.
///
/// WHY DragGesture instead of UIViewRepresentable:
/// UIViewRepresentable overlays don't reliably receive touches at HStack edge positions
/// due to SwiftUI's frame-boundary clipping. DragGesture(minimumDistance: 0) works at
/// all positions and provides touchDown haptic via .onChanged. The ~5-10ms latency
/// difference is imperceptible during normal typing.
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
    /// The initial X position when touch started, used to calculate which accent
    /// the finger is hovering over relative to the key's center.
    @State private var touchStartX: CGFloat = 0
    /// Task for 400ms long-press timer (accent popup).
    @State private var longPressTimer: Task<Void, Never>?
    /// Whether long-press has fired (accent mode active).
    @State private var longPressFired = false

    private var displayLabel: String {
        isShifted ? key.label.uppercased() : key.label.lowercased()
    }

    private var outputChar: String {
        guard let output = key.output else { return "" }
        return isShifted ? output.uppercased() : output
    }

    /// Cell width matching AccentPopup's cellWidth for hit-testing calculations.
    private let accentCellWidth: CGFloat = 36

    /// Fixed font size for key labels — matches native iOS keyboard behavior.
    /// WHY not @ScaledMetric: Native iOS keyboard does NOT scale key labels with
    /// Dynamic Type. Scaling causes layout overflow on larger text sizes.
    private let keyFontSize: CGFloat = 22

    var body: some View {
        Text(displayLabel)
            .font(.system(size: keyFontSize, weight: .regular))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .background(
                keyBackground
                    .padding(.horizontal, KeyMetrics.keySpacing / 2)
                    .padding(.vertical, KeyMetrics.rowSpacing / 2)
            )
            // Popup preview shown above key on press (hidden when accents are showing)
            .overlay(
                Group {
                    if isPressed && !showingAccents {
                        KeyPopup(label: displayLabel)
                            .offset(y: -(KeyMetrics.keyHeight + 8))
                    }
                },
                alignment: .top
            )
            // Accent popup on long-press
            .overlay(
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
            // Extend hit area to entire frame (including gap padding).
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isPressed {
                            handleTouchDown(position: value.location)
                        }
                        if showingAccents {
                            updateSelectedAccent(viewPosition: value.location)
                        }
                    }
                    .onEnded { _ in
                        handleTouchUp()
                    }
            )
    }

    // MARK: - Key Background

    /// Key background: glass on iOS 26, material fallback on older versions.
    @ViewBuilder
    private var keyBackground: some View {
        RoundedRectangle(cornerRadius: KeyMetrics.keyCornerRadius)
            .fill(KeyMetrics.letterKeyColor)
            .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 1)
            .dictusGlass(in: RoundedRectangle(cornerRadius: KeyMetrics.keyCornerRadius))
    }

    // MARK: - Touch handlers

    /// touchDown: visual highlight -> audio -> haptic -> prepare for next -> start long-press timer
    /// Per locked decision: audio AND haptic fire on touchDown (not touchUp)
    private func handleTouchDown(position: CGPoint) {
        let touchDownState = KeyTapSignposter.beginTouchDown()

        // 1. Visual highlight
        isPressed = true
        longPressFired = false
        KeyTapSignposter.emitHighlight(touchDownState)

        // 2. Audio on touchDown
        AudioServicesPlaySystemSound(KeySound.letter)

        // 3. Haptic on touchDown
        HapticFeedback.keyTapped()
        KeyTapSignposter.emitHaptic(touchDownState)

        // 4. Prepare Taptic Engine for NEXT tap
        HapticFeedback.prepareForNextTap()

        KeyTapSignposter.endTouchDown(touchDownState)

        // 5. Record initial touch position for accent popup position calculation
        touchStartX = position.x

        // 6. Start 400ms long-press timer for accent popup
        longPressTimer?.cancel()
        longPressTimer = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            longPressFired = true
            handleLongPress()
        }
    }

    /// touchUp: insert character or selected accent
    private func handleTouchUp() {
        let touchUpState = KeyTapSignposter.beginTouchUp()

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
            // Normal tap: insert character
            onTap(outputChar)
        }

        longPressFired = false
        KeyTapSignposter.endTouchUp(touchUpState)
    }

    /// Long-press fired: show accent popup if key has accented variants
    ///
    /// WHY 400ms: iOS system keyboard uses ~350-500ms for long-press detection.
    /// 400ms balances responsiveness with avoiding false triggers during fast typing.
    private func handleLongPress() {
        if let accents = AccentedCharacters.accents(for: key.label.lowercased()), !accents.isEmpty {
            if isShifted {
                accentOptions = accents.map { $0.uppercased() }
            } else {
                accentOptions = accents
            }
            showingAccents = true
            selectedAccentIndex = nil
        }
    }

    // MARK: - Accent selection

    /// Maps touch position to accent popup cell index.
    private func updateSelectedAccent(viewPosition: CGPoint) {
        guard !accentOptions.isEmpty else { return }

        let totalPopupWidth = CGFloat(accentOptions.count) * accentCellWidth
        let popupStartX = touchStartX - totalPopupWidth / 2

        let relativeX = viewPosition.x - popupStartX
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

    /// Fixed popup font size — same rationale as key labels.
    private let popupFontSize: CGFloat = 32

    var body: some View {
        Text(label)
            .font(.system(size: popupFontSize, weight: .regular))
            .foregroundStyle(.primary)
            .frame(width: 50, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(KeyMetrics.letterKeyColor)
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
            )
    }
}

/// Device class for adaptive keyboard layout.
///
/// Breakpoints based on UIScreen.main.bounds.height:
/// - compact: <= 667pt (iPhone SE 3rd gen = 667pt)
/// - standard: <= 852pt (iPhone 14/15/16 = 844-852pt)
/// - large: > 852pt (iPhone Plus/Max = 926-932pt)
enum DeviceClass {
    case compact    // iPhone SE
    case standard   // iPhone 14/15/16
    case large      // iPhone Plus/Max

    static let current: DeviceClass = {
        let h = UIScreen.main.bounds.height
        if h <= 667 { return .compact }
        else if h <= 852 { return .standard }
        else { return .large }
    }()
}

/// Shared key dimension constants, computed once per device class.
enum KeyMetrics {
    /// Key height per device class (visual key height).
    static let keyHeight: CGFloat = {
        switch DeviceClass.current {
        case .compact:  return 40
        case .standard: return 43
        case .large:    return 46
        }
    }()

    /// Vertical spacing between rows (used as visual gap via background inset).
    static let rowSpacing: CGFloat = {
        switch DeviceClass.current {
        case .compact:  return 9
        case .standard: return 11
        case .large:    return 12
        }
    }()

    /// Horizontal spacing between keys (used as visual gap via background inset).
    static let keySpacing: CGFloat = {
        switch DeviceClass.current {
        case .compact:  return 5
        case .standard: return 6
        case .large:    return 6
        }
    }()

    /// Horizontal padding on each side of a row.
    /// Creates visual side margins matching Apple keyboard proportions (~equal to keySpacing).
    static let rowSidePadding: CGFloat = {
        switch DeviceClass.current {
        case .compact:  return 3
        case .standard: return 4
        case .large:    return 5
        }
    }()

    /// Corner radius for key backgrounds.
    /// Apple keyboard uses ~6pt on standard devices for a softer, more rounded look.
    static let keyCornerRadius: CGFloat = 8

    /// Letter key background color.
    static let letterKeyColor = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 0.22, alpha: 1)
            : .white
    })

    /// Pressed key background color for special keys.
    static let pressedKeyColor = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 0.32, alpha: 1)
            : UIColor(white: 0.88, alpha: 1)
    })
}
