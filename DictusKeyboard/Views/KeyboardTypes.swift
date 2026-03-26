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

/// Custom shape for the key popup: rounded bubble with a tapered stem pointing down.
///
/// WHY a custom shape instead of plain RoundedRectangle:
/// Apple's native keyboard popup has a stem connecting the bubble to the pressed key.
/// This gives the user a clear visual link between the magnified letter and the key.
/// Popup shape with wide-base stem connecting seamlessly to the key below.
/// The stem is an inverted trapezoid: narrow at top (bubble width), wide at bottom (key width).
struct KeyPopupShape: Shape {
    var cornerRadius: CGFloat = 6
    var stemBaseWidth: CGFloat = 38
    var stemHeight: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        let bubbleRect = CGRect(x: rect.minX, y: rect.minY,
                                width: rect.width, height: rect.height - stemHeight)

        var path = Path()

        // Rounded rectangle bubble
        path.addRoundedRect(in: bubbleRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))

        // Wide-base stem: inverted trapezoid connecting bubble to key
        let midX = rect.midX
        let stemTop = bubbleRect.maxY
        let stemBottom = rect.maxY
        let bubbleHalfWidth = min(rect.width / 2, stemBaseWidth / 2 + 4)
        let baseHalfWidth = stemBaseWidth / 2

        path.move(to: CGPoint(x: midX - bubbleHalfWidth, y: stemTop))
        path.addLine(to: CGPoint(x: midX - baseHalfWidth, y: stemBottom))
        path.addLine(to: CGPoint(x: midX + baseHalfWidth, y: stemBottom))
        path.addLine(to: CGPoint(x: midX + bubbleHalfWidth, y: stemTop))
        path.closeSubpath()

        return path
    }
}

/// The popup preview bubble shown above a pressed key with a wide connected stem.
struct KeyPopup: View {
    let label: String

    /// Larger font than key (34pt vs 22pt) for clear popup visibility.
    private let popupFontSize: CGFloat = 34

    /// Bubble height (text area) and stem height.
    private let bubbleHeight: CGFloat = 42
    private let stemHeight: CGFloat = 8

    var body: some View {
        ZStack(alignment: .top) {
            // Background shape: bubble + wide-base stem
            KeyPopupShape(stemBaseWidth: 38, stemHeight: stemHeight)
                .fill(KeyMetrics.letterKeyColor)
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)

            // Text sits in the bubble area only -- larger and lighter than key font
            Text(label)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.primary)
                .frame(width: 44, height: bubbleHeight)
        }
        .frame(width: 44, height: bubbleHeight + stemHeight)
    }
}
