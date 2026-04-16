import SwiftUI
import Combine

struct Bookmark: Identifiable, Codable, Equatable {
    let id: UUID
    var url: String
    var title: String
    var tags: [String]
    var dateAdded: Date

    init(url: String, title: String, tags: [String] = []) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.tags = tags
        self.dateAdded = Date()
    }
}

class BookmarkStore: ObservableObject {
    @Published var bookmarks: [Bookmark] = []

    private var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("XReader", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("bookmarks.json")
    }

    var allTags: [String] {
        Array(Set(bookmarks.flatMap { $0.tags })).sorted()
    }

    init() {
        load()
    }

    func add(url: String, title: String, tags: [String]) {
        let cleaned = tags.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let bookmark = Bookmark(url: url, title: title, tags: cleaned)
        bookmarks.insert(bookmark, at: 0)
        save()
    }

    func remove(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        save()
    }

    func update(_ bookmark: Bookmark) {
        if let idx = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[idx] = bookmark
            save()
        }
    }

    func isBookmarked(url: String) -> Bool {
        bookmarks.contains { $0.url == url }
    }

    func filtered(by tag: String?) -> [Bookmark] {
        guard let tag = tag else { return bookmarks }
        return bookmarks.filter { $0.tags.contains(tag) }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(bookmarks)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("BookmarkStore save error: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            bookmarks = try JSONDecoder().decode([Bookmark].self, from: data)
        } catch {
            print("BookmarkStore load error: \(error)")
        }
    }
}
