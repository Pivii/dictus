// DictusKeyboard/Views/KeyboardTypes.swift
// Shared keyboard types used by both UIKit and SwiftUI layers.
import SwiftUI
import AudioToolbox

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

/// Shift state: off, shifted (single character), or caps locked.
enum ShiftState {
    case off
    case shifted
    case capsLocked
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

// Key popup and accent popup are now UIKit views in KeyPopupLayer.swift.
