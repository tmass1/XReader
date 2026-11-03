# Checks for scripts/release.sh, the production deploy command. Sourced, not run.
#
# Everything that asks GitHub something goes through the provider_* functions,
# so the tests can stand in for GitHub. Plain-language guide: docs/DEPLOYING.md

REPO="tmass1/XReader"
MAIN_BRANCH="main"
TEAM_ID="Y5V8Y3BH9A"
FEED_URL="https://github.com/$REPO/releases/latest/download/appcast.xml"
PBX="$ROOT/XReader.xcodeproj/project.pbxproj"
SCHEME_FILE="$ROOT/XReader.xcodeproj/xcshareddata/xcschemes/XReader.xcscheme"
# What the app is built from. Uncommitted changes here would ship unrecorded.
BUILD_PATHS=(XReader XReader.xcodeproj scripts/ExportOptions.plist)
BUILD_EXCLUDES=(':!XReader' ':!XReader.xcodeproj' ':!scripts/ExportOptions.plist')
# Branches allowed to exist on GitHub; any other one is flagged after a deploy.
PUBLIC_BRANCHES="main"
PRIVATE_EMAIL_SUFFIX="@users.noreply.github.com"
# Written into every release description, and read back to find what's live.
DEPLOY_NOTE="Deployed from commit"

MODE=deploy           # deploy | check | rollback
YES=0
PROBLEMS=0
QUESTION_COUNT=0
STOP_FOOTER="Stopped. Nothing was built or published."
# LIVE_COMMIT=<commit> names the live commit by hand, for when GitHub can't tell.
NAMED_LIVE_COMMIT="${LIVE_COMMIT:-}"

# --- GitHub (the tests replace these) ---

provider_latest_tag()     { gh api "repos/$REPO/releases/latest" --jq .tag_name; }
provider_release_body()   { gh api "repos/$REPO/releases/tags/$1" --jq .body; }
provider_release_assets() { gh api "repos/$REPO/releases/tags/$1" --jq '.assets[].name'; }
provider_tag_commit()     { gh api "repos/$REPO/commits/$1" --jq .sha; }
provider_release_tags()   { gh api "repos/$REPO/releases" --paginate --jq '.[] | select(.draft | not) | .tag_name'; }
provider_feed()           { curl -fsSL --max-time 30 "$FEED_URL"; }
provider_branches()       { git ls-remote --heads origin | sed 's#.*refs/heads/##'; }

# --- Output ---

section() { printf '\n%s\n' "$1"; }
ok()      { printf '  ✓ %s\n' "$1"; }
note()    { printf '  · %s\n' "$1"; }
indent()  { sed 's/^/      /'; }
plural()  { if [[ $1 == 1 ]]; then echo "1 $2"; else echo "$1 ${3:-${2}s}"; fi; }
short()   { echo "${1:0:7}"; }

