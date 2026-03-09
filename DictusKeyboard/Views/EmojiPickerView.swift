// DictusKeyboard/Views/EmojiPickerView.swift
import SwiftUI
import AudioToolbox
import DictusCore

/// The popup preview bubble shown above a pressed key (SwiftUI version).
/// Used by the mini search keyboard in the emoji picker.
struct KeyPopup: View {
    let label: String
    private let popupFontSize: CGFloat = 32

    var body: some View {
        Text(label)
            .font(.system(size: popupFontSize, weight: .regular))
            .foregroundStyle(.primary)
            .frame(width: 50, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(KeyMetrics.letterKeyColor)
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
            )
    }
}

/// Shared model for category bar items (recents + standard categories).
struct CategoryInfo: Identifiable {
    let id: String
    let name: String
    let icon: String
}

/// Full emoji picker matching Apple/SuperWhisper style:
/// - Search bar at top (pill shape)
/// - Single continuous horizontal LazyHGrid (4 rows, swipe left/right)
/// - Category bar at bottom as bookmarks into the grid
struct EmojiPickerView: View {
    let onEmojiInsert: (String) -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    @State private var recentEmojis: [String] = []
    @State private var selectedCategoryID: String = "smileys"
    @State private var scrollToken: Int = 0
    @State private var isSearchActive: Bool = false
    @State private var searchText: String = ""
    @State private var showCursor: Bool = true
    @State private var filteredEmojis: [String] = []
    @State private var searchTask: Task<Void, Never>? = nil

    private let categories = EmojiStore.categories
    private let gridRows = Array(repeating: GridItem(.fixed(46), spacing: 2), count: 4)

    /// Dynamic cell width: exactly 8 emojis per row on any device.
    /// (screenWidth - 4pt grid padding) / 8
    private var emojiCellWidth: CGFloat {
        (UIScreen.main.bounds.width - 4) / 8
    }

    // MARK: - Computed data

    private var flatItems: [EmojiGridItem] {
        var items: [EmojiGridItem] = []
        for (i, emoji) in recentEmojis.enumerated() {
            items.append(EmojiGridItem(id: "recents_\(i)", emoji: emoji, categoryID: "recents"))
        }
        for cat in categories {
            for (i, emoji) in cat.emojis.enumerated() {
                items.append(EmojiGridItem(id: "\(cat.id)_\(i)", emoji: emoji, categoryID: cat.id))
            }
        }
        return items
    }

    private var categoryFirstIDs: [String: String] {
        var result: [String: String] = [:]
        if !recentEmojis.isEmpty { result["recents"] = "recents_0" }
        for cat in categories where !cat.emojis.isEmpty {
            result[cat.id] = "\(cat.id)_0"
        }
        return result
    }

    private var sectionInfos: [CategoryInfo] {
        var infos: [CategoryInfo] = []
        if !recentEmojis.isEmpty {
            infos.append(CategoryInfo(id: "recents", name: "Récents", icon: "clock"))
        }
        for cat in categories {
            infos.append(CategoryInfo(id: cat.id, name: cat.name, icon: cat.icon))
        }
        return infos
    }

    /// Display name for the currently selected category.
    private var selectedCategoryName: String {
        sectionInfos.first(where: { $0.id == selectedCategoryID })?.name.uppercased() ?? ""
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if isSearchActive {
                searchMode
            } else {
                normalMode
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            recentEmojis = RecentEmojis.load()
            if !recentEmojis.isEmpty {
                selectedCategoryID = "recents"
            }
        }
    }

    // MARK: - Normal mode

