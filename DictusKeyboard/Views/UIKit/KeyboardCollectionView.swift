// DictusKeyboard/Views/UIKit/KeyboardCollectionView.swift
// UICollectionView-based keyboard layout with integrated touch handling.
import UIKit
import AudioToolbox
import DictusCore

/// Action callbacks from key presses, wired from KeyboardRootView via the controller.
///
/// WHY a struct instead of individual closures on each button:
/// Consolidating all callbacks into a single struct makes it easy to pass through
/// the UIViewRepresentable boundary and ensures all actions are wired consistently.
struct KeyboardActions {
    var onCharacter: (String) -> Void = { _ in }
    /// Returns true if text was deleted, false if text field was empty.
    var onDelete: () -> Bool = { false }
    var onWordDelete: () -> Void = {}
    var onSpace: () -> Void = {}
    var onReturn: () -> Void = {}
    var onGlobe: () -> Void = {}
    var onEmoji: () -> Void = {}
    var onLayerSwitch: () -> Void = {}
    var onSymbolToggle: () -> Void = {}
    var onAccentAdaptive: (String) -> Void = { _ in }
    var onCursorMove: (Int) -> Void = { _ in }
    var onShiftChanged: (ShiftState) -> Void = { _ in }
    /// Returns the current returnKeyType from the text document proxy.
    var onReturnKeyType: (() -> UIReturnKeyType)? = { .default }
}

/// UIView that renders the keyboard using a UICollectionView and handles all touch routing.
///
/// WHY UICollectionView instead of UIStackView:
/// Inspired by giellakbd-ios (divvun). UICollectionView with minimumInteritemSpacing=0
/// guarantees that cells tile perfectly with ZERO gaps. Every pixel of the keyboard surface
/// belongs to a cell, eliminating dead zones. Visual margins between keys are created by
/// insets INSIDE each DictusKeyCell's keyBackground view.
///
/// WHY this class replaces BOTH KeyboardContainerView AND KeyboardTouchForwardingView:
/// With UICollectionView cells tiling 100%, touch handling via touchesBegan overrides on
/// this parent view + indexPathForItem(at:) replaces the old nearest-neighbor forwarding.
/// No separate forwarding layer needed.
class KeyboardCollectionView: UIView {

    // MARK: - Layout

    private let layout = UICollectionViewFlowLayout()
    private let collectionView: UICollectionView

    // MARK: - Data

    /// Current rows of key definitions (sections = rows, items = keys).
    private var rows: [[KeyDefinition]] = []

    /// Sum of widthMultipliers per row, cached for cell sizing.
    private var rowTotalWidths: [CGFloat] = []

    /// Action callbacks from KeyboardRootView.
    private var actions: KeyboardActions?

    /// Current shift state for rendering and character output.
    private var isShifted = false
    private var shiftState: ShiftState = .off

    /// Last typed character for adaptive accent key.
    private var lastTypedChar: String?

    // MARK: - Touch state

    /// The currently active (pressed) key's index path.
    private var activeIndexPath: IndexPath?

    /// Maps each UITouch to the index path it started on.
    /// Preserves gesture state: once a touch begins on a key, all subsequent
    /// move/end/cancel for that touch go to the SAME key.
    private var touchToIndexPath: [UITouch: IndexPath] = [:]

    /// Whether the long-press accent timer has fired for the current touch.
    private var longPressFired = false

    /// 400ms timer for accent long-press on letter/accent keys.
    private var longPressTimer: Task<Void, Never>?

    /// Delete key repeat task with acceleration.
    private var deleteRepeatTask: Task<Void, Never>?
    private var deleteCount: Int = 0
    private let wordModeThreshold = 10

    /// Shift double-tap detection timestamp.
    private var shiftLastTapTime: Date = .distantPast

    /// Space bar trackpad state.
    private var spaceTrackpadTask: Task<Void, Never>?
    private var isTrackpadMode = false
    private var trackpadActivationLocation: CGPoint = .zero
    private var trackpadLastDragLocation: CGPoint = .zero
    private var trackpadHasExitedDeadZone = false
    private var trackpadLastMoveTime: CFTimeInterval = 0
    private var trackpadAccumulatedX: CGFloat = 0
    private var trackpadAccumulatedY: CGFloat = 0

