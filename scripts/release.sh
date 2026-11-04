#!/usr/bin/env bash
# The only way to publish an XReader update (a production deploy).
#
#   scripts/release.sh --check [<version>]          check everything; build and publish nothing
#   scripts/release.sh <version> ["notes"] [--yes]  check, build, notarize, sign and publish
#   scripts/release.sh --rollback <tag> [--check]   make an earlier release the live one again
#
# --yes answers the questions when there's no terminal. It never skips a stop.
# What each message means, and how to roll back: docs/DEPLOYING.md
#
# One-time setup on the releasing Mac:
#   - Sparkle signing key in your Keychain (Sparkle's generate_keys).
#   - Notarization credentials: xcrun notarytool store-credentials XReader --apple-id <id> --team-id Y5V8Y3BH9A
#     (or set NOTARY_PROFILE to an existing profile name).
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/guard.sh"
NOTARY_PROFILE="${NOTARY_PROFILE:-XReader}"

usage() { sed -n '4,8p' "$ROOT/scripts/release.sh" | sed -E 's/^# ?//'; }

main() {
  local check=0
  VERSION="" NOTES="" ROLLBACK_TO="" LIVE_KNOWN=0 LIVE_IN_BRANCH=0 LIVE_TAG="" LIVE_COMMIT="" BRANCH=""
  while (($#)); do
    case $1 in
      --check) check=1 ;;
      --yes) YES=1 ;;
      --rollback) shift; ROLLBACK_TO="${1:-}"; if [[ -z $ROLLBACK_TO ]]; then usage; exit 1; fi ;;
      -h | --help) usage; exit 0 ;;
      # Release notes can start with a "- " bullet, so that's not an option.
      -[!\ ]*) echo "Unknown option: $1"; usage; exit 1 ;;
      *)
        if [[ -z $VERSION ]]; then VERSION=$1
        elif [[ -z $NOTES ]]; then NOTES=$1
        else usage; exit 1; fi ;;
    esac
    shift
  done
  cd "$ROOT"

  if [[ -n $ROLLBACK_TO ]]; then
    if ((check)); then MODE=check; else MODE=rollback; fi
    rollback "$ROLLBACK_TO"
    return
  fi
  if ((check)); then MODE=check
  elif [[ -z $VERSION ]]; then usage; exit 1
  fi

  preflight
  if [[ $MODE == check ]]; then
    summary
    return
  fi
  confirm_typed deploy
  build_release
  publish_release
  section "Checking the live release"
  local live_ok=1
  verify_live "$VERSION" "$RELEASE_COMMIT" "$OUT/$ZIP" || live_ok=0
  finish "$live_ok"
}

preflight() {
  if [[ $MODE == check ]]; then
    echo "XReader production deploy check (check only: nothing will be built or published)"
  else
    echo "XReader production deploy: version $VERSION"
  fi
  echo "Production is the release marked Latest at https://github.com/$REPO/releases."
  echo "Every installed copy updates to it within a day."

  section "Uncommitted changes"
  check_build_files || true

  section "What's live"
  if fetch_from_github && find_live; then
    LIVE_KNOWN=1
    if check_contains_live; then LIVE_IN_BRANCH=1; fi
  fi

  section "Branch and GitHub"
  check_branch || true
  check_private_emails || true

  section "Version"
  if [[ -n $VERSION ]]; then
    check_version "$VERSION" || true
  else
    note "No version given, so the version number wasn't checked. To check it too: scripts/release.sh --check 1.3"
  fi

  section "Tests"
  run_tests

  section "Release tools"
  check_tools || true

  if [[ $MODE == check && $LIVE_KNOWN == 1 && $LIVE_TAG == v* ]]; then
    section "Health of the live release ($LIVE_TAG)"
    verify_live "${LIVE_TAG#v}" "$LIVE_COMMIT" || true
    LIVE_HEALTH_FAILURES=$LIVE_FAILURES
  fi

  if [[ $LIVE_IN_BRANCH == 1 ]]; then show_additions; fi
}

