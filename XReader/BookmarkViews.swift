import SwiftUI

// MARK: - Bookmarks Panel (shown in sidebar area)
struct BookmarksPanel: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var store: BookmarkStore
    @State private var selectedTag: String?
    @State private var editingBookmark: Bookmark?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Bookmarks")
                    .font(.headline)
                Spacer()
                Button(action: { appState.showBookmarksPanel = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Tag filter bar
            if !store.allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        TagChip(label: "All", isSelected: selectedTag == nil) {
                            selectedTag = nil
                        }
                        ForEach(store.allTags, id: \.self) { tag in
                            TagChip(label: tag, isSelected: selectedTag == tag) {
                                selectedTag = selectedTag == tag ? nil : tag
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                Divider()
            }

            // Bookmark list
            let filtered = store.filtered(by: selectedTag)
            if filtered.isEmpty {
                Spacer()
                Text("No bookmarks")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                Spacer()
            } else {
                List {
                    ForEach(filtered) { bookmark in
                        BookmarkRow(bookmark: bookmark, onTap: {
                            appState.navigate(to: bookmark.url)
                            appState.showBookmarksPanel = false
                        }, onEdit: {
                            editingBookmark = bookmark
                        })
                    }
                    .onDelete { indices in
                        let items = filtered
                        for index in indices {
                            store.remove(items[index])
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 280)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $editingBookmark) { bookmark in
            EditBookmarkSheet(store: store, bookmark: bookmark)
        }
    }
}

// MARK: - Bookmark Row
struct BookmarkRow: View {
    let bookmark: Bookmark
    let onTap: () -> Void
    let onEdit: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(bookmark.title.isEmpty ? bookmark.url : bookmark.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundColor(.primary)

                if !bookmark.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(bookmark.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                }

                Text(bookmark.url)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit Tags") { onEdit() }
            Button("Delete", role: .destructive) {}
        }
    }
}

// MARK: - Add Bookmark Sheet
struct AddBookmarkSheet: View {
    @ObservedObject var store: BookmarkStore
    let url: String
    let title: String
    @Environment(\.dismiss) var dismiss
    @State private var tagInput: String = ""
    @State private var selectedTags: [String] = []

    var body: some View {
        VStack(spacing: 16) {
            Text("Save Bookmark")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text(title.isEmpty ? "Untitled" : title)
                    .font(.subheadline)
                    .lineLimit(2)
                Text(url)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Existing tags to pick from
            if !store.allTags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Existing Tags")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(store.allTags, id: \.self) { tag in
                            TagChip(label: tag, isSelected: selectedTags.contains(tag)) {
                                if selectedTags.contains(tag) {
                                    selectedTags.removeAll { $0 == tag }
                                } else {
                                    selectedTags.append(tag)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // New tag input
            VStack(alignment: .leading, spacing: 6) {
                Text("Add New Tags")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    TextField("Tag name", text: $tagInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addTag() }
                    Button("Add") { addTag() }
                        .disabled(tagInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !selectedTags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(selectedTags, id: \.self) { tag in
                            HStack(spacing: 2) {
                                Text(tag)
                                    .font(.caption)
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(6)
                            .onTapGesture {
                                selectedTags.removeAll { $0 == tag }
                            }
                        }
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    store.add(url: url, title: title, tags: selectedTags)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func addTag() {
        let tag = tagInput.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !selectedTags.contains(tag) else { return }
        selectedTags.append(tag)
        tagInput = ""
    }
}

// MARK: - Edit Bookmark Sheet
struct EditBookmarkSheet: View {
    @ObservedObject var store: BookmarkStore
    let bookmark: Bookmark
    @Environment(\.dismiss) var dismiss
    @State private var tagInput: String = ""
    @State private var selectedTags: [String] = []

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Tags")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text(bookmark.title.isEmpty ? bookmark.url : bookmark.title)
                    .font(.subheadline)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !store.allTags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tags")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(store.allTags, id: \.self) { tag in
                            TagChip(label: tag, isSelected: selectedTags.contains(tag)) {
                                if selectedTags.contains(tag) {
                                    selectedTags.removeAll { $0 == tag }
                                } else {
                                    selectedTags.append(tag)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                TextField("New tag", text: $tagInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTag() }
                Button("Add") { addTag() }
                    .disabled(tagInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !selectedTags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(selectedTags, id: \.self) { tag in
                        HStack(spacing: 2) {
                            Text(tag)
                                .font(.caption)
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(6)
                        .onTapGesture {
                            selectedTags.removeAll { $0 == tag }
                        }
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    var updated = bookmark
                    updated.tags = selectedTags
                    store.update(updated)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear { selectedTags = bookmark.tags }
    }

    private func addTag() {
        let tag = tagInput.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !selectedTags.contains(tag) else { return }
        selectedTags.append(tag)
        tagInput = ""
    }
}

// MARK: - Tag Chip
struct TagChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.12))
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout (wrapping horizontal layout for tags)
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
