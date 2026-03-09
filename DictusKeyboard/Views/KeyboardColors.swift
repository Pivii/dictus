// DictusKeyboard/Views/KeyboardColors.swift
// Apple-standard adaptive colors for keyboard keys (light/dark mode).
// Also contains KeySound and KeyMetrics (previously in KeyboardView.swift / KeyButton.swift).
import UIKit
import AudioToolbox
import SwiftUI

// MARK: - Key sounds

/// System sound IDs matching Apple's 3-category keyboard click sounds.
enum KeySound {
    static let letter: SystemSoundID = 1104
    static let delete: SystemSoundID = 1155
    static let modifier: SystemSoundID = 1156
}

// MARK: - Shift state

enum ShiftState {
    case off
    case shifted
    case capsLocked
}

// MARK: - Key metrics (SwiftUI-compatible, used by EmojiPickerView)

/// Shared key dimension constants used by both UIKit and SwiftUI views.
enum KeyMetrics {
    static var keyHeight: CGFloat { KeyboardColors.keyHeight }
    static let rowSpacing: CGFloat = 6
    static let keySpacing: CGFloat = 4
    static let rowHorizontalPadding: CGFloat = 3
    static let keyCornerRadius: CGFloat = 5

    /// Letter key background — SwiftUI Color wrapper for backward compatibility.
    static let letterKeyColor = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 0.22, alpha: 1)
            : .white
    })
}

/// Adaptive color constants matching Apple's native iOS keyboard.
///
/// WHY two categories (input vs action):
/// Apple's keyboard uses two distinct key colors: white (light) / dark gray (dark)
/// for input keys (letters, space in light mode), and medium gray / darker gray
/// for action keys (shift, delete, return, 123, emoji, globe).
/// Space bar is white in light mode but matches action keys in dark mode.
enum KeyboardColors {

    // MARK: - Key backgrounds

    /// Input key background (letters).
    /// Light: white. Dark: gray (#4A4A4C).
    static let inputKeyBackground = UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.29, green: 0.29, blue: 0.30, alpha: 1) // #4A4A4C
            : .white
    }

    /// Action key background (shift, delete, return, 123, emoji, globe).
    /// Light: medium gray (#ADB0B8). Dark: darker gray (#3A3A3C).
    static let actionKeyBackground = UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.23, green: 0.23, blue: 0.24, alpha: 1) // #3A3A3C
            : UIColor(red: 0.68, green: 0.69, blue: 0.72, alpha: 1) // #ADB0B8
    }

    /// Space bar background.
    /// Light: same as input keys (white). Dark: same as action keys.
    static let spaceKeyBackground = UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.23, green: 0.23, blue: 0.24, alpha: 1) // #3A3A3C
            : .white
    }

    // MARK: - Text colors

    /// Key label color. Light: black. Dark: white.
    static let keyLabel = UIColor.label

    // MARK: - Shadows

    /// Shadow color for all keys: very subtle, 1pt y-offset.
    static let keyShadowColor = UIColor.black.withAlphaComponent(0.15)
    static let keyShadowOffset = CGSize(width: 0, height: 1)
    static let keyShadowRadius: CGFloat = 0

    // MARK: - Key metrics (duplicated from KeyMetrics for UIKit access)

    static let keyCornerRadius: CGFloat = 5

    /// Device-adaptive key height: 42pt (SE/compact), 46pt (standard), 50pt (Plus/Max).
    static var keyHeight: CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        if screenHeight <= 667 { return 42 }
        else if screenHeight <= 852 { return 46 }
        else { return 50 }
    }
    static let rowSpacing: CGFloat = 6
    static let keySpacing: CGFloat = 4
    static let rowHorizontalPadding: CGFloat = 3

    // MARK: - Popup & accent colors

    /// Popup background matches input key background.
    static let popupBackground = inputKeyBackground

    /// Accent popup selected cell background.
    static let accentSelectedBackground = UIColor.systemBlue

    /// Trackpad overlay color.
    static let trackpadOverlay = UIColor.systemBackground.withAlphaComponent(0.6)
}
