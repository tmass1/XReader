import SwiftUI

// MARK: - Bookmarks Panel (Tidy-styled)

struct BookmarksPanel: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var store: BookmarkStore
    @State private var selectedTag: String?
    @State private var editingBookmark: Bookmark?
    @State private var isCloseHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("Bookmarks")
                    .font(TidyTheme.body(.semibold))
                    .foregroundColor(TidyTheme.text)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        appState.showBookmarksPanel = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isCloseHovered ? TidyTheme.text : TidyTheme.textSecondary)
                        .frame(width: TidyTheme.controlSmall, height: TidyTheme.controlSmall)
                        .background(
                            RoundedRectangle(cornerRadius: TidyTheme.radiusAction, style: .continuous)
                                .fill(isCloseHovered ? TidyTheme.surfaceHover : .clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { h in
                    withAnimation(.easeOut(duration: 0.12)) { isCloseHovered = h }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

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
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }

            Rectangle()
                .fill(TidyTheme.borderDefault)
                .frame(height: 1)

            let filtered = store.filtered(by: selectedTag)
            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(TidyTheme.textDisabled)
                    Text("No bookmarks yet")
                        .font(TidyTheme.label())
                        .foregroundColor(TidyTheme.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { bookmark in
                            BookmarkRow(
                                bookmark: bookmark,
                                onTap: {
                                    appState.navigate(to: bookmark.url)
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        appState.showBookmarksPanel = false
                                    }
                                },
                                onEdit: { editingBookmark = bookmark },
                                onDelete: { store.remove(bookmark) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
            }
        }
        .frame(width: 300)
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
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(bookmark.title.isEmpty ? bookmark.url : bookmark.title)
                    .font(TidyTheme.label(.medium))
                    .foregroundColor(TidyTheme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !bookmark.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(bookmark.tags, id: \.self) { tag in
                            Text(tag)
                                .font(TidyTheme.caption(.medium))
                                .foregroundColor(TidyTheme.accentForeground)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: TidyTheme.radiusChip, style: .continuous)
                                        .fill(TidyTheme.accentBackground)
                                )
                        }
                    }
                }

                Text(prettyURL(bookmark.url))
                    .font(TidyTheme.caption())
                    .foregroundColor(TidyTheme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: TidyTheme.radiusAction, style: .continuous)
                    .fill(isHovered ? TidyTheme.surfaceHover : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: TidyTheme.radiusAction, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.1)) { isHovered = h }
        }
        .contextMenu {
            Button("Edit Tags") { onEdit() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private func prettyURL(_ s: String) -> String {
        guard let u = URL(string: s), let host = u.host else { return s }
        let p = u.path.isEmpty ? "" : u.path
        return host.replacingOccurrences(of: "www.", with: "") + p
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
        VStack(alignment: .leading, spacing: 20) {
            Text("Save Bookmark")
                .font(TidyTheme.headingMedium())
                .foregroundColor(TidyTheme.text)

            VStack(alignment: .leading, spacing: 4) {
                Text(title.isEmpty ? "Untitled" : title)
                    .font(TidyTheme.label(.medium))
                    .foregroundColor(TidyTheme.text)
                    .lineLimit(2)
                Text(url)
                    .font(TidyTheme.caption())
                    .foregroundColor(TidyTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: TidyTheme.radiusControl, style: .continuous)
                    .fill(TidyTheme.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TidyTheme.radiusControl, style: .continuous)
                    .stroke(TidyTheme.borderDefault, lineWidth: 1)
            )

            if !store.allTags.isEmpty {
                SectionLabel("Pick tags")
                FlowLayout(spacing: 6) {
                    ForEach(store.allTags, id: \.self) { tag in
                        TagChip(label: tag, isSelected: selectedTags.contains(tag)) {
                            toggle(tag)
                        }
                    }
                }
            }

            SectionLabel("Add new tag")
            HStack(spacing: 8) {
                TidyTextField(placeholder: "Tag name", text: $tagInput)
                    .onSubmit { addTag() }
                TidyButton(
                    title: "Add",
                    kind: .secondary,
                    disabled: tagInput.trimmingCharacters(in: .whitespaces).isEmpty
                ) { addTag() }
            }

            if !selectedTags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(selectedTags, id: \.self) { tag in
                        RemovableTagChip(label: tag) { toggle(tag) }
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                TidyButton(title: "Cancel", kind: .ghost) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                TidyButton(title: "Save", kind: .primary) {
                    store.add(url: url, title: title, tags: selectedTags)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(TidyTheme.surface)
    }

    private func toggle(_ tag: String) {
        if selectedTags.contains(tag) { selectedTags.removeAll { $0 == tag } }
        else { selectedTags.append(tag) }
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
        VStack(alignment: .leading, spacing: 20) {
            Text("Edit Tags")
                .font(TidyTheme.headingMedium())
                .foregroundColor(TidyTheme.text)

            VStack(alignment: .leading, spacing: 4) {
                Text(bookmark.title.isEmpty ? "Untitled" : bookmark.title)
                    .font(TidyTheme.label(.medium))
                    .foregroundColor(TidyTheme.text)
                    .lineLimit(2)
                Text(bookmark.url)
                    .font(TidyTheme.caption())
                    .foregroundColor(TidyTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: TidyTheme.radiusControl, style: .continuous)
                    .fill(TidyTheme.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TidyTheme.radiusControl, style: .continuous)
                    .stroke(TidyTheme.borderDefault, lineWidth: 1)
            )

            if !store.allTags.isEmpty {
                SectionLabel("All tags")
                FlowLayout(spacing: 6) {
                    ForEach(store.allTags, id: \.self) { tag in
                        TagChip(label: tag, isSelected: selectedTags.contains(tag)) {
                            toggle(tag)
                        }
                    }
                }
            }

            SectionLabel("Add new tag")
            HStack(spacing: 8) {
                TidyTextField(placeholder: "Tag name", text: $tagInput)
                    .onSubmit { addTag() }
                TidyButton(
                    title: "Add",
                    kind: .secondary,
                    disabled: tagInput.trimmingCharacters(in: .whitespaces).isEmpty
                ) { addTag() }
            }

            if !selectedTags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(selectedTags, id: \.self) { tag in
                        RemovableTagChip(label: tag) { toggle(tag) }
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                TidyButton(title: "Cancel", kind: .ghost) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                TidyButton(title: "Save", kind: .primary) {
                    var updated = bookmark
                    updated.tags = selectedTags
                    store.update(updated)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(TidyTheme.surface)
        .onAppear { selectedTags = bookmark.tags }
    }

    private func toggle(_ tag: String) {
        if selectedTags.contains(tag) { selectedTags.removeAll { $0 == tag } }
        else { selectedTags.append(tag) }
    }

    private func addTag() {
        let tag = tagInput.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !selectedTags.contains(tag) else { return }
        selectedTags.append(tag)
        tagInput = ""
    }
}

// MARK: - Shared Tidy controls

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(TidyTheme.labelSmall(.medium))
            .foregroundColor(TidyTheme.textSecondary)
    }
}

struct TagChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(TidyTheme.caption(.medium))
                .foregroundColor(
                    isSelected ? TidyTheme.accentForeground
                    : (isHovered ? TidyTheme.text : TidyTheme.textSecondary)
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: TidyTheme.radiusChip, style: .continuous)
                        .fill(
                            isSelected ? TidyTheme.accentBackground
                            : (isHovered ? TidyTheme.surfaceHover : TidyTheme.surfaceSubtle)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: TidyTheme.radiusChip, style: .continuous)
                        .stroke(TidyTheme.borderDefault, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.1)) { isHovered = h }
        }
    }
}

private struct RemovableTagChip: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 5) {
                Text(label)
                    .font(TidyTheme.caption(.medium))
                    .foregroundColor(TidyTheme.accentForeground)
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(TidyTheme.accentForeground.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: TidyTheme.radiusChip, style: .continuous)
                    .fill(TidyTheme.accentBackground)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TidyTextField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .font(TidyTheme.label())
            .foregroundColor(TidyTheme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: TidyTheme.radiusControl, style: .continuous)
                    .fill(TidyTheme.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TidyTheme.radiusControl, style: .continuous)
                    .stroke(
                        focused ? TidyTheme.accentForeground : TidyTheme.borderDefault,
                        lineWidth: focused ? 1.5 : 1
                    )
            )
    }
}

