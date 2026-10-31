import SwiftUI
import Combine

enum ThemePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
    // Applied app-wide through NSApp.appearance rather than SwiftUI's preferredColorScheme,
    // which doesn't switch back to following macOS when set to nil at runtime. The web view
    // inherits it, and X follows prefers-color-scheme live.
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

class AppState: ObservableObject {
    static let homeURL = URL(string: "https://x.com/home")!

    // Last page and rail section are restored on the next launch.
    @Published var currentURL: URL {
        didSet {
            if Self.isRestorable(currentURL) {
                UserDefaults.standard.set(currentURL.absoluteString, forKey: "lastURL")
            }
        }
    }
    @Published var section: String {
        didSet { UserDefaults.standard.set(section, forKey: "section") }
    }
    @Published var shouldRefresh: Bool = false
    @Published var shouldGoBack: Bool = false
    @Published var shouldGoForward: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

    @Published var isLoading: Bool = false
    @Published var pageTitle: String = "X Reader"

    @Published var showBookmarksPanel: Bool = false
    @Published var showAddBookmark: Bool = false
    @Published var showSettings: Bool = false

    // Persisted settings
    @Published var themePreference: ThemePreference {
        didSet {
            UserDefaults.standard.set(themePreference.rawValue, forKey: "themePreference")
            NSApp.appearance = themePreference.appearance
        }
    }
    @Published var zoomLevel: Double {
        didSet { UserDefaults.standard.set(zoomLevel, forKey: "zoomLevel") }
    }
    @Published var minimalMode: Bool {
        didSet { UserDefaults.standard.set(minimalMode, forKey: "minimalMode") }
    }

    init() {
        let d = UserDefaults.standard
        let saved = d.string(forKey: "lastURL").flatMap(URL.init(string:))
        self.currentURL = saved.flatMap { Self.isRestorable($0) ? $0 : nil } ?? Self.homeURL
        self.section = d.string(forKey: "section") ?? "Home"
        self.themePreference = ThemePreference(rawValue: d.string(forKey: "themePreference") ?? "") ?? .system
        self.zoomLevel = d.object(forKey: "zoomLevel") as? Double ?? 1.0
        self.minimalMode = d.object(forKey: "minimalMode") as? Bool ?? true
        NSApplication.shared.appearance = themePreference.appearance
    }

    func navigate(to urlString: String) {
        if let url = URL(string: urlString) {
            currentURL = url
        }
    }

    // Sign-in flows and the chat PIN screen are one-off steps, not places to reopen.
    private static func isRestorable(_ url: URL) -> Bool {
        guard let host = url.host, host == "x.com" || host.hasSuffix(".x.com") else { return false }
        return !url.path.hasPrefix("/i/flow") && !url.path.hasPrefix("/i/chat/pin")
    }

    var unreadBadge: String? { Self.unreadBadge(in: pageTitle) }

    /// X prefixes its page title with the unread count, e.g. "(5) Home / X" or "(20+) Home / X".
    static func unreadBadge(in title: String) -> String? {
        guard title.hasPrefix("("), let close = title.firstIndex(of: ")") else { return nil }
        let count = String(title[title.index(after: title.startIndex)..<close])
        return count.first?.isNumber == true ? count : nil
    }
}
