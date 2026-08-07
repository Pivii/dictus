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
/// WHY the layout column:
/// Selecting a language still writes that language's default layout — the two are
/// welded together. Showing the layout beside each language makes that coupling
/// visible, which is what will make #272 comprehensible when the column becomes
/// editable. It is display-only here.
struct KeyboardPanelView: View {
    /// Space available below the bar, measured by the parent GeometryReader.
    /// Same contract as EmojiPickerView: the hosting controller does not always
    /// hand SwiftUI the full keyboard area, so the parent measures and passes.
    let availableHeight: CGFloat

    /// Notifies the controller that the key grid must be rebuilt for the new
    /// language. The panel deliberately stays open across that rebuild.
    var onLanguageChanged: ((SupportedLanguage) -> Void)?

    /// Mirrors the App Group value so the checkmark moves the instant the row is
    /// tapped, without waiting for the ~200 ms grid rebuild that follows.
    @State private var language: SupportedLanguage = .active

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

            Text("Keyboard language")
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
            // The language can have been changed in DictusApp since this view was
            // last built; the panel is cheap to re-read on every open.
            language = .active

            if reduceMotion {
                contentOpacity = 1
            } else {
                withAnimation(.easeOut(duration: 0.18)) {
                    contentOpacity = 1
                }
            }
        }
    }

    private func languageRow(_ entry: SupportedLanguage) -> some View {
        let isActive = entry == language
        return Button {
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

                Spacer(minLength: 8)

                Text(entry.defaultLayout.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    /// Applies the language. The parent closes the panel on this callback (#241
    /// device feedback): the key grid changing layout underneath is a louder
    /// confirmation than a checkmark, and staying open cost the user a second
    /// trip to the close control before they could type.
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
            details: "language=\(entry.rawValue) layout=\(entry.defaultLayout.rawValue)"
        ))
        onLanguageChanged?(entry)
    }
}
