// DictusKeyboard/Views/KeyboardPanelView.swift
import SwiftUI
import DictusCore

/// Body of the hamburger panel (#241): the keyboard-language list.
///
/// The panel fills the keyboard area below the bar while `KeyboardAreaMode` is
/// `.panel`; the bar itself is `ToolbarView`'s panel presentation, which carries
/// the close control, the Pro entry and the gear. This view owns nothing above
/// the separator.
///
/// WHY a list and not the cycle it replaces:
/// The toolbar control cycled languages on touch-down, which at four languages is
/// already three taps to reach German. Tap count is explicitly not what this
/// optimises — a list with a checkmark on the active entry is legible and stops
/// being a puzzle as languages are added.
///
/// WHY the layout column is editable (#272):
/// the layout is stored per dictionary language and no longer follows from it, so each
/// row's right side is one pill per `LayoutType` and tapping one sets that language's
/// layout. Generating the pills from `LayoutType.allCases` is what made QWERTZ (#151)
/// appear here for free. There is no sub-picker: at three layouts a sheet would cost a
/// tap and a screen to show three words.
struct KeyboardPanelView: View {
    /// Space available below the bar, measured by the parent GeometryReader.
    /// Same contract as EmojiPickerView: the hosting controller does not always
    /// hand SwiftUI the full keyboard area, so the parent measures and passes.
    let availableHeight: CGFloat

    /// Notifies the controller that the key grid must be rebuilt for the new
    /// language. The panel deliberately stays open across that rebuild.
    var onLanguageChanged: ((SupportedLanguage) -> Void)?

    /// Notifies the controller that `language` now types on `layout`. The controller
    /// decides whether that means a rebuild — it only does when the language is the
    /// active one; the other rows are stored for the next time they are selected.
    var onLayoutChanged: ((LayoutType, SupportedLanguage) -> Void)?

    /// Mirrors the App Group value so the checkmark moves the instant the row is
    /// tapped, without waiting for the ~200 ms grid rebuild that follows.
    @State private var language: SupportedLanguage = .active

    /// Effective layout per language, mirrored for the same reason as `language`:
    /// the pill has to fill in on touch-up, not after the grid rebuild.
    @State private var layouts: [SupportedLanguage: LayoutType] = [:]

    /// The open transition, and the only animation in the panel.
    ///
    /// It lives here rather than on the mode change because the keyboard area's
    /// branches are the single child of a VStack: animating the branch swap would
    /// keep the outgoing bar laid out above the incoming one for the duration.
    /// Fading this view in stacks nothing and touches no constraint.
    @State private var contentOpacity: Double = 0

    /// Reduced motion removes the fade rather than shortening it.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let rowHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()

            // Two column headers: the rows carry two independent choices since #272,
            // and without the second label the pills read as a state badge.
            HStack(spacing: 8) {
                Text("Keyboard language")
                Spacer(minLength: 8)
                Text("Layout")
            }
            .font(.system(size: 12, weight: .semibold))
            .textCase(.uppercase)
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)

            // Scrollable so a short keyboard area (landscape, or a small device)
            // clips nothing. With four languages it never actually scrolls.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(SupportedLanguage.allCases, id: \.self) { entry in
                        languageRow(entry)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: availableHeight)
        .opacity(contentOpacity)
        .onAppear {
            // The language and the layouts can have been changed in DictusApp since this
            // view was last built; the panel is cheap to re-read on every open.
            language = .active
            layouts = Dictionary(
                uniqueKeysWithValues: SupportedLanguage.allCases.map {
                    ($0, KeyboardLayoutPreference.layout(for: $0))
                }
            )

            if reduceMotion {
                contentOpacity = 1
            } else {
                withAnimation(.easeOut(duration: 0.18)) {
                    contentOpacity = 1
                }
            }
        }
    }

    /// One row: the language on the left, its layout pills on the right.
    ///
    /// WHY two sibling buttons instead of one row button containing the pills:
    /// a Button nested inside another Button's label never receives the touch — the
    /// outer one swallows it. The row is therefore an HStack of independent controls,
    /// each with its own full-height hit area.
    private func languageRow(_ entry: SupportedLanguage) -> some View {
        let isActive = entry == language
        return HStack(spacing: 8) {
            Button {
                select(entry)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(.label))
                        .frame(width: 18)
                        .opacity(isActive ? 1 : 0)

                    Text(entry.displayName)
                        .font(.system(size: 17))
                        .foregroundColor(Color(.label))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 8)
                }
                .frame(height: rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isActive ? [.isSelected] : [])

            // One pill per layout, so a new LayoutType case surfaces here with no
            // further work — that is how QWERTZ (#151) arrived in this panel.
            ForEach(LayoutType.allCases, id: \.self) { layout in
                layoutPill(layout, for: entry)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: rowHeight)
    }

    private func layoutPill(_ layout: LayoutType, for entry: SupportedLanguage) -> some View {
        let isSelected = layouts[entry] == layout
        return Button {
            selectLayout(layout, for: entry)
        } label: {
            Text(layout.displayName)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                // The three pills plus a language name have to fit a 320 pt row.
                .minimumScaleFactor(0.75)
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.dictusAccent : Color(.tertiarySystemFill))
                )
                // Visually 28 pt, tappable over the full row: a 28 pt target in a
                // keyboard panel is small enough to miss, and the row has the height
                // to give away.
                .frame(height: rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(entry.displayName), \(layout.displayName)"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Applies the language. The panel stays open (#272): a row now carries two
    /// choices, and closing on the first one takes the second away. Nothing here
    /// dismisses the panel — the ✕ in the bar is the only way out.
    private func select(_ entry: SupportedLanguage) {
        // Re-selecting the active language would cost a full key-grid rebuild for
        // no visible change, so it is a no-op.
        guard entry != language else { return }

        SupportedLanguage.activate(entry)
        HapticFeedback.keyTapped()
        language = entry

        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardPanelView",
            instanceID: "",
            action: "languageSelected",
            details: "language=\(entry.rawValue) layout=\(KeyboardLayoutPreference.layout(for: entry).rawValue)"
        ))
        onLanguageChanged?(entry)
    }

    /// Applies a layout to one language (#272), whether or not it is the active one.
    private func selectLayout(_ layout: LayoutType, for entry: SupportedLanguage) {
        HapticFeedback.keyTapped()

        // Written even when the pill is already filled: the pill shows the *effective*
        // layout, which may still be the inherited default. Tapping it is the user
        // saying they want this layout for this language, and that has to stop the
        // language tracking a future change of default.
        KeyboardLayoutPreference.setLayout(layout, for: entry)

        // Nothing on screen changes below this point, so no rebuild either.
        guard layouts[entry] != layout else { return }
        layouts[entry] = layout

        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardPanelView",
            instanceID: "",
            action: "layoutSelected",
            details: "language=\(entry.rawValue) layout=\(layout.rawValue) active=\(language.rawValue)"
        ))
        onLayoutChanged?(layout, entry)
    }
}
