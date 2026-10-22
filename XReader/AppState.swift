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
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

class AppState: ObservableObject {
    @Published var currentURL: URL = URL(string: "https://x.com/home")!
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
        }
    }
    @Published var zoomLevel: Double {
        didSet { UserDefaults.standard.set(zoomLevel, forKey: "zoomLevel") }
    }
    @Published var minimalMode: Bool {
        didSet { UserDefaults.standard.set(minimalMode, forKey: "minimalMode") }
    }
    @Published var forceDarkMode: Bool {
        didSet { UserDefaults.standard.set(forceDarkMode, forKey: "forceDarkMode") }
    }

    init() {
        let d = UserDefaults.standard
        self.themePreference = ThemePreference(rawValue: d.string(forKey: "themePreference") ?? "") ?? .system
        self.zoomLevel = d.object(forKey: "zoomLevel") as? Double ?? 1.0
        self.minimalMode = d.object(forKey: "minimalMode") as? Bool ?? true
        self.forceDarkMode = d.object(forKey: "forceDarkMode") as? Bool ?? false
    }

    func navigate(to urlString: String) {
        if let url = URL(string: urlString) {
            currentURL = url
        }
    }
}