    @ViewBuilder
    private var normalMode: some View {
        // Category name label (e.g. "SMILEYS & PEOPLE")
        HStack {
            Text(selectedCategoryName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 2)

        // Continuous horizontal emoji grid (4 rows, 8 per row)
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: gridRows, alignment: .top, spacing: 0) {
                    ForEach(flatItems) { item in
                        Button {
                            HapticFeedback.keyTapped()
                            onEmojiInsert(item.emoji)
                            RecentEmojis.add(item.emoji)
                        } label: {
                            Text(item.emoji)
                                .font(.system(size: 34))
                                .frame(width: emojiCellWidth, height: 46)
                        }
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 2)
            }
            .onChange(of: scrollToken) { _ in
                if let firstID = categoryFirstIDs[selectedCategoryID] {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(firstID, anchor: .leading)
                    }
                }
            }
        }

        EmojiCategoryBar(
            sections: sectionInfos,
            selectedCategoryID: selectedCategoryID,
            onSelectCategory: { id in
                selectedCategoryID = id
                scrollToken += 1
            },
            onSearch: { isSearchActive = true },
            onDelete: onDelete,
            onDismiss: onDismiss
        )
    }

    // MARK: - Search mode

    @ViewBuilder
    private var searchMode: some View {
        // Search input bar
        searchInputBar
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 2)

        // Emoji row: recents when empty, results when searching.
        // Apple always shows emojis here — recents if nothing typed, or all emojis
        // sorted by last usage if no recents exist (row is never empty).
        let emojiRow = searchModeEmojis
        if emojiRow.isEmpty {
            Text("Aucun résultat")
                .foregroundColor(.secondary)
                .font(.system(size: 14))
                .frame(height: 48)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(emojiRow.enumerated()), id: \.offset) { _, emoji in
                        Button {
                            HapticFeedback.keyTapped()
                            onEmojiInsert(emoji)
                            RecentEmojis.add(emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 34))
                                .frame(width: emojiCellWidth, height: 46)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 48)
        }

        Spacer(minLength: 0)

        EquatableView(content: MiniSearchKeyboard(
            onCharacter: { searchText.append($0) },
            onDelete: { if !searchText.isEmpty { searchText.removeLast() } },
            onSpace: { searchText.append(" ") }
        ))
        .onChange(of: searchText) { newValue in
            searchTask?.cancel()
            if newValue.isEmpty {
                filteredEmojis = []
                return
            }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms debounce
                guard !Task.isCancelled else { return }
                let results = performSearch(query: newValue)
                guard !Task.isCancelled else { return }
                filteredEmojis = results
            }
        }
    }

    /// Search bar for search mode with cursor.
    private var searchInputBar: some View {
        let barWidth = UIScreen.main.bounds.width - 16 // 8pt margin each side
        return HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .padding(.trailing, 6)

            // Cursor at the start, then text or placeholder
            if searchText.isEmpty {
                blinkingCursor
                Text("Rechercher des Emoji")
                    .foregroundColor(.secondary)
            } else {
                Text(searchText)
                    .foregroundColor(.primary)
                blinkingCursor
            }

            Spacer(minLength: 0)

            // × button: clears text if any, closes search if empty
            Button {
                if searchText.isEmpty {
                    isSearchActive = false
                } else {
                    searchText = ""
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(width: barWidth)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.systemGray6))
        )
    }

    private var blinkingCursor: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 2, height: 18)
            .opacity(showCursor ? 1 : 0)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: showCursor)
            .onAppear { showCursor.toggle() }
    }

    /// Emojis to show in search mode row.
    /// When nothing typed: recents (or first emojis from catalog if no recents).
    /// When searching: debounced filtered results.
    private var searchModeEmojis: [String] {
        if searchText.isEmpty {
            if recentEmojis.isEmpty {
                return Array(EmojiStore.allEmojis.prefix(30))
            }
            return recentEmojis
        }
        return filteredEmojis
    }

    // MARK: - Search logic (debounced, pre-computed names)

    private func performSearch(query: String) -> [String] {
        let q = query.lowercased()
        let language = AppGroup.defaults.string(forKey: SharedKeys.language) ?? "fr"

        if language == "fr" {
            return searchFrench(query: q)
        } else {
            return searchUnicodeName(query: q)
        }
    }

    private func searchFrench(query: String) -> [String] {
        var results: [String] = []
        var seen = Set<String>()

        for (keyword, emojis) in EmojiSearchFR.keywords {
            if keyword.contains(query) {
                for emoji in emojis where !seen.contains(emoji) {
                    results.append(emoji)
                    seen.insert(emoji)
                }
            }
        }

        // Fallback to pre-computed Unicode names
        for entry in EmojiStore.allEmojiNames where !seen.contains(entry.emoji) {
            if entry.name.contains(query) {
                results.append(entry.emoji)
                seen.insert(entry.emoji)
            }
        }
        return results
    }

    private func searchUnicodeName(query: String) -> [String] {
        EmojiStore.allEmojiNames
            .filter { $0.name.contains(query) }
            .map { $0.emoji }
    }
}

