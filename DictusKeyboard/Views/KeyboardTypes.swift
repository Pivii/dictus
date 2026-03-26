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
/// Popup shape: one continuous rounded shape that flows from the wider bubble
/// down to the key width, matching Apple's native keyboard popup style.
///
/// The shape is drawn as a single path: rounded top corners, straight sides,
/// then smooth quad-curve transition narrowing to the key width at the bottom.
struct KeyPopupShape: Shape {
    /// Width of the bubble (wider than the key).
    var bubbleWidth: CGFloat = 52
    /// Width at the bottom where the shape meets the key.
    var stemBaseWidth: CGFloat = 38
    /// Height of the transition zone between bubble and key.
    var stemHeight: CGFloat = 10
    /// Corner radius for the top corners of the bubble.
    var cornerRadius: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        let midX = rect.midX
        let bubbleBottom = rect.height - stemHeight
        let bubbleHW = bubbleWidth / 2
        let baseHW = stemBaseWidth / 2
        let cr = cornerRadius

        var path = Path()

        // Start at top-left, after the corner radius
        path.move(to: CGPoint(x: midX - bubbleHW + cr, y: 0))

        // Top edge
        path.addLine(to: CGPoint(x: midX + bubbleHW - cr, y: 0))

        // Top-right corner
        path.addQuadCurve(
            to: CGPoint(x: midX + bubbleHW, y: cr),
            control: CGPoint(x: midX + bubbleHW, y: 0)
        )

        // Right edge of bubble
        path.addLine(to: CGPoint(x: midX + bubbleHW, y: bubbleBottom))

        // Right transition curve: bubble width → key width
        path.addQuadCurve(
            to: CGPoint(x: midX + baseHW, y: rect.height),
            control: CGPoint(x: midX + bubbleHW, y: rect.height)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: midX - baseHW, y: rect.height))

        // Left transition curve: key width → bubble width
        path.addQuadCurve(
            to: CGPoint(x: midX - bubbleHW, y: bubbleBottom),
            control: CGPoint(x: midX - bubbleHW, y: rect.height)
        )

        // Left edge of bubble
        path.addLine(to: CGPoint(x: midX - bubbleHW, y: cr))

        // Top-left corner
        path.addQuadCurve(
            to: CGPoint(x: midX - bubbleHW + cr, y: 0),
            control: CGPoint(x: midX - bubbleHW, y: 0)
        )

        path.closeSubpath()
        return path
    }
}

/// The popup preview shown above a pressed key — wider bubble flowing into key.
struct KeyPopup: View {
    let label: String

    /// Bubble height (letter area) + stem transition height.
    private let bubbleHeight: CGFloat = 42
    private let stemHeight: CGFloat = 10
    private let totalWidth: CGFloat = 52

    var body: some View {
        ZStack(alignment: .top) {
            // One continuous shape: bubble flowing into key
            KeyPopupShape(bubbleWidth: totalWidth, stemBaseWidth: 38, stemHeight: stemHeight)
                .fill(KeyMetrics.letterKeyColor)
                .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)

            // Letter — larger and lighter than key font
            Text(label)
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: totalWidth, height: bubbleHeight)
        }
        .frame(width: totalWidth, height: bubbleHeight + stemHeight)
    }
}
