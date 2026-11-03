#!/usr/bin/env bash
# Tests for the checks in scripts/release.sh, run against small throwaway
# projects with a stand-in for GitHub. Nothing here touches the real releases.
set -uo pipefail
source "$(dirname "$0")/helpers.sh"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/xreader-check.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
EMAIL="1+test@users.noreply.github.com"

# A project with two releases' worth of history:
#   A "Start"  →  B "Add bookmarks"  →  R "Release 1.0" (tag v1.0, build 2), all on GitHub
new_fixture() {
  FX="$TMP_ROOT/$1"
  git init -q --bare -b main "$FX-origin.git"
  git init -q -b main "$FX"
  cd "$FX" || exit 1
  git config user.name Test
  git config user.email "$EMAIL"
  git remote add origin "$FX-origin.git"
  mkdir -p XReader XReader.xcodeproj scripts/lib
  echo 'start' >XReader/App.swift
  printf 'MARKETING_VERSION = 0.9;\nCURRENT_PROJECT_VERSION = 1;\n' >XReader.xcodeproj/project.pbxproj
  echo 'export options' >scripts/ExportOptions.plist
  echo 'readme' >README.md
  cp "$REAL_ROOT/scripts/release.sh" scripts/
  cp "$REAL_ROOT/scripts/lib/guard.sh" scripts/lib/
  git add -A && git commit -qm "Start"
  A="$(git rev-parse HEAD)"
  echo 'bookmarks' >>XReader/App.swift
  git commit -qam "Add bookmarks"
  printf 'MARKETING_VERSION = 1.0;\nCURRENT_PROJECT_VERSION = 2;\n' >XReader.xcodeproj/project.pbxproj
  git commit -qam "Release 1.0"
  git tag v1.0
  R="$(git rev-parse HEAD)"
  git push -q origin main v1.0
  git branch -q -u origin/main
}

# Stand-ins for GitHub and for the slow or outside steps. STUB_* variables steer them.
stub_outside_world() {
  provider_latest_tag()     { if [[ ${STUB_NO_GITHUB:-} == 1 ]]; then return 1; fi; echo "${STUB_TAG:-v1.0}"; }
  provider_tag_commit()     { if [[ -n ${STUB_SHA:-} ]]; then echo "$STUB_SHA"; else git rev-parse "$1^{commit}"; fi; }
  provider_release_body()   { echo "${STUB_BODY:-Notes}"; }
  provider_release_tags()   { printf '%s\n' ${STUB_TAGS:-v1.0}; }
  provider_feed()           { printf '<sparkle:shortVersionString>%s</sparkle:shortVersionString>\n' "${STUB_FEED:-1.0}"; }
  run_tests()       { ok "tests (stand-in)"; }
  check_tools()     { ok "tools (stand-in)"; }
  verify_live()     { ok "live health (stand-in)"; }
  build_release()   { echo "BUILD STARTED"; OUT=/nonexistent ZIP=none; }
  publish_release() { echo "PUBLISHED"; RELEASE_COMMIT="$(git rev-parse HEAD)"; }
  finish()          { echo "FINISHED"; }
}

# release <args...>: runs scripts/release.sh in the fixture, with no terminal attached.
release() {
  RESULT="$(cd "$FX" && (source scripts/release.sh && stub_outside_world && main "$@") </dev/null 2>&1)"
  STATUS=$?
}

echo "# Ready to deploy"
new_fixture ready
echo 'zoom' >>XReader/App.swift && git commit -qam "Add zoom" && git push -q origin main
release --check 1.1
expect "check passes on main with everything live" 0 "$STATUS" "$RESULT" \
  "Live: v1.0, built from commit ${R:0:7}" "This branch has everything that's live" \
  "Version 1.1 (build 3)" "Add zoom" "Result: ready" "!STOP"

echo "# Missing live work"
new_fixture missing
git switch -qc old-idea "$A"
echo 'old' >XReader/Old.swift && git add -A && git commit -qm "Old idea"
release --check 1.1
expect "stops on a branch missing live work" 1 "$STATUS" "$RESULT" \
  "STOP: This branch is missing work that's already live" "2 changes" \
  "Add bookmarks" "Release 1.0" "git merge v1.0" "main" "Result: a deploy would STOP"
