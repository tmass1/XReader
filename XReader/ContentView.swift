import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var bookmarkStore = BookmarkStore()

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(bookmarkStore: bookmarkStore)
            Divider()
            VStack(spacing: 0) {
                if appState.isLoading {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(height: 2)
                }
                XWebView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if appState.showBookmarksPanel {
                Divider()
                BookmarksPanel(store: bookmarkStore)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $appState.showAddBookmark) {
            AddBookmarkSheet(
                store: bookmarkStore,
                url: appState.currentURL.absoluteString,
                title: appState.pageTitle
            )
        }
    }
}

// MARK: - Icon-only Sidebar (matches X left nav)
struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var bookmarkStore: BookmarkStore

    var body: some View {
        VStack(spacing: 0) {
            // X logo
            NavIcon(icon: "xmark", size: 15, weight: .heavy, tooltip: "X") {
                appState.navigate(to: "https://x.com/home")
            }
            .padding(.top, 14)
            .padding(.bottom, 4)

            VStack(spacing: 0) {
                NavIcon(icon: "house.fill", size: 18, weight: .light, tooltip: "Home") {
                    appState.navigate(to: "https://x.com/home")
                }
                NavIcon(icon: "number", size: 18, weight: .light, tooltip: "Explore") {
                    appState.navigate(to: "https://x.com/explore")
                }
                NavIcon(icon: "bell", size: 18, weight: .light, tooltip: "Notifications") {
                    appState.navigate(to: "https://x.com/notifications")
                }
                NavIcon(icon: "arrow.2.squarepath", size: 18, weight: .light, tooltip: "Communities") {
                    appState.navigate(to: "https://x.com/communities")
                }
                NavIcon(icon: "envelope", size: 18, weight: .light, tooltip: "Messages") {
                    appState.navigate(to: "https://x.com/messages")
                }
                NavIcon(icon: "bookmark", size: 18, weight: .light, tooltip: "X Bookmarks") {
                    appState.navigate(to: "https://x.com/i/bookmarks")
                }
                NavIcon(icon: "list.bullet", size: 18, weight: .light, tooltip: "Lists") {
                    appState.navigate(to: "https://x.com/lists")
                }
                NavIcon(icon: "person.crop.circle", size: 18, weight: .light, tooltip: "Profile") {
                    appState.navigate(to: "https://x.com/profile")
                }
                NavIcon(icon: "face.smiling", size: 18, weight: .light, tooltip: "More") {
                    appState.navigate(to: "https://x.com/settings")
                }
            }

            Spacer()

            // Local bookmark actions
            Divider()
                .padding(.horizontal, 8)

            NavIcon(
                icon: bookmarkStore.isBookmarked(url: appState.currentURL.absoluteString)
                    ? "bookmark.fill" : "bookmark.badge.plus",
                size: 16,
                weight: .regular,
                tooltip: "Save Bookmark"
            ) {
                appState.showAddBookmark = true
            }

            NavIcon(
                icon: "tray.full",
                size: 16,
                weight: .regular,
                tooltip: "My Bookmarks"
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.showBookmarksPanel.toggle()
                }
            }
            .padding(.bottom, 12)
        }
        .frame(width: 48)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Nav Icon
struct NavIcon: View {
    let icon: String
    var size: CGFloat = 18
    var weight: Font.Weight = .light
    let tooltip: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: weight))
                .foregroundColor(.primary.opacity(isHovered ? 1.0 : 0.85))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}
