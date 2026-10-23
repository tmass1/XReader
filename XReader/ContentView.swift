import SwiftUI
import AppKit

// MARK: - Tidy Design Tokens
// Values from the Tidy UI token explorer. Light-first, neutral actions,
// lavender reserved for selection and focus.

enum TidyTheme {
    // Surfaces
    static let canvas          = dynamicColor(light: "F0EFF5", dark: "1E1C24")
    static let surface         = dynamicColor(light: "FCFCFF", dark: "26252E")
    static let surfaceSubtle   = dynamicColor(light: "F7F6FB", dark: "2B2934")
    static let surfaceRaised   = dynamicColor(light: "F9F8FD", dark: "2C2935")
    static let surfaceHover    = dynamicColor(light: "ECEBF4", dark: "36323F", lightAlpha: 0.702, darkAlpha: 0.659)
    static let surfaceControls = dynamicColor(light: "F0EDF7", dark: "302B3C", lightAlpha: 0.502, darkAlpha: 0.502)

    // Text
    static let text          = dynamicColor(light: "292832", dark: "F0EEF7")
    static let textSecondary = dynamicColor(light: "74717F", dark: "B6B1C4")
    static let textDisabled  = dynamicColor(light: "9B96A5", dark: "7E778B")
    static let textOnAction  = dynamicColor(light: "FFFFFF", dark: "282432")

    // Actions
    static let actionDefault = dynamicColor(light: "292832", dark: "EEEBF6")
    static let actionHover   = dynamicColor(light: "3B3746", dark: "FFFFFF")
    static let actionPressed = dynamicColor(light: "17131D", dark: "D5CCE4")

    // Accent
    static let accentForeground = dynamicColor(light: "6350C5", dark: "BCABFF")
    static let accentBackground = dynamicColor(light: "EEE9FF", dark: "393047")

    // Borders and elevation
    static let borderDefault = dynamicColor(light: "ACA2BD", dark: "B9AACA", lightAlpha: 0.188, darkAlpha: 0.145)
    static let borderStrong  = dynamicColor(light: "D4CDDD", dark: "655B74")
    static let shadowControl = dynamicColor(light: "272036", dark: "000000", lightAlpha: 0.133, darkAlpha: 0.314)

    // Status
    static let negativeText = dynamicColor(light: "A54B56", dark: "F1AFB7")
    static let positiveText = dynamicColor(light: "286248", dark: "A3D8B9")

    // Geometry
    static let radiusSmall: CGFloat = 4
    static let radiusChip: CGFloat = 7
    static let radiusControl: CGFloat = 8
    static let radiusAction: CGFloat = 11
    static let radiusCompactWindow: CGFloat = 13
    static let radiusPanel: CGFloat = 16
    static let radiusRound: CGFloat = 999

    // Sizes
    static let controlMedium: CGFloat = 36
    static let controlSmall: CGFloat = 28
    static let iconDefault: CGFloat = 16

    // Typography (SF Pro stands in for Inter on native, per Tidy's guidance)
    static func caption(_ weight: Font.Weight = .regular) -> Font { .system(size: 11, weight: weight) }
    static func labelSmall(_ weight: Font.Weight = .regular) -> Font { .system(size: 12, weight: weight) }
    static func label(_ weight: Font.Weight = .regular) -> Font { .system(size: 13, weight: weight) }
    static func bodySmall(_ weight: Font.Weight = .regular) -> Font { .system(size: 14, weight: weight) }
    static func body(_ weight: Font.Weight = .regular) -> Font { .system(size: 16, weight: weight) }
    static func headingMedium(_ weight: Font.Weight = .semibold) -> Font { .system(size: 20, weight: weight) }

    private static func dynamicColor(light: String, dark: String, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .vibrantDark, .vibrantLight])
            let isDark = match == .darkAqua || match == .vibrantDark
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

private extension NSColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        self.init(
            srgbRed: CGFloat((v >> 16) & 0xff) / 255,
            green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255,
            alpha: alpha
        )
    }
}

// MARK: - Shell layout

private enum Shell {
    // Wide enough that the traffic lights sit inside the rail, clear of the panel.
    static let railWidth: CGFloat = 76
    static let gutter: CGFloat = 8
    static let panelRadius: CGFloat = 12
}

private struct InsetPanel: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Shell.panelRadius, style: .continuous)
        content
            .clipShape(shape)
            .background(shape.fill(TidyTheme.surface).shadow(color: TidyTheme.shadowControl, radius: 3, y: 1))
            .overlay(shape.strokeBorder(TidyTheme.borderDefault, lineWidth: 1))
    }
}

extension View {
    func insetPanel() -> some View { modifier(InsetPanel()) }
}

