// DictusKeyboard/Views/KeyButton.swift
import SwiftUI

/// A standard keyboard key that inserts a character on tap.
/// Shows a popup preview above the key during the press gesture.
struct KeyButton: View {
    let key: KeyDefinition
    let isShifted: Bool
    let onTap: (String) -> Void

    @State private var isPressed = false

    private var displayLabel: String {
        isShifted ? key.label.uppercased() : key.label.lowercased()
    }

    private var outputChar: String {
        guard let output = key.output else { return "" }
        return isShifted ? output.uppercased() : output
    }

    var body: some View {
        // Using a plain gesture to get press/release states
        Text(displayLabel)
            .font(.system(size: 22, weight: .regular))
            .frame(maxWidth: .infinity)
            .frame(height: KeyMetrics.keyHeight)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 1)
            )
            .overlay(
                // Popup preview shown above key on press
                Group {
                    if isPressed {
                        KeyPopup(label: displayLabel)
                            .offset(y: -(KeyMetrics.keyHeight + 8))
                    }
                },
                alignment: .top
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        onTap(outputChar)
                    }
            )
    }
}

/// The popup preview bubble shown above a pressed key.
struct KeyPopup: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 32, weight: .regular))
            .frame(width: 50, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
            )
    }
}

/// Shared key dimension constants.
enum KeyMetrics {
    static let keyHeight: CGFloat = 42
    static let rowSpacing: CGFloat = 6
    static let keySpacing: CGFloat = 4
    static let rowHorizontalPadding: CGFloat = 3
}
