// DictusKeyboard/Views/UIKit/DictusKeyCell.swift
// UICollectionViewCell for keyboard keys — purely visual, no touch handling.
import UIKit

/// A UICollectionViewCell that renders a single keyboard key.
///
/// WHY a single cell class for all key types:
/// Unlike the old architecture (LetterKeyButton + 8 BaseSpecialKeyButton subclasses),
/// a single cell class configured by KeyType keeps the code simple and avoids duplicating
/// visual styling across subclasses. All touch handling lives in KeyboardCollectionView.
///
/// WHY margins INSIDE the cell:
/// The UICollectionView uses minimumInteritemSpacing=0 and minimumLineSpacing=0, so cells
/// tile perfectly with zero gaps. The visible spacing between keys comes from insets on the
/// inner keyBackground view. This guarantees zero dead zones — every pixel of the keyboard
/// surface belongs to a cell, so touches always resolve to a key.
class DictusKeyCell: UICollectionViewCell {

    // MARK: - Subviews

    /// Inner view for the visible key appearance (background color, corner radius, shadow).
    /// Inset from cell bounds to create visual gaps while the cell's touch area fills 100%.
    let keyBackground = UIView()

    /// Text label for letters, numbers, symbols, and text-based special keys.
    let label = UILabel()

    /// Image view for SF Symbol icons (shift, delete, globe, emoji, return).
    let iconView = UIImageView()

    // MARK: - State

    /// The key definition this cell is currently displaying.
    private(set) var keyDef: KeyDefinition?

    /// Whether the return key uses the blue "action" style (go, search, send).
    private(set) var isActionReturn = false

    // MARK: - Dynamic colors