    // Trackpad tuning constants
    private let basePtsPerChar: CGFloat = 12.0
    private let deadZoneRadius: CGFloat = 8.0
    private let minMoveInterval: CFTimeInterval = 0.016
    private let slowVelocity: CGFloat = 100
    private let fastVelocity: CGFloat = 400
    private let maxAccelMultiplier: CGFloat = 2.5

    /// Accent popup hit-testing cell width (matches AccentPopup.cellWidth).
    private let accentCellWidth: CGFloat = 36

    /// Semi-transparent overlay shown during space bar trackpad mode.
    private let trackpadOverlayView = UIView()

    // MARK: - Bridge to SwiftUI

    /// ObservableObject bridge for popup preview, accent strip, and trackpad overlay.
    weak var touchState: KeyboardTouchState?

    // MARK: - Init

    override init(frame: CGRect) {
        // Configure flow layout BEFORE creating collectionView
        layout.minimumInteritemSpacing = 0  // CRITICAL: zero horizontal gap
        layout.minimumLineSpacing = 0       // CRITICAL: zero vertical gap
        layout.scrollDirection = .vertical

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)

        super.init(frame: frame)

        backgroundColor = .clear

        // CRITICAL: Disable collectionView interaction — this parent view handles all touches
        collectionView.isUserInteractionEnabled = false
        collectionView.isScrollEnabled = false
        collectionView.backgroundColor = .clear
        collectionView.register(DictusKeyCell.self, forCellWithReuseIdentifier: "key")

