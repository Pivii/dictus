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
        // `modesAreArmable` and not `showsReason`: the non-subscriber's fan refuses
        // every mode and shows no sentence, so inferring one from the other would draw
        // its rows enabled (#404).
        let isEnabled = entry.smartMode == nil || state.modesAreArmable
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

    /// What a row says about itself when the finger is not on it (#423, #404).
    ///
    /// Three tags, never two at once, and the precedence lives in
    /// `SmartModeFanLayout.tag(for:...)` — in DictusCore, because this target has no
    /// test bundle and the rule has enough branches to be worth checking.
    ///
    /// - **The check** goes on the row that will actually run. "Armed" and "in force"
    ///   stopped being the same thing the moment a mode could stay armed and not run:
    ///   greying a mode row says *you cannot pick this*, not *the thing you already
    ///   picked will not happen*, and only the second was true when the maintainer hit
    ///   #423.
    /// - **`INACTIF`** goes on the armed row when it is not the one running. The choice
    ///   survived — `resolveArmedMode` keeps it deliberately — and the tag says so
    ///   without claiming it is active.
    /// - **`PRO`** goes on every mode row of a non-subscriber's fan (#404). Verbatim
    ///   and not localised: it is the product's own abbreviation and reads the same in
    ///   both languages, like "Dictus Pro" beside it.
    @ViewBuilder
    private func marker(for entry: SmartModeFanEntry) -> some View {
        switch state.tag(for: entry) {
        case .effective:
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
        case .inactive:
            tagCapsule(Text(
                "Off",
                comment: "Marker on the Smart Mode fan row the user armed, when that mode will not run and the dictation goes in as Normal."
            ))
        case .pro:
            tagCapsule(Text(verbatim: "PRO"))
        case nil:
            EmptyView()
        }
    }

    /// The pill a word-tag sits in. Muted on purpose: it labels a row the user cannot
    /// choose, and a loud badge on an unreachable row reads as an alarm.
    private func tagCapsule(_ label: Text) -> some View {
        label
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(Capsule().fill(Color.secondary.opacity(0.18)))
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

    /// The Dictus Pro row: the last of the four in a non-subscriber's fan (#404).
    ///
    /// ### Why it is the same size and shape as its neighbours
    ///
    /// It was a single full-height row until 2026-08-29, when the maintainer saw it on
    /// device: *"je ne suis pas fan qu'on ait cette grosse pilule qui prend tout le
    /// clavier"*. The aesthetic objection turned out to be the smallest of three — the
    /// one-row fan also removed the `Normal` row, and with it the only way a
    /// non-subscriber could start a recording from the fan at all. Now the fan is the
    /// same object for everyone, and subscribing un-greys it rather than replacing it.
    ///
    /// So it takes the capsule, the height and the layout of a mode row, and differs
    /// only where it must: the paywall's own gradient, so the Pro signal reads the same
    /// here as on `ToolbarView.proEntry`, and a chevron, because it is the one row that
    /// leaves the keyboard.
    private func proRow(isHighlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .medium))

            Text(verbatim: "Dictus Pro")
                .font(.system(size: 17, weight: isHighlighted ? .bold : .semibold))
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
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
        .background(rowSurface(isHighlighted: isHighlighted))
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