# A stop. In check mode it's reported and the check carries on; otherwise it ends the run.
problem() {
  PROBLEMS=$((PROBLEMS + 1))
  printf '\n  ✗ STOP: %s\n' "$1"
  shift
  if (($#)); then printf '%s\n' "$@" | indent; fi
  echo
  if [[ $MODE != check ]]; then
    echo "$STOP_FOOTER"
    exit 1
  fi
}

# A question for you. --yes answers it; without a terminal and without --yes, it's a stop.
confirm() {
  if [[ $MODE == check ]]; then
    QUESTION_COUNT=$((QUESTION_COUNT + 1))
    printf '  ? Would ask: %s\n' "$1"
    return 0
  fi
  if [[ $YES == 1 ]]; then
    printf '  ? %s  → yes (--yes)\n' "$1"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    problem "This needs your OK, and there's no terminal to ask in" "Question: $1" \
      "Run the command yourself in Terminal, or, if you've already said yes in chat, add --yes."
  fi
  local answer
  read -r -p "  ? $1 [y/N] " answer
  if [[ $answer != [yY]* ]]; then problem "You answered no"; fi
}

# The last gate: you type the word (deploy, rollback) to go ahead.
confirm_typed() {
  if [[ $YES == 1 ]]; then
    echo "  (--yes: going ahead as if you typed $1)"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    problem "This needs you to type $1, and there's no terminal to ask in" \
      "Run the command yourself in Terminal, or, if you've already said yes in chat, add --yes."
  fi
  local answer
  echo
  read -r -p "Type $1 to go ahead: " answer
  if [[ $answer != "$1" ]]; then problem "You didn't type $1"; fi
}

# --- Small helpers ---

# True when $1 is a higher version than $2 (1.10 is higher than 1.9).
version_gt() {
  local IFS=. a b i x y
  read -r -a a <<<"$1"
  read -r -a b <<<"$2"
  for i in 0 1 2 3; do
    x=${a[i]:-0} y=${b[i]:-0}
    if ((10#$x > 10#$y)); then return 0; fi
    if ((10#$x < 10#$y)); then return 1; fi
  done
  return 1
}

# The commit a release description says it was deployed from, if it says.
deploy_note_commit() { printf '%s\n' "$1" | sed -nE "s/.*$DEPLOY_NOTE ([0-9a-f]{40}).*/\1/p" | head -1; }

# Read the update feed on stdin: feed_field shortVersionString, feed_attr url.
feed_field() { sed -nE "s#.*<sparkle:$1>([^<]*)</sparkle:$1>.*#\1#p" | head -1; }
feed_attr()  { grep -oE "$1=\"[^\"]*\"" | head -1 | sed -E 's/^[^=]+="(.*)"$/\1/'; }

build_number_in() { grep -m1 -oE 'CURRENT_PROJECT_VERSION = [0-9]+;' | grep -oE '[0-9]+'; }

# --- Checks ---

check_build_files() {
  local changes others
  changes="$(git status --porcelain --untracked-files=all -- "${BUILD_PATHS[@]}")"
  if [[ -n $changes ]]; then
    problem "Files the app is built from have changes that aren't committed" \
      "A release built from them wouldn't match any commit, so nobody could tell later what shipped:" \
      "$(printf '%s\n' "$changes" | sed 's/^/  /')" \
      "Commit them (or undo them), then run the check again."
    return 1
  fi
  ok "Everything the app is built from is committed"
  others="$(git status --porcelain --untracked-files=all -- . "${BUILD_EXCLUDES[@]}" | awk '{print $NF}' | paste -sd, - | sed 's/,/, /g')"
  if [[ -n $others ]]; then
    note "Not part of the build, so not in this release either way: $others"
  fi
}

fetch_from_github() {
  local err
  if err="$(git fetch -q --tags origin 2>&1)"; then return 0; fi
  problem "Couldn't get the latest from GitHub" "$err" \
    "Check your connection, then run the check again." \
    "If it says a tag would be \"clobbered\", a release tag was moved on GitHub. Ask before going further."
  return 1
}

# Works out which commit is live: LIVE_TAG, LIVE_COMMIT, LIVE_SOURCE.
# A commit named with LIVE_COMMIT only counts when GitHub can't tell.
find_live() {
  local named=$NAMED_LIVE_COMMIT tag commit body noted feed feed_version
  LIVE_TAG="" LIVE_COMMIT="" LIVE_SOURCE=""
  if [[ -n $named ]] && ! named="$(git rev-parse -q --verify "$named^{commit}")"; then
    problem "The commit you named ($NAMED_LIVE_COMMIT) isn't in this copy of the project" \
      "Fetch first (git fetch origin --tags), or check you copied the whole commit."
    return 1
  fi

  if ! tag="$(provider_latest_tag 2>/dev/null)" || [[ -z $tag ]]; then
    if [[ -n $named ]]; then
      LIVE_TAG="(named by hand)" LIVE_COMMIT=$named LIVE_SOURCE="named by you with LIVE_COMMIT, because GitHub couldn't tell"
      ok "Live commit: $(short "$named"), $LIVE_SOURCE"
      return 0
    fi
    problem "Couldn't find out which version is live" \
      "GitHub didn't say which release is marked Latest. Check you're online and signed in (gh auth status), then run the check again." \
      "If GitHub really can't tell, name the live commit yourself:" \
      "  1. Open https://github.com/$REPO/releases and find the release marked Latest." \
      "  2. Click its commit link (under the tag name) and copy the long commit ID." \
      "  3. Run: LIVE_COMMIT=<that ID> scripts/release.sh --check"
    return 1
  fi

  if ! commit="$(provider_tag_commit "$tag" 2>/dev/null)" || [[ ! $commit =~ ^[0-9a-f]{40}$ ]]; then
    problem "GitHub says $tag is live, but couldn't say which commit it was built from" \
      "Run the check again in a minute. If it keeps happening, name the commit yourself:" \
      "  LIVE_COMMIT=<commit ID of $tag> scripts/release.sh --check"
    return 1
  fi

  body="$(provider_release_body "$tag" 2>/dev/null || true)"
  noted="$(deploy_note_commit "$body")"
  if [[ -n $noted && $noted != "$commit" ]]; then
    if [[ $named == "$noted" || $named == "$commit" ]]; then
      note "$tag's records disagree; going with $(short "$named"), the commit you named"
      commit=$named
    else
      problem "The live release's records disagree" \
        "$tag's description says it was deployed from $(short "$noted"), but its tag points at $(short "$commit")." \
        "Someone may have moved the tag. Don't deploy until you know which is right:" \
        "ask whoever released $tag, then name it: LIVE_COMMIT=<commit ID> scripts/release.sh --check"
      return 1
    fi
  elif [[ -n $named && $named != "$commit" ]]; then
    problem "The commit you named isn't what's live" \
      "GitHub says $tag is live, built from $(short "$commit"). You named $(short "$named")." \
      "LIVE_COMMIT is only for when GitHub can't tell. Run the check again without it."
    return 1
  fi

  if ! feed="$(provider_feed 2>/dev/null)"; then
    problem "The update feed didn't load" "Installed copies read $FEED_URL to find updates." \
      "Check your connection and run the check again. If it still fails, the live release itself is broken: fix that before deploying anything else."
    return 1
  fi
  feed_version="$(feed_field shortVersionString <<<"$feed")"
  if [[ $feed_version != "${tag#v}" ]]; then
    problem "GitHub and the update feed disagree about what's live" \
      "GitHub marks $tag as Latest, but the feed installed copies read offers ${feed_version:-nothing}." \
      "Wait a minute and run the check again (GitHub can lag right after a release). If it persists, look at the releases page before deploying."
    return 1
  fi

  LIVE_TAG=$tag LIVE_COMMIT=$commit
  if [[ -n $noted ]]; then
    LIVE_SOURCE="from the deploy note on the release"
  else
    LIVE_SOURCE="from the release tag (this release predates the deploy check)"
  fi
  ok "Live: $tag, built from commit $(short "$commit"), $LIVE_SOURCE"
  ok "The update feed agrees: it offers ${tag#v}"
}

check_contains_live() {
  if ! git cat-file -e "$LIVE_COMMIT^{commit}" 2>/dev/null; then
    problem "The live commit isn't in this copy of the project" \
      "$LIVE_TAG was built from $(short "$LIVE_COMMIT"), and this checkout has never seen it." \
      "Fetch it: git fetch origin --tags" \
      "If it's still missing after that, whoever released $LIVE_TAG hasn't pushed their work yet." \
      "Have them push it from that computer or branch, then fetch and run the check again."
    return 1
  fi
  if git merge-base --is-ancestor "$LIVE_COMMIT" HEAD; then
    ok "This branch has everything that's live"
    return 0
  fi
  local missing count holders
  missing="$(git log --format='%h %s' "HEAD..$LIVE_COMMIT")"
  count="$(printf '%s\n' "$missing" | grep -c .)"
  holders="$(git for-each-ref --contains "$LIVE_COMMIT" --format='%(refname)' refs/heads refs/remotes \
    | grep -v '/HEAD$' | sed -E 's#^refs/(heads|remotes)/##' | head -3 | paste -sd, - | sed 's/,/, /g' || true)"
  problem "This branch is missing work that's already live" \
    "Releasing it would take $(plural "$count" change) away from everyone who updates:" \
    "$(printf '%s\n' "$missing" | head -15 | sed 's/^/  /')" \
    "Fix: merge the live release into this branch, then run the check again:" \
    "  git merge $LIVE_TAG" \
    "${holders:+(Branches that already have it: $holders)}"
  return 1
}

check_branch() {
  BRANCH="$(git branch --show-current)"
  if [[ -z $BRANCH ]]; then
    problem "You're not on a branch" \
      "This copy is sitting on a single commit (a \"detached HEAD\"), so the release commit wouldn't belong to any branch." \
      "Switch to a branch first, for example: git switch $MAIN_BRANCH"
    return 1
  fi
  if [[ $BRANCH == "$MAIN_BRANCH" ]]; then
    ok "Branch: $BRANCH"
  else
    note "Branch: $BRANCH (the main branch is $MAIN_BRANCH)"
    local main_extra
    main_extra="$(git rev-list --count "HEAD..origin/$MAIN_BRANCH" 2>/dev/null || echo 0)"
    if ((main_extra > 0)); then
      note "$MAIN_BRANCH on GitHub has $(plural "$main_extra" commit) this branch doesn't. They aren't live, so that's not a stop, but they won't be in this release."
    fi
    confirm "You're releasing from $BRANCH, not $MAIN_BRANCH. Release from $BRANCH anyway?"
  fi

  local upstream ahead behind
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  if [[ -z $upstream ]] && git show-ref -q --verify "refs/remotes/origin/$BRANCH"; then upstream="origin/$BRANCH"; fi
  if [[ -z $upstream ]]; then
    confirm "$BRANCH isn't on GitHub at all, so nobody else can see this work. Release it anyway?"
    return 0
  fi
  ahead="$(git rev-list --count "$upstream..HEAD")"
  behind="$(git rev-list --count "HEAD..$upstream")"
  if ((ahead > 0)); then
    confirm "$(plural "$ahead" "of your commits" "of your commits") on $BRANCH $( ((ahead == 1)) && echo "isn't" || echo "aren't") on GitHub yet. Release anyway?"
  fi
  if ((behind > 0)); then
    confirm "GitHub has $(plural "$behind" commit) on $BRANCH that you don't. Release without $( ((behind == 1)) && echo it || echo them)?"
  fi
  if ((ahead == 0 && behind == 0)); then ok "$BRANCH matches GitHub"; fi
}

# Anything this deploy makes public must carry your private GitHub email.
check_private_emails() {
  local configured exposed
  configured="$(git config user.email || true)"
  if [[ $configured != *"$PRIVATE_EMAIL_SUFFIX" ]]; then
    problem "Your git email for this project isn't your private GitHub address" \
      "The release commit would carry it, and it becomes public with the release." \
      "Find your private address at https://github.com/settings/emails, then run:" \
      "  git config user.email <id>+<username>$PRIVATE_EMAIL_SUFFIX"
    return 1
  fi
  exposed="$(git log --format='%h %ae %ce %s' HEAD --not --remotes=origin --tags \
    | awk -v s="$PRIVATE_EMAIL_SUFFIX" 'index($2, s) == 0 || index($3, s) == 0 { $2 = ""; $3 = ""; print }' || true)"
  if [[ -n $exposed ]]; then
    problem "Commits that would become public use an email that isn't your private GitHub address" \
      "$(printf '%s\n' "$exposed" | sed 's/^/  /')" \
      "Don't release them as they are. Ask for help rewriting them with your private address first."
    return 1
  fi
  ok "Everything this would make public uses your private GitHub email"
}

check_version() {
  local v=$1 tags t
  if [[ ! $v =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    problem "\"$v\" isn't a version number" "Use something like 1.3 or 1.3.1."
    return 1
  fi
  if git rev-parse -q --verify "refs/tags/v$v" >/dev/null; then
    problem "Version $v was already released" "Tag v$v exists. Pick a higher version."
    return 1
  fi
  if ! tags="$(provider_release_tags 2>/dev/null)"; then
    problem "Couldn't list the published releases" "Check your connection and gh auth status, then run the check again."
    return 1
  fi
  for t in $tags; do
    if ! version_gt "$v" "${t#v}"; then
      problem "Version $v isn't higher than $t, which is already published" \
        "Installed copies ignore an update that isn't newer. Pick a version above ${t#v}."
      return 1
    fi
  done
  # Build numbers are what the updater compares, so go above every published one.
  local max b
  max="$(build_number_in <"$PBX")"
  for t in $tags; do
    if ! b="$(git show "$t:XReader.xcodeproj/project.pbxproj" 2>/dev/null | build_number_in)"; then
      problem "Release $t isn't in this copy of the project" "Fetch it first: git fetch origin --tags"
      return 1
    fi
    if ((b > max)); then max=$b; fi
  done
  NEXT_BUILD=$((max + 1))
  ok "Version $v (build $NEXT_BUILD) is newer than everything published"
}

run_tests() {
  local out
  if out="$("$ROOT/scripts/tests/run.sh" 2>&1)"; then
    ok "Deploy-check tests: $(printf '%s\n' "$out" | tail -1)"
  else
    problem "The deploy check's own tests failed" "$(printf '%s\n' "$out" | grep -v '^  ok' | tail -20)"
  fi
  if grep -q '<TestableReference' "$SCHEME_FILE" 2>/dev/null; then
    if out="$(xcodebuild -project "$ROOT/XReader.xcodeproj" -scheme XReader -destination 'platform=macOS' -quiet test 2>&1)"; then
      ok "App tests passed"
    else
      problem "The app's tests failed" "$(printf '%s\n' "$out" | tail -20)"
    fi
  else
    note "The app has no automated tests yet (none are set up in Xcode)"
  fi
}

find_sparkle_bin() {
  local build_dir
  build_dir="$(xcodebuild -project "$ROOT/XReader.xcodeproj" -scheme XReader -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILD_DIR = /{print $2; exit}')"
  SPARKLE_BIN="${build_dir%/Build/Products}/SourcePackages/artifacts/sparkle/Sparkle/bin"
  [[ -x "$SPARKLE_BIN/sign_update" ]]
}

check_tools() {
  local failed=0 key app_key
  if ! gh auth status >/dev/null 2>&1; then
    problem "The GitHub command-line tool isn't signed in" "Run: gh auth login"
    failed=1
  fi
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    problem "There's no notarization login named \"$NOTARY_PROFILE\" on this Mac" \
      "Apple has to approve every release. Set it up once (README → Releasing):" \
      "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <apple-id> --team-id $TEAM_ID"
    failed=1
  fi
  if ! find_sparkle_bin; then
    problem "Sparkle's signing tools weren't found" "Build the project once in Xcode, then run the check again."
    return 1
  fi
  key="$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null || true)"
  app_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$ROOT/XReader/Info.plist" 2>/dev/null || true)"
  if [[ -z $key ]]; then
    problem "This Mac has no update signing key" \
      "Installed copies only accept updates signed with it. Restore it from your backup:" \
      "  generate_keys -f <backup file>   (in $SPARKLE_BIN)"
    failed=1
  elif [[ $key != "$app_key" ]]; then
    problem "This Mac's update signing key doesn't match the one built into the app" \
      "Every installed copy would reject an update signed with it. Restore the right key from your backup."
    failed=1
  fi
  if ((failed == 0)); then ok "GitHub sign-in, notarization login, Sparkle tools and signing key are all set"; fi
}

show_additions() {
  local count app_files
  count="$(git rev-list --count "$LIVE_COMMIT..HEAD")"
  section "What this release adds since $LIVE_TAG"
  if ((count == 0)); then
    echo "    Nothing: this branch is exactly what's live."
    confirm "This would ship the same app as $LIVE_TAG under a new number. Release anyway?"
    return 0
  fi
  git log --no-merges --format='    %h %s' "$LIVE_COMMIT..HEAD" | head -30 || true
  if ((count > 30)); then echo "    …and $((count - 30)) more"; fi
  echo "    Files:$(git diff --shortstat "$LIVE_COMMIT" HEAD)"
  app_files="$(git diff --name-only "$LIVE_COMMIT" HEAD -- "${BUILD_PATHS[@]}" | grep -c . || true)"
  if ((app_files == 0)); then
    note "None of these change the app itself (only scripts, docs or settings)."
  fi
}

# --- The live release, as an installed copy sees it ---

LIVE_FAILURES=0
live_fail() {
  LIVE_FAILURES=$((LIVE_FAILURES + 1))
  printf '  ✗ %s\n' "$1"
  shift
  if (($#)); then printf '%s\n' "$@" | indent; fi
}

# verify_live <version> <commit> [<zip we just built>]
verify_live() {
  local v=$1 commit=$2 built_zip=${3:-} feed tries=0 build url length sig work app spctl_out assets branches b exposed
  LIVE_FAILURES=0
  work="$(mktemp -d "${TMPDIR:-/tmp}/xreader-live.XXXXXX")"

  # GitHub can take a moment to point "latest" at a brand-new release.
  while :; do
    feed="$(provider_feed 2>/dev/null || true)"
    if [[ "$(feed_field shortVersionString <<<"$feed")" == "$v" ]]; then break; fi
    tries=$((tries + 1))
    if ((tries >= 12)); then
      live_fail "The update feed doesn't offer $v" "Installed copies won't see it. Look at https://github.com/$REPO/releases"
      rm -rf "$work"
      return 1
    fi
    sleep 5
  done
  build="$(feed_field version <<<"$feed")"
  url="$(feed_attr url <<<"$feed")"
  length="$(feed_attr length <<<"$feed")"
  sig="$(feed_attr 'sparkle:edSignature' <<<"$feed")"
  ok "Public: the update feed offers $v (build $build)"

  if curl -fsSL --max-time 120 -o "$work/update.zip" "$url" && [[ "$(stat -f %z "$work/update.zip")" == "$length" ]]; then
    ok "Public: the download works and its size matches the feed ($length bytes)"
  else
    live_fail "The download is missing or the wrong size" "$url"
    rm -rf "$work"
    return 1
  fi
  if [[ -n $built_zip ]]; then
    if cmp -s "$built_zip" "$work/update.zip"; then ok "Public: it's byte-for-byte the file this run built"
    else live_fail "The download isn't the file this run built"; fi
  fi
  if [[ -n ${SPARKLE_BIN:-} ]] && "$SPARKLE_BIN/sign_update" --verify "$work/update.zip" "$sig" >/dev/null 2>&1; then
    ok "Protected: the update's signature checks out"
  else
    live_fail "The update's signature didn't check out" "Installed copies will refuse to install it."
  fi

  ditto -x -k "$work/update.zip" "$work/x" 2>/dev/null || true
  app="$work/x/XReader.app"
  spctl_out="$(spctl -a -t exec -vv "$app" 2>&1 || true)"
  if [[ $spctl_out == *accepted* && $spctl_out == *"source=Notarized Developer ID"* && $spctl_out == *"($TEAM_ID)"* ]]; then
    ok "Protected: Apple's security check accepts the app (notarized, signed by your developer account)"
  else
    live_fail "Apple's security check doesn't accept the downloaded app" "$spctl_out"
  fi
  if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null)" == "$v" ]]; then
    ok "Public: the app inside says it's version $v"
  else
    live_fail "The app inside the download isn't version $v"
  fi
  if [[ "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$app/Contents/Info.plist" 2>/dev/null)" == \
        "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$ROOT/XReader/Info.plist" 2>/dev/null)" ]]; then
    ok "Protected: the update key built into the app matches this project's, so only your key can sign updates"
  else
    live_fail "The update key built into the app doesn't match this project's"
  fi
  if [[ -z "$(zipinfo -1 "$work/update.zip" | grep -vE '^(__MACOSX/)?XReader\.app/|^__MACOSX/$' || true)" ]]; then
    ok "Protected: the download holds only XReader.app"
  else
    live_fail "The download holds more than XReader.app" "$(zipinfo -1 "$work/update.zip" | grep -vE '^(__MACOSX/)?XReader\.app/|^__MACOSX/$' | head -5)"
  fi

  assets="$(provider_release_assets "v$v" 2>/dev/null | LC_ALL=C sort | paste -sd' ' - || true)"
  if [[ $assets == "XReader-$v.zip appcast.xml" ]]; then
    ok "Protected: the release holds only XReader-$v.zip and appcast.xml"
  else
    live_fail "The release holds unexpected files" "Found: ${assets:-nothing}"
  fi
  if curl -fsSL --max-time 30 -o /dev/null "https://github.com/$REPO/releases/tag/v$v"; then
    ok "Public: the release page loads"
  else
    live_fail "The release page doesn't load" "https://github.com/$REPO/releases/tag/v$v"
  fi

  local extra=""
  branches="$(provider_branches 2>/dev/null || true)"
  for b in $branches; do
    if [[ " $PUBLIC_BRANCHES " != *" $b "* ]]; then extra="$extra $b"; fi
  done
  if [[ -z $branches ]]; then
    live_fail "Hidden: couldn't list the branches on GitHub"
  elif [[ -n $extra ]]; then
    live_fail "Hidden: unexpected branches are on GitHub:$extra" "Only $PUBLIC_BRANCHES should be. If one shouldn't be public, delete it on GitHub."
  else
    ok "Hidden: GitHub has only the branches meant to be public ($PUBLIC_BRANCHES)"
  fi
  exposed="$(git log --format='%h %ae %ce' "$commit" 2>/dev/null \
    | awk -v s="$PRIVATE_EMAIL_SUFFIX" 'index($2, s) == 0 || index($3, s) == 0 { print $1 }' | head -5 || true)"
  if [[ -z $exposed ]]; then
    ok "Hidden: every published commit uses your private GitHub email"
  else
    live_fail "Hidden: published commits use an email that isn't your private GitHub address" "$exposed"
  fi

  rm -rf "$work"
  ((LIVE_FAILURES == 0))
}