summary() {
  echo
  if ((PROBLEMS > 0)); then
    echo "Result: a deploy would STOP ($(plural "$PROBLEMS" problem) above). Nothing was built or published."
    exit 1
  fi
  if [[ -n $ROLLBACK_TO ]]; then
    echo "Result: ready. A real rollback would ask you to type rollback, then mark $ROLLBACK_TO as Latest."
    return
  fi
  if ((QUESTION_COUNT > 0)); then
    echo "Result: ready. A real deploy would ask you the $(plural "$QUESTION_COUNT" question) above, then ask you to type deploy."
  else
    echo "Result: ready. A real deploy would ask you to type deploy, then build, notarize and publish."
  fi
  if [[ -z $VERSION ]]; then echo "        (The version number wasn't checked. Add it: scripts/release.sh --check 1.3)"; fi
  if ((${LIVE_HEALTH_FAILURES:-0} > 0)); then
    echo "        The live release itself has $(plural "$LIVE_HEALTH_FAILURES" problem) (marked ✗ above), not caused by your branch."
  fi
}

build_release() {
  OUT="$ROOT/build/release-$VERSION"
  ZIP="XReader-$VERSION.zip"
  STOP_FOOTER="Stopped. Nothing was published."

  # Bump the version; undone automatically if any later step fails
  trap 'echo "Build failed, so nothing was published. Undoing the version bump." >&2; git checkout -- "$PBX"' ERR
  sed -i '' -E "s/(MARKETING_VERSION = )[^;]+;/\1$VERSION;/; s/(CURRENT_PROJECT_VERSION = )[0-9]+;/\1$NEXT_BUILD;/" "$PBX"
  section "Building XReader $VERSION (build $NEXT_BUILD)"

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
  local signature notes_html
  signature="$("$SPARKLE_BIN/sign_update" "$OUT/$ZIP")"

  # Release notes: given text, or the commit subjects since the live release
  if [[ -z $NOTES ]]; then NOTES="$(git log --no-merges --format='- %s' "$LIVE_COMMIT..HEAD")"; fi
  notes_html="$(printf '%s\n' "$NOTES" | sed -e 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' -e 's/^- \(.*\)/<li>\1<\/li>/')"

  cat >"$OUT/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>XReader</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$NEXT_BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <link>https://github.com/$REPO/releases/tag/v$VERSION</link>
      <description><![CDATA[<ul>
$notes_html
</ul>]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/$ZIP" type="application/octet-stream" $signature />
    </item>
  </channel>
</rss>
EOF

  # Building takes minutes. Make sure nobody released in the meantime.
  local now now_commit
  now="$(provider_latest_tag 2>/dev/null || true)"
  now_commit="$(provider_tag_commit "$now" 2>/dev/null || true)"
  if [[ $LIVE_TAG == v* && ($now != "$LIVE_TAG" || $now_commit != "$LIVE_COMMIT") ]]; then
    git checkout -- "$PBX"
    trap - ERR
    if [[ -z $now ]]; then
      problem "Couldn't re-check what's live after building" \
        "GitHub didn't answer, so there's no way to be sure nobody released in the meantime." \
        "The version bump was undone. Run scripts/release.sh --check again."
    fi
    problem "Someone released while this was building" \
      "$now is live now, not $LIVE_TAG. This build may be missing that work." \
      "The version bump was undone. Run scripts/release.sh --check again."
  fi
}

publish_release() {
  section "Publishing"
  git commit -q -m "Release $VERSION" -- "$PBX"
  trap - ERR
  RELEASE_COMMIT="$(git rev-parse HEAD)"
  git tag "v$VERSION"

  # Only the tag goes to GitHub (the release needs it). Pushing the branch waits for you.
  if ! git push -q origin "refs/tags/v$VERSION"; then
    git tag -d "v$VERSION" >/dev/null
    git reset -q --keep HEAD~1
    problem "Couldn't send the release tag to GitHub" \
      "Nothing went live, and the release commit was undone." \
      "Check your connection and gh auth status, then run the check again."
  fi

  printf '%s\n\n---\n%s %s on branch `%s`, with scripts/release.sh.\n' \
    "$NOTES" "$DEPLOY_NOTE" "$RELEASE_COMMIT" "$BRANCH" >"$OUT/release-notes.md"
  if ! gh release create "v$VERSION" "$OUT/$ZIP" "$OUT/appcast.xml" --repo "$REPO" \
      --title "XReader $VERSION" --notes-file "$OUT/release-notes.md" --verify-tag --latest; then
    problem "GitHub didn't create the release" \
      "The tag v$VERSION is on GitHub but there's no release, so nothing went live yet." \
      "Fix the error above, then finish it yourself in Terminal:" \
      "  gh release create v$VERSION \"$OUT/$ZIP\" \"$OUT/appcast.xml\" --repo $REPO --title \"XReader $VERSION\" --notes-file \"$OUT/release-notes.md\" --verify-tag --latest"
  fi
  ok "Published XReader $VERSION from commit $(short "$RELEASE_COMMIT") on $BRANCH"
}

finish() {
  local previous=$LIVE_TAG
  if [[ $previous != v* ]]; then previous="<previous version tag>"; fi
  echo
  if [[ $1 == 1 ]]; then
    echo "XReader $VERSION is live. Installed copies will pick it up within a day."
  else
    echo "XReader $VERSION is published, but the live check found $(plural "$LIVE_FAILURES" problem) (marked ✗ above)."
  fi
  echo
  echo "If something's wrong, roll back. This stops anyone else from getting $VERSION:"
  echo "    scripts/release.sh --rollback $previous"
  echo "(People who already installed $VERSION keep it. To fix it for them, release a newer version.)"
  echo
  echo "To do:"
  echo "  [ ] Write the release note: polish the text at https://github.com/$REPO/releases/tag/v$VERSION"
  if [[ $BRANCH != "$MAIN_BRANCH" ]]; then
    echo "  [ ] Merge $BRANCH into $MAIN_BRANCH, so the next release from $MAIN_BRANCH keeps this work"
  fi
  echo "  [ ] Push $BRANCH to GitHub when you say so: git push origin $BRANCH"
  if [[ $1 != 1 ]]; then exit 1; fi
}

rollback() {
  local target=$1 target_commit target_body tags
  if [[ $target != v* ]]; then target="v$target"; fi
  STOP_FOOTER="Stopped. Nothing was changed."
  echo "XReader production rollback to $target$([[ $MODE == check ]] && echo " (check only: nothing will change)")"

  section "What's live"
  if ! fetch_from_github || ! find_live; then
    if [[ $MODE == check ]]; then summary; fi
    return
  fi
  if [[ $target == "$LIVE_TAG" ]]; then
    problem "$target is already the live release" "There's nothing to roll back to."
  fi
  if ! tags="$(provider_release_tags 2>/dev/null)" || ! grep -qx "$target" <<<"$tags"; then
    problem "$target isn't a published release" "Published: $(paste -sd' ' - <<<"${tags:-}")"
  fi
  if ((PROBLEMS == 0)); then
    target_commit="$(provider_tag_commit "$target" 2>/dev/null || true)"
    section "What rolling back does"
    echo "    Now live:  $LIVE_TAG (commit $(short "$LIVE_COMMIT"))"
    echo "    After:     $target (commit $(short "$target_commit"))"
    echo "    Anyone who hasn't installed $LIVE_TAG yet stops being offered it."
    echo "    Anyone who already installed $LIVE_TAG keeps it: the updater never moves people to an older version."
    echo "    $LIVE_TAG stays on GitHub, just not marked Latest. To fix it for everyone, release a version above ${LIVE_TAG#v}."
    echo "    Your branches still contain $LIVE_TAG's changes. Undo or fix them first, or the next release ships them again."
  fi
  if [[ $MODE == check ]]; then
    summary
    return
  fi

  confirm_typed rollback
  gh release edit "$target" --repo "$REPO" --latest >/dev/null
  section "Checking the live release"
  local tries=0 feed
  while :; do
    feed="$(provider_feed 2>/dev/null || true)"
    if [[ "$(feed_field shortVersionString <<<"$feed")" == "${target#v}" ]]; then break; fi
    tries=$((tries + 1))
    if ((tries >= 12)); then
      echo "  ✗ The update feed still doesn't offer ${target#v}. Look at https://github.com/$REPO/releases"
      exit 1
    fi
    sleep 5
  done
  ok "The update feed now offers ${target#v}"
  echo
  echo "Rolled back: $target is live again."
  echo "To undo the rollback: scripts/release.sh --rollback $LIVE_TAG"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