// MARK: - Content

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var bookmarkStore = BookmarkStore()

    var body: some View {
        HStack(spacing: 0) {
            Rail(bookmarkStore: bookmarkStore)

            HStack(spacing: Shell.gutter) {
                ZStack(alignment: .top) {
                    XWebView(cornerRadius: Shell.panelRadius)
                    if appState.isLoading {
                        LoadingBar()
                            .frame(height: 2)
                            .transition(.opacity)
                    }
                }
                .insetPanel()

                if appState.showBookmarksPanel {
                    BookmarksPanel(store: bookmarkStore)
                        .insetPanel()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.vertical, Shell.gutter)
            .padding(.trailing, Shell.gutter)
        }
        .background {
            ZStack {
                TidyTheme.surface
                WindowDragArea()
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.2), value: appState.showBookmarksPanel)
        .animation(.easeOut(duration: 0.2), value: appState.isLoading)
        .sheet(isPresented: $appState.showAddBookmark) {
            AddBookmarkSheet(
                store: bookmarkStore,
                url: appState.currentURL.absoluteString,
                title: appState.pageTitle
            )
        }
        .sheet(isPresented: $appState.showSettings) {
            SettingsSheet()
                .environmentObject(appState)
        }
    }
}

// MARK: - Rail

private struct Destination: Identifiable {
    let id: String
    let icon: String
    let activeIcon: String
    // X redirects several routes (Messages → /i/chat, Profile → /<handle>), so match on all known paths.
    let paths: [String]
    let url: String
    let shortcut: String?

    func matches(_ path: String) -> Bool {
        paths.contains { path.contains($0) }
    }
}

private let destinations: [Destination] = [
    .init(id: "Home",          icon: "house",           activeIcon: "house.fill",      paths: ["/home"],                 url: "https://x.com/home",          shortcut: "⌘1"),
    .init(id: "Explore",       icon: "magnifyingglass", activeIcon: "magnifyingglass", paths: ["/explore", "/search"],   url: "https://x.com/explore",       shortcut: nil),
    .init(id: "Notifications", icon: "bell",            activeIcon: "bell.fill",       paths: ["/notifications"],        url: "https://x.com/notifications", shortcut: "⌘3"),
    .init(id: "Messages",      icon: "envelope",        activeIcon: "envelope.fill",   paths: ["/messages", "/i/chat"],  url: "https://x.com/i/chat",        shortcut: "⌘4"),
    .init(id: "Bookmarks",     icon: "bookmark",        activeIcon: "bookmark.fill",   paths: ["/i/bookmarks", "/i/history"], url: "https://x.com/i/bookmarks", shortcut: "⌘2"),
    .init(id: "Lists",         icon: "list.bullet",     activeIcon: "list.bullet",     paths: ["/lists"],                url: "https://x.com/lists",         shortcut: nil),
    .init(id: "Profile",       icon: "person",          activeIcon: "person.fill",     paths: [],                        url: "https://x.com/profile",       shortcut: nil),
]

private struct Rail: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var bookmarkStore: BookmarkStore
    // Last section entered. Stays selected while drilling into tweets or profiles,
    // and is what keeps Profile lit (its URL is the user's handle, which we don't know).
    @State private var section = "Home"

    private var isSaved: Bool { bookmarkStore.isBookmarked(url: appState.currentURL.absoluteString) }

    var body: some View {
        VStack(spacing: 4) {
            Color.clear.frame(height: 38) // traffic lights

            ForEach(destinations) { d in
                let active = section == d.id
                RailButton(
                    icon: active ? d.activeIcon : d.icon,
                    help: [d.id, d.shortcut].compactMap { $0 }.joined(separator: "  "),
                    isActive: active
                ) {
                    section = d.id
                    appState.navigate(to: d.url)
                }
            }

            Spacer(minLength: 12)

            RailButton(
                icon: isSaved ? "tray.and.arrow.down.fill" : "tray.and.arrow.down",
                help: "Save Bookmark  ⌘D",
                isActive: isSaved
            ) {
                appState.showAddBookmark = true
            }
            RailButton(icon: "tray.full", help: "My Bookmarks  ⇧⌘B", isActive: appState.showBookmarksPanel) {
                appState.showBookmarksPanel.toggle()
            }
            RailButton(icon: "slider.horizontal.3", help: "Settings  ⌘,") {
                appState.showSettings = true
            }
        }
        .padding(.bottom, 14)
        .frame(width: Shell.railWidth)
        .onReceive(appState.$currentURL) { url in
            let path = url.path.lowercased()
            if let match = destinations.first(where: { $0.matches(path) }) {
                section = match.id
            }
        }
    }
}

private struct RailButton: View {
    let icon: String
    let help: String
    var isActive = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: TidyTheme.iconDefault, weight: isActive ? .semibold : .regular))
                .frame(width: TidyTheme.controlMedium, height: TidyTheme.controlMedium)
                .contentShape(Rectangle())
        }
        .buttonStyle(RailButtonStyle(isActive: isActive, isHovered: isHovered))
        .help(help)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// Pressed reads as lavender immediately, so the press flows straight into the selected state.