private struct TidyButton: View {
    enum Kind { case primary, secondary, ghost, destructive }
    let title: String
    var kind: Kind = .primary
    var disabled: Bool = false
    let action: () -> Void
    @State private var isHovered = false
    @State private var isPressed = false

    private var fg: Color {
        switch kind {
        case .primary:      return TidyTheme.textOnAction
        case .secondary:    return TidyTheme.text
        case .ghost:        return TidyTheme.textSecondary
        case .destructive:  return .white
        }
    }
    private var bg: Color {
        switch kind {
        case .primary:
            if isPressed { return TidyTheme.actionPressed }
            if isHovered { return TidyTheme.actionHover }
            return TidyTheme.actionDefault
        case .secondary:
            if isHovered { return TidyTheme.surfaceHover }
            return TidyTheme.surfaceSubtle
        case .ghost:
            if isHovered { return TidyTheme.surfaceHover }
            return .clear
        case .destructive:
            if isHovered { return TidyTheme.negativeText.opacity(0.9) }
            return TidyTheme.negativeText
        }
    }
    private var border: Color {
        switch kind {
        case .secondary: return TidyTheme.borderDefault
        default: return .clear
        }
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(TidyTheme.label(.semibold))
                .foregroundColor(fg)
                .padding(.horizontal, 14)
                .frame(height: TidyTheme.controlMedium - 4)
                .background(
                    RoundedRectangle(cornerRadius: TidyTheme.radiusAction, style: .continuous)
                        .fill(bg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: TidyTheme.radiusAction, style: .continuous)
                        .stroke(border, lineWidth: 1)
                )
                .opacity(disabled ? 0.45 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.1)) { isHovered = h }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
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
