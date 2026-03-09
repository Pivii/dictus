// DictusKeyboard/Views/EmojiPickerView.swift
import SwiftUI
import AudioToolbox
import DictusCore

/// Shared model for category bar items (recents + standard categories).
struct CategoryInfo: Identifiable {
    let id: String
    let icon: String
}

/// Full emoji picker matching Apple/SuperWhisper style:
/// - Search bar at top
/// - Single continuous horizontal LazyHGrid (4 rows, swipe left/right)
/// - Category bar at bottom as bookmarks into the grid
///
/// WHY continuous grid instead of TabView pages:
/// Apple and Super Whisper treat all emojis as one long strip. Categories
/// in the bottom bar are shortcuts to jump within that strip, not separate pages.
/// Recents appear first, followed by smileys, people, etc. in one flow.
struct EmojiPickerView: View {
    let onEmojiInsert: (String) -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    /// Loaded once on appear, NOT updated live (avoids emoji "holes" mid-session).
    @State private var recentEmojis: [String] = []
    @State private var selectedCategoryID: String = "smileys"
    @State private var scrollToken: Int = 0
    @State private var isSearchActive: Bool = false
    @State private var searchText: String = ""

    private let categories = EmojiStore.categories
    private let gridRows = Array(repeating: GridItem(.fixed(42), spacing: 2), count: 4)

    // MARK: - Computed data

    /// Flat list of all emoji items: recents first, then each category in order.
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

    /// First emoji ID per category (for ScrollViewReader bookmark scrolling).
    private var categoryFirstIDs: [String: String] {
        var result: [String: String] = [:]
        if !recentEmojis.isEmpty { result["recents"] = "recents_0" }
        for cat in categories where !cat.emojis.isEmpty {
            result[cat.id] = "\(cat.id)_0"
        }
        return result
    }

    /// Ordered list of sections for the category bar.
    private var sectionInfos: [CategoryInfo] {
        var infos: [CategoryInfo] = []
        if !recentEmojis.isEmpty {
            infos.append(CategoryInfo(id: "recents", icon: "clock"))
        }
        for cat in categories {
            infos.append(CategoryInfo(id: cat.id, icon: cat.icon))
        }
        return infos
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
        .onAppear {
            recentEmojis = RecentEmojis.load()
            if !recentEmojis.isEmpty {
                selectedCategoryID = "recents"
            }
        }
    }

    // MARK: - Normal mode (grid + category bar)

    @ViewBuilder
    private var normalMode: some View {
        // Search bar button
        Button { isSearchActive = true } label: {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                Text("Rechercher des Emoji")
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(.tertiarySystemFill))
            .cornerRadius(10)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 4)

        // Continuous horizontal emoji grid (4 rows)
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: gridRows, alignment: .top, spacing: 0) {
                    ForEach(flatItems) { item in
                        Button {
                            onEmojiInsert(item.emoji)
                            RecentEmojis.add(item.emoji)
                        } label: {
                            Text(item.emoji)
                                .font(.system(size: 32))
                                .frame(width: 44, height: 42)
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

        // Category bar (bookmarks)
        EmojiCategoryBar(
            sections: sectionInfos,
            selectedCategoryID: selectedCategoryID,
            onSelectCategory: { id in
                selectedCategoryID = id
                scrollToken += 1
            },
            onDelete: onDelete,
            onDismiss: onDismiss
        )
    }

    // MARK: - Search mode

    @ViewBuilder
    private var searchMode: some View {
        // Search input
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                Text(searchText.isEmpty ? "Rechercher des Emoji" : searchText)
                    .foregroundColor(searchText.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color(.tertiarySystemFill))
            .cornerRadius(10)

            Button("Annuler") {
                isSearchActive = false
                searchText = ""
            }
            .foregroundColor(.accentColor)
            .font(.system(size: 15))
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)

        // Search results
        let results = searchResults
        if searchText.isEmpty {
            Spacer()
        } else if results.isEmpty {
            Spacer()
            Text("Aucun résultat")
                .foregroundColor(.secondary)
                .font(.system(size: 15))
            Spacer()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(
                    rows: Array(repeating: GridItem(.fixed(42)), count: 2),
                    spacing: 0
                ) {
                    ForEach(results, id: \.self) { emoji in
                        Button {
                            onEmojiInsert(emoji)
                            RecentEmojis.add(emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 32))
                                .frame(width: 44, height: 42)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 88)
        }

        // Mini AZERTY keyboard for typing search queries
        MiniSearchKeyboard(
            onCharacter: { searchText.append($0) },
            onDelete: { if !searchText.isEmpty { searchText.removeLast() } },
            onSpace: { searchText.append(" ") }
        )
    }

    // MARK: - Search logic

    /// Filter emojis by Unicode name matching the search query.
    private var searchResults: [String] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        return EmojiStore.allEmojis.filter { emoji in
            guard let name = emoji.applyingTransform(.toUnicodeName, reverse: false) else {
                return false
            }
            return name.lowercased().contains(query)
        }
    }
}

// MARK: - Supporting types

/// A single emoji in the flat grid with its category membership.
private struct EmojiGridItem: Identifiable {
    let id: String
    let emoji: String
    let categoryID: String
}

/// Compact AZERTY keyboard for typing emoji search queries.
/// Self-contained within the emoji picker — no need to route through
/// the main keyboard's textDocumentProxy.
private struct MiniSearchKeyboard: View {
    let onCharacter: (String) -> Void
    let onDelete: () -> Void
    let onSpace: () -> Void

    private let rows: [[String]] = [
        ["a", "z", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["q", "s", "d", "f", "g", "h", "j", "k", "l", "m"],
        ["w", "x", "c", "v", "b", "n"]
    ]

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 3) {
                    ForEach(row, id: \.self) { letter in
                        Button {
                            AudioServicesPlaySystemSound(1104)
                            onCharacter(letter)
                        } label: {
                            Text(letter)
                                .font(.system(size: 18))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(KeyMetrics.letterKeyColor)
                                .cornerRadius(5)
                        }
                        .foregroundColor(Color(.label))
                    }
                    if rowIndex == 2 {
                        Button {
                            AudioServicesPlaySystemSound(1155)
                            onDelete()
                        } label: {
                            Image(systemName: "delete.backward")
                                .font(.system(size: 16))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(KeyMetrics.letterKeyColor)
                                .cornerRadius(5)
                        }
                        .foregroundColor(Color(.label))
                    }
                }
            }
            // Space bar
            Button {
                AudioServicesPlaySystemSound(1156)
                onSpace()
            } label: {
                Text("espace")
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(KeyMetrics.letterKeyColor)
                    .cornerRadius(5)
            }
            .foregroundColor(Color(.label))
        }
        .padding(.horizontal, 3)
        .padding(.bottom, 2)
    }
}