// MARK: - Supporting types

private struct EmojiGridItem: Identifiable {
    let id: String
    let emoji: String
    let categoryID: String
}

/// Mini keyboard for emoji search with key popups and haptic feedback.
/// Uses 40pt key height to fit within the emoji picker without clipping.
/// Equatable to prevent re-renders when search text changes (layout is static).
private struct MiniSearchKeyboard: View, Equatable {
    let onCharacter: (String) -> Void
    let onDelete: () -> Void
    let onSpace: () -> Void

    static func == (lhs: MiniSearchKeyboard, rhs: MiniSearchKeyboard) -> Bool {
        true // Layout never changes, only closures differ
    }

    private let keyHeight: CGFloat = 40

    private var rows: [[String]] {
        switch LayoutType.active {
        case .azerty:
            return [
                ["a", "z", "e", "r", "t", "y", "u", "i", "o", "p"],
                ["q", "s", "d", "f", "g", "h", "j", "k", "l", "m"],
                ["w", "x", "c", "v", "b", "n"]
            ]
        case .qwerty:
            return [
                ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
                ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
                ["z", "x", "c", "v", "b", "n", "m"]
            ]
        }
    }

    var body: some View {
        VStack(spacing: 5) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { letter in
                        MiniKeyButton(label: letter, height: keyHeight) {
                            HapticFeedback.keyTapped()
                            AudioServicesPlaySystemSound(1104)
                            onCharacter(letter)
                        }
                    }
                    if rowIndex == 2 {
                        Button {
                            HapticFeedback.keyTapped()
                            AudioServicesPlaySystemSound(1155)
                            onDelete()
                        } label: {
                            Image(systemName: "delete.backward")
                                .font(.system(size: 18))
                                .frame(maxWidth: .infinity)
                                .frame(height: keyHeight)
                                .background(KeyMetrics.letterKeyColor)
                                .cornerRadius(KeyMetrics.keyCornerRadius)
                        }
                        .foregroundColor(Color(.label))
                    }
                }
            }
            Button {
                HapticFeedback.keyTapped()
                AudioServicesPlaySystemSound(1156)
                onSpace()
            } label: {
                Text("espace")
                    .font(.system(size: 16))
                    .frame(maxWidth: .infinity)
                    .frame(height: keyHeight)
                    .background(KeyMetrics.letterKeyColor)
                    .cornerRadius(KeyMetrics.keyCornerRadius)
            }
            .foregroundColor(Color(.label))
        }
        .padding(.horizontal, KeyMetrics.rowHorizontalPadding)
        .padding(.bottom, 4)
    }
}

/// A single key in the mini search keyboard with press popup.
/// Uses a lightweight ButtonStyle instead of DragGesture for better performance.
private struct MiniKeyButton: View {
    let label: String
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 22))
                .foregroundColor(Color(.label))
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(KeyMetrics.letterKeyColor)
                .cornerRadius(KeyMetrics.keyCornerRadius)
        }
        .buttonStyle(MiniKeyButtonStyle(label: label, height: height))
    }
}

private struct MiniKeyButtonStyle: ButtonStyle {
    let label: String
    let height: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                Group {
                    if configuration.isPressed {
                        KeyPopup(label: label)
                            .offset(y: -(height + 8))
                    }
                },
                alignment: .top
            )
    }
}
