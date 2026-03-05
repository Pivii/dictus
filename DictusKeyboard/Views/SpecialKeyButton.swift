// DictusKeyboard/Views/SpecialKeyButton.swift
import SwiftUI

/// Shift key with three states: off, shift (single character), caps lock.
/// Double-tap detected via timestamp: if second tap arrives within 400ms, activate caps lock.
struct ShiftKey: View {
    @Binding var shiftState: ShiftState
    let width: CGFloat

    @State private var lastTapTime: Date = .distantPast

    var body: some View {
        Button {
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
                    RoundedRectangle(cornerRadius: 5)
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
                RoundedRectangle(cornerRadius: 5)
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
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(.systemBackground))
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
                    RoundedRectangle(cornerRadius: 5)
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
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(.systemGray3))
                )
        }
        .foregroundColor(Color(.label))
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
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(.systemGray3))
                )
        }
        .foregroundColor(Color(.label))
    }
}
