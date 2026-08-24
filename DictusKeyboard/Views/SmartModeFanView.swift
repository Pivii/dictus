// DictusKeyboard/Views/SmartModeFanView.swift
// The long-press Smart Mode fan (issue #79).
import SwiftUI
import DictusCore

/// The vertical fan of modes that replaces the keys while the mic is held.
///
/// ### It handles no touches at all
///
/// The gesture belongs to the mic pill in the toolbar — the finger went down there,
/// and a single `DragGesture` tracks it from the long-press to the release. So this
/// view is purely a drawing of somebody else's state: `allowsHitTesting(false)` at
/// the bottom is load-bearing, not defensive. A row that accepted a touch would take
/// it from the gesture recogniser mid-drag and the release would land nowhere.
///
/// ### The geometry is not in this file
///
/// Row height and the y-to-row mapping live in `SmartModeFanLayout`, in DictusCore,
/// because the keyboard target has no test bundle and that arithmetic is what
/// settled #79's fan-capacity contradiction. This view reads the numbers; it does
/// not decide them.
struct SmartModeFanView: View {

    let state: SmartModeFanState

    /// Space below the toolbar, measured by the caller.
    let availableHeight: CGFloat

    private var showsReason: Bool { state.unavailableReason != nil }

    private var rowHeight: CGFloat {
        SmartModeFanLayout.rowHeight(
            availableHeight: availableHeight,
            entryCount: state.entries.count,
            showsReason: showsReason
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(state.entries.enumerated()), id: \.element.id) { index, entry in
                row(entry, isHighlighted: index == state.highlightedIndex)
            }

            if let reason = state.unavailableReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    // The sentence must not truncate: it is the whole of what the user
                    // is being told, and half of it is worse than none. It gives up
                    // size on a narrow screen instead, the same trade the #315 notice
                    // makes in the toolbar.
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(height: SmartModeFanLayout.reasonHeight)
                    .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // A surface of its own, because the fan is the only one in this keyboard
        // without one (device feedback, 2026-08-24).
        //
        // The keyboard container is translucent, and the *keys* are what normally
        // give the eye something opaque to lock onto. The fan replaces them with
        // text on nothing, so the host app's own sentences read straight through the
        // rows — visible in both device screenshots. Every other Dictus surface over
        // a host carries a backing: the mic pill, the hamburger, the panel, the
        // recording overlay.
        //
        // `dictusGlass` rather than an opacity or a fill because it **blurs**, which
        // is what actually destroys sharp host text — dimming only makes it grey.
        // It resolves to Liquid Glass on iOS 26 and `.regularMaterial` below, and
        // adapts to the light and dark keyboard for free.
        .dictusGlass(in: Rectangle())
        // Below the backdrop, so neither the rows nor the glass can take a touch.
        // See the type's doc comment: this is what keeps the drag on the mic's
        // recogniser instead of letting the fan swallow it.
        .allowsHitTesting(false)
    }

    // MARK: - Rows

    /// One fan row: icon, name, and the highlight that says where the finger is.
    ///
    /// WHY the highlight is a filled capsule and not a tint on the text: the thumb is
    /// covering this row while choosing it. Only the edges are visible, so the signal
    /// has to be at the edges.
    ///
    /// A disabled row still draws its name and icon rather than being hidden. The
    /// user is entitled to see what the feature is before being told they cannot have
    /// it here — that is the same honesty the paywall's capability filter applies
    /// (#79), one surface earlier.
    private func row(_ entry: SmartModeFanEntry, isHighlighted: Bool) -> some View {
        let isEnabled = entry.smartMode == nil || !showsReason
        // Icon and label centred as one group, not the label centred inside a
        // leading-aligned row (device feedback, 2026-08-24): the highlight capsule
        // spans the full width, and a label pinned to its left edge reads as text
        // that happens to sit on a pill rather than as the pill's own label.
        return HStack(spacing: 10) {
            Image(systemName: entry.icon)
                .font(.system(size: 17, weight: .medium))

            Text(name(entry))
                .font(.system(size: 17, weight: isHighlighted ? .semibold : .regular))
                .lineLimit(1)
        }
        .foregroundColor(foreground(entry, isHighlighted: isHighlighted, isEnabled: isEnabled))
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight)
        .background(
            Capsule()
                .fill(tint(entry).opacity(isHighlighted ? 0.22 : 0))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
        )
        .opacity(isEnabled ? 1 : 0.4)
    }

    /// Normal is named here rather than on the entry: DictusCore ships no string
    /// catalog, and every other mode's label is the catalogue's own — deliberately
    /// language-neutral, so "→ EN" reads the same in every UI locale.
    private func name(_ entry: SmartModeFanEntry) -> String {
        entry.smartMode?.displayName
            ?? String(
                localized: "Normal",
                comment: "The Smart Mode fan row that clears the armed mode and returns to the free polish."
            )
    }

    /// The row's colour is the colour the mic pill will take if this row is chosen —
    /// accent for Normal, Smart Mode purple for a mode. The fan is where that
    /// association is taught; the pill is where it is read afterwards.
    private func tint(_ entry: SmartModeFanEntry) -> Color {
        entry.smartMode == nil ? .dictusAccent : .dictusSmartMode
    }

    /// Highlighted rows take their own tint rather than a shared accent, so the
    /// glyph, the label and the capsule all say the same thing about which of the two
    /// states the release will produce.
    private func foreground(_ entry: SmartModeFanEntry,
                            isHighlighted: Bool,
                            isEnabled: Bool) -> Color {
        guard isEnabled else { return .secondary }
        return isHighlighted ? tint(entry) : .primary
    }
}
