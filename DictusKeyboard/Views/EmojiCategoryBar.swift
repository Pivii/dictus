// DictusKeyboard/Views/EmojiCategoryBar.swift
import SwiftUI
import AudioToolbox
import DictusCore

/// Bottom bar for emoji picker matching Apple/SuperWhisper style:
/// ABC button (left) | search icon | category icons (center) | delete button (right).
/// Icons act as bookmarks into the continuous horizontal emoji grid.
struct EmojiCategoryBar: View {
    let sections: [CategoryInfo]
    let selectedCategoryID: String
    let onSelectCategory: (String) -> Void
    let onSearch: () -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // ABC button — return to letter keyboard
            Button {
                onDismiss()
            } label: {
                Text("ABC")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(.label))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }

            // Search button
            Button {
                HapticFeedback.keyTapped()
                onSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17))
                    .foregroundColor(Color(.label))
                    .frame(width: 28, height: 28)
            }

            // Category icons
            HStack(spacing: 12) {
                ForEach(sections) { section in
                    let isSelected = selectedCategoryID == section.id
                    Button {
                        onSelectCategory(section.id)
                    } label: {
                        Image(systemName: section.icon)
                            .font(.system(size: 17))
                            .foregroundColor(isSelected ? Color(.label) : Color(.tertiaryLabel))
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(isSelected ? Color(.systemGray4) : Color.clear)
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Delete button
            Button {
                HapticFeedback.keyTapped()
                AudioServicesPlaySystemSound(KeySound.delete)
                onDelete()
            } label: {
                Image(systemName: "delete.backward")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Color(.label))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
        .frame(height: 40)
    }
}