release 1.1 --yes
expect "--yes never gets past a stop" 1 "$STATUS" "$RESULT" \
  "missing work that's already live" "Stopped. Nothing was built or published." "!BUILD STARTED"
git merge -q --no-edit v1.0
release --check 1.1
expect "merging the live release clears the stop" 0 "$STATUS" "$RESULT" "This branch has everything that's live"

echo "# Live commit not in this checkout"
new_fixture unseen
STUB_SHA=1234567890abcdef1234567890abcdef12345678 release --check
expect "stops when the live commit isn't here" 1 "$STATUS" "$RESULT" \
  "The live commit isn't in this copy" "git fetch origin --tags" "hasn't pushed"

echo "# Uncommitted changes"
new_fixture dirty
echo 'edit' >>XReader/App.swift
release --check
expect "stops on an uncommitted change the build uses" 1 "$STATUS" "$RESULT" "aren't committed" "XReader/App.swift"
git checkout -q -- XReader/App.swift && echo 'new' >XReader/New.swift
release --check
expect "stops on a new file the build would use" 1 "$STATUS" "$RESULT" "aren't committed" "XReader/New.swift"
rm XReader/New.swift && echo 'docs' >>README.md
release --check
expect "doesn't stop for files the build doesn't use" 0 "$STATUS" "$RESULT" "Not part of the build" "README.md"

echo "# Finding what's live"
new_fixture live
STUB_NO_GITHUB=1 release --check
expect "stops and explains when GitHub can't tell" 1 "$STATUS" "$RESULT" \
  "Couldn't find out which version is live" "LIVE_COMMIT=<that ID> scripts/release.sh --check"
