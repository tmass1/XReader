import SwiftUI
import Combine

class AppState: ObservableObject {
    @Published var currentURL: URL = URL(string: "https://x.com/home")!
    @Published var shouldRefresh: Bool = false
    @Published var shouldGoBack: Bool = false
    @Published var shouldGoForward: Bool = false
    @Published var zoomLevel: Double = 1.0
    @Published var forceDarkMode: Bool = false
    @Published var minimalMode: Bool = true
    @Published var isLoading: Bool = false
    @Published var pageTitle: String = "X Reader"
    @Published var showBookmarksPanel: Bool = false
    @Published var showAddBookmark: Bool = false
    
    func navigate(to urlString: String) {
        if let url = URL(string: urlString) {
            currentURL = url
        }
    }
}
