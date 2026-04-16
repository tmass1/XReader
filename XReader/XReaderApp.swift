import SwiftUI

@main
struct XReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 480, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {} // Remove "New Window"
            
            CommandMenu("Navigation") {
                Button("Home Feed") {
                    appState.navigate(to: "https://x.com/home")
                }
                .keyboardShortcut("1", modifiers: .command)
                
                Button("X Bookmarks") {
                    appState.navigate(to: "https://x.com/i/bookmarks")
                }
                .keyboardShortcut("2", modifiers: .command)
                
                Button("Notifications") {
                    appState.navigate(to: "https://x.com/notifications")
                }
                .keyboardShortcut("3", modifiers: .command)
                
                Button("Messages") {
                    appState.navigate(to: "https://x.com/messages")
                }
                .keyboardShortcut("4", modifiers: .command)
                
                Divider()
                
                Button("Refresh") {
                    appState.shouldRefresh = true
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Button("Back") {
                    appState.shouldGoBack = true
                }
                .keyboardShortcut("[", modifiers: .command)
                
                Button("Forward") {
                    appState.shouldGoForward = true
                }
                .keyboardShortcut("]", modifiers: .command)

                Divider()

                Button("Save Bookmark") {
                    appState.showAddBookmark = true
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("My Bookmarks") {
                    appState.showBookmarksPanel.toggle()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }
            
            CommandMenu("View") {
                Button("Zoom In") {
                    appState.zoomLevel = min(appState.zoomLevel + 0.1, 2.0)
                }
                .keyboardShortcut("+", modifiers: .command)
                
                Button("Zoom Out") {
                    appState.zoomLevel = max(appState.zoomLevel - 0.1, 0.5)
                }
                .keyboardShortcut("-", modifiers: .command)
                
                Button("Actual Size") {
                    appState.zoomLevel = 1.0
                }
                .keyboardShortcut("0", modifiers: .command)
                
                Divider()
                
                Toggle("Minimal Mode", isOn: $appState.minimalMode)
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {

    }
}