STUB_NO_GITHUB=1 LIVE_COMMIT=$R release --check
expect "a commit named by hand works when GitHub can't tell" 0 "$STATUS" "$RESULT" "named by you"
LIVE_COMMIT=$A release --check
expect "a commit named by hand can't overrule GitHub" 1 "$STATUS" "$RESULT" "The commit you named isn't what's live"
STUB_FEED=0.9 release --check
expect "stops when the update feed disagrees" 1 "$STATUS" "$RESULT" "disagree about what's live" "offers 0.9"
STUB_BODY="Notes
---
Deployed from commit $R on branch \`main\`, with scripts/release.sh." release --check
expect "reads the deploy note on the release" 0 "$STATUS" "$RESULT" "from the deploy note on the release"
STUB_BODY="Deployed from commit $A on branch \`main\`." release --check
expect "stops when the deploy note and tag disagree" 1 "$STATUS" "$RESULT" "records disagree"
release --check
expect "falls back to the tag for older releases" 0 "$STATUS" "$RESULT" "this release predates the deploy check"

echo "# Version numbers"
new_fixture versions
release --check 1.0
expect "stops on a version already released" 1 "$STATUS" "$RESULT" "Version 1.0 was already released"
release --check 0.9
expect "stops on a lower version" 1 "$STATUS" "$RESULT" "isn't higher than v1.0"
release --check 1.x
expect "stops on something that isn't a version" 1 "$STATUS" "$RESULT" "isn't a version number"
release --check 1.0.1
expect "accepts a patch version" 0 "$STATUS" "$RESULT" "Version 1.0.1 (build 3)"
# 1.1 shipped with build 5, then was rolled back: v1.0 is live again.
git switch -qc rolled-back
printf 'MARKETING_VERSION = 1.1;\nCURRENT_PROJECT_VERSION = 5;\n' >XReader.xcodeproj/project.pbxproj
git commit -qam "Release 1.1" && git tag v1.1 && git switch -q main
STUB_TAGS="v1.0 v1.1" release --check 1.0.5
expect "stops below a rolled-back release's version" 1 "$STATUS" "$RESULT" "isn't higher than v1.1"
STUB_TAGS="v1.0 v1.1" release --check 1.2
expect "build number goes above every published release" 0 "$STATUS" "$RESULT" "Version 1.2 (build 6)"

echo "# Questions"
new_fixture questions
git switch -qc feature && echo 'x' >>XReader/App.swift && git commit -qam "Feature work"
release --check 1.1
expect "check lists the questions a deploy would ask" 0 "$STATUS" "$RESULT" \
  "Would ask: You're releasing from feature, not main" "feature isn't on GitHub at all" "2 questions"
release 1.1
expect "with no terminal and no --yes, a question is a stop" 1 "$STATUS" "$RESULT" \
  "there's no terminal to ask in" "add --yes" "!BUILD STARTED"
release 1.1 --yes
expect "--yes answers the questions and the deploy prompt" 0 "$STATUS" "$RESULT" \
  "→ yes (--yes)" "going ahead as if you typed deploy" "BUILD STARTED" "PUBLISHED"
git switch -q main && echo 'y' >>XReader/App.swift && git commit -qam "Local work"
release --check
expect "asks about commits that aren't on GitHub" 0 "$STATUS" "$RESULT" "1 of your commits on main isn't on GitHub yet"
git reset -q --hard origin/main
git clone -q "$FX-origin.git" "$FX-other" && (cd "$FX-other" && git config user.email "$EMAIL" &&
  echo z >>README.md && git commit -qam "Someone else's work" && git push -q origin main)
git fetch -q origin
release --check
expect "asks about commits on GitHub you don't have" 0 "$STATUS" "$RESULT" "GitHub has 1 commit on main that you don't"
git merge -q --ff-only origin/main
release --check
expect "no same-app question when there's something new" 0 "$STATUS" "$RESULT" "!Would ask: This would ship"
git reset -q --hard "$R"
git push -qf origin main
release --check
expect "nothing new: asks before shipping the same app" 0 "$STATUS" "$RESULT" "Would ask: This would ship the same app as v1.0"

echo "# Keeping things private"
new_fixture private
git -c user.email=someone@example.com commit -q --allow-empty -m "Work with a public email"
release --check
expect "stops on commits with a public email" 1 "$STATUS" "$RESULT" "an email that isn't your private GitHub address" "Work with a public email"
git reset -q --hard origin/main
git config user.email someone@example.com
release --check
expect "stops when your git email isn't private" 1 "$STATUS" "$RESULT" "Your git email for this project isn't your private GitHub address"
git config user.email "$EMAIL"
git checkout -q --detach
release --check
expect "stops on a detached HEAD" 1 "$STATUS" "$RESULT" "You're not on a branch"

echo "# Helpers"
(
  ROOT=$REAL_ROOT
  source "$REAL_ROOT/scripts/lib/guard.sh"
  version_gt 1.10 1.9 && version_gt 1.2.1 1.2 && version_gt 2.0 1.99 &&
    ! version_gt 1.2 1.2 && ! version_gt 1.2 1.10 && ! version_gt 1.2 1.2.0
) && pass "version_gt compares versions number by number" || fail "version_gt compares versions number by number"
(
  ROOT=$REAL_ROOT
  source "$REAL_ROOT/scripts/lib/guard.sh"
  sha=0123456789abcdef0123456789abcdef01234567
  [[ "$(deploy_note_commit "notes
---
Deployed from commit $sha on branch \`main\`.")" == "$sha" ]] && [[ -z "$(deploy_note_commit "- Just notes")" ]]
) && pass "deploy_note_commit reads the note, and only the note" || fail "deploy_note_commit reads the note, and only the note"
(
  ROOT=$REAL_ROOT
  source "$REAL_ROOT/scripts/lib/guard.sh"
  feed='<sparkle:version>3</sparkle:version><sparkle:shortVersionString>1.2</sparkle:shortVersionString>
<enclosure url="https://example.com/X.zip" type="application/octet-stream" sparkle:edSignature="abc+/=" length="2932468" />'
  [[ "$(feed_field version <<<"$feed")" == 3 && "$(feed_field shortVersionString <<<"$feed")" == 1.2 &&
    "$(feed_attr url <<<"$feed")" == https://example.com/X.zip && "$(feed_attr length <<<"$feed")" == 2932468 &&
    "$(feed_attr sparkle:edSignature <<<"$feed")" == "abc+/=" ]]
) && pass "reads the update feed's fields" || fail "reads the update feed's fields"

finish_tests