private struct RailButtonStyle: ButtonStyle {
    let isActive: Bool
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        let lit = isActive || configuration.isPressed
        configuration.label
            .foregroundStyle(lit ? TidyTheme.accentForeground : (isHovered ? TidyTheme.text : TidyTheme.textSecondary))
            .background(
                RoundedRectangle(cornerRadius: TidyTheme.radiusAction, style: .continuous)
                    .fill(lit ? TidyTheme.accentBackground : (isHovered ? TidyTheme.surfaceHover : .clear))
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Window drag area

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DraggableView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DraggableView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

// MARK: - Loading Bar

private struct LoadingBar: View {
    @State private var animating = false

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(TidyTheme.accentForeground)
                .frame(width: geo.size.width * 0.35)
                .offset(x: animating ? geo.size.width * 0.65 : -geo.size.width * 0.35)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false), value: animating)
        }
        .background(TidyTheme.accentForeground.opacity(0.12))
        .onAppear { animating = true }
    }
}

// MARK: - Settings Sheet

struct SettingsSheet: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var updater = Updater.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Settings")
                    .font(TidyTheme.headingMedium())
                    .foregroundColor(TidyTheme.text)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(TidyTheme.textSecondary)
                        .frame(width: TidyTheme.controlSmall, height: TidyTheme.controlSmall)
                        .background(
                            RoundedRectangle(cornerRadius: TidyTheme.radiusAction, style: .continuous)
                                .fill(TidyTheme.surfaceSubtle)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }

            SettingsRow(label: "Appearance", help: "System follows macOS.") {
                SegmentedPicker(
                    selection: $appState.themePreference,
                    options: ThemePreference.allCases,
                    label: { $0.label }
                )
            }

            SettingsRow(label: "Minimal mode", help: "Hide X's nav, trends, compose and upsells.") {
                Toggle("", isOn: $appState.minimalMode)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            SettingsRow(label: "Text size", help: "\(Int((appState.zoomLevel * 100).rounded()))%") {
                HStack(spacing: 6) {
                    StepButton(icon: "textformat.size.smaller") {
                        appState.zoomLevel = max(0.5, appState.zoomLevel - 0.1)
                    }
                    Button("Reset") { appState.zoomLevel = 1.0 }
                        .buttonStyle(.plain)
                        .font(TidyTheme.labelSmall(.medium))
                        .foregroundColor(TidyTheme.textSecondary)
                        .padding(.horizontal, 8)
                    StepButton(icon: "textformat.size.larger") {
                        appState.zoomLevel = min(2.0, appState.zoomLevel + 0.1)
                    }
                }
            }

            SettingsRow(label: "Updates", help: "Version \(updater.version) · checks daily") {
                Button {
                    dismiss()
                    updater.checkForUpdates()
                } label: {
                    Text("Check Now")
                        .font(TidyTheme.labelSmall(.medium))
                        .foregroundColor(TidyTheme.text)
                        .padding(.horizontal, 12)
                        .frame(height: TidyTheme.controlSmall)
                        .background(
                            RoundedRectangle(cornerRadius: TidyTheme.radiusControl, style: .continuous)
                                .fill(TidyTheme.surfaceSubtle)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: TidyTheme.radiusControl, style: .continuous)
                                .stroke(TidyTheme.borderDefault, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!updater.canCheckForUpdates)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 440, height: 350)
        .background(TidyTheme.surface)
    }
}

private struct StepButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .foregroundColor(TidyTheme.text)
                .frame(width: TidyTheme.controlSmall, height: TidyTheme.controlSmall)
                .background(
                    RoundedRectangle(cornerRadius: TidyTheme.radiusControl, style: .continuous)
                        .fill(TidyTheme.surfaceSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: TidyTheme.radiusControl, style: .continuous)
                        .stroke(TidyTheme.borderDefault, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsRow<Content: View>: View {
    let label: String
    let help: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(TidyTheme.label(.medium))
                    .foregroundColor(TidyTheme.text)
                Text(help)
                    .font(TidyTheme.caption())
                    .foregroundColor(TidyTheme.textSecondary)
            }
            Spacer()
            content()
        }
    }
}

struct SegmentedPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [T]
    let label: (T) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = selection == option
                Button { selection = option } label: {
                    Text(label(option))
                        .font(TidyTheme.labelSmall(.medium))
                        .foregroundColor(selected ? TidyTheme.text : TidyTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: TidyTheme.controlSmall)
                        .background(
                            RoundedRectangle(cornerRadius: TidyTheme.radiusControl - 2, style: .continuous)
                                .fill(selected ? TidyTheme.surface : .clear)
                                .shadow(color: selected ? TidyTheme.shadowControl : .clear, radius: 2, y: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: TidyTheme.radiusControl, style: .continuous)
                .fill(TidyTheme.surfaceSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TidyTheme.radiusControl, style: .continuous)
                .stroke(TidyTheme.borderDefault, lineWidth: 1)
        )
    }
}
