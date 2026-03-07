// DictusKeyboard/Views/AccentPopup.swift
// Horizontal popup showing accented character variants when a key is long-pressed.
import SwiftUI
import DictusCore

/// Accent picker popup shown above a pressed key during a long-press gesture.
///
/// WHY a horizontal row of cells (not a vertical list or grid):
/// This matches iOS system keyboard behavior. Users expect accented characters
/// displayed in a horizontal strip above the key, with slide-to-select.
///
/// WHY the popup stays within the keyboard frame:
/// Apple's documentation states that keyboard extensions cannot draw above their
/// top edge. If the popup would clip above the keyboard (e.g., for top-row keys),
/// it must be positioned below or beside the key instead.
struct AccentPopup: View {
    let accents: [String]
    let selectedIndex: Int?

    /// Width of each accent cell in the popup.
    private let cellWidth: CGFloat = 36
    /// Height of each accent cell.
    private let cellHeight: CGFloat = 48
    /// Font size for accent characters.
    private let fontSize: CGFloat = 22

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(accents.enumerated()), id: \.offset) { index, accent in
                Text(accent)
                    .font(.system(size: fontSize, weight: .regular))
                    .frame(width: cellWidth, height: cellHeight)
                    .background(
                        RoundedRectangle(cornerRadius: KeyMetrics.keyCornerRadius)
                            .fill(index == selectedIndex
                                  ? Color.dictusAccent
                                  : KeyMetrics.letterKeyColor)
                    )
                    .foregroundColor(index == selectedIndex ? .white : .primary)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(KeyMetrics.letterKeyColor)
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
        )
    }

    /// Total width of the popup, useful for centering calculations.
    var totalWidth: CGFloat {
        CGFloat(accents.count) * cellWidth
    }
}
