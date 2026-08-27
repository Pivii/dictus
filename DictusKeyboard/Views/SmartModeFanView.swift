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
                if case .pro = entry {
                    proRow(isHighlighted: index == state.highlightedIndex)
                } else {
                    row(entry, isHighlighted: index == state.highlightedIndex)
                }
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
        // See the type's doc comment. This is what keeps the drag on the mic's
        // recogniser instead of letting a row swallow it.
        .allowsHitTesting(false)
    }

    // MARK: - Rows

    /// One fan row: icon, name, and the highlight that says where the finger is.
    ///
    /// ### Why every row has a surface, not only the highlighted one
    ///
    /// The keyboard container is translucent, and what normally gives the eye
    /// something opaque to sit on is the *keys*. The fan replaces them, so before
    /// this the rows were text floating on the host app's own text — legible enough
    /// to read the wrong thing through, on the captures of 2026-08-24. One glass
    /// panel behind the whole fan was tried and refused on sight: it came out lighter
    /// than the keyboard with hard edges top and bottom, a square laid over the
    /// product rather than part of it. A capsule per row is the fix that belongs
    /// here, because it is the shape the keys already have — the fan reads as a
    /// column of wide keys instead of as a sheet.
    ///
    /// ### Why the highlight is a filled capsule and not a tint on the text
    ///
    /// The thumb is covering this row while choosing it. Only the edges are visible,
    /// so the signal has to be at the edges.
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

            marker(for: entry)
        }
        .foregroundColor(foreground(isHighlighted: isHighlighted, isEnabled: isEnabled))
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight)
        .background(rowSurface(isHighlighted: isHighlighted))
        .opacity(isEnabled ? 1 : 0.4)
    }

    /// What a row says about itself when the finger is not on it (#423).
    ///
    /// Two markers, because "armed" and "in force" stopped being the same thing the
    /// moment a mode could stay armed and not run. Greying the mode rows says *you
    /// cannot pick this*; it does not say *the thing you already picked will not
    /// happen*, and only the second was true when the maintainer hit this.
    ///
    /// - The row that **will run** carries the check. When the armed mode is
    ///   honoured that is the mode; when it is not, it is Normal, because Normal is
    ///   what the dictation does.
    /// - The armed row, when it is not the one running, carries a muted `Off`
    ///   instead. The choice survived — `resolveArmedMode` keeps it deliberately, so
    ///   re-subscribing or switching the feature back on restores it without
    ///   re-arming — and the marker is what says so without claiming it is active.
    ///
    /// A row can never carry both: the check is on `effectiveEntryID` and the `Off`
    /// only on an armed row that is not it.
    @ViewBuilder
    private func marker(for entry: SmartModeFanEntry) -> some View {
        if entry.id == state.effectiveEntryID {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
        } else if entry.id == state.armedEntryID {
            Text(
                "Off",
                comment: "Marker on the Smart Mode fan row the user armed, when that mode will not run and the dictation goes in as Normal."
            )
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(Capsule().fill(Color.secondary.opacity(0.18)))
        }
    }

    /// The Dictus Pro row: the whole of a non-subscriber's fan (#404, decided in
    /// #392).
    ///
    /// ### Why it does not look like a mode row
    ///
    /// It is not one. Every other row changes a setting and stays in the keyboard;
    /// this one leaves for the app's paywall. It wears the paywall's own gradient —
    /// the same one `ToolbarView.proEntry` carries — so the Pro signal reads
    /// identically across surfaces, and it says out loud what releasing on it does,
    /// because a blind release at the end of a drag is not a place to be surprised.
    ///
    /// ### Why a rounded rectangle and not the capsule its neighbours use
    ///
    /// Because it has no neighbours. As the only entry it gets the whole area —
    /// about 205 pt on a standard iPhone — and a capsule that tall is a lozenge with
    /// a 100 pt radius, which reads as a shape rather than as a control. The capsule
    /// exists to make a row look like one of the wide keys it replaced; one row
    /// covering the whole keyboard is not that, and should not pretend to be.
    private func proRow(isHighlighted: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 24, weight: .medium))

            Text(verbatim: "Dictus Pro")
                .font(.system(size: 22, weight: .bold))

            Text(
                "Release here to see the plans",
                comment: "Caption on the Dictus Pro row of the Smart Mode fan, telling the user what releasing the long-press does."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
        }
        .foregroundStyle(
            LinearGradient(
                colors: [.dictusGradientStart, .dictusGradientEnd],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.dictusAccent.opacity(isHighlighted ? 0.25 : 0))
                .dictusGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
        )
    }

    /// The capsule under a row: glass at rest, washed accent under the finger.
    ///
    /// The accent fill goes *over* the glass rather than replacing it, so the
    /// highlighted row keeps the same opacity as its neighbours and only gains
    /// colour. Swapping the material out instead made the chosen row look like a
    /// hole in the column.
    private func rowSurface(isHighlighted: Bool) -> some View {
        Capsule()
            .fill(Color.dictusAccent.opacity(isHighlighted ? 0.25 : 0))
            .dictusGlass(in: Capsule())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
    }

    /// The colour of a row's glyph and label.
    ///
    /// ### Why only the highlighted row is blue
    ///
    /// Between #79's visual pass and #399 every enabled row was accent blue. The
    /// commit that did it was getting the Smart Mode purple out of the keyboard,
    /// which was right; it took `.primary` with it, which was not. Three blue rows
    /// on three pale capsules read as three chosen things, and the highlight was
    /// left saying "this one" against two neighbours wearing its own colour.
    ///
    /// ### Why the resting rows are `.primary` rather than a near-black literal
    ///
    /// The fan stands in for the keys, so its resting rows should read as key
    /// glyphs — and those invert: the vendored theme paints them black on a light
    /// keyboard and white on a dark one. `.primary` is that pair, already resolved
    /// by the environment; a literal would be right in one appearance only.
    private func foreground(isHighlighted: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else { return .secondary }
        return isHighlighted ? .dictusAccent : .primary
    }

    /// Normal is named here rather than on the entry: DictusCore ships no string
    /// catalog, and every other mode's label is the catalogue's own — deliberately
    /// language-neutral, so "→ EN" reads the same in every UI locale.
    private func name(_ entry: SmartModeFanEntry) -> String {
        entry.smartMode?.localizedDisplayName
            ?? String(
                localized: "Normal",
                comment: "The Smart Mode fan row that clears the armed mode and returns to the free polish."
            )
    }
}