        collectionView.dataSource = self
        collectionView.delegate = self

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: KeyMetrics.rowSidePadding),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -KeyMetrics.rowSidePadding),
        ])

        // Trackpad overlay (shown during space bar cursor mode)
        trackpadOverlayView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.6)
        trackpadOverlayView.layer.cornerRadius = 8
        trackpadOverlayView.isHidden = true
        trackpadOverlayView.isUserInteractionEnabled = false
        addSubview(trackpadOverlayView)

        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Publish keyboard width for accent strip edge clamping
        touchState?.keyboardWidth = bounds.width
        // Invalidate collection view layout when bounds change (rotation)
        collectionView.collectionViewLayout.invalidateLayout()
        // Trackpad overlay fills the collection view bounds
        trackpadOverlayView.frame = bounds
    }

    // MARK: - Public API (same interface as old KeyboardContainerView)

    /// Build all keys from layout definitions and wire action callbacks.
    func buildKeys(rows: [[KeyDefinition]], actions: KeyboardActions) {
        self.actions = actions

        // Filter out .mic keys (mic is in toolbar, not keyboard grid)
        self.rows = rows.map { row in
            row.filter { $0.type != .mic }
        }

        // Cache total width multipliers per row for cell sizing
        self.rowTotalWidths = self.rows.map { row in
            row.reduce(0) { $0 + $1.widthMultiplier }
        }

        collectionView.reloadData()
    }

    /// Update shift state on all visible letter cells without rebuilding.
    func updateShift(_ shifted: Bool) {
        isShifted = shifted
        for cell in collectionView.visibleCells {
            guard let keyCell = cell as? DictusKeyCell else { continue }
            keyCell.updateShift(shifted)
        }
    }

    /// Update the shift icon without rebuilding.
    func updateShiftIcon(_ state: ShiftState) {
        shiftState = state
        for cell in collectionView.visibleCells {
            guard let keyCell = cell as? DictusKeyCell else { continue }
            keyCell.updateShiftIcon(state)
        }
    }

    /// Update the adaptive accent key's display state.
    func updateAccentState(lastTypedChar: String?, isShifted: Bool) {
        self.lastTypedChar = lastTypedChar
        self.isShifted = isShifted
        let displayChar = AccentedCharacters.adaptiveKeyLabel(afterTyping: lastTypedChar)
        for cell in collectionView.visibleCells {
            guard let keyCell = cell as? DictusKeyCell else { continue }
            keyCell.updateAccentLabel(displayChar)
        }
    }

    /// Update the return key label based on the host text field's returnKeyType.
    func updateReturnKeyType() {
        let type = actions?.onReturnKeyType?() ?? .default
        for cell in collectionView.visibleCells {
            guard let keyCell = cell as? DictusKeyCell else { continue }
            keyCell.updateReturnKeyType(type)
        }
    }

    // MARK: - Touch handling

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled, alpha > 0.01 else { return nil }
        guard self.point(inside: point, with: event) else { return nil }
        return self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let pointInCV = touch.location(in: collectionView)

            // Primary: direct hit on a cell. Fallback: nearest visible cell.
            // WHY fallback: floating-point rounding in cell sizing can create sub-pixel
            // gaps between cells where indexPathForItem returns nil. The nearest-cell
            // fallback ensures every touch on the keyboard surface resolves to a key.
            let indexPath: IndexPath
            if let ip = collectionView.indexPathForItem(at: pointInCV) {
                indexPath = ip
            } else if let ip = nearestVisibleCellIndexPath(to: pointInCV) {
                indexPath = ip
            } else {
                continue
            }

            let key = rows[indexPath.section][indexPath.item]
            touchToIndexPath[touch] = indexPath

            // Cancel any previous long-press/delete timers
            cancelTimers()

            // Unhighlight previous active key
            if let prev = activeIndexPath, prev != indexPath {
                (collectionView.cellForItem(at: prev) as? DictusKeyCell)?.setPressed(false)
            }

            activeIndexPath = indexPath

            // Highlight cell
            (collectionView.cellForItem(at: indexPath) as? DictusKeyCell)?.setPressed(true)

            switch key.type {
            case .character:
                handleCharacterTouchDown(key: key, indexPath: indexPath)

            case .accentAdaptive:
                handleAccentAdaptiveTouchDown(indexPath: indexPath)

            case .shift:
                HapticFeedback.keyTapped()
                AudioServicesPlaySystemSound(KeySound.modifier)

            case .delete:
                handleDeleteTouchDown()

            case .space:
                handleSpaceTouchDown(touch: touch)

            case .returnKey:
                HapticFeedback.keyTapped()
                AudioServicesPlaySystemSound(KeySound.modifier)

            case .globe, .emoji, .layerSwitch, .symbolToggle:
                HapticFeedback.keyTapped()
                AudioServicesPlaySystemSound(KeySound.modifier)

            case .mic:
                break
            }

            HapticFeedback.prepareForNextTap()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let indexPath = touchToIndexPath[touch] else { continue }
            let key = rows[indexPath.section][indexPath.item]

            // Handle accent popup drag
            if longPressFired, touchState?.showingAccents == true,
               (key.type == .character || key.type == .accentAdaptive) {
                let location = touch.location(in: self)
                updateAccentSelection(location: location, keyIndexPath: indexPath)
                continue
            }

            // Handle space trackpad
            if key.type == .space, isTrackpadMode {
                let currentLocation = touch.location(in: self)
                handleTrackpadDrag(currentLocation: currentLocation)
                trackpadLastDragLocation = currentLocation
                continue
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let indexPath = touchToIndexPath[touch] else { continue }
            let key = rows[indexPath.section][indexPath.item]

            // Unhighlight
            (collectionView.cellForItem(at: indexPath) as? DictusKeyCell)?.setPressed(false)

            switch key.type {
            case .character:
                handleCharacterTouchUp(key: key)

            case .accentAdaptive:
                handleAccentAdaptiveTouchUp()

            case .shift:
                handleShiftTouchUp()

            case .delete:
                handleDeleteTouchUp()

            case .space:
                handleSpaceTouchUp()

            case .returnKey:
                actions?.onReturn()

            case .globe:
                actions?.onGlobe()

            case .emoji:
                actions?.onEmoji()

            case .layerSwitch:
                actions?.onLayerSwitch()

            case .symbolToggle:
                actions?.onSymbolToggle()

            case .mic:
                break
            }

            touchToIndexPath[touch] = nil
            activeIndexPath = nil
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let indexPath = touchToIndexPath[touch] {
                (collectionView.cellForItem(at: indexPath) as? DictusKeyCell)?.setPressed(false)
            }
            touchToIndexPath[touch] = nil
        }
        cancelAllState()
    }

    // MARK: - Character key handling

    private func handleCharacterTouchDown(key: KeyDefinition, indexPath: IndexPath) {
        AudioServicesPlaySystemSound(KeySound.letter)
        HapticFeedback.keyTapped()

        // Show popup preview in SwiftUI
        let frame = frameForKey(at: indexPath)
        let displayLabel = isShifted ? key.label.uppercased() : key.label.lowercased()
        touchState?.showPress(label: displayLabel, frame: frame)

        // Start 400ms accent long-press timer
        longPressFired = false
        longPressTimer?.cancel()
        longPressTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.handleCharacterLongPress(key: key, indexPath: indexPath)
        }
    }

    private func handleCharacterLongPress(key: KeyDefinition, indexPath: IndexPath) {
        longPressFired = true

        guard let accents = AccentedCharacters.accents(for: key.label.lowercased()),
              !accents.isEmpty else { return }

        let accentList: [String]
        if isShifted {
            accentList = accents.map { $0.uppercased() }
        } else {
            accentList = accents
        }

        let frame = frameForKey(at: indexPath)
        touchState?.showAccents(accentList, keyFrame: frame)
    }

    private func handleCharacterTouchUp(key: KeyDefinition) {
        longPressTimer?.cancel()
        longPressTimer = nil

        if let state = touchState, state.showingAccents,
           let index = state.selectedAccentIndex,
           index >= 0, index < state.accentOptions.count {
            actions?.onCharacter(state.accentOptions[index])
            touchState?.hideAccents()
        } else if !longPressFired {
            let char = isShifted ? key.label.uppercased() : key.label.lowercased()
            actions?.onCharacter(char)
        }

        touchState?.hidePress()
        touchState?.hideAccents()
        longPressFired = false
    }

    // MARK: - Accent adaptive key handling

    private func handleAccentAdaptiveTouchDown(indexPath: IndexPath) {
        AudioServicesPlaySystemSound(KeySound.letter)
        HapticFeedback.keyTapped()

        let displayChar = AccentedCharacters.adaptiveKeyLabel(afterTyping: lastTypedChar)
        let frame = frameForKey(at: indexPath)
        touchState?.showPress(label: displayChar, frame: frame)

        longPressFired = false
        longPressTimer?.cancel()
        longPressTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.handleAccentAdaptiveLongPress(indexPath: indexPath)
        }
    }

    private func handleAccentAdaptiveLongPress(indexPath: IndexPath) {
        longPressFired = true

        guard let vowel = AccentedCharacters.adaptiveKeyVowel(afterTyping: lastTypedChar),
              let accents = AccentedCharacters.accents(for: vowel), !accents.isEmpty else { return }

        let isUppercase = lastTypedChar?.uppercased() == lastTypedChar
            && lastTypedChar?.lowercased() != lastTypedChar
        let accentList: [String]
        if isUppercase {
            accentList = accents.map { $0.uppercased() }
        } else {
            accentList = accents
        }

        let frame = frameForKey(at: indexPath)
        touchState?.showAccents(accentList, keyFrame: frame)
    }

    private func handleAccentAdaptiveTouchUp() {
        longPressTimer?.cancel()
        longPressTimer = nil

        let displayChar = AccentedCharacters.adaptiveKeyLabel(afterTyping: lastTypedChar)

        if let state = touchState, state.showingAccents,
           let index = state.selectedAccentIndex,
           index >= 0, index < state.accentOptions.count {
            actions?.onAccentAdaptive(state.accentOptions[index])
            touchState?.hideAccents()
        } else if !longPressFired {
            actions?.onAccentAdaptive(displayChar)
        }

        touchState?.hidePress()
        touchState?.hideAccents()
        longPressFired = false
    }

    // MARK: - Accent selection tracking

    private func updateAccentSelection(location: CGPoint, keyIndexPath: IndexPath) {
        let accentCount = touchState?.accentOptions.count ?? 0
        guard accentCount > 0 else { return }

        let totalWidth = CGFloat(accentCount) * accentCellWidth
        let kbWidth = touchState?.keyboardWidth ?? bounds.width * 10
        let frameInKB = frameForKey(at: keyIndexPath)
        let rawMidX = frameInKB.midX
        let halfWidth = totalWidth / 2
        let clampedMidX = max(halfWidth, min(rawMidX, kbWidth - halfWidth))

        // Convert to self coordinates
        let localX = location.x
        let selfMidX = frameInKB.midX  // already in self coords since frameForKey uses convert to self
        let clampedLocalMidX = selfMidX + (clampedMidX - rawMidX)
        let popupStartX = clampedLocalMidX - totalWidth / 2
        let index = Int((localX - popupStartX) / accentCellWidth)

        if index >= 0 && index < accentCount {
            touchState?.updateAccentSelection(at: index)
        } else {
            touchState?.updateAccentSelection(at: nil)
        }
    }

    // MARK: - Shift key handling

    private func handleShiftTouchUp() {
        let now = Date()
        let interval = now.timeIntervalSince(shiftLastTapTime)
        shiftLastTapTime = now

        if interval < 0.4 && shiftState == .shifted {
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

        actions?.onShiftChanged(shiftState)
    }

    // MARK: - Delete key handling

    private func handleDeleteTouchDown() {
        let deleted = actions?.onDelete() ?? false
        if deleted {
            HapticFeedback.keyTapped()
            AudioServicesPlaySystemSound(KeySound.delete)
        }
        deleteCount = 1

        deleteRepeatTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            while !Task.isCancelled {
                guard let self = self else { return }
                if self.deleteCount >= self.wordModeThreshold {
                    self.actions?.onWordDelete()
                    try? await Task.sleep(nanoseconds: 120_000_000)
                } else {
                    _ = self.actions?.onDelete()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                self.deleteCount += 1
            }
        }
    }

    private func handleDeleteTouchUp() {
        deleteRepeatTask?.cancel()
        deleteRepeatTask = nil
        deleteCount = 0
    }

    // MARK: - Space key handling

    private func handleSpaceTouchDown(touch: UITouch) {
        HapticFeedback.keyTapped()
        AudioServicesPlaySystemSound(KeySound.modifier)
        trackpadLastDragLocation = touch.location(in: self)

        spaceTrackpadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.activateTrackpad()
        }
    }

    private func handleSpaceTouchUp() {
        if !isTrackpadMode {
            actions?.onSpace()
        }
        deactivateTrackpad()
    }

    private func activateTrackpad() {
        isTrackpadMode = true
        trackpadActivationLocation = trackpadLastDragLocation
        trackpadHasExitedDeadZone = false
        trackpadLastMoveTime = CACurrentMediaTime()
        trackpadAccumulatedX = 0
        trackpadAccumulatedY = 0
        trackpadOverlayView.isHidden = false
        HapticFeedback.trackpadActivated()
    }

    private func deactivateTrackpad() {
        spaceTrackpadTask?.cancel()
        spaceTrackpadTask = nil

        if isTrackpadMode {
            isTrackpadMode = false
            trackpadOverlayView.isHidden = true
        }
        trackpadAccumulatedX = 0
        trackpadAccumulatedY = 0
        trackpadHasExitedDeadZone = false
        trackpadLastMoveTime = 0
    }

    private func handleTrackpadDrag(currentLocation: CGPoint) {
        if !trackpadHasExitedDeadZone {
            let dx = currentLocation.x - trackpadActivationLocation.x
            let dy = currentLocation.y - trackpadActivationLocation.y
            let distance = sqrt(dx * dx + dy * dy)
            if distance < deadZoneRadius { return }
            trackpadHasExitedDeadZone = true
            trackpadLastDragLocation = currentLocation
            trackpadLastMoveTime = CACurrentMediaTime()
            return
        }

        let now = CACurrentMediaTime()
        let elapsed = now - trackpadLastMoveTime
        let deltaX = currentLocation.x - trackpadLastDragLocation.x
        let deltaY = currentLocation.y - trackpadLastDragLocation.y

        if elapsed < minMoveInterval {
            trackpadAccumulatedX += deltaX
            trackpadAccumulatedY += deltaY
            return
        }

        let totalDeltaX = trackpadAccumulatedX + deltaX
        let totalDeltaY = trackpadAccumulatedY + deltaY

        let dragMagnitude = sqrt(totalDeltaX * totalDeltaX + totalDeltaY * totalDeltaY)
        let velocity = elapsed > 0 ? dragMagnitude / CGFloat(elapsed) : 0

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
        let charsFromX = Int(totalDeltaX / effectivePtsPerChar)
        let charsFromY = Int(totalDeltaY / effectivePtsPerChar)
        let totalChars = charsFromX + charsFromY

        if totalChars != 0 {
            actions?.onCursorMove(totalChars)
            HapticFeedback.cursorMoved()
            trackpadAccumulatedX = totalDeltaX - CGFloat(charsFromX) * effectivePtsPerChar
            trackpadAccumulatedY = totalDeltaY - CGFloat(charsFromY) * effectivePtsPerChar
            trackpadLastMoveTime = now
        } else {
            trackpadAccumulatedX = totalDeltaX
            trackpadAccumulatedY = totalDeltaY
        }
    }

    // MARK: - Helpers

    /// Get the frame of a key cell in this view's coordinate space.
    private func frameForKey(at indexPath: IndexPath) -> CGRect {
        guard let attrs = collectionView.layoutAttributesForItem(at: indexPath) else {
            return .zero
        }
        return collectionView.convert(attrs.frame, to: self)
    }

    /// Find the nearest visible cell to a point by squared Euclidean distance.
    /// Used as fallback when indexPathForItem(at:) returns nil due to sub-pixel gaps.
    private func nearestVisibleCellIndexPath(to point: CGPoint) -> IndexPath? {
        var bestIP: IndexPath?
        var bestDist: CGFloat = .greatestFiniteMagnitude
        for cell in collectionView.visibleCells {
            let center = cell.center
            let dx = point.x - center.x
            let dy = point.y - center.y
            let dist = dx * dx + dy * dy  // squared distance, skip sqrt
            if dist < bestDist {
                bestDist = dist
                bestIP = collectionView.indexPath(for: cell)
            }
        }
        return bestIP
    }

    /// Cancel long-press and delete timers (but not trackpad).
    private func cancelTimers() {
        longPressTimer?.cancel()
        longPressTimer = nil
        deleteRepeatTask?.cancel()
        deleteRepeatTask = nil
        deleteCount = 0
    }

    /// Reset all touch state.
    private func cancelAllState() {
        cancelTimers()
        deactivateTrackpad()
        touchState?.hidePress()
        touchState?.hideAccents()
        longPressFired = false
        activeIndexPath = nil
    }
}

