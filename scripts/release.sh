#!/usr/bin/env bash
# Builds, notarizes, signs and publishes an XReader update to GitHub Releases.
# Usage: scripts/release.sh <version> ["release notes"]
#
# One-time setup:
#   - Sparkle signing key in your Keychain (Sparkle's generate_keys).
#   - Notarization credentials: xcrun notarytool store-credentials XReader --apple-id <id> --team-id Y5V8Y3BH9A
#     (or set NOTARY_PROFILE to an existing profile name).
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version> [\"release notes\"]}"
NOTES="${2:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-XReader}"
REPO="tmass1/XReader"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBX="$ROOT/XReader.xcodeproj/project.pbxproj"
OUT="$ROOT/build/release-$VERSION"
ZIP="XReader-$VERSION.zip"
cd "$ROOT"

fail() { echo "error: $*" >&2; exit 1; }

# Preconditions, checked before anything changes
[[ "$(git branch --show-current)" == main ]] || fail "release from main"
[[ -z "$(git status --porcelain)" ]] || fail "working tree has uncommitted changes"
git fetch -q origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main is not in sync with origin/main"
! git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null || fail "tag v$VERSION already exists"
gh auth status >/dev/null 2>&1 || fail "gh is not signed in"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || fail "no notarization profile '$NOTARY_PROFILE' (see setup at the top of this script)"

BUILD_DIR="$(xcodebuild -project XReader.xcodeproj -scheme XReader -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILD_DIR = /{print $2; exit}')"
SPARKLE_BIN="${BUILD_DIR%/Build/Products}/SourcePackages/artifacts/sparkle/Sparkle/bin"
[[ -x "$SPARKLE_BIN/sign_update" ]] || fail "Sparkle tools not found; build the project once in Xcode"

# Bump version; undone automatically if any later step fails
PREV_BUILD="$(grep -m1 -E 'CURRENT_PROJECT_VERSION = [0-9]+;' "$PBX" | grep -oE '[0-9]+')"
BUILD_NUMBER=$((PREV_BUILD + 1))
trap 'echo "Release failed; reverting version bump." >&2; git checkout -- "$PBX"' ERR
sed -i '' -E "s/(MARKETING_VERSION = )[^;]+;/\1$VERSION;/; s/(CURRENT_PROJECT_VERSION = )[0-9]+;/\1$BUILD_NUMBER;/" "$PBX"
echo "==> XReader $VERSION (build $BUILD_NUMBER)"

# Build and export with Developer ID
rm -rf "$OUT" && mkdir -p "$OUT"
echo "==> Archiving"
xcodebuild -project XReader.xcodeproj -scheme XReader -configuration Release \
  -archivePath "$OUT/XReader.xcarchive" -allowProvisioningUpdates -quiet archive
echo "==> Exporting"
xcodebuild -exportArchive -archivePath "$OUT/XReader.xcarchive" \
  -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist" -exportPath "$OUT/export" \
  -allowProvisioningUpdates -quiet
APP="$OUT/export/XReader.app"

# Notarize, staple, and confirm Gatekeeper accepts it
echo "==> Notarizing (usually a few minutes)"
ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
spctl -a -t exec -vv "$APP"

# Package and sign the update
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$ZIP"
SIGNATURE="$("$SPARKLE_BIN/sign_update" "$OUT/$ZIP")"

# Release notes: given text, or commit subjects since the last release
if [[ -z "$NOTES" ]]; then
  LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
  NOTES="$(git log --format='- %s' ${LAST_TAG:+"$LAST_TAG"..}HEAD)"
fi
NOTES_HTML="$(printf '%s\n' "$NOTES" | sed -e 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' -e 's/^- \(.*\)/<li>\1<\/li>/')"

cat > "$OUT/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>XReader</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <link>https://github.com/$REPO/releases/tag/v$VERSION</link>
      <description><![CDATA[<ul>
$NOTES_HTML
</ul>]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/$ZIP" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
EOF

# Publish
echo "==> Publishing"
git commit -q -m "Release $VERSION" -- "$PBX"
trap - ERR
git tag "v$VERSION"
git push -q origin main "v$VERSION"
gh release create "v$VERSION" "$OUT/$ZIP" "$OUT/appcast.xml" \
  --repo "$REPO" --title "XReader $VERSION" --notes "$NOTES"

echo "==> Released XReader $VERSION: https://github.com/$REPO/releases/tag/v$VERSION"
echo "    App: $APP"