    /// Normal background for letter/input keys: dark=22% white, light=white.
    private static let letterNormal = UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 0.22, alpha: 1) : .white
    }

    /// Normal background for special keys: dark=15% white, light=68% white.
    /// Matches Apple's native keyboard modifier key styling.
    private static let specialNormal = UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 0.15, alpha: 1) : UIColor(white: 0.68, alpha: 1)
    }

    /// Pressed background: dark=32% white, light=88% white.
    static let pressedBackground = UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 0.32, alpha: 1) : UIColor(white: 0.88, alpha: 1)
    }

    /// Blue background for action return keys (Go, Search, Send).
    private static let actionBackground = UIColor.systemBlue

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        // Cell background is clear — the keyBackground provides visuals
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        // Key background with rounded corners and shadow
        keyBackground.layer.cornerRadius = KeyMetrics.keyCornerRadius
        keyBackground.layer.shadowColor = UIColor.black.cgColor
        keyBackground.layer.shadowOpacity = 0.15
        keyBackground.layer.shadowOffset = CGSize(width: 0, height: 1)
        keyBackground.layer.shadowRadius = 0
        keyBackground.clipsToBounds = false
        contentView.addSubview(keyBackground)

        // Text label (centered)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.isUserInteractionEnabled = false
        contentView.addSubview(label)

        // Icon view (centered, content mode)
        iconView.contentMode = .center
        iconView.tintColor = .label
        iconView.isUserInteractionEnabled = false
        contentView.addSubview(iconView)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        // keyBackground is inset from cell bounds = visual gap between keys
        let hInset = KeyMetrics.keySpacing / 2
        let vInset = KeyMetrics.rowSpacing / 2
        keyBackground.frame = contentView.bounds.insetBy(dx: hInset, dy: vInset)

        // Label and icon fill the keyBackground frame
        label.frame = keyBackground.frame
        iconView.frame = keyBackground.frame
    }

    // MARK: - Configuration

    /// Configure the cell to display a key definition.
    func configure(with key: KeyDefinition, shifted: Bool, shiftState: ShiftState = .off) {
        self.keyDef = key

        // Reset visibility
        label.isHidden = true
        iconView.isHidden = true
        iconView.image = nil
        label.text = nil
        isActionReturn = false

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)

        switch key.type {
        case .character:
            label.isHidden = false
            label.text = shifted ? key.label.uppercased() : key.label.lowercased()
            label.font = .systemFont(ofSize: 22)
            label.textColor = .label
            keyBackground.backgroundColor = Self.letterNormal

        case .accentAdaptive:
            label.isHidden = false
            label.text = key.label  // Dynamic label set by updateAccentState
            label.font = .systemFont(ofSize: 22)
            label.textColor = .label
            keyBackground.backgroundColor = Self.letterNormal

        case .shift:
            iconView.isHidden = false
            let iconName: String
            switch shiftState {
            case .off: iconName = "shift"
            case .shifted: iconName = "shift.fill"
            case .capsLocked: iconName = "capslock.fill"
            }
            iconView.image = UIImage(systemName: iconName, withConfiguration: symbolConfig)
            keyBackground.backgroundColor = Self.specialNormal

        case .delete:
            iconView.isHidden = false
            iconView.image = UIImage(systemName: "delete.backward", withConfiguration: symbolConfig)
            keyBackground.backgroundColor = Self.specialNormal

        case .space:
            label.isHidden = false
            label.text = "espace"
            label.font = .systemFont(ofSize: 15)
            label.textColor = .label
            keyBackground.backgroundColor = Self.letterNormal

        case .returnKey:
            // Default return icon — updateReturnKeyType will override if needed
            iconView.isHidden = false
            iconView.image = UIImage(systemName: "return.left", withConfiguration: symbolConfig)
            keyBackground.backgroundColor = Self.specialNormal

        case .globe:
            iconView.isHidden = false
            iconView.image = UIImage(systemName: "globe", withConfiguration: symbolConfig)
            keyBackground.backgroundColor = Self.specialNormal

        case .emoji:
            iconView.isHidden = false
            let emojiConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            iconView.image = UIImage(systemName: "face.smiling", withConfiguration: emojiConfig)
            keyBackground.backgroundColor = Self.specialNormal

        case .layerSwitch, .symbolToggle:
            label.isHidden = false
            label.text = key.label
            label.font = .systemFont(ofSize: 15, weight: .medium)
            label.textColor = .label
            keyBackground.backgroundColor = Self.specialNormal

        case .mic:
            // Mic is in the toolbar, not in the keyboard grid
            break
        }
    }

    // MARK: - Visual state

    /// Show pressed highlight.
    func setPressed(_ pressed: Bool) {
        if pressed {
            if isActionReturn {
                keyBackground.backgroundColor = Self.actionBackground.withAlphaComponent(0.7)
            } else {
                keyBackground.backgroundColor = Self.pressedBackground
            }
        } else {
            restoreNormalBackground()
        }
    }

    /// Restore normal background based on key type.
    private func restoreNormalBackground() {
        guard let key = keyDef else { return }
        switch key.type {
        case .character, .space, .accentAdaptive:
            keyBackground.backgroundColor = Self.letterNormal
        case .returnKey where isActionReturn:
            keyBackground.backgroundColor = Self.actionBackground
        default:
            keyBackground.backgroundColor = Self.specialNormal
        }
    }

    // MARK: - Shift update

    /// Update shift display without full reconfiguration.
    func updateShift(_ shifted: Bool) {
        guard let key = keyDef, key.type == .character else { return }
        label.text = shifted ? key.label.uppercased() : key.label.lowercased()
    }

    /// Update shift icon.
    func updateShiftIcon(_ state: ShiftState) {
        guard let key = keyDef, key.type == .shift else { return }
        let iconName: String
        switch state {
        case .off: iconName = "shift"
        case .shifted: iconName = "shift.fill"
        case .capsLocked: iconName = "capslock.fill"
        }
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        iconView.image = UIImage(systemName: iconName, withConfiguration: config)
    }

    // MARK: - Return key type

    /// Update the return key label/icon based on the host text field's returnKeyType.
    func updateReturnKeyType(_ type: UIReturnKeyType) {
        guard let key = keyDef, key.type == .returnKey else { return }

        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)

        // Determine if this is an "action" type that gets blue styling
        let wantsAction: Bool
        switch type {
        case .go, .search, .send:
            wantsAction = true
        default:
            wantsAction = false
        }

        // Reset
        label.isHidden = true
        iconView.isHidden = false

        switch type {
        case .go:
            let arrowConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
            iconView.image = UIImage(systemName: "arrow.right", withConfiguration: arrowConfig)
        case .search:
            iconView.image = UIImage(systemName: "magnifyingglass", withConfiguration: config)
        case .send:
            iconView.isHidden = true
            label.isHidden = false
            label.text = "Send"
            label.font = .systemFont(ofSize: 15, weight: .medium)
        case .done:
            iconView.isHidden = true
            label.isHidden = false
            label.text = "OK"
            label.font = .systemFont(ofSize: 15, weight: .medium)
        case .join:
            iconView.isHidden = true
            label.isHidden = false
            label.text = "Join"
            label.font = .systemFont(ofSize: 15, weight: .medium)
        case .route:
            iconView.isHidden = true
            label.isHidden = false
            label.text = "Route"
            label.font = .systemFont(ofSize: 15, weight: .medium)
        case .continue:
            iconView.isHidden = true
            label.isHidden = false
            label.text = "Suite"
            label.font = .systemFont(ofSize: 15, weight: .medium)
        case .emergencyCall:
            iconView.isHidden = true
            label.isHidden = false
            label.text = "SOS"
            label.font = .systemFont(ofSize: 15, weight: .medium)
        default:
            iconView.image = UIImage(systemName: "return.left", withConfiguration: config)
        }

        // Apply action style
        isActionReturn = wantsAction
        if wantsAction {
            keyBackground.backgroundColor = Self.actionBackground
            iconView.tintColor = .white
            label.textColor = .white
        } else {
            keyBackground.backgroundColor = Self.specialNormal
            iconView.tintColor = .label
            label.textColor = .label
        }
    }

    // MARK: - Accent adaptive update

    /// Update the adaptive accent key label.
    func updateAccentLabel(_ text: String) {
        guard let key = keyDef, key.type == .accentAdaptive else { return }
        label.text = text
    }

    // MARK: - Reuse

    override func prepareForReuse() {
        super.prepareForReuse()
        keyDef = nil
        label.isHidden = true
        iconView.isHidden = true
        iconView.image = nil
        label.text = nil
        isActionReturn = false
        iconView.tintColor = .label
        label.textColor = .label
    }
}