// MARK: - UICollectionViewDataSource

extension KeyboardCollectionView: UICollectionViewDataSource {

    /// Sections = keyboard rows.
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        rows.count
    }

    /// Items = keys in each row.
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        rows[section].count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "key", for: indexPath) as! DictusKeyCell
        let key = rows[indexPath.section][indexPath.item]
        cell.configure(with: key, shifted: isShifted, shiftState: shiftState)

        // Apply return key type if this is a return key
        if key.type == .returnKey {
            let type = actions?.onReturnKeyType?() ?? .default
            cell.updateReturnKeyType(type)
        }

        return cell
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension KeyboardCollectionView: UICollectionViewDelegateFlowLayout {

    /// Cell size: proportional width based on widthMultiplier, equal height per row.
    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let key = rows[indexPath.section][indexPath.item]
        let rowTotal = rowTotalWidths[indexPath.section]
        guard rowTotal > 0 else { return .zero }

        // Subtract 1 pixel from available width to prevent floating-point rounding
        // from creating sub-pixel gaps between cells. Pattern from giellakbd-ios.
        // Without this, UIKit rounds individual cell widths such that their sum is
        // less than the total width, leaving 1-2 pixel dead zones between keys.
        let availableWidth = collectionView.bounds.width - 1
        let width = key.widthMultiplier * (availableWidth / rowTotal)
        let height = collectionView.bounds.height / CGFloat(rows.count)
        return CGSize(width: width, height: height)
    }
}
