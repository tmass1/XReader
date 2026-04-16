# X Reader - A Minimal macOS Desktop Client for X

A lightweight native Mac app for reading your X (formerly Twitter) feed without the clutter. Built with SwiftUI + WKWebView.

## What It Does

- **Dedicated Mac app** - Lives in your Dock, gets its own window, no browser tabs
- **Read-only focused** - Hides the compose button and promotional upsells in Minimal Mode
- **Bookmarking works** - Uses X native web bookmarking, so bookmarks sync to your account
- **Persistent login** - Cookies stored via WKWebsiteDataStore.default(), stay logged in between launches
- **Keyboard shortcuts** - Navigate with Cmd+1 (Home), Cmd+2 (Bookmarks), Cmd+3 (Notifications), Cmd+R (Refresh)
- **Zoom controls** - Cmd+/- to adjust text size
- **Dark mode** - Forces dark appearance to match X dark theme
- **External link safety** - Links to non-X domains open in your default browser

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later

## Setup

1. Open the project in Xcode: `open XReader.xcodeproj`
2. Select the XReader target > Signing and Capabilities > choose your Personal Team or Apple Developer account
3. Build and Run (Cmd+R)
4. Log in to X - the app loads x.com/home. Sign in with your account. Session persists between launches.

## Project Structure

- `XReaderApp.swift` - App entry point, menu bar commands, app delegate
- `AppState.swift` - Observable state (URL, zoom, settings flags)
- `ContentView.swift` - Main layout: sidebar + toolbar + web view
- `XWebView.swift` - WKWebView wrapper with CSS injection and navigation
- `XReader.entitlements` - Sandbox + network entitlements

## Key Features

### Minimal Mode (on by default)
Injects CSS to hide: compose/post button, Subscribe to Premium sidebar, Get Verified prompts, and X left nav (replaced by our own sidebar). Toggle off in sidebar or via Cmd+Shift+M.

### CSS Injection Strategy
X is a single-page React app, so CSS is re-injected on every page navigation, at 0.5s and 2.0s delays after load, and whenever settings change.

### Domain Allowlist
Only allows X-related domains plus OAuth providers (Google, Apple). Other links open in Safari.

## Customization

- Edit `injectCSS()` in XWebView.swift to hide/style more elements
- Use Safari Web Inspector on x.com to find selectors
- Drop icon PNGs into Assets.xcassets/AppIcon.appiconset/ for a custom app icon

## Troubleshooting

- **Blank screen**: Verify entitlements include com.apple.security.network.client = true
- **CSS not working**: X updates their DOM frequently. Inspect in Safari (Develop > XReader) and update selectors
- **Login does not persist**: Ensure WKWebsiteDataStore.default() is used (not .nonPersistent())
