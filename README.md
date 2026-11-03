# X Reader - A Minimal macOS Desktop Client for X

A lightweight native Mac app for reading your X (formerly Twitter) feed without the clutter. Built with SwiftUI + WKWebView.

## What It Does

- **Dedicated Mac app** - Lives in your Dock, gets its own window, no browser tabs
- **One calm column** - An icon rail replaces X's nav, and the timeline sits centered in a single panel
- **Reading-focused** - Minimal Mode hides compose, upsells and the trends column
- **Instant navigation** - The rail drives X's own router, so sections switch without reloading
- **Unread badge** - X's unread count shows on the Dock icon and the rail's bell
- **Light, Dark or System** - X's own theme follows along live
- **Picks up where you left off** - Reopens your last page
- **Bookmarks** - Uses X's bookmarks, so they sync to your account
- **Keyboard shortcuts** - ⌘1 Home, ⌘2 Bookmarks, ⌘3 Notifications, ⌘4 Messages, ⌘R Refresh, ⌘[ / ⌘] Back / Forward
- **Zoom controls** - ⌘+ / ⌘- / ⌘0, or Settings → Text size
- **External link safety** - Links that leave X open in your default browser

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later

## Setup

1. Open the project in Xcode: `open XReader.xcodeproj`
2. Select the XReader target > Signing and Capabilities > choose your Personal Team or Apple Developer account
3. Build and Run (Cmd+R)
4. Log in to X - the app loads x.com/home. Sign in with your account. Session persists between launches.

## Updates

XReader updates itself with [Sparkle](https://sparkle-project.org). It checks daily, and you can check any time from **XReader → Check for Updates…** or **Settings → Updates**. Updates come from this repo's [GitHub Releases](https://github.com/tmass1/XReader/releases) and are only installed if they carry a valid signature from the release key.

### Releasing a new version

Publishing a release is a production deploy: every installed copy picks it up. `scripts/release.sh` is the only way to do it, and it checks first that your branch has everything that's already live.

```bash
scripts/release.sh --check 1.3                       # check everything, change nothing
scripts/release.sh 1.3 "What changed in this version"
```

After the checks, the script bumps the version, builds with the Developer ID certificate, notarizes and staples the app, signs the update with Sparkle, then tags the release and publishes it with its `appcast.xml`. Leave out the notes to use the commit messages since the live release. What each stop means, and how to roll back: [docs/DEPLOYING.md](docs/DEPLOYING.md).

One-time setup on the releasing Mac:
- **Signing key:** generated with Sparkle's `generate_keys`, stored in the login Keychain. Back it up (`generate_keys -x <file>`); without it, existing installs can't verify new updates.
- **Notarization:** `xcrun notarytool store-credentials XReader --apple-id <apple-id> --team-id Y5V8Y3BH9A`

## Project Structure

- `XReaderApp.swift` - App entry point, menu commands, Sparkle updater
- `AppState.swift` - Observable state: current page, rail section, settings, unread count
- `ContentView.swift` - Tidy design tokens, icon rail, web panel, Settings sheet
- `XWebView.swift` - WKWebView wrapper: stylesheet, router navigation, link policy
- `AppIcon.icon` - Icon Composer app icon (two vector layers)
- `scripts/release.sh` - The production deploy command: checks, then builds, notarizes, signs and publishes a release
- `scripts/lib/guard.sh` - The deploy checks; `scripts/tests/` tests them
- `AGENTS.md` - Rules for coding agents, including deploys
- `.claude/` - Hook that stops Claude from publishing without the deploy check

## Key Features

### Minimal Mode (on by default)
Hides the compose button, Premium and verification prompts, X's left nav (replaced by the rail) and the trends column, and centers the timeline. Toggle it in Settings or with ⌘⇧M.

### Styling
The stylesheet is installed at document start, so X's own chrome never flashes on load, and is updated in place when settings change.

### Navigation
Once X has loaded, the rail and menu navigate through X's own router (its hidden nav links, or `pushState`), so switching sections is instant. A full page load is only the fallback.

### Link Policy
Pages stay on X-related domains and the Google and Apple sign-in providers. A link that leaves X opens in your default browser; embedded players and widgets load in place.

## Customization

- Edit `XWebView.css(for:)` to hide or restyle more of X
- Use Safari Web Inspector on x.com to find selectors
- Edit `XReader/AppIcon.icon` in Icon Composer to change the app icon

## Troubleshooting

- **Blank screen**: Verify entitlements include com.apple.security.network.client = true
- **CSS not working**: X updates their DOM frequently. Inspect in Safari (Develop > XReader) and update selectors
- **Login does not persist**: Ensure WKWebsiteDataStore.default() is used (not .nonPersistent())
